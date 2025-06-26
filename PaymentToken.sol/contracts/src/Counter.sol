// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

// An upgradeable counter contract with UUPS pattern
contract Counter is UUPSUpgradeable, OwnableUpgradeable {
    // Counter value
    uint256 private count;

    uint256 public supply;
    // The number of bytes in the authorization itself.
    uint16 public authorizationSize;
    // The number of bytes in the signed authorization.
    uint8 public signedAuthorizationSize;
    // is the system halted?
    bool public isHalted;

    mapping(address => bool) private canSponsor;
    mapping(address => bool) private registeredAccounts;
    struct Account {
        // User balance
        uint256 balance;
        // The nonce of the account.
        uint256 nonce;
        /*
            Options for revoking authorizations
            - Keep a list of revoked authorizations, prune when they expire.
            - Associate each authorization with an index, store revoked indicies in a map
            - Map each authorization to a value i \in [0, 255] and store in a bitmap
                - this means a user can only have 256 unique authorizations (could expand to larger type?)
                - Assuming this is OK for now
        */
        // A bitmap of all the authorizations that have been issued for this account.
        // NOTE: Re-enable this if we assume that authorizations are not rememebred off-chain
        // uint256 authBitmap;
        // A bitmap of all the authorizations that have been disabled for this account.
        uint256 disabledAuthsBitmap;
        // The sponsor of this account.
        // TODO: This may want to be a list of sponsors.
        address sponsor;
        // Whether the account is frozen.
        bool isFrozen;
        // The account's locked balance.
        uint256 lockedBalance;
    }
    mapping(address => Account) private _accounts;
    mapping(address account => mapping(address spender => uint256))
        private _allowances;

    // Event emitted when count changes
    event CountChanged(uint256 count);

    // Initializes the contract, setting up ownership and upgrade capabilities
    // This function replaces the constructor and can only be called once due to the initializer modifier
    function initialize() public initializer {
        // Initialize the Ownable module
        // This function sets up the contract's ownership, making msg.sender the initial owner
        // It's part of the OwnableUpgradeable contract from OpenZeppelin
        __Ownable_init(msg.sender);

        // Initialize the UUPSUpgradeable module
        // This sets up the necessary state variables for the UUPS (Universal Upgradeable Proxy Standard) pattern
        // It's part of the UUPSUpgradeable contract from OpenZeppelin
        __UUPSUpgradeable_init();
    }

    // Increments the counter by 1
    function increment() public {
        count += 1;
        emit CountChanged(count);
    }

    // Returns the current count
    function getCount() public view returns (uint256) {
        return count;
    }

    // Authorizes an upgrade (only owner can call)
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
