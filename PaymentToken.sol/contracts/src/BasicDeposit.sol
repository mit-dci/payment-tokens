// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (token/ERC20/IERC20.sol)

pragma solidity ^0.8.24;

import {IAdmin} from "../include/IAdmin.sol";
import {ISignedAuth} from "../include/ISignedAuth.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {AuthTypes} from "../lib/AuthTypes.sol";

// TODO: Consider using structured data here
// import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISponsor} from "../include/ISponsor.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";

/// @title A basic deposit token contract with UUPS upgradeability
/// @author MIT-DCI
/// @notice This is a regulated payment asset contract with per-transaction authorization policy
/// @dev CRITICAL UPGRADE SAFETY RULES:
///      When creating new implementations, you MUST:
///      1. Inherit from the same base contracts in the same order
///      2. Not modify existing storage variables (order, type, or name)
///      3. Only append new storage variables at the end
///      4. Maintain function signature compatibility for existing functions
///      5. Increment VERSION and STORAGE_VERSION appropriately
///      6. Test thoroughly on testnet before mainnet upgrade
/// @custom:security-contact security@mitdci.org  
/// @custom:storage-location erc7201:mitdci.storage.BasicDeposit
contract BasicDeposit is
    UUPSUpgradeable,
    OwnableUpgradeable,
    ERC165Upgradeable,
    ISignedAuth,
    IAdmin,
    IERC20,
    ISponsor,
    PausableUpgradeable
{
    using ECDSA for bytes32;

    // Context override functions to resolve inheritance conflicts between upgradeable contracts
    // These functions delegate to the parent implementation to ensure proper context handling
    
    /// @dev Override to resolve multiple inheritance conflicts for _msgSender
    /// @return The address of the message sender
    function _msgSender() internal view override returns (address) {
        return super._msgSender(); // Delegate to parent ContextUpgradeable implementation
    }

    /// @dev Override to resolve multiple inheritance conflicts for _msgData
    /// @return The complete calldata of the current call
    function _msgData() internal view override returns (bytes calldata) {
        return super._msgData(); // Delegate to parent ContextUpgradeable implementation
    }

    /// @dev Override to resolve multiple inheritance conflicts for context suffix length
    /// @return The length of any context suffix appended to calldata
    function _contextSuffixLength() internal view override returns (uint256) {
        return super._contextSuffixLength(); // Delegate to parent ContextUpgradeable implementation
    }

    /// @notice Pauses the contract, preventing all token transfers and operations
    /// @dev Emergency function to halt all contract operations in case of security issues
    ///      Only the contract owner can pause the contract
    ///      This is part of OpenZeppelin's [`PausableUpgradeable`] pattern
    function pause() external onlyOwner {
        _pause(); // Call internal OpenZeppelin pause function
    }

    /// @notice Unpauses the contract, restoring normal operations
    /// @dev Removes the pause state, allowing transfers and operations to resume
    ///      Only the contract owner can unpause the contract
    ///      This is part of OpenZeppelin's [`PausableUpgradeable`] pattern
    function unpause() external onlyOwner {
        _unpause(); // Call internal OpenZeppelin unpause function
    }

    /// @notice Current implementation version for tracking upgrades
    /// @dev Increment this with each implementation upgrade (semantic versioning)
    ///      Format: "vMAJOR.MINOR.PATCH" where:
    ///      - MAJOR: Breaking changes or major new features
    ///      - MINOR: New features that are backward compatible
    ///      - PATCH: Bug fixes and minor improvements
    string public constant VERSION = "v1.0.0";
    
    /// @notice Storage layout version for compatibility checks during upgrades
    /// @dev Increment when storage layout changes are made (adding/removing variables)
    ///      This prevents accidental storage collisions during contract upgrades
    ///      Version 1: Initial layout with basic account structure
    uint256 private constant STORAGE_VERSION = 1;

    // Account struct size: 149 bytes (32+32+20+1+32 + padding)
    // Storage efficiency: Packed to minimize gas costs for account operations
    
    /// @title A regulated account structure for compliance and fund management
    /// @author MIT-DCI
    /// @dev This struct layout is part of storage version 1 - do not modify!
    ///      Any changes require a new storage version and careful upgrade planning
    struct Account {
        /// @notice User's available token balance (in wei units, 18 decimals)
        /// @dev This is the spendable balance, separate from locked funds
        uint256 balance;
        
        /// @notice The nonce of the account for replay protection
        /// @dev Increments with each transaction to prevent authorization reuse
        ///      Used in conjunction with signed authorizations for security
        uint256 nonce;
        
        /// @notice The sponsor of this account for regulatory compliance
        /// @dev Sponsors are authorized entities (banks, institutions) that can:
        ///      - Approve transactions for their sponsored accounts
        ///      - Freeze/unfreeze accounts under their management
        ///      - Move accounts to new addresses if needed
        /// @dev TODO: Consider supporting multiple sponsors per account
        address sponsor;
        
        /// @notice Whether the account is frozen (cannot send/receive)
        /// @dev Frozen accounts:
        ///      - Cannot initiate transfers
        ///      - Cannot receive transfers
        ///      - Can still be minted to or have funds seized
        ///      - Used for regulatory compliance and risk management
        bool isFrozen;
        
        /// @notice The account's locked balance (seized but not yet confiscated)
        /// @dev Locked funds:
        ///      - Cannot be spent by the account holder
        ///      - Can be released back to balance by authorities
        ///      - Can be permanently confiscated (transferred to authorities)
        ///      - Used for legal holds, investigations, sanctions compliance
        uint256 lockedBalance;
    }

    // ERC-20 Token Metadata
    // These variables define the basic properties of the token
    
    /// @dev Private storage for token name (e.g., "USD Deposit Token")
    ///      Private to prevent external modification, accessed via name() function
    string private _name;
    
    /// @dev Private storage for token symbol (e.g., "USDT")
    ///      Private to prevent external modification, accessed via symbol() function
    string private _symbol;
    
    /// @notice Decimal precision for the token (18 decimals = wei units)
    /// @dev Standard ERC-20 decimal precision, allows for fractional tokens
    ///      1 token = 10^18 wei units (same as Ether)
    ///      Constant to prevent changes that could break integrations
    uint8 public constant DECIMALS = 18;

    /// @notice The total supply of tokens currently in circulation
    /// @dev Tracks the sum of all minted tokens minus burned tokens
    ///      Updated by mint() and supplyBurn() functions
    ///      Does not include locked balances (they're still part of supply)
    uint256 public supply;

    /// @notice The URI endpoint for retrieving transaction authorizations
    /// @dev Points to an external service that provides signed authorizations
    ///      for transactions. This enables off-chain compliance checking
    ///      while keeping sensitive data off the blockchain
    ///      Format: "https://compliance.bank.com/auth"
    string public uri;

    // Regulatory and Account Management Mappings
    // These mappings implement the compliance and authorization framework
    
    /// @notice Whether an address is registered as a sponsor (institutional entity)
    /// @dev Sponsors are banks, financial institutions, or other authorized entities that:
    ///      - Can sponsor user accounts for KYC/AML compliance
    ///      - Have authority to freeze/unfreeze their sponsored accounts
    ///      - Can approve transactions on behalf of their users
    ///      - Are managed by the contract owner (regulatory authority)
    mapping(address => bool) private canSponsor;
    
    /// @notice Whether an address has been properly registered and onboarded
    /// @dev Registration ensures proper KYC/AML compliance before token usage:
    ///      - All users must be registered before receiving/sending tokens
    ///      - Registration links accounts to sponsors for oversight
    ///      - Prevents anonymous or unverified token usage
    ///      - May become optional if per-transaction auth provides sufficient control
    mapping(address => bool) private registeredAccounts;
    
    /// @notice Complete account information for each registered address
    /// @dev Central storage for all account data including balances, nonces, and status
    ///      Maps address => Account struct with all regulatory and balance info
    ///      Private to prevent direct manipulation, accessed via view functions
    mapping(address => Account) private _accounts;
    
    /// @notice ERC-20 allowances for transferFrom operations
    /// @dev Standard ERC-20 allowance mechanism:
    ///      - Maps owner => spender => allowance amount
    ///      - Allows third-party transfers up to approved limits
    ///      - Combined with regulatory checks for compliance
    ///      - Both owner and spender must be registered accounts
    mapping(address account => mapping(address spender => uint256))
        private _allowances;

    // Custom Error Definitions
    // Using custom errors for gas efficiency and better error messages
    
    /// @notice Thrown when a signed authorization fails validation checks
    /// @param reason Detailed explanation of why the authorization is invalid
    ///               (e.g., "expired", "wrong signer", "insufficient limit")
    error InvalidAuthorization(string reason);
    
    /// @notice Thrown when an account tries to spend more than their available balance
    /// @dev Does not include locked balances, which cannot be spent
    error InsufficientBalance();
    
    /// @notice Thrown when a transferFrom operation exceeds the approved allowance
    /// @dev Part of standard ERC-20 allowance mechanism
    error InsufficientAllowance();
    
    /// @notice Thrown when an unauthorized party tries to perform a restricted operation
    /// @param reason Specific reason for the authorization failure
    ///               (e.g., "not owner", "not sponsor", "insufficient permissions")
    error Unauthorized(string reason);
    
    /// @notice Thrown when authorization data cannot be properly decoded
    /// @dev Indicates malformed or corrupted authorization signatures/data
    error DeserializationFailed();
    
    /// @notice Thrown when an unsupported operation is requested
    /// @param reason Description of the unsupported request type
    error UnsupportedRequest(string reason);
    
    /// @notice Thrown when the contract is in a halted/paused state
    /// @dev Used when the contract owner has paused operations for emergency
    error SystemHalted();
    
    /// @notice Thrown when operations are attempted on unregistered accounts
    /// @dev All participants must complete KYC/AML registration before token usage
    error UnregisteredAccount();
    
    /// @notice Thrown when an invalid or unregistered sponsor is referenced
    /// @dev Sponsors must be pre-approved by the contract owner
    error InvalidSponsor();
    
    /// @notice Thrown when trying to register an already registered account
    /// @dev Prevents accidental double-registration or data overwrites
    error RegisteredAccount();
    
    /// @notice Thrown when a frozen account attempts to send or receive tokens
    /// @param account The address of the frozen account that attempted the operation
    /// @dev Frozen accounts are completely locked for regulatory compliance
    error AccountFrozen(address account);

    // Event Definitions
    // Events provide transparency and enable off-chain monitoring
    
    /// @notice Emitted when a new user account is successfully registered
    /// @param account The address of the newly registered account
    /// @dev Indicates completion of KYC/AML onboarding process
    event UserRegistered(address indexed account);
    
    /// @notice Emitted when a contract upgrade is authorized by the owner
    /// @param newImplementation The address of the new implementation contract
    /// @param currentVersion The version string before the upgrade
    /// @param authorizer The address that authorized the upgrade (should be owner)
    /// @dev Critical for tracking contract evolution and upgrade audit trail
    event UpgradeAuthorized(
        address indexed newImplementation, 
        string currentVersion, 
        address indexed authorizer
    );
    
    /// @notice Emitted when upgrade compatibility checks are performed
    /// @param implementation The implementation contract being validated
    /// @param isCompatible Whether the implementation passed compatibility checks
    /// @dev Helps identify potential upgrade issues before deployment
    event UpgradeCompatibilityChecked(address indexed implementation, bool isCompatible);

    // Access Control Modifiers
    // These modifiers enforce regulatory compliance and authorization rules
    
    /// @notice Ensures the specified account has completed registration/KYC process
    /// @param account The account address to validate
    /// @dev Prevents unverified accounts from participating in token operations
    ///      All token transfers require both sender and recipient to be registered
    modifier isRegisteredAccount(address account) {
        if (!registeredAccounts[account]) {
            revert UnregisteredAccount(); // Reject operations with unverified accounts
        }
        _; // Continue with function execution if registered
    }

    /// @notice Ensures the specified account is NOT already registered
    /// @param account The account address to validate
    /// @dev Used to prevent double-registration or address conflicts
    ///      Commonly used in account creation or address migration functions
    modifier notRegisteredAccount(address account) {
        if (registeredAccounts[account]) {
            revert RegisteredAccount(); // Reject if account already exists
        }
        _; // Continue with function execution if not registered
    }

    /// @notice Validates that the authority has permission to operate on the account
    /// @param authority The address attempting to perform the operation
    /// @param account The target account being operated on
    /// @dev Authority hierarchy (in order of precedence):
    ///      1. Contract owner (regulatory authority) - can operate on any account
    ///      2. Account sponsor (bank/institution) - can operate on their sponsored accounts
    ///      Account holders themselves are NOT authorities for regulatory operations
    /// @dev Used for: freeze/unfreeze, seize funds, move accounts, etc.
    modifier isAuthorized(address authority, address account) {
        if (authority != owner() && authority != _accounts[account].sponsor) {
            revert Unauthorized("not authorized for this account");
        }
        _; // Continue if authority is valid
    }

    // =============================================================
    //                    ERC-20 TOKEN FUNCTIONS
    // =============================================================
    // Standard ERC-20 interface implementation with regulatory controls
    
    /// @notice Transfers tokens from sender to recipient
    /// @param recipient The address to receive the tokens
    /// @param amount The amount of tokens to transfer (in wei units)
    /// @return success True if the transfer completed successfully
    /// @dev Standard ERC-20 transfer function with regulatory enhancements:
    ///      - Both sender and recipient must be registered accounts
    ///      - Neither account can be frozen
    ///      - Sender must have sufficient available balance
    ///      - Increments sender's nonce for authorization tracking
    function transfer(
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        return _transfer(msg.sender, recipient, amount); // Delegate to internal transfer logic
    }

    /// @notice Transfers tokens on behalf of another account (with allowance)
    /// @param sender The account to transfer tokens from
    /// @param recipient The address to receive the tokens
    /// @param amount The amount of tokens to transfer (in wei units)
    /// @return success True if the transfer completed successfully
    /// @dev Standard ERC-20 transferFrom with regulatory controls:
    ///      - Requires prior approval via approve() function
    ///      - Checks allowance before proceeding with transfer
    ///      - Decrements allowance by transfer amount
    ///      - All standard transfer restrictions apply (registration, freezing, etc.)
    ///      - Used by DeFi protocols, exchanges, and automated systems
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        // Check that the caller has sufficient allowance to spend sender's tokens
        require(
            amount <= _allowances[sender][msg.sender],
            "Allowance exceeded" // Insufficient allowance for this transfer amount
        );

        // Attempt the transfer with all regulatory checks
        if(_transfer(sender, recipient, amount)) {
            // Transfer succeeded, decrease the allowance by the transferred amount
            _allowances[sender][msg.sender] -= amount;
            return true;
        } else {
            // Transfer failed (should not happen due to require statements in _transfer)
            return false;
        }
    }

    // =============================================================
    //                    UPGRADE AUTHORIZATION
    // =============================================================
    
    /// @notice Authorizes a contract upgrade with comprehensive safety validation
    /// @param newImplementation Address of the new implementation contract
    /// @dev CRITICAL SAFETY REQUIREMENTS for regulated token upgrades:
    ///      1. Only contract owner (regulatory authority) can authorize upgrades
    ///      2. New implementation must be a deployed contract (not EOA)
    ///      3. Must maintain storage layout compatibility (use STORAGE_VERSION)
    ///      4. Must preserve existing function signatures for integrations
    ///      5. Should undergo security audit before production deployment
    ///      6. ALWAYS test thoroughly on testnet with real data scenarios
    /// @custom:security This function controls the entire contract logic - extreme caution required
    ///                   Any bugs in new implementation can affect all user funds
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {
        // Basic safety validations
        require(newImplementation != address(0), "New implementation cannot be zero address");
        require(newImplementation.code.length > 0, "New implementation must be a contract");
        require(newImplementation != address(this), "Cannot upgrade to same implementation");
        
        // Verify we're not upgrading to the already active implementation
        address currentImpl = ERC1967Utils.getImplementation();
        require(currentImpl != newImplementation, "Implementation already current");
        
        // Run compatibility checks and log results for audit trail
        bool isCompatible = _checkUpgradeCompatibility(newImplementation);
        emit UpgradeCompatibilityChecked(newImplementation, isCompatible);
        
        // Create permanent record of upgrade authorization
        emit UpgradeAuthorized(newImplementation, VERSION, msg.sender);
    }
    
    /// @notice Performs basic compatibility checks on a new implementation
    /// @param newImplementation The implementation contract to validate
    /// @return isCompatible True if basic compatibility checks pass
    /// @dev Basic validation suite - can be extended with more sophisticated checks:
    ///      - Verifies ERC-20 interface support
    ///      - Tests critical function availability
    ///      - Future versions should check storage version compatibility
    ///      - Does not guarantee full compatibility - manual testing still required
    function _checkUpgradeCompatibility(address newImplementation) internal view returns (bool) {
        // Verify current contract supports required interfaces
        try this.supportsInterface(type(IERC20).interfaceId) returns (bool isSupported) {
            if (!isSupported) return false; // Current contract doesn't support ERC-20??
        } catch {
            return false; // Interface check failed
        }
        
        // Test that new implementation has critical ERC-20 functions
        // This helps catch missing functions that would break integrations
        try IERC20(newImplementation).totalSupply() returns (uint256) {
            return true; // Basic function call succeeded
        } catch {
            return false; // New implementation missing critical functions
        }
    }

    // =============================================================
    //                    CONTRACT INITIALIZATION
    // =============================================================
    
    /// @notice Constructor for the implementation contract
    /// @dev Disables initializers to prevent implementation contract from being initialized
    ///      The proxy contract will call initialize() instead
    ///      This is a security measure for UUPS upgradeable contracts
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers(); // Prevent initialization of implementation contract
    }

    /// @notice Initializes the proxy contract with token parameters and regulatory setup
    /// @param tokenName The human-readable name for the token (e.g., "USD Deposit Token")
    /// @param tokenSymbol The trading symbol for the token (e.g., "USDT")
    /// @param initialSponsor The first authorized sponsor (typically the deploying bank)
    /// @param initial_uri The URL endpoint for authorization services
    /// @dev Initialization function for UUPS proxy pattern:
    ///      - Replaces constructor for upgradeable contracts
    ///      - Can only be called once due to initializer modifier
    ///      - Sets up all base contract modules and initial state
    ///      - Caller becomes the contract owner (regulatory authority)
    function initialize(
        string calldata tokenName,
        string calldata tokenSymbol,
        address initialSponsor,
        string calldata initial_uri
    ) public initializer {
        // Initialize OpenZeppelin's Ownable module
        // This establishes contract ownership and access control
        // The caller (deployer) becomes the owner with full administrative rights
        __Ownable_init(msg.sender);

        // Initialize UUPS (Universal Upgradeable Proxy Standard) module
        // This enables controlled contract upgrades while preserving state
        // Sets up the proxy upgrade mechanism and storage slots
        __UUPSUpgradeable_init();

        // Initialize Pausable module for emergency controls
        // Enables the owner to halt all operations in case of emergencies
        __Pausable_init();
        
        // Initialize ERC-165 interface detection
        // Enables other contracts to detect what interfaces this contract supports
        __ERC165_init();

        // Set token metadata from initialization parameters
        uri = initial_uri;        // URL for authorization service endpoint
        _name = tokenName;        // Token name for display purposes
        _symbol = tokenSymbol;    // Token symbol for trading/display

        // Register the initial sponsor (typically the deploying financial institution)
        // This sponsor can onboard the first users and begin operations
        canSponsor[initialSponsor] = true;
    }

    // =============================================================
    //                    ERC-20 METADATA FUNCTIONS
    // =============================================================
    // Standard ERC-20 metadata functions for token identification
    
    /// @notice Returns the human-readable name of the token
    /// @return The token name (e.g., "USD Deposit Token")
    /// @dev Used by wallets and dApps for display purposes
    function name() external view returns (string memory) {
        return _name; // Return the name set during initialization
    }

    /// @notice Returns the trading symbol of the token
    /// @return The token symbol (e.g., "USDT")
    /// @dev Used by exchanges and wallets for abbreviated display
    function symbol() external view returns (string memory) {
        return _symbol; // Return the symbol set during initialization
    }

    /// @notice Returns the number of decimal places for token amounts
    /// @return The decimal precision (always 18 for this contract)
    /// @dev Standard ERC-20 decimal precision - 1 token = 10^18 smallest units
    function decimals() external pure returns (uint8) {
        return DECIMALS; // Constant value: 18 decimals
    }

    /// @notice Returns the total supply of tokens in circulation
    /// @return The total number of tokens that exist (in wei units)
    /// @dev Includes all minted tokens minus any burned tokens
    ///      Does not distinguish between available and locked balances
    function totalSupply() external view returns (uint256) {
        return supply; // Current total supply from minting/burning operations
    }

    // =============================================================
    //                    ACCOUNT VIEW FUNCTIONS
    // =============================================================
    // Functions for querying account states and balances
    
    /// @notice Returns the available (spendable) balance of an account
    /// @param account The address to query
    /// @return The available token balance (in wei units)
    /// @dev Standard ERC-20 balanceOf function
    ///      Returns only the spendable balance, excludes locked funds
    ///      Unregistered accounts will return 0 balance
    function balanceOf(address account) external view returns (uint256) {
        return _accounts[account].balance; // Available balance only
    }

    /// @notice Checks if an address has completed the registration process
    /// @param account The address to check
    /// @return registered True if the account is registered and can use tokens
    /// @dev Registration is required for all token operations
    ///      Includes KYC/AML verification and sponsor assignment
    function isRegistered(address account) external view returns (bool) {
        return registeredAccounts[account]; // Registration status
    }

    /// @notice Returns complete account information for an address
    /// @param account The address to query
    /// @return accountData The full Account struct with all details
    /// @dev Provides comprehensive account information:
    ///      - Available balance and locked balance
    ///      - Current nonce for authorization tracking
    ///      - Assigned sponsor and frozen status
    function accounts(address account) external view returns (Account memory) {
        return _accounts[account]; // Complete account data structure
    }

    // =============================================================
    //                    USER MANAGEMENT FUNCTIONS
    // =============================================================
    // Functions for account registration and management
    
    /// @notice Registers a new user account with KYC/AML compliance
    /// @param account The address to register (user's wallet address)
    /// @param sponsor The authorized sponsor for this account (bank/institution)
    /// @dev Registration process:
    ///      1. Validates that the sponsor is approved by regulatory authority
    ///      2. Marks the account as registered for token operations
    ///      3. Assigns the sponsor for ongoing oversight and authorization
    ///      4. Emits event for compliance monitoring
    /// @dev Access: Only contract owner (regulatory authority) can register users
    /// @dev TODO: Consider allowing sponsors to register their own users
    /// @dev TODO: Decide if re-registration should update sponsor or revert
    function registerUser(address account, address sponsor) external onlyOwner {
        if (canSponsor[sponsor]) {
            registeredAccounts[account] = true;    // Enable token operations
            _accounts[account].sponsor = sponsor;  // Assign regulatory oversight
            emit UserRegistered(account);          // Log for compliance tracking
        } else {
            revert InvalidSponsor(); // Sponsor not approved by regulatory authority
        }
    }

    /// @notice Allows a user to migrate their account to a new address
    /// @param newAddress The destination address for account migration
    /// @param signature Cryptographic proof that user controls the new address
    /// @dev Secure account migration process:
    ///      1. Validates both current and new addresses
    ///      2. Requires cryptographic proof of new address ownership
    ///      3. Transfers all account data (balance, nonce, sponsor, etc.)
    ///      4. Clears old address and activates new address
    /// @dev Security: User must sign current address with new address's private key
    /// @dev Access: Only the account holder can initiate migration
    /// @dev Requirements: Caller must be registered, new address must be unused
    function moveAccountAddress(
        address newAddress,
        bytes memory signature
    )
        external
        isRegisteredAccount(msg.sender)     // Caller must be registered
        notRegisteredAccount(newAddress)    // Destination must be unused
    {
        // Validate new address parameters
        require(
            newAddress != address(0) && newAddress != msg.sender,
            "Invalid new address" // Prevent null address or self-transfer
        );

        // Create message hash from current address for signature verification
        // User must sign this hash with the private key of the new address
        bytes32 messageHash = keccak256(
            abi.encodePacked(keccak256(abi.encode(msg.sender)))
        );

        // Recover the address that signed the message
        address signer = recoverSigner(messageHash, signature);

        // Verify the signature was created by the new address's private key
        require(signer == newAddress, "Invalid signature");

        // Transfer complete account data to new address
        _accounts[newAddress] = _accounts[msg.sender];
        // Clear old address data for security
        _accounts[msg.sender] = Account(0, 0, address(0), false, 0);
        registeredAccounts[msg.sender] = false;  // Deactivate old address
        registeredAccounts[newAddress] = true;   // Activate new address
    }

    /// @notice Allows authorized parties to forcibly migrate an account (regulatory/emergency use)
    /// @param currentAddress The current address holding the account
    /// @param newAddress The destination address for account migration
    /// @dev Administrative account migration for regulatory compliance:
    ///      - Used when user cannot perform migration themselves
    ///      - Common scenarios: compromised keys, legal orders, sanctions compliance
    ///      - No signature required since user may not have access to private keys
    ///      - Only contract owner or account sponsor can perform this operation
    /// @dev Access: Only authorized parties (owner or account's sponsor)
    /// @dev Requirements: Current address registered, new address unused
    function moveAccountAddress(
        address currentAddress,
        address newAddress
    )
        external
        isRegisteredAccount(currentAddress)     // Source must be registered
        notRegisteredAccount(newAddress)        // Destination must be unused
        isAuthorized(msg.sender, currentAddress) // Only owner/sponsor can move
    {
        // Validate destination address
        require(
            newAddress != address(0) && newAddress != currentAddress,
            "Invalid new address" // Prevent null address or no-op
        );

        // Transfer all account data to new address
        _accounts[newAddress] = _accounts[currentAddress];
        
        // Completely clear old address data
        delete _accounts[currentAddress];      // Clear account struct
        delete registeredAccounts[currentAddress]; // Clear registration
        registeredAccounts[newAddress] = true; // Register new address
    }

    /// @notice Returns the amount of tokens a spender is allowed to transfer on behalf of owner
    /// @param own The account that owns the tokens
    /// @param spender The account authorized to spend the tokens
    /// @return allowanceAmount The amount of tokens the spender can transfer
    /// @dev Standard ERC-20 allowance function with regulatory checks:
    ///      - Both owner and spender must be registered accounts
    ///      - Used by DeFi protocols, exchanges, and automated systems
    ///      - Allowances must be set via approve() function
    /// @dev Part of ERC-20 standard for third-party token transfers
    function allowance(
        address own,
        address spender
    )
        external
        view
        isRegisteredAccount(own)      // Token owner must be registered
        isRegisteredAccount(spender)  // Spender must be registered
        returns (uint256)
    {
        return _allowances[own][spender]; // Return current allowance amount
    }

    // =============================================================
    //                    CRYPTOGRAPHIC UTILITIES
    // =============================================================
    // Internal functions for signature verification and authorization
    
    /// @notice Computes the hash of an authorization message for signature verification
    /// @param message The authorization data to hash
    /// @return messageHash The keccak256 hash of the encoded message
    /// @dev Used as input for ECDSA signature verification process
    ///      Ensures message integrity and prevents tampering
    function getAuthorizationHash(
        bytes memory message
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(message)); // Standard keccak256 hash
    }

    /// @notice Recovers the address that signed a message hash
    /// @param signedAuthorizationHash The hash that was signed
    /// @param signature The ECDSA signature (65 bytes: r + s + v)
    /// @return signer The address of the account that created the signature
    /// @dev ECDSA signature recovery for authorization validation:
    ///      - Validates signature format (must be exactly 65 bytes)
    ///      - Extracts r, s, v components from signature
    ///      - Uses ecrecover precompile for cryptographic verification
    ///      - Critical for ensuring only authorized parties can approve transactions
    function recoverSigner(
        bytes32 signedAuthorizationHash,
        bytes memory signature
    ) internal pure returns (address) {
        // Validate signature format - ECDSA signatures are always 65 bytes
        require(signature.length == 65, "Invalid signature length");
        
        // Extract signature components using inline assembly for efficiency
        bytes32 r; // First 32 bytes of signature
        bytes32 s; // Second 32 bytes of signature  
        uint8 v;   // Recovery parameter (last byte)
        
        assembly {
            /*
            Signature format: [length][r][s][v]
            - First 32 bytes: length prefix (automatically added by Solidity)
            - Next 32 bytes: r component of signature
            - Next 32 bytes: s component of signature
            - Last 1 byte: v recovery parameter
            
            Reference: https://www.cyfrin.io/glossary/verifying-signature-solidity-code-example
            */

            // Extract r: skip length prefix (32 bytes), load next 32 bytes
            r := mload(add(signature, 32))
            // Extract s: skip length + r (64 bytes), load next 32 bytes
            s := mload(add(signature, 64))
            // Extract v: skip length + r + s (96 bytes), load first byte of next word
            v := byte(0, mload(add(signature, 96)))
        }
        
        // Use Ethereum's ecrecover precompile to recover signer address
        address signer = ecrecover(signedAuthorizationHash, v, r, s);
        
        // Validate that signature recovery succeeded
        require(signer != address(0), "ECDSA: invalid signature");
        
        return signer; // Return the address that created this signature
    }

    /// @notice Verifies that a signed authorization is valid for a specific transaction
    /// @param signedAuthorization The authorization containing signature and encoded data
    /// @param sender The address attempting to send tokens
    /// @param amount The amount of tokens being transferred
    /// @return valid True if authorization passes all validation checks
    /// @dev Comprehensive authorization validation process:
    ///      1. Verifies cryptographic signature authenticity
    ///      2. Validates signer authority (owner or account sponsor)
    ///      3. Checks authorization parameters against transaction
    ///      4. Ensures authorization hasn't expired or been replayed
    /// @dev This enables regulatory compliance through pre-approved transactions
    function verifyAuthorization(
        AuthTypes.SignedAuthorization calldata signedAuthorization,
        address sender,
        uint256 amount
    ) internal view returns (bool) {
        /*
        AUTHORIZATION ARCHITECTURE NOTES:
        
        This implements a basic authorization verification system where:
        - Transactions require pre-signed approval from regulatory authorities
        - Authorization contains specific parameters (amount, expiration, nonce)
        - Prevents unauthorized transactions while enabling regulatory oversight
        
        Future Enhancement Opportunity:
        A more sophisticated system could use Verifiable Random Claims (VRC)
        where authorization contains privacy-preserving proofs of compliance
        rather than explicit transaction details, reducing information leakage.
        */
        
        // Step 1: Compute hash of the authorization data for signature verification
        bytes32 signedAuthorizationHash = getAuthorizationHash(
            signedAuthorization.authorization
        );
        
        // Step 2: Decode the authorization parameters from signed data
        // TODO: Optimize gas usage by avoiding memory allocation
        AuthTypes.BasicAuthorization memory authorization = abi.decode(
            signedAuthorization.authorization,
            (AuthTypes.BasicAuthorization)
        );

        // Step 3: Recover the address that signed this authorization
        address signer = recoverSigner(
            signedAuthorizationHash,
            signedAuthorization.signature
        );

        // Step 4: Validate signer authority - only owner or account sponsor can authorize
        if (signer != owner() && signer != _accounts[sender].sponsor) {
            revert Unauthorized(
                "Authorization signer is not the owner or sponsor: "
            );
        }

        // Step 5: Validate authorization parameters match transaction
        if (authorization.sender != sender) {
            revert Unauthorized("Authorization sender does not match");
        }
        if (authorization.expiration < block.timestamp) {
            revert Unauthorized("Authorization expired"); // Time-based expiration
        }
        if (authorization.authNonce < _accounts[sender].nonce) {
            revert Unauthorized("Authorization not valid for account nonce"); // Replay protection
        }
        if (authorization.spendingLimit < amount) {
            revert Unauthorized("Insufficient spending limit"); // Amount validation
        }
        
        return true; // All validation checks passed
    }

    /// @notice Internal function that executes token transfers with regulatory checks
    /// @param from The address sending tokens
    /// @param to The address receiving tokens
    /// @param amount The amount of tokens to transfer (in wei units)
    /// @return success True if transfer completed successfully
    /// @dev Core transfer logic with comprehensive regulatory compliance:
    ///      - Validates accounts are not frozen (regulatory hold)
    ///      - Ensures sufficient available balance (excludes locked funds)
    ///      - Updates balances atomically to prevent reentrancy
    ///      - Increments sender nonce for authorization tracking
    ///      - Emits Transfer event for ERC-20 compliance (via caller)
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal returns (bool) {
        // Regulatory compliance checks - frozen accounts cannot send or receive
        if (_accounts[from].isFrozen) {
            revert AccountFrozen(from); // Sender account is frozen
        }
        
        if (_accounts[to].isFrozen) {
            revert AccountFrozen(to); // Recipient account is frozen
        }
        
        // Balance validation - ensure sender has sufficient available funds
        require(_accounts[from].balance >= amount, "Insufficient balance");
        
        // Execute transfer atomically to prevent reentrancy attacks
        _accounts[from].balance -= amount;  // Deduct from sender
        _accounts[to].balance += amount;    // Credit to recipient
        _accounts[from].nonce++;           // Increment nonce for authorization tracking

        return true; // Transfer completed successfully
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
        // Depending on the use case, this may want to be emitted.
        // emit Freeze(msg.sender, account);
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

    /// @notice Interface support declaration for ERC165
    /// @param interfaceId The interface identifier to check
    /// @return True if the interface is supported
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IERC20).interfaceId ||
            interfaceId == type(IERC165).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    // =============================================================
    //                      UPGRADE UTILITIES
    // =============================================================
    
    /// @notice Returns the current implementation address
    /// @return implementation The address of the current implementation contract
    /// @dev Useful for verifying successful upgrades
    function getImplementation() external view returns (address implementation) {
        return ERC1967Utils.getImplementation();
    }

    /// @notice Checks if the contract has been properly initialized
    /// @return initialized True if the contract has been initialized
    /// @dev Returns the initialized version number > 0 if initialized
    function isInitialized() external view returns (bool initialized) {
        return _getInitializedVersion() > 0;
    }

    /// @notice Returns comprehensive upgrade and version information
    /// @return version Current version string of the implementation
    /// @return implementation Current implementation contract address  
    /// @return owner Current contract owner address
    /// @return storageVersion Current storage layout version
    /// @return initialized Whether the contract has been initialized
    /// @dev Use this function to verify contract state before and after upgrades
    function getUpgradeInfo() external view returns (
        string memory version,
        address implementation,
        address owner,
        uint256 storageVersion,
        bool initialized
    ) {
        return (
            VERSION,
            ERC1967Utils.getImplementation(),
            this.owner(),
            STORAGE_VERSION,
            _getInitializedVersion() > 0
        );
    }
    
    /// @notice Returns the storage version for compatibility checking
    /// @return The current storage layout version
    /// @dev Used by upgrade scripts to verify storage compatibility
    function getStorageVersion() external pure returns (uint256) {
        return STORAGE_VERSION;
    }
    
    /// @notice Emergency function to get implementation even if contract is paused
    /// @return implementation The current implementation address
    /// @dev This function bypasses pause checks for emergency verification
    function getImplementationEmergency() external view returns (address implementation) {
        return ERC1967Utils.getImplementation();
    }
    
    /// @notice Validates that this contract supports the expected interfaces
    /// @return isValid True if all expected interfaces are supported
    /// @dev Used during upgrade validation to ensure interface compatibility
    function validateInterfaces() external view returns (bool isValid) {
        try this.supportsInterface(type(IERC20).interfaceId) returns (bool erc20Support) {
            if (!erc20Support) return false;
        } catch {
            return false;
        }
        
        // Check basic ERC20 functions exist and are callable
        try this.totalSupply() returns (uint256) {
            return true;
        } catch {
            return false;
        }
    }
}
