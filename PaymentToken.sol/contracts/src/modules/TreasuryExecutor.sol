// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC7579Module} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import {IERC7579Execution, Execution} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";

uint256 constant MODULE_TYPE_EXECUTOR = 2;

/// @title Treasury Management Executor Module
/// @author MIT-DCI
/// @notice ERC-7579 executor module for automated treasury operations and financial management
contract TreasuryExecutor is IERC7579Module {
    
    struct ScheduledOperation {
        uint256 operationId;
        address target;
        uint256 value;
        bytes data;
        uint256 executeAt;
        uint256 validUntil;
        bool executed;
        bool cancelled;
        string operationType;
        address requester;
    }

    struct TreasuryConfig {
        address treasuryAccount;
        address depositTokenAccount;
        uint256 maxDailyMint;
        uint256 maxDailyBurn;
        uint256 reserveRatio; // Percentage (0-10000, where 10000 = 100%)
        uint256 lastRebalance;
        bool autoRebalanceEnabled;
    }

    struct ReservePool {
        address poolAddress;
        uint256 balance;
        uint256 lastUpdate;
        string poolType; // "OPERATIONAL", "REGULATORY", "EMERGENCY"
        bool isActive;
    }

    // State variables
    TreasuryConfig private _treasuryConfig;
    mapping(uint256 => ScheduledOperation) private _scheduledOperations;
    mapping(address => ReservePool) private _reservePools;
    mapping(string => uint256) private _dailyOperationLimits;
    mapping(uint256 => mapping(string => uint256)) private _dailyOperationCounts; // day => operationType => count
    
    address private _treasuryManager;
    address private _riskManager;
    uint256 private _nextOperationId;
    
    // Daily tracking
    mapping(uint256 => uint256) private _dailyMinted; // day => amount
    mapping(uint256 => uint256) private _dailyBurned;  // day => amount
    
    // Events
    event OperationScheduled(
        uint256 indexed operationId,
        string operationType,
        address indexed requester,
        uint256 executeAt
    );
    event OperationExecuted(uint256 indexed operationId, bool success, bytes result);
    event OperationCancelled(uint256 indexed operationId, address indexed canceller);
    event TreasuryConfigUpdated(address indexed treasuryAccount, uint256 maxDailyMint, uint256 maxDailyBurn);
    event RebalanceExecuted(uint256 newBalance, uint256 targetBalance, uint256 timestamp);
    event ReservePoolAdded(address indexed poolAddress, string poolType);
    event ReservePoolUpdated(address indexed poolAddress, uint256 newBalance);
    event EmergencyAction(string actionType, address indexed target, uint256 value);

    // Errors
    error UnauthorizedTreasuryAccess();
    error OperationNotFound(uint256 operationId);
    error OperationAlreadyExecuted(uint256 operationId);
    error OperationIsCancelled(uint256 operationId);
    error OperationNotReady(uint256 operationId, uint256 currentTime, uint256 executeAt);
    error OperationExpired(uint256 operationId, uint256 currentTime, uint256 validUntil);
    error DailyLimitExceeded(string operationType, uint256 limit, uint256 attempted);
    error InvalidReserveRatio(uint256 ratio);
    error InsufficientReserves(uint256 required, uint256 available);

    modifier onlyTreasuryManager() {
        require(msg.sender == _treasuryManager, "Not treasury manager");
        _;
    }

    modifier onlyAuthorized() {
        require(
            msg.sender == _treasuryManager || 
            msg.sender == _riskManager ||
            msg.sender == _treasuryConfig.treasuryAccount,
            "Not authorized"
        );
        _;
    }

    constructor(address treasuryManager, address riskManager) {
        _treasuryManager = treasuryManager;
        _riskManager = riskManager;
        _nextOperationId = 1;
        
        // Set default operation limits
        _dailyOperationLimits["MINT"] = 10;
        _dailyOperationLimits["BURN"] = 10;
        _dailyOperationLimits["REBALANCE"] = 5;
        _dailyOperationLimits["TRANSFER"] = 50;
    }

    // =============================================================
    //                    ERC-7579 MODULE INTERFACE
    // =============================================================

    function onInstall(bytes calldata data) external {
        if (data.length > 0) {
            (
                address treasuryAccount,
                address depositTokenAccount,
                uint256 maxDailyMint,
                uint256 maxDailyBurn,
                uint256 reserveRatio
            ) = abi.decode(data, (address, address, uint256, uint256, uint256));

            _treasuryConfig = TreasuryConfig({
                treasuryAccount: treasuryAccount,
                depositTokenAccount: depositTokenAccount,
                maxDailyMint: maxDailyMint,
                maxDailyBurn: maxDailyBurn,
                reserveRatio: reserveRatio,
                lastRebalance: block.timestamp,
                autoRebalanceEnabled: true
            });

            emit TreasuryConfigUpdated(treasuryAccount, maxDailyMint, maxDailyBurn);
        }
    }

    function onUninstall(bytes calldata) external {
        // Perform final reconciliation
        _performFinalReconciliation();
    }

    function isModuleType(uint256 moduleTypeId) external pure returns (bool) {
        return moduleTypeId == MODULE_TYPE_EXECUTOR;
    }

    // =============================================================
    //                    TREASURY OPERATIONS
    // =============================================================

    function scheduleMint(
        address recipient,
        uint256 amount,
        uint256 executeAt,
        uint256 validUntil
    ) external onlyAuthorized returns (uint256) {
        _checkDailyLimit("MINT");
        
        bytes memory mintData = abi.encodeWithSignature(
            "mint(address,uint256)",
            recipient,
            amount
        );

        uint256 operationId = _scheduleOperation(
            _treasuryConfig.depositTokenAccount,
            0,
            mintData,
            executeAt,
            validUntil,
            "MINT"
        );

        return operationId;
    }

    function scheduleBurn(
        address from,
        uint256 amount,
        uint256 executeAt,
        uint256 validUntil
    ) external onlyAuthorized returns (uint256) {
        _checkDailyLimit("BURN");
        
        bytes memory burnData = abi.encodeWithSignature(
            "burn(address,uint256)",
            from,
            amount
        );

        uint256 operationId = _scheduleOperation(
            _treasuryConfig.depositTokenAccount,
            0,
            burnData,
            executeAt,
            validUntil,
            "BURN"
        );

        return operationId;
    }

    function scheduleRebalance(
        uint256 executeAt,
        uint256 validUntil
    ) external onlyAuthorized returns (uint256) {
        _checkDailyLimit("REBALANCE");
        
        bytes memory rebalanceData = abi.encodeWithSignature("performRebalance()");

        uint256 operationId = _scheduleOperation(
            address(this),
            0,
            rebalanceData,
            executeAt,
            validUntil,
            "REBALANCE"
        );

        return operationId;
    }

    function executeScheduledOperation(uint256 operationId) external returns (bool, bytes memory) {
        ScheduledOperation storage operation = _scheduledOperations[operationId];
        
        if (operation.operationId == 0) {
            revert OperationNotFound(operationId);
        }
        
        if (operation.executed) {
            revert OperationAlreadyExecuted(operationId);
        }
        
        if (operation.cancelled) {
            revert OperationIsCancelled(operationId);
        }
        
        if (block.timestamp < operation.executeAt) {
            revert OperationNotReady(operationId, block.timestamp, operation.executeAt);
        }
        
        if (block.timestamp > operation.validUntil) {
            revert OperationExpired(operationId, block.timestamp, operation.validUntil);
        }

        // Execute through the deposit token account
        operation.executed = true;
        
        Execution memory execution = Execution({
            target: operation.target,
            value: operation.value,
            callData: operation.data
        });

        bytes32 mode = _encodeSingleExecutionMode();
        bytes memory executionCalldata = abi.encode(execution);

        (bool success, bytes memory result) = _treasuryConfig.depositTokenAccount.call(
            abi.encodeWithSignature(
                "executeFromExecutor(bytes32,bytes)",
                mode,
                executionCalldata
            )
        );

        // Update daily tracking
        _updateDailyTracking(operation.operationType);

        emit OperationExecuted(operationId, success, result);
        return (success, result);
    }

    function cancelScheduledOperation(uint256 operationId) external onlyAuthorized {
        ScheduledOperation storage operation = _scheduledOperations[operationId];
        
        if (operation.operationId == 0) {
            revert OperationNotFound(operationId);
        }
        
        if (operation.executed) {
            revert OperationAlreadyExecuted(operationId);
        }

        operation.cancelled = true;
        emit OperationCancelled(operationId, msg.sender);
    }

    // =============================================================
    //                    RESERVE MANAGEMENT
    // =============================================================

    function addReservePool(
        address poolAddress,
        uint256 initialBalance,
        string memory poolType
    ) external onlyTreasuryManager {
        _reservePools[poolAddress] = ReservePool({
            poolAddress: poolAddress,
            balance: initialBalance,
            lastUpdate: block.timestamp,
            poolType: poolType,
            isActive: true
        });

        emit ReservePoolAdded(poolAddress, poolType);
    }

    function updateReservePool(address poolAddress, uint256 newBalance) external onlyAuthorized {
        ReservePool storage pool = _reservePools[poolAddress];
        require(pool.isActive, "Pool not active");

        pool.balance = newBalance;
        pool.lastUpdate = block.timestamp;

        emit ReservePoolUpdated(poolAddress, newBalance);
    }

    function performRebalance() external onlyAuthorized {
        TreasuryConfig storage config = _treasuryConfig;
        
        // Get current token balance
        (bool success, bytes memory result) = config.depositTokenAccount.call(
            abi.encodeWithSignature("totalSupply()")
        );
        require(success, "Failed to get total supply");
        
        uint256 totalSupply = abi.decode(result, (uint256));
        uint256 targetReserve = (totalSupply * config.reserveRatio) / 10000;
        
        // Calculate current reserves
        uint256 currentReserves = _calculateTotalReserves();
        
        if (currentReserves < targetReserve) {
            // Need to increase reserves
            uint256 deficit = targetReserve - currentReserves;
            _increaseReserves(deficit);
        } else if (currentReserves > targetReserve) {
            // Can decrease reserves
            uint256 excess = currentReserves - targetReserve;
            _decreaseReserves(excess);
        }

        config.lastRebalance = block.timestamp;
        emit RebalanceExecuted(currentReserves, targetReserve, block.timestamp);
    }

    function _increaseReserves(uint256 amount) internal {
        // Implementation would depend on the reserve mechanism
        // For example, minting to reserve pools or transferring from treasury
        emit EmergencyAction("INCREASE_RESERVES", address(0), amount);
    }

    function _decreaseReserves(uint256 amount) internal {
        // Implementation would depend on the reserve mechanism
        // For example, burning from reserves or transferring to treasury
        emit EmergencyAction("DECREASE_RESERVES", address(0), amount);
    }

    function _calculateTotalReserves() internal view returns (uint256) {
        uint256 totalReserves = 0;
        
        // This would iterate through all reserve pools
        // For simplicity, we'll return a placeholder
        return totalReserves;
    }

    // =============================================================
    //                    EMERGENCY FUNCTIONS
    // =============================================================

    function emergencyMint(address to, uint256 amount) external onlyTreasuryManager {
        bytes memory mintData = abi.encodeWithSignature("mint(address,uint256)", to, amount);
        
        (bool success, ) = _treasuryConfig.depositTokenAccount.call(mintData);
        require(success, "Emergency mint failed");
        
        emit EmergencyAction("EMERGENCY_MINT", to, amount);
    }

    function emergencyBurn(address from, uint256 amount) external onlyTreasuryManager {
        bytes memory burnData = abi.encodeWithSignature("burn(address,uint256)", from, amount);
        
        (bool success, ) = _treasuryConfig.depositTokenAccount.call(burnData);
        require(success, "Emergency burn failed");
        
        emit EmergencyAction("EMERGENCY_BURN", from, amount);
    }

    function emergencyPause() external onlyTreasuryManager {
        (bool success, ) = _treasuryConfig.depositTokenAccount.call(
            abi.encodeWithSignature("pause()")
        );
        require(success, "Emergency pause failed");
        
        emit EmergencyAction("EMERGENCY_PAUSE", _treasuryConfig.depositTokenAccount, 0);
    }

    // =============================================================
    //                    UTILITY FUNCTIONS
    // =============================================================

    function _scheduleOperation(
        address target,
        uint256 value,
        bytes memory data,
        uint256 executeAt,
        uint256 validUntil,
        string memory operationType
    ) internal returns (uint256) {
        uint256 operationId = _nextOperationId++;
        
        _scheduledOperations[operationId] = ScheduledOperation({
            operationId: operationId,
            target: target,
            value: value,
            data: data,
            executeAt: executeAt,
            validUntil: validUntil,
            executed: false,
            cancelled: false,
            operationType: operationType,
            requester: msg.sender
        });

        emit OperationScheduled(operationId, operationType, msg.sender, executeAt);
        return operationId;
    }

    function _checkDailyLimit(string memory operationType) internal {
        uint256 today = block.timestamp / 86400;
        uint256 currentCount = _dailyOperationCounts[today][operationType];
        uint256 limit = _dailyOperationLimits[operationType];
        
        if (currentCount >= limit) {
            revert DailyLimitExceeded(operationType, limit, currentCount + 1);
        }
    }

    function _updateDailyTracking(string memory operationType) internal {
        uint256 today = block.timestamp / 86400;
        _dailyOperationCounts[today][operationType]++;
    }

    function _encodeSingleExecutionMode() internal pure returns (bytes32) {
        // Single call mode (0x00)
        return bytes32(0);
    }

    function _performFinalReconciliation() internal {
        // Perform final cleanup and reconciliation before module removal
        emit EmergencyAction("MODULE_UNINSTALL", address(this), block.timestamp);
    }

    // =============================================================
    //                    ADMIN FUNCTIONS
    // =============================================================

    function updateTreasuryConfig(
        address newTreasuryAccount,
        uint256 newMaxDailyMint,
        uint256 newMaxDailyBurn,
        uint256 newReserveRatio
    ) external onlyTreasuryManager {
        if (newReserveRatio > 10000) {
            revert InvalidReserveRatio(newReserveRatio);
        }

        _treasuryConfig.treasuryAccount = newTreasuryAccount;
        _treasuryConfig.maxDailyMint = newMaxDailyMint;
        _treasuryConfig.maxDailyBurn = newMaxDailyBurn;
        _treasuryConfig.reserveRatio = newReserveRatio;

        emit TreasuryConfigUpdated(newTreasuryAccount, newMaxDailyMint, newMaxDailyBurn);
    }

    function setOperationLimit(string memory operationType, uint256 newLimit) external onlyTreasuryManager {
        _dailyOperationLimits[operationType] = newLimit;
    }

    function setTreasuryManager(address newManager) external onlyTreasuryManager {
        _treasuryManager = newManager;
    }

    function setRiskManager(address newManager) external onlyTreasuryManager {
        _riskManager = newManager;
    }

    // =============================================================
    //                    VIEW FUNCTIONS
    // =============================================================

    function getScheduledOperation(uint256 operationId) external view returns (ScheduledOperation memory) {
        return _scheduledOperations[operationId];
    }

    function getTreasuryConfig() external view returns (TreasuryConfig memory) {
        return _treasuryConfig;
    }

    function getReservePool(address poolAddress) external view returns (ReservePool memory) {
        return _reservePools[poolAddress];
    }

    function getDailyOperationCount(string memory operationType) external view returns (uint256) {
        uint256 today = block.timestamp / 86400;
        return _dailyOperationCounts[today][operationType];
    }

    function getOperationLimit(string memory operationType) external view returns (uint256) {
        return _dailyOperationLimits[operationType];
    }

    function getTreasuryManager() external view returns (address) {
        return _treasuryManager;
    }

    function getRiskManager() external view returns (address) {
        return _riskManager;
    }

    function getNextOperationId() external view returns (uint256) {
        return _nextOperationId;
    }
}