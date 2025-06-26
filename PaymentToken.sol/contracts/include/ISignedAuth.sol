// MIT DCI Jan 2025

// Base of code originally from:
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (token/ERC20/IERC20.sol)

pragma solidity ^0.8.20;
import {AuthTypes} from "../lib/AuthTypes.sol";


/// @title An interface defining transfer behavior with signed authorizations
/// @author MIT-DCI
interface ISignedAuth {
    // Events
    /// @notice An event emitted when a transfer is made
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param amount The amount transferred
    /// @param authorization The authorization used
    event TransferWithAuthorization(
        address indexed from,
        address indexed to,
        uint256 amount,
        AuthTypes.SignedAuthorization authorization
    );

    /// @notice An event emitted when the authorization URI is updated
    /// @param uri The new URI
    event URIUpdated(string uri);

    /// @notice A URI indicating where to get the authorization from
    /// @return The authorization URI
    function authorizationURI() external view returns (string memory);

    /// @notice Updates the authorization URI
    /// @param uri The new URI
    function updateAuthorizationURI(string calldata uri) external;

    /// @notice `transfer` with an authorization
    /// @param to The address of the recipient
    /// @param amount The amount to transfer
    /// @param authorization The authorization
    /// @return True if the transfer was successful
    function transferWithAuthorization(
        address to,
        uint256 amount,
        AuthTypes.SignedAuthorization calldata authorization
    ) external returns (bool);

    /// @notice `transferFrom` with an authorization
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param amount The amount to transfer
    /// @param authorization The authorization
    /// @return True if the transfer was successful
    function transferFromWithAuthorization(
        address from,
        address to,
        uint256 amount,
        AuthTypes.SignedAuthorization calldata authorization
    ) external returns (bool);
}

/*
Scratch space:

Authorization JSON Schema:
{
    amount: uint256,
    expiration: <timestamp>,
    recipients: [
        - Either a list of addresses, or some sort of "tag" indicating a group of recipients
    ],
    sender: <address>,
    # Need some way to commit to a number uses in this authorization
    spendingLimit: uint256,
}


How to revoke?

1) In the USER store a list of revoked authorizations
2) Should tie the authorization to a user's nonce to handle the spending limit on the auths

*/
