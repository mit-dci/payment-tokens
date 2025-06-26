// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC7579Validator, IERC7579Module} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

uint256 constant MODULE_TYPE_VALIDATOR = 1;
uint256 constant VALIDATION_SUCCESS = 0;
uint256 constant VALIDATION_FAILED = 1;

/// @title Regulatory Compliance Validator Module
/// @author MIT-DCI
/// @notice ERC-7579 validator module implementing regulatory compliance for deposit tokens
contract RegulatoryValidator is IERC7579Validator {
    using ECDSA for bytes32;

    struct AuthorizedSigner {
        bool isAuthorized;
        uint256 authLevel; // 0: User, 1: Sponsor, 2: Regulator
        uint256 validUntil;
        uint256 nonce;
    }

    struct ComplianceRule {
        bool isActive;
        uint256 dailyLimit;
        uint256 monthlyLimit;
        bytes32 jurisdictionCode;
        bool requiresAuthorization;
    }

    // Account state
    mapping(address account => mapping(address signer => AuthorizedSigner)) private _authorizedSigners;
    mapping(address account => ComplianceRule) private _complianceRules;
    mapping(address account => address) private _accountSponsors;
    mapping(address account => bool) private _frozenAccounts;
    mapping(address account => uint256) private _accountNonces;
    
    // Daily/Monthly tracking
    mapping(address account => mapping(uint256 day => uint256 amount)) private _dailySpent;
    mapping(address account => mapping(uint256 month => uint256 amount)) private _monthlySpent;
    
    // Regulatory authority
    address private _regulatoryAuthority;
    mapping(address => bool) private _approvedSponsors;
    
    // Events
    event SignerAuthorized(address indexed account, address indexed signer, uint256 authLevel);
    event SignerRevoked(address indexed account, address indexed signer);
    event ComplianceRuleUpdated(address indexed account, uint256 dailyLimit, uint256 monthlyLimit);
    event AccountFrozen(address indexed account, address indexed authority);
    event AccountUnfrozen(address indexed account, address indexed authority);
    event SuspiciousActivity(address indexed account, string reason);

    // Errors
    error UnauthorizedSigner(address signer);
    error AccountIsFrozen(address account);
    error ComplianceViolation(string reason);
    error InvalidAuthLevel(uint256 level);
    error ExpiredAuthorization();
    error InvalidNonce(uint256 expected, uint256 provided);
    error DailyLimitExceeded(uint256 limit, uint256 attempted);
    error MonthlyLimitExceeded(uint256 limit, uint256 attempted);

    modifier onlyRegulatoryAuthority() {
        require(msg.sender == _regulatoryAuthority, "Not regulatory authority");
        _;
    }

    modifier onlyAuthorizedForAccount(address account) {
        require(
            msg.sender == _regulatoryAuthority ||
            msg.sender == _accountSponsors[account] ||
            _authorizedSigners[account][msg.sender].isAuthorized,
            "Not authorized for account"
        );
        _;
    }

    constructor(address regulatoryAuthority) {
        _regulatoryAuthority = regulatoryAuthority;
    }

    // =============================================================
    //                    ERC-7579 MODULE INTERFACE
    // =============================================================

    function onInstall(bytes calldata data) external {
        if (data.length > 0) {
            (address[] memory sponsors, address[] memory accounts, address[] memory accountSponsors) = 
                abi.decode(data, (address[], address[], address[]));
            
            // Set up initial sponsors
            for (uint256 i = 0; i < sponsors.length; i++) {
                _approvedSponsors[sponsors[i]] = true;
            }
            
            // Set up initial account sponsors
            for (uint256 i = 0; i < accounts.length; i++) {
                _accountSponsors[accounts[i]] = accountSponsors[i];
                
                // Set default compliance rules
                _complianceRules[accounts[i]] = ComplianceRule({
                    isActive: true,
                    dailyLimit: 10000 * 1e18, // 10,000 tokens
                    monthlyLimit: 100000 * 1e18, // 100,000 tokens
                    jurisdictionCode: keccak256("DEFAULT"),
                    requiresAuthorization: true
                });
            }
        }
    }

    function onUninstall(bytes calldata) external {
        // Clean up can be implemented here if needed
        // For security, we don't automatically clear all data
    }

    function isModuleType(uint256 moduleTypeId) external pure returns (bool) {
        return moduleTypeId == MODULE_TYPE_VALIDATOR;
    }

    // =============================================================
    //                    ERC-7579 VALIDATOR INTERFACE
    // =============================================================

    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash
    ) external returns (uint256) {
        return _validateSignature(userOp.sender, userOpHash, userOp.signature) ? 
               VALIDATION_SUCCESS : VALIDATION_FAILED;
    }

    function isValidSignatureWithSender(
        address sender,
        bytes32 hash,
        bytes calldata signature
    ) external view returns (bytes4) {
        if (_validateSignature(sender, hash, signature)) {
            return IERC1271.isValidSignature.selector;
        }
        return 0xffffffff;
    }

    function _validateSignature(
        address account,
        bytes32 hash,
        bytes calldata signature
    ) internal view returns (bool) {
        // Check if account is frozen
        if (_frozenAccounts[account]) {
            return false;
        }

        // Recover signer from signature
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(hash);
        address signer = ECDSA.recover(ethSignedHash, signature);

        // Check authorization hierarchy
        if (signer == _regulatoryAuthority) {
            return true; // Regulatory authority can always sign
        }

        if (signer == _accountSponsors[account]) {
            return true; // Account sponsor can sign
        }

        // Check if signer is explicitly authorized for this account
        AuthorizedSigner memory authSigner = _authorizedSigners[account][signer];
        if (authSigner.isAuthorized && authSigner.validUntil > block.timestamp) {
            return true;
        }

        return false;
    }

    // =============================================================
    //                    REGULATORY FUNCTIONS
    // =============================================================

    function authorizeSigner(
        address account,
        address signer,
        uint256 authLevel,
        uint256 validUntil
    ) external onlyAuthorizedForAccount(account) {
        if (authLevel > 2) {
            revert InvalidAuthLevel(authLevel);
        }

        _authorizedSigners[account][signer] = AuthorizedSigner({
            isAuthorized: true,
            authLevel: authLevel,
            validUntil: validUntil,
            nonce: 0
        });

        emit SignerAuthorized(account, signer, authLevel);
    }

    function revokeSigner(address account, address signer) external onlyAuthorizedForAccount(account) {
        _authorizedSigners[account][signer].isAuthorized = false;
        emit SignerRevoked(account, signer);
    }

    function setComplianceRules(
        address account,
        uint256 dailyLimit,
        uint256 monthlyLimit,
        bytes32 jurisdictionCode,
        bool requiresAuthorization
    ) external onlyRegulatoryAuthority {
        _complianceRules[account] = ComplianceRule({
            isActive: true,
            dailyLimit: dailyLimit,
            monthlyLimit: monthlyLimit,
            jurisdictionCode: jurisdictionCode,
            requiresAuthorization: requiresAuthorization
        });

        emit ComplianceRuleUpdated(account, dailyLimit, monthlyLimit);
    }

    function freezeAccount(address account) external onlyRegulatoryAuthority {
        _frozenAccounts[account] = true;
        emit AccountFrozen(account, msg.sender);
    }

    function unfreezeAccount(address account) external onlyRegulatoryAuthority {
        _frozenAccounts[account] = false;
        emit AccountUnfrozen(account, msg.sender);
    }

    function setSponsor(address account, address sponsor) external onlyRegulatoryAuthority {
        require(_approvedSponsors[sponsor], "Invalid sponsor");
        _accountSponsors[account] = sponsor;
    }

    function addApprovedSponsor(address sponsor) external onlyRegulatoryAuthority {
        _approvedSponsors[sponsor] = true;
    }

    function removeApprovedSponsor(address sponsor) external onlyRegulatoryAuthority {
        _approvedSponsors[sponsor] = false;
    }

    // =============================================================
    //                    COMPLIANCE VALIDATION
    // =============================================================

    function validateTransaction(
        address account,
        uint256 amount,
        address recipient,
        bytes calldata context
    ) external returns (bool) {
        ComplianceRule memory rules = _complianceRules[account];
        
        if (!rules.isActive) {
            return true; // No rules active
        }

        if (_frozenAccounts[account]) {
            revert AccountIsFrozen(account);
        }

        // Check daily limits
        uint256 today = block.timestamp / 86400; // Days since epoch
        uint256 dailySpent = _dailySpent[account][today];
        if (dailySpent + amount > rules.dailyLimit) {
            revert DailyLimitExceeded(rules.dailyLimit, dailySpent + amount);
        }

        // Check monthly limits
        uint256 thisMonth = block.timestamp / (86400 * 30); // Approximate months
        uint256 monthlySpent = _monthlySpent[account][thisMonth];
        if (monthlySpent + amount > rules.monthlyLimit) {
            revert MonthlyLimitExceeded(rules.monthlyLimit, monthlySpent + amount);
        }

        // Update spending tracking
        _dailySpent[account][today] = dailySpent + amount;
        _monthlySpent[account][thisMonth] = monthlySpent + amount;

        // Check for suspicious patterns
        _checkSuspiciousActivity(account, amount, recipient);

        return true;
    }

    function _checkSuspiciousActivity(
        address account,
        uint256 amount,
        address recipient
    ) internal {
        // Simple suspicious activity detection
        ComplianceRule memory rules = _complianceRules[account];
        
        // Large transaction warning
        if (amount > rules.dailyLimit / 2) {
            emit SuspiciousActivity(account, "Large transaction");
        }

        // Rapid transaction pattern (simplified)
        uint256 today = block.timestamp / 86400;
        if (_dailySpent[account][today] > rules.dailyLimit * 80 / 100) {
            emit SuspiciousActivity(account, "Approaching daily limit");
        }
    }

    // =============================================================
    //                    VIEW FUNCTIONS
    // =============================================================

    function getAuthorizedSigner(
        address account,
        address signer
    ) external view returns (AuthorizedSigner memory) {
        return _authorizedSigners[account][signer];
    }

    function getComplianceRules(address account) external view returns (ComplianceRule memory) {
        return _complianceRules[account];
    }

    function getAccountSponsor(address account) external view returns (address) {
        return _accountSponsors[account];
    }

    function isAccountFrozen(address account) external view returns (bool) {
        return _frozenAccounts[account];
    }

    function getDailySpent(address account, uint256 day) external view returns (uint256) {
        return _dailySpent[account][day];
    }

    function getMonthlySpent(address account, uint256 month) external view returns (uint256) {
        return _monthlySpent[account][month];
    }

    function getCurrentDailySpent(address account) external view returns (uint256) {
        uint256 today = block.timestamp / 86400;
        return _dailySpent[account][today];
    }

    function getCurrentMonthlySpent(address account) external view returns (uint256) {
        uint256 thisMonth = block.timestamp / (86400 * 30);
        return _monthlySpent[account][thisMonth];
    }

    function getRegulatoryAuthority() external view returns (address) {
        return _regulatoryAuthority;
    }

    function isApprovedSponsor(address sponsor) external view returns (bool) {
        return _approvedSponsors[sponsor];
    }
}