// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC7579Execution, IERC7579AccountConfig, IERC7579ModuleConfig, IERC7579Module, Execution} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import {IERC7579Validator, IERC7579Hook} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

// Module type constants from ERC-7579
uint256 constant MODULE_TYPE_VALIDATOR = 1;
uint256 constant MODULE_TYPE_EXECUTOR = 2;
uint256 constant MODULE_TYPE_FALLBACK = 3;
uint256 constant MODULE_TYPE_HOOK = 4;

// Execution mode constants
bytes32 constant EXECTYPE_DEFAULT = 0x0000000000000000000000000000000000000000000000000000000000000000;
bytes32 constant EXECTYPE_TRY = 0x0000000000000000000000000000000000000000000000000000000000000001;

/// @title Modular Deposit Token with ERC-7579 Support
/// @author MIT-DCI
/// @notice A regulated deposit token implementing ERC-7579 modular smart account architecture
contract ModularDepositToken is 
    IERC7579Execution,
    IERC7579AccountConfig,
    IERC7579ModuleConfig,
    IERC20,
    IERC165,
    IERC1271,
    UUPSUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable
{
    // Token metadata
    string private _name;
    string private _symbol;
    uint8 public constant DECIMALS = 18;
    string public constant VERSION = "v1.0.0-ERC7579";
    
    // Token state
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address account => mapping(address spender => uint256)) private _allowances;
    
    // ERC-7579 Module management
    mapping(uint256 moduleType => mapping(address module => bool)) private _installedModules;
    mapping(uint256 moduleType => address[]) private _modulesByType;
    mapping(address module => bytes) private _moduleData;
    
    // Account management
    mapping(address => bool) private _registeredAccounts;
    mapping(address => address) private _accountSponsors;
    mapping(address => uint256) private _accountNonces;
    mapping(address => bool) private _frozenAccounts;
    mapping(address => uint256) private _lockedBalances;
    
    // Sponsor management
    mapping(address => bool) private _approvedSponsors;
    
    // Authorization URI for compliance
    string public authorizationURI;

    // Custom Events (ERC-20 Transfer/Approval events inherited from IERC20)
    event UserRegistered(address indexed account, address indexed sponsor);
    event AccountFrozen(address indexed account);
    event AccountUnfrozen(address indexed account);
    event SponsorAdded(address indexed sponsor);
    event SponsorRemoved(address indexed sponsor);
    event Mint(address indexed to, uint256 amount);
    event Burn(address indexed from, uint256 amount);

    // Errors
    error ModuleNotInstalled(uint256 moduleType, address module);
    error ModuleAlreadyInstalled(uint256 moduleType, address module);
    error InvalidModuleType(uint256 moduleType);
    error UnregisteredAccount(address account);
    error AccountIsFrozen(address account);
    error InvalidSponsor(address sponsor);
    error InsufficientBalance();
    error InsufficientAllowance();
    error ExecutionFailed();
    error InvalidExecutionMode();
    error UnauthorizedModule();

    modifier onlyValidModule(uint256 moduleType, address module) {
        if (!_installedModules[moduleType][module]) {
            revert ModuleNotInstalled(moduleType, module);
        }
        _;
    }

    modifier onlyRegistered(address account) {
        if (!_registeredAccounts[account]) {
            revert UnregisteredAccount(account);
        }
        _;
    }

    modifier notFrozen(address account) {
        if (_frozenAccounts[account]) {
            revert AccountIsFrozen(account);
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the modular deposit token
    function initialize(
        string calldata tokenName,
        string calldata tokenSymbol,
        address initialSponsor,
        string calldata authURI
    ) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __Pausable_init();

        _name = tokenName;
        _symbol = tokenSymbol;
        authorizationURI = authURI;

        // Set initial sponsor
        _approvedSponsors[initialSponsor] = true;
        emit SponsorAdded(initialSponsor);
    }

    // =============================================================
    //                    ERC-7579 ACCOUNT CONFIG
    // =============================================================

    function accountId() external pure returns (string memory) {
        return "mitdci.modular-deposit.1.0.0";
    }

    function supportsExecutionMode(bytes32 encodedMode) external pure returns (bool) {
        // Extract CallType (first byte)
        bytes1 callType = bytes1(encodedMode);
        // Support single call (0x00) and batch call (0x01)
        return callType == 0x00 || callType == 0x01;
    }

    function supportsModule(uint256 moduleTypeId) external pure returns (bool) {
        return moduleTypeId >= MODULE_TYPE_VALIDATOR && moduleTypeId <= MODULE_TYPE_HOOK;
    }

    // =============================================================
    //                    ERC-7579 MODULE CONFIG
    // =============================================================

    function installModule(
        uint256 moduleTypeId,
        address module,
        bytes calldata initData
    ) external onlyOwner {
        if (!this.supportsModule(moduleTypeId)) {
            revert InvalidModuleType(moduleTypeId);
        }
        
        if (_installedModules[moduleTypeId][module]) {
            revert ModuleAlreadyInstalled(moduleTypeId, module);
        }

        // Verify module supports the claimed type
        if (!IERC7579Module(module).isModuleType(moduleTypeId)) {
            revert InvalidModuleType(moduleTypeId);
        }

        _installedModules[moduleTypeId][module] = true;
        _modulesByType[moduleTypeId].push(module);
        _moduleData[module] = initData;

        // Initialize the module
        IERC7579Module(module).onInstall(initData);

        emit ModuleInstalled(moduleTypeId, module);
    }

    function uninstallModule(
        uint256 moduleTypeId,
        address module,
        bytes calldata deInitData
    ) external onlyOwner {
        if (!_installedModules[moduleTypeId][module]) {
            revert ModuleNotInstalled(moduleTypeId, module);
        }

        _installedModules[moduleTypeId][module] = false;
        
        // Remove from array
        address[] storage modules = _modulesByType[moduleTypeId];
        for (uint256 i = 0; i < modules.length; i++) {
            if (modules[i] == module) {
                modules[i] = modules[modules.length - 1];
                modules.pop();
                break;
            }
        }

        delete _moduleData[module];

        // Deinitialize the module
        IERC7579Module(module).onUninstall(deInitData);

        emit ModuleUninstalled(moduleTypeId, module);
    }

    function isModuleInstalled(
        uint256 moduleTypeId,
        address module,
        bytes calldata
    ) external view returns (bool) {
        return _installedModules[moduleTypeId][module];
    }

    // =============================================================
    //                    ERC-7579 EXECUTION
    // =============================================================

    function execute(
        bytes32 mode,
        bytes calldata executionCalldata
    ) external payable whenNotPaused {
        // Run pre-execution hooks
        bytes memory hookData = _executePreHooks(msg.sender, msg.value, msg.data);

        // Validate execution
        _validateExecution(msg.sender, mode, executionCalldata);

        // Execute the transaction
        _performExecution(mode, executionCalldata);

        // Run post-execution hooks
        _executePostHooks(hookData);
    }

    function executeFromExecutor(
        bytes32 mode,
        bytes calldata executionCalldata
    ) external payable whenNotPaused returns (bytes[] memory) {
        // Only installed executor modules can call this
        if (!_installedModules[MODULE_TYPE_EXECUTOR][msg.sender]) {
            revert UnauthorizedModule();
        }

        return _performExecution(mode, executionCalldata);
    }

    function _performExecution(
        bytes32 mode,
        bytes calldata executionCalldata
    ) internal returns (bytes[] memory) {
        bytes1 callType = bytes1(mode);
        
        if (callType == 0x00) {
            // Single execution
            Execution memory execution = abi.decode(executionCalldata, (Execution));
            return _executeSingle(execution);
        } else if (callType == 0x01) {
            // Batch execution
            Execution[] memory executions = abi.decode(executionCalldata, (Execution[]));
            return _executeBatch(executions);
        } else {
            revert InvalidExecutionMode();
        }
    }

    function _executeSingle(Execution memory execution) internal returns (bytes[] memory) {
        bytes[] memory results = new bytes[](1);
        (bool success, bytes memory result) = execution.target.call{value: execution.value}(execution.callData);
        
        if (!success) {
            revert ExecutionFailed();
        }
        
        results[0] = result;
        return results;
    }

    function _executeBatch(Execution[] memory executions) internal returns (bytes[] memory) {
        bytes[] memory results = new bytes[](executions.length);
        
        for (uint256 i = 0; i < executions.length; i++) {
            (bool success, bytes memory result) = executions[i].target.call{value: executions[i].value}(executions[i].callData);
            
            if (!success) {
                revert ExecutionFailed();
            }
            
            results[i] = result;
        }
        
        return results;
    }

    function _validateExecution(
        address sender,
        bytes32 mode,
        bytes calldata executionCalldata
    ) internal view {
        // Execute validator modules
        address[] memory validators = _modulesByType[MODULE_TYPE_VALIDATOR];
        
        for (uint256 i = 0; i < validators.length; i++) {
            // Custom validation logic can be implemented in validator modules
            // For now, we just check if validators are present
        }
        
        // Basic validation: sender must be registered and not frozen
        if (!_registeredAccounts[sender]) {
            revert UnregisteredAccount(sender);
        }
        
        if (_frozenAccounts[sender]) {
            revert AccountIsFrozen(sender);
        }
    }

    function _executePreHooks(
        address msgSender,
        uint256 value,
        bytes calldata msgData
    ) internal returns (bytes memory) {
        address[] memory hooks = _modulesByType[MODULE_TYPE_HOOK];
        bytes memory combinedHookData = "";
        
        for (uint256 i = 0; i < hooks.length; i++) {
            bytes memory hookData = IERC7579Hook(hooks[i]).preCheck(msgSender, value, msgData);
            combinedHookData = abi.encodePacked(combinedHookData, hookData);
        }
        
        return combinedHookData;
    }

    function _executePostHooks(bytes memory hookData) internal {
        address[] memory hooks = _modulesByType[MODULE_TYPE_HOOK];
        
        for (uint256 i = 0; i < hooks.length; i++) {
            IERC7579Hook(hooks[i]).postCheck(hookData);
        }
    }

    // =============================================================
    //                         ERC-20
    // =============================================================

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
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function transfer(
        address to,
        uint256 amount
    ) external onlyRegistered(msg.sender) onlyRegistered(to) notFrozen(msg.sender) notFrozen(to) returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external onlyRegistered(from) onlyRegistered(to) notFrozen(from) notFrozen(to) returns (bool) {
        uint256 currentAllowance = _allowances[from][msg.sender];
        if (currentAllowance < amount) {
            revert InsufficientAllowance();
        }

        _transfer(from, to, amount);
        _allowances[from][msg.sender] = currentAllowance - amount;
        
        return true;
    }

    function approve(address spender, uint256 amount) external onlyRegistered(msg.sender) returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        uint256 fromBalance = _balances[from];
        if (fromBalance < amount) {
            revert InsufficientBalance();
        }

        _balances[from] = fromBalance - amount;
        _balances[to] += amount;
        _accountNonces[from]++;

        emit Transfer(from, to, amount);
    }

    // =============================================================
    //                    REGULATORY FUNCTIONS
    // =============================================================

    function registerUser(address account, address sponsor) external onlyOwner {
        if (!_approvedSponsors[sponsor]) {
            revert InvalidSponsor(sponsor);
        }

        _registeredAccounts[account] = true;
        _accountSponsors[account] = sponsor;

        emit UserRegistered(account, sponsor);
    }

    function freezeAccount(address account) external onlyOwner {
        _frozenAccounts[account] = true;
        emit AccountFrozen(account);
    }

    function unfreezeAccount(address account) external onlyOwner {
        _frozenAccounts[account] = false;
        emit AccountUnfrozen(account);
    }

    function addSponsor(address sponsor) external onlyOwner {
        _approvedSponsors[sponsor] = true;
        emit SponsorAdded(sponsor);
    }

    function removeSponsor(address sponsor) external onlyOwner {
        _approvedSponsors[sponsor] = false;
        emit SponsorRemoved(sponsor);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _totalSupply += amount;
        _balances[to] += amount;
        emit Mint(to, amount);
        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount) external onlyOwner {
        uint256 fromBalance = _balances[from];
        if (fromBalance < amount) {
            revert InsufficientBalance();
        }

        _balances[from] = fromBalance - amount;
        _totalSupply -= amount;
        
        emit Burn(from, amount);
        emit Transfer(from, address(0), amount);
    }

    // =============================================================
    //                         VIEW FUNCTIONS
    // =============================================================

    function isRegistered(address account) external view returns (bool) {
        return _registeredAccounts[account];
    }

    function isFrozen(address account) external view returns (bool) {
        return _frozenAccounts[account];
    }

    function getSponsor(address account) external view returns (address) {
        return _accountSponsors[account];
    }

    function getAccountNonce(address account) external view returns (uint256) {
        return _accountNonces[account];
    }

    function getLockedBalance(address account) external view returns (uint256) {
        return _lockedBalances[account];
    }

    function getInstalledModules(uint256 moduleType) external view returns (address[] memory) {
        return _modulesByType[moduleType];
    }

    // =============================================================
    //                    ERC-165 & ERC-1271
    // =============================================================

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IERC7579Execution).interfaceId ||
            interfaceId == type(IERC7579AccountConfig).interfaceId ||
            interfaceId == type(IERC7579ModuleConfig).interfaceId ||
            interfaceId == type(IERC20).interfaceId ||
            interfaceId == type(IERC165).interfaceId ||
            interfaceId == type(IERC1271).interfaceId;
    }

    function isValidSignature(
        bytes32 hash,
        bytes calldata signature
    ) external view returns (bytes4) {
        // Delegate to validator modules for signature validation
        address[] memory validators = _modulesByType[MODULE_TYPE_VALIDATOR];
        
        for (uint256 i = 0; i < validators.length; i++) {
            bytes4 result = IERC7579Validator(validators[i]).isValidSignatureWithSender(
                msg.sender,
                hash,
                signature
            );
            
            if (result == IERC1271.isValidSignature.selector) {
                return IERC1271.isValidSignature.selector;
            }
        }
        
        return 0xffffffff; // Invalid signature
    }

    // =============================================================
    //                         UPGRADES
    // =============================================================

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // =============================================================
    //                         FALLBACK
    // =============================================================

    fallback() external payable {
        address[] memory fallbackHandlers = _modulesByType[MODULE_TYPE_FALLBACK];
        
        if (fallbackHandlers.length > 0) {
            address handler = fallbackHandlers[0]; // Use first fallback handler
            assembly {
                calldatacopy(0, 0, calldatasize())
                let result := delegatecall(gas(), handler, 0, calldatasize(), 0, 0)
                returndatacopy(0, 0, returndatasize())
                
                switch result
                case 0 { revert(0, returndatasize()) }
                default { return(0, returndatasize()) }
            }
        }
    }

    receive() external payable {}
}