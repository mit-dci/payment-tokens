// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (token/ERC20/IERC20.sol)

pragma solidity ^0.8.24;

import {IAdmin} from "../include/IAdmin.sol";
import {ISignedAuth} from "../include/ISignedAuth.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {AuthTypes} from "../lib/AuthTypes.sol";

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISponsor} from "../include/ISponsor.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

// ERC-4337 Account Abstraction imports
import {PackedUserOperation, IAccount, IEntryPoint} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";

/// @title A basic deposit token contract with ERC-4337 Account Abstraction support
/// @author MIT-DCI
/// @notice This is a regulated payment asset contract with ERC-4337 account abstraction capabilities
contract BasicDepositERC4337 is
    UUPSUpgradeable,
    OwnableUpgradeable,
    ISignedAuth,
    IAdmin,
    IERC20,
    ISponsor,
    PausableUpgradeable,
    IAccount
{
    using ECDSA for bytes32;

    /// @notice The EntryPoint contract address for ERC-4337
    IEntryPoint public immutable entryPoint;

    /// @notice Validation result constants for ERC-4337
    uint256 internal constant SIG_VALIDATION_SUCCESS = 0;
    uint256 internal constant SIG_VALIDATION_FAILED = 1;

    /// @notice Constructor to set the EntryPoint
    /// @param _entryPoint The EntryPoint contract address
    constructor(IEntryPoint _entryPoint) {
        entryPoint = _entryPoint;
        _disableInitializers();
    }

    function _msgSender() internal view override returns (address) {
        return super._msgSender();
    }

    function _msgData() internal view override returns (bytes calldata) {
        return super._msgData();
    }

    function _contextSuffixLength() internal view override returns (uint256) {
        return super._contextSuffixLength();
    }

    /// @notice Modifier to ensure only the EntryPoint can call certain functions
    modifier onlyEntryPoint() {
        require(msg.sender == address(entryPoint), "Account: not from EntryPoint");
        _;
    }

    /// @notice Pauses the contract.
    /// @dev This is part of [`Pausable`].
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpauses the contract.
    /// @dev This is part of [`Pausable`].
    function unpause() external onlyOwner {
        _unpause();
    }

    // Account size: 149 bytes
    /// @title A regulated account
    /// @author MIT-DCI
    struct Account {
        /// @notice User balance
        uint256 balance;
        /// @notice The nonce of the account.
        uint256 nonce;
        /// @notice The sponsor of this account.
        /// @dev TODO: This may want to be a list of sponsors.
        address sponsor;
        /// @notice Whether the account is frozen.
        bool isFrozen;
        /// @notice The account's locked balance.
        uint256 lockedBalance;
    }

    string private _name;
    string private _symbol;
    string public constant VERSION = "v0.0.1-ERC4337";
    /// @dev TODO: what should this actually be?
    uint8 public constant DECIMALS = 18;

    /// @notice The total supply of the token.
    uint256 public supply;

    /// @notice The URI to retrieve authorizations from.
    string public uri;

    /// @notice Whether an address is registered as a sponsor.
    mapping(address => bool) private canSponsor;
    /// @notice Whether an address is registered as an account.
    /// @dev this can be used to see if an address was onboarded properly, it may be moot with per-transaction authorizations
    mapping(address => bool) private registeredAccounts;
    /// @notice The account information for each address.
    mapping(address => Account) private _accounts;
    /// @notice The allowances for transferFrom operations.
    mapping(address account => mapping(address spender => uint256))
        private _allowances;

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

    /// @notice An event emitted when a user is registered.
    event UserRegistered(address indexed account);

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

    /// @notice A modifier that reverts if the `authority` is not the owner or sponsor of the `account` (therefore it is not authorized to operate on the account)
    /// @param authority The address which must be authoritative over the `account`.
    /// @param account The account in question.
    modifier isAuthorized(address authority, address account) {
        if (authority != owner() && authority != _accounts[account].sponsor) {
            revert Unauthorized("not authorized for this account");
        }
        _;
    }

    /// @notice ERC-4337 validateUserOp implementation
    /// @param userOp The user operation to validate
    /// @param userOpHash The hash of the user operation
    /// @param missingAccountFunds The amount of funds missing from the account
    /// @return validationData Packed validation data (authorizer, validUntil, validAfter)
    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external override onlyEntryPoint returns (uint256 validationData) {
        // Pay the EntryPoint the missing funds
        if (missingAccountFunds > 0) {
            (bool success, ) = payable(msg.sender).call{value: missingAccountFunds}("");
            (success);
        }

        // Validate the signature
        if (_validateSignature(userOp, userOpHash)) {
            return SIG_VALIDATION_SUCCESS;
        }
        return SIG_VALIDATION_FAILED;
    }

    /// @notice Internal function to validate signatures for ERC-4337
    /// @param userOp The user operation
    /// @param userOpHash The hash of the user operation
    /// @return True if signature is valid
    function _validateSignature(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash
    ) internal view returns (bool) {
        bytes32 hash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        address signer = ECDSA.recover(hash, userOp.signature);
        
        // Check if signer is the account owner, contract owner, or account sponsor
        return (signer == userOp.sender || 
                signer == owner() || 
                signer == _accounts[userOp.sender].sponsor);
    }

    /// @notice Execute a user operation (ERC-4337)
    /// @param dest The destination address
    /// @param value The value to send
    /// @param data The calldata to execute
    function execute(address dest, uint256 value, bytes calldata data) external onlyEntryPoint {
        (bool success, bytes memory result) = dest.call{value: value}(data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }

    /// @notice Execute a batch of user operations (ERC-4337)
    /// @param dests Array of destination addresses
    /// @param values Array of values to send
    /// @param datas Array of calldata to execute
    function executeBatch(
        address[] calldata dests,
        uint256[] calldata values,
        bytes[] calldata datas
    ) external onlyEntryPoint {
        require(dests.length == values.length && values.length == datas.length, "Length mismatch");
        
        for (uint256 i = 0; i < dests.length; i++) {
            (bool success, bytes memory result) = dests[i].call{value: values[i]}(datas[i]);
            if (!success) {
                assembly {
                    revert(add(result, 32), mload(result))
                }
            }
        }
    }

    /// @notice Deposit funds to this account for EntryPoint
    function deposit() external payable {
        entryPoint.depositTo{value: msg.value}(address(this));
    }

    /// @notice Withdraw funds from EntryPoint
    /// @param withdrawAddress The address to withdraw to
    /// @param amount The amount to withdraw
    function withdraw(address payable withdrawAddress, uint256 amount) external onlyOwner {
        entryPoint.withdrawTo(withdrawAddress, amount);
    }

    /// @notice Get the deposit balance in EntryPoint
    /// @return The deposit balance
    function getDeposit() external view returns (uint256) {
        return entryPoint.balanceOf(address(this));
    }

    /// @notice Runs a transfer.
    /// @param recipient The recipient of the transfer.
    /// @param amount The amount of tokens to transfer.
    /// @return True if the transfer was successful.
    /// @dev This is part of [`ERC20`].
    function transfer(
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        return _transfer(msg.sender, recipient, amount);
    }

    /// @notice Runs a transferFrom.
    /// @param sender The sender of the transfer.
    /// @param recipient The recipient of the transfer.
    /// @param amount The amount of tokens to transfer.
    /// @return True if the transfer was successful.
    /// @dev This is part of [`ERC20`].
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        require(
            amount <= _allowances[sender][msg.sender],
            "Allowance exceeded"
        );
        return _transfer(sender, recipient, amount);
    }

    /// @notice Authorizes an upgrade (only owner can call)
    /// @param newImplementation The new implementation to authorize.
    /// @dev This is part of [`UUPSUpgradeable`].
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    /// @notice Initializes the contract, setting up ownership and upgrade capabilities
    /// @param tokenName The name of the token
    /// @param tokenSymbol The symbol of the token
    /// @param initialSponsor The initial sponsor address
    /// @param initial_uri The initial address to set for contacting for authorizations.
    /// @dev This function replaces the constructor and can only be called once due to the initializer modifier
    function initialize(
        string calldata tokenName,
        string calldata tokenSymbol,
        address initialSponsor,
        string calldata initial_uri
    ) public initializer {
        // Initialize the Ownable module
        // This function sets up the contract's ownership, making msg.sender the initial owner
        // It's part of the OwnableUpgradeable contract from OpenZeppelin
        __Ownable_init(msg.sender);

        // Initialize the UUPSUpgradeable module
        // This sets up the necessary state variables for the UUPS (Universal Upgradeable Proxy Standard) pattern
        // It's part of the UUPSUpgradeable contract from OpenZeppelin
        __UUPSUpgradeable_init();

        __Pausable_init();

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

    /// @notice Registers a user.
    /// @param account The account to register.
    /// @param sponsor The sponsor of the account.
    /// @dev TODO: Should this be callable by a specific role besides owner?
    /// @dev If the user is already registered, this just changes the sponsor. TODO: Should it revert?
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
    /// @dev This makes sure that the new address is not already registered before proceeding.
    /// @dev TODO: This needs to prove that the user controls the new address and therefore needs a signature.
    function moveAccountAddress(
        address newAddress,
        bytes memory signature
    )
        external
        isRegisteredAccount(msg.sender)
        notRegisteredAccount(newAddress)
    {
        require(
            newAddress != address(0) || newAddress != msg.sender,
            "Invalid new address"
        );

        // The user will sign a message containing their current address with the private key corresponding
        // to the new address.
        bytes32 messageHash = keccak256(
            abi.encodePacked(keccak256(abi.encode(msg.sender)))
        );

        address signer = recoverSigner(messageHash, signature);

        require(signer == newAddress, "Invalid signature");

        _accounts[newAddress] = _accounts[msg.sender];
        _accounts[msg.sender] = Account(0, 0, address(0), false, 0);
        registeredAccounts[msg.sender] = false;
        registeredAccounts[newAddress] = true;
    }

    /// @notice Moves an account to a new address in case an authorized party needs to move an account to a new address.
    /// @param currentAddress The current address of the account.
    /// @param newAddress The new address to move the account to.
    /// @dev This makes sure that the new address is not already registered before proceeding.
    /// @dev This does not require a signature because we cannot assume that the sponsor can sign OBO the user.
    function moveAccountAddress(
        address currentAddress,
        address newAddress
    )
        external
        isRegisteredAccount(currentAddress)
        notRegisteredAccount(newAddress)
        isAuthorized(msg.sender, currentAddress)
    {
        require(
            newAddress != address(0) && newAddress != currentAddress,
            "Invalid new address"
        );

        _accounts[newAddress] = _accounts[currentAddress];
        delete _accounts[currentAddress];
        delete registeredAccounts[currentAddress];
        registeredAccounts[newAddress] = true;
    }

    function allowance(
        address own,
        address spender
    )
        external
        view
        isRegisteredAccount(own)
        isRegisteredAccount(spender)
        returns (uint256)
    {
        return _allowances[own][spender];
    }

    function getAuthorizationHash(
        bytes memory message
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(message));
    }

    function recoverSigner(
        bytes32 signedAuthorizationHash,
        bytes memory signature
    ) internal pure returns (address) {
        require(signature.length == 65, "Invalid signature length");
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            /*
            https://www.cyfrin.io/glossary/verifying-signature-solidity-code-example
            First 32 bytes stores the length of the signature

            add(sig, 32) = pointer of sig + 32
            effectively, skips first 32 bytes of signature

            mload(p) loads next 32 bytes starting at the memory address p into memory
            */

            // first 32 bytes, after the length prefix
            r := mload(add(signature, 32))
            // second 32 bytes
            s := mload(add(signature, 64))
            // final byte (first byte of the next 32 bytes)
            v := byte(0, mload(add(signature, 96)))
        }
        address signer = ecrecover(signedAuthorizationHash, v, r, s);
        require(signer != address(0), "ECDSA: invalid signature");
        return signer;
    }

    function verifyAuthorization(
        AuthTypes.SignedAuthorization calldata signedAuthorization,
        address sender,
        uint256 amount
    ) internal view returns (bool) {
        /*
            This is the naïve implementation of authorization verification.
            There is a signed auth and the transaction verifier checks the signature,
            decodes the authorization, and then checks if it's OK.

            A more interesting implementation would not use a VRC to specify a set of claims
            and then check if the transaction satisfies the claims, so the authorization is
            essentially private to the node beyond what's needed.
        */
        bytes32 signedAuthorizationHash = getAuthorizationHash(
            signedAuthorization.authorization
        );
        // TODO: try to take this out of memory (reduce gas)
        AuthTypes.BasicAuthorization memory authorization = abi.decode(
            signedAuthorization.authorization,
            (AuthTypes.BasicAuthorization)
        );

        address signer = recoverSigner(
            signedAuthorizationHash,
            signedAuthorization.signature
        );

        if (signer != owner() && signer != _accounts[sender].sponsor) {
            revert Unauthorized(
                "Authorization signer is not the owner or sponsor: "
            );
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

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal returns (bool) {
        _accounts[from].balance -= amount;
        _accounts[to].balance += amount;
        _accounts[from].nonce++;

        return true;
    }

    function transferWithAuthorization(
        address to,
        uint256 amount,
        AuthTypes.SignedAuthorization calldata authorization
    )
        external
        isRegisteredAccount(msg.sender)
        isRegisteredAccount(to)
        whenNotPaused
        returns (bool)
    {
        if (!verifyAuthorization(authorization, msg.sender, amount)) {
            revert InvalidAuthorization("Invalid authorization");
        }
        return _transfer(msg.sender, to, amount);
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
        whenNotPaused
        returns (bool)
    {
        if (!verifyAuthorization(authorization, from, amount)) {
            revert InvalidAuthorization("Invalid authorization");
        }
        if (_allowances[from][msg.sender] < amount) {
            revert InsufficientAllowance();
        }
        return _transfer(from, to, amount);
    }

    function approve(
        address spender,
        uint256 amount
    )
        external
        whenNotPaused
        isRegisteredAccount(msg.sender)
        isRegisteredAccount(spender)
        returns (bool)
    {
        _allowances[msg.sender][spender] = amount;
        return true;
    }

    function freeze(
        address account
    ) external isAuthorized(msg.sender, account) returns (bool) {
        _accounts[account].isFrozen = true;
        return true;
    }

    function unfreeze(
        address account
    ) external isAuthorized(msg.sender, account) returns (bool) {
        _accounts[account].isFrozen = false;
        emit Unfreeze(msg.sender, account);
        return true;
    }

    function mint(
        address to,
        uint256 amount
    ) external onlyOwner returns (bool) {
        supply += amount;
        _accounts[to].balance += amount;
        emit Mint(msg.sender, to, amount);
        return true;
    }

    function redeem(
        address to,
        uint256 amount
    )
        external
        whenNotPaused
        isRegisteredAccount(msg.sender)
        isAuthorized(to, msg.sender)
        returns (bool)
    {
        require(to != address(0), "Invalid recipient");
        require(
            amount <= _accounts[msg.sender].balance,
            "Insufficient balance to burn"
        );
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

    function seize(
        address seizeFrom,
        uint256 amount
    ) external isAuthorized(msg.sender, seizeFrom) returns (bool) {
        // TODO: Should this just seize all balance if this exceeds available balance?
        require(amount <= _accounts[seizeFrom].balance, "Insufficient balance");
        _accounts[seizeFrom].balance -= amount;
        // TODO: Is this the "legally correct" flow? Or does this need to send to a holding account?
        _accounts[seizeFrom].lockedBalance += amount;
        return true;
    }

    function releaseLockedBalance(
        address account,
        uint256 amount
    ) external isAuthorized(msg.sender, account) returns (bool) {
        require(
            amount <= _accounts[account].lockedBalance,
            "Insufficient locked balance"
        );
        _accounts[account].lockedBalance -= amount;
        _accounts[account].balance += amount;
        return true;
    }

    function seizeLockedBalance(
        address account,
        uint256 amount
    ) external isAuthorized(msg.sender, account) returns (bool) {
        require(
            amount <= _accounts[account].lockedBalance,
            "Insufficient locked balance"
        );
        _accounts[account].lockedBalance -= amount;
        _accounts[msg.sender].balance += amount;
        return true;
    }

    function setSponsor(
        address account,
        address sponsor
    ) external isRegisteredAccount(account) onlyOwner {
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

    // Add receive function to accept ETH
    receive() external payable {}
}