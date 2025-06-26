// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/MultiUseAuthDeposit.sol";
import "../lib/MultiUseAuthTypes.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MultiUseAuthDepositTest is Test {
    MultiUseAuthDeposit public token;
    address public owner;
    address public bank;
    address public sponsor;
    address public user1;
    address public user2;
    
    uint256 constant INITIAL_BALANCE = 1000 ether;
    
    event AuthorizationUsed(bytes32 indexed authHash, address indexed sender, uint256 amount, uint256 timesUsed, uint256 totalSpent);
    event AuthorizationRevoked(bytes32 indexed authHash, address indexed revokedBy);

    function setUp() public {
        owner = makeAddr("owner");
        bank = makeAddr("bank");
        sponsor = makeAddr("sponsor");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        
        vm.startPrank(owner);
        
        // Deploy implementation
        MultiUseAuthDeposit implementation = new MultiUseAuthDeposit();
        
        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(
            MultiUseAuthDeposit.initialize.selector,
            "Multi-Use Deposit Token",
            "MUDT",
            bank,
            "https://bank.example.com/auth"
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        token = MultiUseAuthDeposit(address(proxy));
        
        // Set up initial state
        token.newSponsor(sponsor);
        token.registerUser(user1, bank);
        token.registerUser(user2, bank);
        
        // Mint tokens to user1
        token.mint(user1, INITIAL_BALANCE);
        
        vm.stopPrank();
    }

    function createMultiUseAuthorization(
        address sender,
        uint256 spendingLimit,
        uint256 totalLimit,
        uint256 expiration,
        uint256 authNonce,
        uint256 maxUses,
        uint256 signerKey
    ) internal view returns (MultiUseAuthTypes.SignedAuthorization memory) {
        MultiUseAuthTypes.MultiUseAuthorization memory auth = MultiUseAuthTypes.MultiUseAuthorization({
            sender: sender,
            spendingLimit: spendingLimit,
            totalLimit: totalLimit,
            expiration: expiration,
            authNonce: authNonce,
            maxUses: maxUses
        });
        
        bytes memory encodedAuth = abi.encode(auth);
        bytes32 authHash = keccak256(abi.encode(encodedAuth));
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, authHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        return MultiUseAuthTypes.SignedAuthorization({
            authorization: encodedAuth,
            signature: signature
        });
    }

    function test_MultiUseAuthorizationBasic() public {
        // Create a multi-use authorization that allows 3 uses, 100 tokens per use, 250 tokens total
        uint256 bankKey = uint256(keccak256(abi.encodePacked("bank")));
        vm.addr(bankKey); // This generates the address for the private key
        
        // We need to use the bank as the signer since it's the sponsor
        vm.startPrank(owner);
        address bankAddr = vm.addr(bankKey);
        token.newSponsor(bankAddr);
        token.setSponsor(user1, bankAddr); // Change sponsor instead of registering again
        vm.stopPrank();
        
        MultiUseAuthTypes.SignedAuthorization memory signedAuth = createMultiUseAuthorization(
            user1,
            100 ether, // spendingLimit per transaction
            250 ether, // totalLimit across all uses
            block.timestamp + 3600, // expiration
            0, // authNonce
            3, // maxUses
            bankKey
        );
        
        // First transfer - should work
        vm.startPrank(user1);
        token.transferWithMultiUseAuthorization(user2, 100 ether, signedAuth);
        
        assertEq(token.balanceOf(user1), INITIAL_BALANCE - 100 ether);
        assertEq(token.balanceOf(user2), 100 ether);
        
        // Check usage tracking
        bytes32 authHash = keccak256(abi.encode(signedAuth.authorization));
        MultiUseAuthTypes.AuthorizationUsage memory usage = token.getAuthorizationUsage(authHash);
        assertEq(usage.timesUsed, 1);
        assertEq(usage.totalSpent, 100 ether);
        assertEq(usage.isRevoked, false);
        
        // Second transfer - should work
        token.transferWithMultiUseAuthorization(user2, 80 ether, signedAuth);
        
        usage = token.getAuthorizationUsage(authHash);
        assertEq(usage.timesUsed, 2);
        assertEq(usage.totalSpent, 180 ether);
        
        // Third transfer - should work (but only 70 tokens due to total limit)
        token.transferWithMultiUseAuthorization(user2, 70 ether, signedAuth);
        
        usage = token.getAuthorizationUsage(authHash);
        assertEq(usage.timesUsed, 3);
        assertEq(usage.totalSpent, 250 ether);
        
        vm.stopPrank();
    }

    function test_MultiUseAuthorizationMaxUsesExceeded() public {
        uint256 bankKey = uint256(keccak256(abi.encodePacked("bank")));
        address bankAddr = vm.addr(bankKey);
        
        vm.startPrank(owner);
        token.newSponsor(bankAddr);
        token.setSponsor(user1, bankAddr); // Change sponsor instead of registering again
        vm.stopPrank();
        
        MultiUseAuthTypes.SignedAuthorization memory signedAuth = createMultiUseAuthorization(
            user1,
            100 ether,
            1000 ether,
            block.timestamp + 3600,
            0,
            2, // Only 2 uses allowed
            bankKey
        );
        
        vm.startPrank(user1);
        
        // Use authorization twice
        token.transferWithMultiUseAuthorization(user2, 100 ether, signedAuth);
        token.transferWithMultiUseAuthorization(user2, 100 ether, signedAuth);
        
        // Third use should fail
        vm.expectRevert(abi.encodeWithSelector(MultiUseAuthDeposit.AuthorizationExhausted.selector, "Maximum uses exceeded"));
        token.transferWithMultiUseAuthorization(user2, 100 ether, signedAuth);
        
        vm.stopPrank();
    }

    function test_MultiUseAuthorizationTotalLimitExceeded() public {
        uint256 bankKey = uint256(keccak256(abi.encodePacked("bank")));
        address bankAddr = vm.addr(bankKey);
        
        vm.startPrank(owner);
        token.newSponsor(bankAddr);
        token.setSponsor(user1, bankAddr); // Change sponsor instead of registering again
        vm.stopPrank();
        
        MultiUseAuthTypes.SignedAuthorization memory signedAuth = createMultiUseAuthorization(
            user1,
            150 ether,
            200 ether, // Total limit
            block.timestamp + 3600,
            0,
            5,
            bankKey
        );
        
        vm.startPrank(user1);
        
        // First transfer - 150 tokens
        token.transferWithMultiUseAuthorization(user2, 150 ether, signedAuth);
        
        // Second transfer - should fail because 150 + 100 > 200 total limit
        vm.expectRevert(abi.encodeWithSelector(MultiUseAuthDeposit.AuthorizationExhausted.selector, "Total spending limit exceeded"));
        token.transferWithMultiUseAuthorization(user2, 100 ether, signedAuth);
        
        // But a smaller transfer should work
        token.transferWithMultiUseAuthorization(user2, 50 ether, signedAuth);
        
        vm.stopPrank();
    }

    function test_MultiUseAuthorizationRevocation() public {
        uint256 bankKey = uint256(keccak256(abi.encodePacked("bank")));
        address bankAddr = vm.addr(bankKey);
        
        vm.startPrank(owner);
        token.newSponsor(bankAddr);
        token.setSponsor(user1, bankAddr); // Change sponsor instead of registering again
        vm.stopPrank();
        
        MultiUseAuthTypes.SignedAuthorization memory signedAuth = createMultiUseAuthorization(
            user1,
            100 ether,
            300 ether,
            block.timestamp + 3600,
            0,
            3,
            bankKey
        );
        
        bytes32 authHash = keccak256(abi.encode(signedAuth.authorization));
        
        vm.startPrank(user1);
        
        // First transfer should work
        token.transferWithMultiUseAuthorization(user2, 100 ether, signedAuth);
        
        vm.stopPrank();
        
        // Revoke the authorization
        vm.startPrank(owner);
        vm.expectEmit(true, true, false, true);
        emit AuthorizationRevoked(authHash, owner);
        token.revokeAuthorization(authHash);
        vm.stopPrank();
        
        // Subsequent transfers should fail
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(MultiUseAuthDeposit.AuthorizationAlreadyRevoked.selector));
        token.transferWithMultiUseAuthorization(user2, 100 ether, signedAuth);
        vm.stopPrank();
    }

    function test_MultiUseAuthorizationPerTransactionLimit() public {
        uint256 bankKey = uint256(keccak256(abi.encodePacked("bank")));
        address bankAddr = vm.addr(bankKey);
        
        vm.startPrank(owner);
        token.newSponsor(bankAddr);
        token.setSponsor(user1, bankAddr); // Change sponsor instead of registering again
        vm.stopPrank();
        
        MultiUseAuthTypes.SignedAuthorization memory signedAuth = createMultiUseAuthorization(
            user1,
            100 ether, // Per-transaction limit
            500 ether,
            block.timestamp + 3600,
            0,
            5,
            bankKey
        );
        
        vm.startPrank(user1);
        
        // Transfer within per-transaction limit should work
        token.transferWithMultiUseAuthorization(user2, 100 ether, signedAuth);
        
        // Transfer exceeding per-transaction limit should fail
        vm.expectRevert(abi.encodeWithSelector(MultiUseAuthDeposit.Unauthorized.selector, "Insufficient per-transaction spending limit"));
        token.transferWithMultiUseAuthorization(user2, 150 ether, signedAuth);
        
        vm.stopPrank();
    }

    function test_MultiUseAuthorizationExpiration() public {
        uint256 bankKey = uint256(keccak256(abi.encodePacked("bank")));
        address bankAddr = vm.addr(bankKey);
        
        vm.startPrank(owner);
        token.newSponsor(bankAddr);
        token.setSponsor(user1, bankAddr); // Change sponsor instead of registering again
        vm.stopPrank();
        
        uint256 expiration = block.timestamp + 3600;
        
        MultiUseAuthTypes.SignedAuthorization memory signedAuth = createMultiUseAuthorization(
            user1,
            100 ether,
            300 ether,
            expiration,
            0,
            3,
            bankKey
        );
        
        vm.startPrank(user1);
        
        // Transfer before expiration should work
        token.transferWithMultiUseAuthorization(user2, 100 ether, signedAuth);
        
        // Fast forward past expiration
        vm.warp(expiration + 1);
        
        // Transfer after expiration should fail
        vm.expectRevert(abi.encodeWithSelector(MultiUseAuthDeposit.Unauthorized.selector, "Authorization expired"));
        token.transferWithMultiUseAuthorization(user2, 100 ether, signedAuth);
        
        vm.stopPrank();
    }

    function test_MultiUseAuthorizationEvents() public {
        uint256 bankKey = uint256(keccak256(abi.encodePacked("bank")));
        address bankAddr = vm.addr(bankKey);
        
        vm.startPrank(owner);
        token.newSponsor(bankAddr);
        token.setSponsor(user1, bankAddr); // Change sponsor instead of registering again
        vm.stopPrank();
        
        MultiUseAuthTypes.SignedAuthorization memory signedAuth = createMultiUseAuthorization(
            user1,
            100 ether,
            300 ether,
            block.timestamp + 3600,
            0,
            3,
            bankKey
        );
        
        bytes32 authHash = keccak256(abi.encode(signedAuth.authorization));
        
        vm.startPrank(user1);
        
        // Expect AuthorizationUsed event
        vm.expectEmit(true, true, false, true);
        emit AuthorizationUsed(authHash, user1, 100 ether, 1, 100 ether);
        token.transferWithMultiUseAuthorization(user2, 100 ether, signedAuth);
        
        vm.stopPrank();
    }

    function test_MultiUseAuthorizationUsageTracking() public {
        uint256 bankKey = uint256(keccak256(abi.encodePacked("bank")));
        address bankAddr = vm.addr(bankKey);
        
        vm.startPrank(owner);
        token.newSponsor(bankAddr);
        token.setSponsor(user1, bankAddr); // Change sponsor instead of registering again
        vm.stopPrank();
        
        MultiUseAuthTypes.SignedAuthorization memory signedAuth = createMultiUseAuthorization(
            user1,
            100 ether,
            300 ether,
            block.timestamp + 3600,
            0,
            3,
            bankKey
        );
        
        bytes32 authHash = keccak256(abi.encode(signedAuth.authorization));
        
        // Initial usage should be zero
        MultiUseAuthTypes.AuthorizationUsage memory usage = token.getAuthorizationUsage(authHash);
        assertEq(usage.timesUsed, 0);
        assertEq(usage.totalSpent, 0);
        assertEq(usage.isRevoked, false);
        
        vm.startPrank(user1);
        
        // After first use
        token.transferWithMultiUseAuthorization(user2, 80 ether, signedAuth);
        usage = token.getAuthorizationUsage(authHash);
        assertEq(usage.timesUsed, 1);
        assertEq(usage.totalSpent, 80 ether);
        
        // After second use
        token.transferWithMultiUseAuthorization(user2, 90 ether, signedAuth);
        usage = token.getAuthorizationUsage(authHash);
        assertEq(usage.timesUsed, 2);
        assertEq(usage.totalSpent, 170 ether);
        
        vm.stopPrank();
    }

    function test_MultiUseAuthorizationNonceValidation() public {
        uint256 bankKey = uint256(keccak256(abi.encodePacked("bank")));
        address bankAddr = vm.addr(bankKey);
        
        vm.startPrank(owner);
        token.newSponsor(bankAddr);
        token.setSponsor(user1, bankAddr); // Change sponsor instead of registering again
        vm.stopPrank();
        
        // Create authorization with nonce 0 when account nonce is 0
        MultiUseAuthTypes.SignedAuthorization memory signedAuth = createMultiUseAuthorization(
            user1,
            100 ether,
            300 ether,
            block.timestamp + 3600,
            0, // nonce
            3,
            bankKey
        );
        
        vm.startPrank(user1);
        
        // First transfer should work (nonce remains 0 for multi-use authorizations)
        token.transferWithMultiUseAuthorization(user2, 100 ether, signedAuth);
        
        // Second transfer should also work since multi-use authorizations don't increment nonce
        token.transferWithMultiUseAuthorization(user2, 100 ether, signedAuth);
        
        // Now use a regular transfer to increment the nonce
        token.transfer(user2, 50 ether);
        
        // Now the authorization with nonce 0 should fail because account nonce is 1
        vm.expectRevert(abi.encodeWithSelector(MultiUseAuthDeposit.Unauthorized.selector, "Authorization not valid for account nonce"));
        token.transferWithMultiUseAuthorization(user2, 100 ether, signedAuth);
        
        vm.stopPrank();
    }
}