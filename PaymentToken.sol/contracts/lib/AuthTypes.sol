// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (token/ERC20/IERC20.sol)

pragma solidity ^0.8.24;

/// @title A library for different authorization types
/// @author MIT-DCI
library AuthTypes {
    /// @title A signed payload that we may verify
    /// @param authorization The authorization to verify.
    /// @param signature The signature of the authorization.
    struct SignedAuthorization {
        // NOTE: This is expected to be a packed struct
        // If solidity had generics, this would be a generic type T
        // but it does not. So we'll use `bytes` and have the author of
        // the `DepToken` itself implement the authorization structure itself.
        // NOTE: This also removes the benefit of EIP-712, which we may prefer
        // to use instead.
        bytes authorization;
        bytes signature;
    }

    /// @title A basic authorization
    /// @param sender The authorized sender to use this authorization.
    /// @param spendingLimit The spending limit of the authorization.
    /// @param expiration The expiration of the authorization (block time).
    /// @param authNonce The nonce this authorization is associated with.
    struct BasicAuthorization {
        /// @notice The authorized sender to use this authorization.
        address sender;
        /// @notice The spending limit of the authorization.
        uint256 spendingLimit;
        /// @notice The expiration of the authorization (block time).
        uint256 expiration;
        /// @notice The nonce this authorization is associated with.
        uint256 authNonce;
    }
}