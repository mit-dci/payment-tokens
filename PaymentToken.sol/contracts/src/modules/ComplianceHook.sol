// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC7579Hook, IERC7579Module} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";

uint256 constant MODULE_TYPE_HOOK = 4;

/// @title Compliance Monitoring Hook Module
/// @author MIT-DCI
/// @notice ERC-7579 hook module for real-time compliance monitoring and reporting
contract ComplianceHook is IERC7579Hook {
    
    struct TransactionRecord {
        address from;
        address to;
        uint256 amount;
        uint256 timestamp;
        bytes32 transactionHash;
        bool flagged;
    }

    struct RiskProfile {
        uint256 riskScore; // 0-100, 100 being highest risk
        uint256 lastUpdated;
        uint256 suspiciousTransactionCount;
        uint256 totalTransactionCount;
        bool isHighRisk;
    }

    struct ComplianceReport {
        uint256 reportId;
        address account;
        string violationType;
        uint256 severity; // 1-5, 5 being most severe
        uint256 timestamp;
        bytes details;
        bool resolved;
    }

    // State variables
    mapping(address => RiskProfile) private _riskProfiles;
    mapping(address => TransactionRecord[]) private _transactionHistory;
    mapping(uint256 => ComplianceReport) private _complianceReports;
    
    address private _complianceOfficer;
    address private _regulatoryAuthority;
    
    uint256 private _nextReportId;
    uint256 public constant MAX_TRANSACTION_HISTORY = 1000;
    uint256 public constant RISK_THRESHOLD = 70;
    uint256 public constant SUSPICIOUS_AMOUNT_THRESHOLD = 50000 * 1e18; // 50,000 tokens
    
    // Velocity tracking
    mapping(address => mapping(uint256 => uint256)) private _hourlyVolume;
    mapping(address => mapping(uint256 => uint256)) private _dailyVolume;
    
    // Events
    event TransactionMonitored(
        address indexed from,
        address indexed to,
        uint256 amount,
        uint256 riskScore,
        bool flagged
    );
    event RiskProfileUpdated(address indexed account, uint256 oldScore, uint256 newScore);
    event ComplianceViolation(
        uint256 indexed reportId,
        address indexed account,
        string violationType,
        uint256 severity
    );
    event HighRiskActivity(address indexed account, string reason, uint256 riskScore);
    event VelocityAlert(address indexed account, uint256 volume, uint256 timeframe);

    // Errors
    error UnauthorizedAccess();
    error InvalidRiskScore(uint256 score);
    error InvalidSeverity(uint256 severity);
    error ReportNotFound(uint256 reportId);

    modifier onlyAuthorized() {
        require(
            msg.sender == _complianceOfficer || 
            msg.sender == _regulatoryAuthority,
            "Unauthorized access"
        );
        _;
    }

    constructor(address complianceOfficer, address regulatoryAuthority) {
        _complianceOfficer = complianceOfficer;
        _regulatoryAuthority = regulatoryAuthority;
        _nextReportId = 1;
    }

    // =============================================================
    //                    ERC-7579 MODULE INTERFACE
    // =============================================================

    function onInstall(bytes calldata data) external {
        if (data.length > 0) {
            (address[] memory accounts, uint256[] memory initialRiskScores) = 
                abi.decode(data, (address[], uint256[]));
            
            require(accounts.length == initialRiskScores.length, "Array length mismatch");
            
            for (uint256 i = 0; i < accounts.length; i++) {
                _riskProfiles[accounts[i]] = RiskProfile({
                    riskScore: initialRiskScores[i],
                    lastUpdated: block.timestamp,
                    suspiciousTransactionCount: 0,
                    totalTransactionCount: 0,
                    isHighRisk: initialRiskScores[i] >= RISK_THRESHOLD
                });
            }
        }
    }

    function onUninstall(bytes calldata) external {
        // Generate final compliance report before uninstall
        _generateFinalComplianceReport();
    }

    function isModuleType(uint256 moduleTypeId) external pure returns (bool) {
        return moduleTypeId == MODULE_TYPE_HOOK;
    }

    // =============================================================
    //                    ERC-7579 HOOK INTERFACE
    // =============================================================

    function preCheck(
        address msgSender,
        uint256 value,
        bytes calldata msgData
    ) external returns (bytes memory hookData) {
        // Extract transaction details from msgData
        (address to, uint256 amount) = _extractTransactionData(msgData);
        
        // Calculate risk score for this transaction
        uint256 riskScore = _calculateTransactionRisk(msgSender, to, amount);
        
        // Update velocity tracking
        _updateVelocityTracking(msgSender, amount);
        
        // Check for compliance violations
        bool flagged = _checkComplianceViolations(msgSender, to, amount, riskScore);
        
        // Update risk profile
        _updateRiskProfile(msgSender, riskScore, flagged);
        
        // Emit monitoring event
        emit TransactionMonitored(msgSender, to, amount, riskScore, flagged);
        
        // Return context for post-check
        return abi.encode(msgSender, to, amount, riskScore, flagged, block.timestamp);
    }

    function postCheck(bytes calldata hookData) external {
        (
            address from,
            address to,
            uint256 amount,
            uint256 riskScore,
            bool flagged,
            uint256 timestamp
        ) = abi.decode(hookData, (address, address, uint256, uint256, bool, uint256));
        
        // Record transaction in history
        _recordTransaction(from, to, amount, timestamp, flagged);
        
        // Update daily/monthly aggregates
        _updateTransactionAggregates(from, amount);
        
        // Generate compliance reports if needed
        if (flagged || riskScore >= RISK_THRESHOLD) {
            _generateComplianceReport(from, "HIGH_RISK_TRANSACTION", riskScore >= 90 ? 5 : 3, hookData);
        }
        
        // Check for pattern violations
        _checkTransactionPatterns(from);
    }

    // =============================================================
    //                    RISK ASSESSMENT
    // =============================================================

    function _calculateTransactionRisk(
        address from,
        address to,
        uint256 amount
    ) internal view returns (uint256) {
        uint256 riskScore = 0;
        
        // Base risk from account profiles
        RiskProfile memory fromProfile = _riskProfiles[from];
        RiskProfile memory toProfile = _riskProfiles[to];
        
        riskScore += fromProfile.riskScore / 4; // 25% weight
        riskScore += toProfile.riskScore / 8;   // 12.5% weight
        
        // Amount-based risk
        if (amount > SUSPICIOUS_AMOUNT_THRESHOLD) {
            riskScore += 30;
        } else if (amount > SUSPICIOUS_AMOUNT_THRESHOLD / 2) {
            riskScore += 15;
        }
        
        // Velocity risk
        uint256 currentHour = block.timestamp / 3600;
        uint256 hourlyVolume = _hourlyVolume[from][currentHour];
        if (hourlyVolume + amount > SUSPICIOUS_AMOUNT_THRESHOLD / 10) {
            riskScore += 20;
        }
        
        // Historical risk
        if (fromProfile.suspiciousTransactionCount > 5) {
            riskScore += 25;
        }
        
        // Cap at 100
        return riskScore > 100 ? 100 : riskScore;
    }

    function _updateRiskProfile(address account, uint256 transactionRiskScore, bool flagged) internal {
        RiskProfile storage profile = _riskProfiles[account];
        
        // Update counters
        profile.totalTransactionCount++;
        if (flagged) {
            profile.suspiciousTransactionCount++;
        }
        
        // Calculate new risk score (weighted average)
        uint256 oldWeight = profile.totalTransactionCount > 10 ? 80 : 50;
        uint256 newWeight = 100 - oldWeight;
        
        uint256 oldRiskScore = profile.riskScore;
        profile.riskScore = (profile.riskScore * oldWeight + transactionRiskScore * newWeight) / 100;
        profile.lastUpdated = block.timestamp;
        profile.isHighRisk = profile.riskScore >= RISK_THRESHOLD;
        
        if (oldRiskScore != profile.riskScore) {
            emit RiskProfileUpdated(account, oldRiskScore, profile.riskScore);
        }
        
        if (profile.isHighRisk && profile.riskScore >= 90) {
            emit HighRiskActivity(account, "Critical risk level reached", profile.riskScore);
        }
    }

    // =============================================================
    //                    COMPLIANCE MONITORING
    // =============================================================

    function _checkComplianceViolations(
        address from,
        address to,
        uint256 amount,
        uint256 riskScore
    ) internal returns (bool) {
        bool flagged = false;
        
        // High-value transaction flagging
        if (amount > SUSPICIOUS_AMOUNT_THRESHOLD) {
            flagged = true;
        }
        
        // High-risk score flagging
        if (riskScore >= RISK_THRESHOLD) {
            flagged = true;
        }
        
        // Velocity checks
        uint256 currentHour = block.timestamp / 3600;
        uint256 currentDay = block.timestamp / 86400;
        
        if (_hourlyVolume[from][currentHour] + amount > SUSPICIOUS_AMOUNT_THRESHOLD / 5) {
            emit VelocityAlert(from, _hourlyVolume[from][currentHour] + amount, 1); // 1 hour
            flagged = true;
        }
        
        if (_dailyVolume[from][currentDay] + amount > SUSPICIOUS_AMOUNT_THRESHOLD * 2) {
            emit VelocityAlert(from, _dailyVolume[from][currentDay] + amount, 24); // 24 hours
            flagged = true;
        }
        
        return flagged;
    }

    function _checkTransactionPatterns(address account) internal {
        TransactionRecord[] storage history = _transactionHistory[account];
        
        if (history.length < 5) return; // Need some history
        
        // Check for rapid consecutive transactions
        uint256 recentCount = 0;
        uint256 cutoff = block.timestamp - 300; // 5 minutes
        
        for (uint256 i = history.length; i > 0 && i > history.length - 10; i--) {
            if (history[i-1].timestamp > cutoff) {
                recentCount++;
            }
        }
        
        if (recentCount >= 5) {
            _generateComplianceReport(
                account,
                "RAPID_TRANSACTION_PATTERN",
                3,
                abi.encode("Rapid transactions", recentCount, cutoff)
            );
        }
    }

    // =============================================================
    //                    REPORTING
    // =============================================================

    function _generateComplianceReport(
        address account,
        string memory violationType,
        uint256 severity,
        bytes memory details
    ) internal {
        uint256 reportId = _nextReportId++;
        
        _complianceReports[reportId] = ComplianceReport({
            reportId: reportId,
            account: account,
            violationType: violationType,
            severity: severity,
            timestamp: block.timestamp,
            details: details,
            resolved: false
        });
        
        emit ComplianceViolation(reportId, account, violationType, severity);
    }

    function _generateFinalComplianceReport() internal {
        // Create summary report before module removal
        _generateComplianceReport(
            address(this),
            "MODULE_UNINSTALL",
            1,
            abi.encode("Compliance module being uninstalled", block.timestamp)
        );
    }

    // =============================================================
    //                    UTILITY FUNCTIONS
    // =============================================================

    function _extractTransactionData(bytes calldata msgData) internal pure returns (address to, uint256 amount) {
        // Parse the function selector and parameters
        if (msgData.length >= 68) {
            bytes4 selector = bytes4(msgData[0:4]);
            
            // Standard transfer function: transfer(address,uint256)
            if (selector == 0xa9059cbb) {
                to = address(bytes20(msgData[16:36]));
                amount = abi.decode(msgData[36:68], (uint256));
            }
            // TransferFrom function: transferFrom(address,address,uint256)
            else if (selector == 0x23b872dd) {
                to = address(bytes20(msgData[48:68]));
                amount = abi.decode(msgData[68:100], (uint256));
            }
        }
    }

    function _recordTransaction(
        address from,
        address to,
        uint256 amount,
        uint256 timestamp,
        bool flagged
    ) internal {
        TransactionRecord memory record = TransactionRecord({
            from: from,
            to: to,
            amount: amount,
            timestamp: timestamp,
            transactionHash: keccak256(abi.encode(from, to, amount, timestamp)),
            flagged: flagged
        });
        
        TransactionRecord[] storage history = _transactionHistory[from];
        
        // Maintain history size limit
        if (history.length >= MAX_TRANSACTION_HISTORY) {
            // Remove oldest entries (shift array)
            for (uint256 i = 0; i < history.length - 1; i++) {
                history[i] = history[i + 1];
            }
            history[history.length - 1] = record;
        } else {
            history.push(record);
        }
    }

    function _updateVelocityTracking(address account, uint256 amount) internal {
        uint256 currentHour = block.timestamp / 3600;
        uint256 currentDay = block.timestamp / 86400;
        
        _hourlyVolume[account][currentHour] += amount;
        _dailyVolume[account][currentDay] += amount;
    }

    function _updateTransactionAggregates(address account, uint256 amount) internal {
        // Additional aggregate tracking can be implemented here
        // For example: weekly, monthly volumes, transaction counts, etc.
    }

    // =============================================================
    //                    ADMIN FUNCTIONS
    // =============================================================

    function setComplianceOfficer(address newOfficer) external onlyAuthorized {
        _complianceOfficer = newOfficer;
    }

    function setRegulatoryAuthority(address newAuthority) external onlyAuthorized {
        _regulatoryAuthority = newAuthority;
    }

    function resolveComplianceReport(uint256 reportId) external onlyAuthorized {
        if (_complianceReports[reportId].reportId == 0) {
            revert ReportNotFound(reportId);
        }
        
        _complianceReports[reportId].resolved = true;
    }

    function setAccountRiskScore(address account, uint256 riskScore) external onlyAuthorized {
        if (riskScore > 100) {
            revert InvalidRiskScore(riskScore);
        }
        
        uint256 oldScore = _riskProfiles[account].riskScore;
        _riskProfiles[account].riskScore = riskScore;
        _riskProfiles[account].lastUpdated = block.timestamp;
        _riskProfiles[account].isHighRisk = riskScore >= RISK_THRESHOLD;
        
        emit RiskProfileUpdated(account, oldScore, riskScore);
    }

    // =============================================================
    //                    VIEW FUNCTIONS
    // =============================================================

    function getRiskProfile(address account) external view returns (RiskProfile memory) {
        return _riskProfiles[account];
    }

    function getTransactionHistory(address account) external view returns (TransactionRecord[] memory) {
        return _transactionHistory[account];
    }

    function getComplianceReport(uint256 reportId) external view returns (ComplianceReport memory) {
        return _complianceReports[reportId];
    }

    function getHourlyVolume(address account, uint256 hour) external view returns (uint256) {
        return _hourlyVolume[account][hour];
    }

    function getDailyVolume(address account, uint256 day) external view returns (uint256) {
        return _dailyVolume[account][day];
    }

    function getCurrentHourlyVolume(address account) external view returns (uint256) {
        return _hourlyVolume[account][block.timestamp / 3600];
    }

    function getCurrentDailyVolume(address account) external view returns (uint256) {
        return _dailyVolume[account][block.timestamp / 86400];
    }

    function getComplianceOfficer() external view returns (address) {
        return _complianceOfficer;
    }

    function getRegulatoryAuthority() external view returns (address) {
        return _regulatoryAuthority;
    }

    function getNextReportId() external view returns (uint256) {
        return _nextReportId;
    }
}