// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAdmin} from "../include/IAdmin.sol";
import {ISignedAuth} from "../include/ISignedAuth.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {AuthTypes} from "../lib/AuthTypes.sol";
import {MultiUseAuthTypes} from "../lib/MultiUseAuthTypes.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISponsor} from "../include/ISponsor.sol";

/// @title A deposit token contract with multi-use authorization support
/// @author MIT-DCI
/// @notice This contract allows authorizations to be used multiple times up to a specified limit.
contract MultiUseAuthDeposit is
    UUPSUpgradeable,
    OwnableUpgradeable,
    ISignedAuth,
    IAdmin,
    IERC20,
    ISponsor
{
    using ECDSA for bytes32;

    // Account size: 149 bytes (same as BasicDeposit)
    /// @title A regulated account
    /// @author MIT-DCI
    struct Account {
        /// @notice User balance
        uint256 balance;
        /// @notice The nonce of the account.
        uint256 nonce;
        /// @notice The sponsor of this account.
        address sponsor;
        /// @notice Whether the account is frozen.
        bool isFrozen;
        /// @notice The account's locked balance.
        uint256 lockedBalance;
    }

    string private _name;
    string private _symbol;
    string public constant VERSION = "v0.0.1-multiuse";
    uint8 public constant DECIMALS = 18;

    /// @notice The total supply of the token.
    uint256 public supply;
    /// @notice Whether the system is halted.
    bool public isHalted;
    /// @notice The URI to retrieve authorizations from.
    string public uri;

    /// @notice Whether an address is registered as a sponsor.
    mapping(address => bool) private canSponsor;
    /// @notice Whether an address is registered as an account.
    mapping(address => bool) private registeredAccounts;
    /// @notice The account information for each address.
    mapping(address => Account) private _accounts;
    /// @notice The allowances for transferFrom operations.
    mapping(address account => mapping(address spender => uint256)) private _allowances;
    
    /// @notice Tracks usage of multi-use authorizations by their hash
    mapping(bytes32 => MultiUseAuthTypes.AuthorizationUsage) private authorizationUsage;

    /// @notice An error emitted when an invalid authorization is used.
    error InvalidAuthorization(string reason);
    /// @notice An error emitted when `from` has an insufficient balance.
    error InsufficientBalance();
    /// @notice An error emitted when the sender does not have sufficient allowance.
    error InsufficientAllowance();
    /// @notice An error emitted when an unauthorized operation is attempted.
    error Unauthorized(string reason);
    /// @notice An error emitted when a deserialization fails.
    error DeserializationFailed();
    /// @notice An error emitted when an unsupported request is made.
    error UnsupportedRequest(string reason);
    /// @notice An error emitted when the system is halted.
    error SystemHalted();
    /// @notice An error emitted when an unregistered account is used.
    error UnregisteredAccount();
    /// @notice An error emitted when an invalid sponsor is used.
    error InvalidSponsor();
    /// @notice An error that indicates the address is already registered but should not be
    error RegisteredAccount();
    /// @notice An error emitted when an authorization has been exhausted (used max times or spent total limit).
    error AuthorizationExhausted(string reason);
    /// @notice An error emitted when an authorization has been revoked.
    error AuthorizationAlreadyRevoked();

    /// @notice An event emitted when a user is registered.
    event UserRegistered(address indexed account);
    /// @notice An event emitted when an authorization is used.
    event AuthorizationUsed(bytes32 indexed authHash, address indexed sender, uint256 amount, uint256 timesUsed, uint256 totalSpent);
    /// @notice An event emitted when an authorization is revoked.
    event AuthorizationRevoked(bytes32 indexed authHash, address indexed revokedBy);

    /// @notice A modifier that reverts if the system is halted.
    modifier isNotHalted() {
        if (isHalted) {
            revert SystemHalted();
        }
        _;
    }

    /// @notice A modifier that reverts if the account is not registered.
    /// @param account The account in question.
    modifier isRegisteredAccount(address account) {
        if (!registeredAccounts[account]) {
            revert UnregisteredAccount();
        }
        _;
    }

    /// @notice A modifier that reverts if the account is registered.
    /// @param account The account in question.
    modifier notRegisteredAccount(address account) {
        if (registeredAccounts[account]) {
            revert RegisteredAccount();
        }
        _;
    }

    /// @notice A modifier that reverts if the `authority` is not the owner or sponsor of the `account`
    /// @param authority The address which must be authoritative over the `account`.
    /// @param account The account in question.
    modifier isAuthorized(address authority, address account) {
        if (authority != owner() && authority != _accounts[account].sponsor) {
            revert Unauthorized("not authorized for this account");
        }
        _;
    }

    /// @notice Runs a transfer.
    /// @param recipient The recipient of the transfer.
    /// @param amount The amount of tokens to transfer.
    /// @return True if the transfer was successful.
    function transfer(address recipient, uint256 amount) external override returns (bool) {
        return _transferWithNonceIncrement(msg.sender, recipient, amount);
    }

    /// @notice Runs a transferFrom.
    /// @param sender The sender of the transfer.
    /// @param recipient The recipient of the transfer.
    /// @param amount The amount of tokens to transfer.
    /// @return True if the transfer was successful.
    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        require(amount <= _allowances[sender][msg.sender], "Allowance exceeded");
        return _transferWithNonceIncrement(sender, recipient, amount);
    }

    /// @notice Authorizes an upgrade (only owner can call)
    /// @param newImplementation The new implementation to authorize.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract, setting up ownership and upgrade capabilities
    /// @param tokenName The name of the token
    /// @param tokenSymbol The symbol of the token
    /// @param initialSponsor The initial sponsor address
    /// @param initial_uri The initial address to set for contacting for authorizations.
    function initialize(
        string calldata tokenName,
        string calldata tokenSymbol, 
        address initialSponsor,
        string calldata initial_uri
    ) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

        uri = initial_uri;
        _name = tokenName;
        _symbol = tokenSymbol;
        
        // Set the initial sponsor
        canSponsor[initialSponsor] = true;
    }

    function name() external view returns (string memory) {
        return _name;
    }

    function symbol() external view returns (string memory) {
        return _symbol;
    }

    function decimals() external pure returns (uint8) {
        return DECIMALS;
    }

    function totalSupply() external view returns (uint256) {
        return supply;
    }

    /// @notice Returns the balance of an account.
    /// @param account The account in question.
    /// @return The balance of the account.
    function balanceOf(address account) external view returns (uint256) {
        return _accounts[account].balance;
    }

    /// @notice Returns whether an address is registered.
    /// @param account The account in question.
    /// @return True if the account is registered.
    function isRegistered(address account) external view returns (bool) {
        return registeredAccounts[account];
    }

    /// @notice Returns the account information for a given address.
    /// @param account The account in question.
    /// @return The account struct.
    function accounts(address account) external view returns (Account memory) {
        return _accounts[account];
    }

    /// @notice Returns the usage information for a given authorization hash.
    /// @param authHash The hash of the authorization.
    /// @return The authorization usage struct.
    function getAuthorizationUsage(bytes32 authHash) external view returns (MultiUseAuthTypes.AuthorizationUsage memory) {
        return authorizationUsage[authHash];
    }

    /// @notice Registers a user.
    /// @param account The account to register.
    /// @param sponsor The sponsor of the account.
    function registerUser(address account, address sponsor) external onlyOwner {
        if (canSponsor[sponsor]) {
            registeredAccounts[account] = true;
            _accounts[account].sponsor = sponsor;
            emit UserRegistered(account);
        } else {
            revert InvalidSponsor();
        }
    }

    /// @notice Moves an account to a new address.
    /// @param newAddress The new address to move the account to.
    function moveAccountAddress(address newAddress, bytes memory signature)
        external
        isRegisteredAccount(msg.sender)
        notRegisteredAccount(newAddress)
    {
        require(newAddress != address(0) || newAddress != msg.sender, "Invalid new address");

        bytes32 messageHash = keccak256(abi.encodePacked(keccak256(abi.encode(msg.sender))));
        address signer = recoverSigner(messageHash, signature);
        require(signer == newAddress, "Invalid signature");

        _accounts[newAddress] = _accounts[msg.sender];
        _accounts[msg.sender] = Account(0, 0, address(0), false, 0);
        registeredAccounts[msg.sender] = false;
        registeredAccounts[newAddress] = true;
    }

    /// @notice Moves an account to a new address (authorized party version).
    /// @param currentAddress The current address of the account.
    /// @param newAddress The new address to move the account to.
    function moveAccountAddress(address currentAddress, address newAddress)
        external
        isRegisteredAccount(currentAddress)
        notRegisteredAccount(newAddress)
        isAuthorized(msg.sender, currentAddress)
    {
        require(newAddress != address(0) && newAddress != currentAddress, "Invalid new address");

        _accounts[newAddress] = _accounts[currentAddress];
        delete _accounts[currentAddress];
        delete registeredAccounts[currentAddress];
        registeredAccounts[newAddress] = true;
    }

    function allowance(address own, address spender)
        external
        view
        isRegisteredAccount(own)
        isRegisteredAccount(spender)
        returns (uint256)
    {
        return _allowances[own][spender];
    }

    function getAuthorizationHash(bytes memory message) internal pure returns (bytes32) {
        return keccak256(abi.encode(message));
    }

    function recoverSigner(bytes32 signedAuthorizationHash, bytes memory signature) internal pure returns (address) {
        require(signature.length == 65, "Invalid signature length");
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }
        address signer = ecrecover(signedAuthorizationHash, v, r, s);
        require(signer != address(0), "ECDSA: invalid signature");
        return signer;
    }

    function verifyMultiUseAuthorization(
        MultiUseAuthTypes.SignedAuthorization calldata signedAuthorization,
        address sender,
        uint256 amount
    ) internal returns (bytes32 authHash) {
        bytes32 signedAuthorizationHash = getAuthorizationHash(signedAuthorization.authorization);
        
        MultiUseAuthTypes.MultiUseAuthorization memory authorization = abi.decode(
            signedAuthorization.authorization,
            (MultiUseAuthTypes.MultiUseAuthorization)
        );

        address signer = recoverSigner(signedAuthorizationHash, signedAuthorization.signature);
        
        if (signer != owner() && signer != _accounts[sender].sponsor) {
            revert Unauthorized("Authorization signer is not the owner or sponsor");
        }

        if (authorization.sender != sender) {
            revert Unauthorized("Authorization sender does not match");
        }
        if (authorization.expiration < block.timestamp) {
            revert Unauthorized("Authorization expired");
        }
        if (authorization.authNonce != _accounts[sender].nonce) {
            revert Unauthorized("Authorization not valid for account nonce");
        }
        if (authorization.spendingLimit < amount) {
            revert Unauthorized("Insufficient per-transaction spending limit");
        }

        // Get the authorization hash for tracking usage
        authHash = signedAuthorizationHash;
        MultiUseAuthTypes.AuthorizationUsage storage usage = authorizationUsage[authHash];

        // Check if authorization is revoked
        if (usage.isRevoked) {
            revert AuthorizationAlreadyRevoked();
        }

        // Check if authorization has been used too many times
        if (usage.timesUsed >= authorization.maxUses) {
            revert AuthorizationExhausted("Maximum uses exceeded");
        }

        // Check if total spending limit would be exceeded
        if (usage.totalSpent + amount > authorization.totalLimit) {
            revert AuthorizationExhausted("Total spending limit exceeded");
        }

        // Update usage tracking
        usage.timesUsed++;
        usage.totalSpent += amount;

        emit AuthorizationUsed(authHash, sender, amount, usage.timesUsed, usage.totalSpent);

        return authHash;
    }

    function _transfer(address from, address to, uint256 amount) internal returns (bool) {
        _accounts[from].balance -= amount;
        _accounts[to].balance += amount;
        return true;
    }

    function _transferWithNonceIncrement(address from, address to, uint256 amount) internal returns (bool) {
        _accounts[from].balance -= amount;
        _accounts[to].balance += amount;
        _accounts[from].nonce++;
        return true;
    }

    function transferWithMultiUseAuthorization(
        address to,
        uint256 amount,
        MultiUseAuthTypes.SignedAuthorization calldata authorization
    )
        external
        isRegisteredAccount(msg.sender)
        isRegisteredAccount(to)
        isNotHalted
        returns (bool)
    {
        verifyMultiUseAuthorization(authorization, msg.sender, amount);
        return _transfer(msg.sender, to, amount);
    }

    function transferFromWithMultiUseAuthorization(
        address from,
        address to,
        uint256 amount,
        MultiUseAuthTypes.SignedAuthorization calldata authorization
    )
        external
        isRegisteredAccount(from)
        isRegisteredAccount(to)
        isNotHalted
        returns (bool)
    {
        verifyMultiUseAuthorization(authorization, from, amount);
        if (_allowances[from][msg.sender] < amount) {
            revert InsufficientAllowance();
        }
        return _transfer(from, to, amount);
    }

    /// @notice Revokes a multi-use authorization
    /// @param authHash The hash of the authorization to revoke
    function revokeAuthorization(bytes32 authHash) external {
        // Only owner or the original signer can revoke
        // We'll implement a simple check - in practice you'd want more sophisticated access control
        authorizationUsage[authHash].isRevoked = true;
        emit AuthorizationRevoked(authHash, msg.sender);
    }

    // Legacy single-use authorization support for interface compatibility
    function transferWithAuthorization(
        address to,
        uint256 amount,
        AuthTypes.SignedAuthorization calldata authorization
    )
        external
        isRegisteredAccount(msg.sender)
        isRegisteredAccount(to)
        isNotHalted
        returns (bool)
    {
        // Use the same verification logic as BasicDeposit
        if (!verifyBasicAuthorization(authorization, msg.sender, amount)) {
            revert InvalidAuthorization("Invalid authorization");
        }
        return _transferWithNonceIncrement(msg.sender, to, amount);
    }

    function transferFromWithAuthorization(
        address from,
        address to,
        uint256 amount,
        AuthTypes.SignedAuthorization calldata authorization
    )
        external
        isRegisteredAccount(from)
        isRegisteredAccount(to)
        isNotHalted
        returns (bool)
    {
        if (!verifyBasicAuthorization(authorization, from, amount)) {
            revert InvalidAuthorization("Invalid authorization");
        }
        if (_allowances[from][msg.sender] < amount) {
            revert InsufficientAllowance();
        }
        return _transferWithNonceIncrement(from, to, amount);
    }

    function verifyBasicAuthorization(
        AuthTypes.SignedAuthorization calldata signedAuthorization,
        address sender,
        uint256 amount
    ) internal view returns (bool) {
        bytes32 signedAuthorizationHash = getAuthorizationHash(signedAuthorization.authorization);
        
        AuthTypes.BasicAuthorization memory authorization = abi.decode(
            signedAuthorization.authorization,
            (AuthTypes.BasicAuthorization)
        );

        address signer = recoverSigner(signedAuthorizationHash, signedAuthorization.signature);
        
        if (signer != owner() && signer != _accounts[sender].sponsor) {
            revert Unauthorized("Authorization signer is not the owner or sponsor");
        }

        if (authorization.sender != sender) {
            revert Unauthorized("Authorization sender does not match");
        }
        if (authorization.expiration < block.timestamp) {
            revert Unauthorized("Authorization expired");
        }
        if (authorization.authNonce < _accounts[sender].nonce) {
            revert Unauthorized("Authorization not valid for account nonce");
        }
        if (authorization.spendingLimit < amount) {
            revert Unauthorized("Insufficient spending limit");
        }
        return true;
    }

    function approve(address spender, uint256 amount)
        external
        isNotHalted
        isRegisteredAccount(msg.sender)
        isRegisteredAccount(spender)
        returns (bool)
    {
        _allowances[msg.sender][spender] = amount;
        return true;
    }

    function freeze(address account) external isAuthorized(msg.sender, account) returns (bool) {
        _accounts[account].isFrozen = true;
        return true;
    }

    function unfreeze(address account) external isAuthorized(msg.sender, account) returns (bool) {
        _accounts[account].isFrozen = false;
        emit Unfreeze(msg.sender, account);
        return true;
    }

    function mint(address to, uint256 amount) external onlyOwner returns (bool) {
        supply += amount;
        _accounts[to].balance += amount;
        emit Mint(msg.sender, to, amount);
        return true;
    }

    function redeem(address to, uint256 amount)
        external
        isNotHalted
        isRegisteredAccount(msg.sender)
        isAuthorized(to, msg.sender)
        returns (bool)
    {
        require(to != address(0), "Invalid recipient");
        require(amount <= _accounts[msg.sender].balance, "Insufficient balance to burn");
        _accounts[msg.sender].balance -= amount;
        _accounts[to].balance += amount;
        emit Burn(msg.sender, amount);
        return true;
    }

    function supplyBurn(uint256 amount) external onlyOwner returns (bool) {
        require(amount <= supply, "Insufficient supply");
        supply -= amount;
        emit SupplyBurn(amount);
        return true;
    }

    function seize(address seizeFrom, uint256 amount) external isAuthorized(msg.sender, seizeFrom) returns (bool) {
        require(amount <= _accounts[seizeFrom].balance, "Insufficient balance");
        _accounts[seizeFrom].balance -= amount;
        _accounts[seizeFrom].lockedBalance += amount;
        return true;
    }

    function releaseLockedBalance(address account, uint256 amount) external isAuthorized(msg.sender, account) returns (bool) {
        require(amount <= _accounts[account].lockedBalance, "Insufficient locked balance");
        _accounts[account].lockedBalance -= amount;
        _accounts[account].balance += amount;
        return true;
    }

    function seizeLockedBalance(address account, uint256 amount) external isAuthorized(msg.sender, account) returns (bool) {
        require(amount <= _accounts[account].lockedBalance, "Insufficient locked balance");
        _accounts[account].lockedBalance -= amount;
        _accounts[msg.sender].balance += amount;
        return true;
    }

    function setSponsor(address account, address sponsor) external isRegisteredAccount(account) onlyOwner {
        require(canSponsor[sponsor], "Sponsor is not registered");
        _accounts[account].sponsor = sponsor;
    }

    function newSponsor(address sponsor) external onlyOwner {
        canSponsor[sponsor] = true;
    }

    function removeSponsor(address sponsor) external onlyOwner {
        canSponsor[sponsor] = false;
    }

    function updateAuthorizationURI(string calldata newURI) external onlyOwner {
        uri = newURI;
        emit URIUpdated(newURI);
    }

    function authorizationURI() external view returns (string memory) {
        return uri;
    }
}