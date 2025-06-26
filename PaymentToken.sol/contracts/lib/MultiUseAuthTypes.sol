// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title A library for multi-use authorization types
/// @author MIT-DCI
library MultiUseAuthTypes {
    /// @title A signed payload that we may verify
    /// @param authorization The authorization to verify.
    /// @param signature The signature of the authorization.
    struct SignedAuthorization {
        bytes authorization;
        bytes signature;
    }

    // Authorization size: 172 bytes (32 bytes more than BasicAuthorization)
    /// @title A multi-use authorization that can be used n times
    /// @param sender The authorized sender to use this authorization.
    /// @param spendingLimit The per-transaction spending limit of the authorization.
    /// @param totalLimit The total amount that can be spent across all uses of this authorization.
    /// @param expiration The expiration of the authorization (block time).
    /// @param authNonce The nonce this authorization is associated with.
    /// @param maxUses The maximum number of times this authorization can be used.
    struct MultiUseAuthorization {
        /// @notice The authorized sender to use this authorization.
        address sender;
        /// @notice The per-transaction spending limit of the authorization.
        uint256 spendingLimit;
        /// @notice The total amount that can be spent across all uses of this authorization.
        uint256 totalLimit;
        /// @notice The expiration of the authorization (block time).
        uint256 expiration;
        /// @notice The nonce this authorization is associated with.
        uint256 authNonce;
        /// @notice The maximum number of times this authorization can be used.
        uint256 maxUses;
    }

    /// @title Tracks the usage of a multi-use authorization
    /// @param timesUsed The number of times this authorization has been used.
    /// @param totalSpent The total amount spent using this authorization.
    /// @param isRevoked Whether this authorization has been revoked.
    struct AuthorizationUsage {
        /// @notice The number of times this authorization has been used.
        uint256 timesUsed;
        /// @notice The total amount spent using this authorization.
        uint256 totalSpent;
        /// @notice Whether this authorization has been revoked.
        bool isRevoked;
    }
}