// MIT DCI Jan 2025

// Base of code originally from:
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (token/ERC20/IERC20.sol)

pragma solidity ^0.8.20;

/// @title An interface for managing sponsors
/// @author MIT-DCI
interface ISponsor {
    /// @notice Sets an address as a legal sponsor
    /// @param sponsor The address to set as a sponsor
    function newSponsor(address sponsor) external;

    /// @notice Removes an address as a legal sponsor
    /// @param sponsor The address to remove as a sponsor
    function removeSponsor(address sponsor) external;

    /// @notice Sets the sponsor for an account
    /// @param account The address to set the sponsor for
    /// @param sponsor The address to set as the sponsor
    function setSponsor(address account, address sponsor) external;
}
