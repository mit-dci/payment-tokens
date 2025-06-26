// MIT DCI Jan 2025

// Base of code originally from:
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (token/ERC20/IERC20.sol)

pragma solidity ^0.8.20;

/// @title An interface for some payment token administrative functions
/// @author MIT-DCI
interface IAdmin {
    /// @notice An event emitted when new tokens are minted
    /// @param minter The address of the minter
    /// @param to The address of the recipient
    /// @param amount The amount of tokens minted
    event Mint(address indexed minter, address indexed to, uint256 amount);

    /// @notice An event emitted when tokens are burned
    /// @param burner The address of the burner
    /// @param amount The amount of tokens burned
    event Burn(address indexed burner, uint256 amount);

    /// @notice An event emitted when tokens are frozen for an account
    /// @param freezer The address of the freezer
    /// @param target The address of the target
    event Freeze(
        address indexed freezer,
        address indexed target
    );

    /// @notice An event emitted when tokens are unfrozen for an account
    /// @param unfreezer The address of the unfreezer
    /// @param target The address of the target
    event Unfreeze(
        address indexed unfreezer,
        address indexed target
    );

    /// @notice An event emitted when tokens are burned from the system
    /// @param amount The amount of tokens burned
    // TODO: Remove? 
    event SupplyBurn(uint256 amount);

    /// @notice Freezes an account
    /// @param account The address of the account to freeze
    /// @return True if the account was frozen
    function freeze(address account) external returns (bool);

    /// @notice Unfreezes an account
    /// @param account The address of the account to unfreeze
    /// @return True if the account was unfreezed
    function unfreeze(address account) external returns (bool);

    /// @notice Mints new tokens
    /// @param to The address of the recipient (mintee?)
    /// @param value The amount of tokens to mint
    /// @return True if the tokens were minted
    function mint(address to, uint256 value) external returns (bool);

    /// @notice Redeems tokens
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to redeem
    /// @return True if the tokens were redeemed
    function redeem(address to, uint256 amount) external returns (bool);
    
    /// @notice Burns tokens from supply
    /// @param amount The amount of tokens to burn
    /// @return True
    function supplyBurn(uint256 amount) external returns (bool);

    /// @notice Seizes tokens from an account (locks them)
    /// @param seizeFrom The address of the account to seize from
    /// @param amount The amount of tokens to seize
    /// @return True if the tokens were seized
    // TODO: Specify a destination address?
    function seize(address seizeFrom, uint256 amount) external returns (bool);

    /// @notice Releases locked tokens from an account
    /// @param account The address of the account to release from
    /// @param amount The amount of tokens to release
    /// @return True if the tokens were released
    // TODO: Specify a destination address? i.e. release to a different address?
    function releaseLockedBalance(address account, uint256 amount) external returns (bool);
}
