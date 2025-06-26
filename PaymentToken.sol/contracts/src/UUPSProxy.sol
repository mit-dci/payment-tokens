// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (token/ERC20/IERC20.sol)

pragma solidity ^0.8.20;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract UUPSProxy is ERC1967Proxy {
    constructor(address _implementation, bytes memory _data) ERC1967Proxy(_implementation, _data) payable {}

    /**
     * @dev Storage slot with the address of the current implementation.
     * This is the keccak-256 hash of "org.zeppelinos.proxy.implementation", and is
     * validated in the constructor.
     */
    bytes32
        private constant IMPLEMENTATION_SLOT = 0x7050c9e0f4ca769c69bd3a8ef740bc37934f8e2c036e5a723fd8ee048ed3f8c3;
}
