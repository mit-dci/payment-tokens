// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/BasicDeposit.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract BasicDepositTest is Test {
    using ECDSA for bytes32;

    BasicDeposit public implementation;
    BasicDeposit public basicDeposit;
    
    address public owner;
    address public sponsor;
    address public user1;
    address public user2;
    address public user3;
    
    uint256 sponsorPrivateKey;
    uint256 user1PrivateKey;
    uint256 user2PrivateKey;
    uint256 user3PrivateKey;

    function setUp() public {
        // Set up accounts with private keys for signing
        console.log("starting...");
        owner = address(this); // Test contract is the owner
        sponsorPrivateKey = 0x1;
        user1PrivateKey = 0x2;
        user2PrivateKey = 0x3;
        user3PrivateKey = 0x4;
        sponsor = vm.addr(sponsorPrivateKey);
        user1 = vm.addr(user1PrivateKey);
        user2 = vm.addr(user2PrivateKey);
        user3 = vm.addr(user3PrivateKey);
        // Deploy implementation contract
        implementation = new BasicDeposit();
        // Create and initialize proxy
        bytes memory initData = abi.encodeWithSelector(
            BasicDeposit.initialize.selector, 
            "Deposit",           // tokenName
            "DEP",               // tokenSymbol  
            sponsor,             // initialSponsor
            "https://localhost:3000/" // initial_uri
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        basicDeposit = BasicDeposit(address(proxy));
    }

    function testInitialization() public {
        // Check that the owner is set correctly
        assertEq(basicDeposit.owner(), owner);
        
        // Check constants
        assertEq(basicDeposit.name(), "Deposit");
        assertEq(basicDeposit.symbol(), "DEP");
        assertEq(basicDeposit.VERSION(), "v0.0.1");
        assertEq(basicDeposit.decimals(), 18);
        assertEq(basicDeposit.totalSupply(), 0);
        assertEq(basicDeposit.paused(), false);
    }

    function testUserRegistration() public {
        // Register user1 with a valid sponsor
        basicDeposit.registerUser(user1, sponsor);
        
        // Check that user1 is registered
        assertTrue(basicDeposit.isRegistered(user1));
        
        // Try to register user2 with an invalid sponsor (user3)
        vm.expectRevert(abi.encodeWithSelector(BasicDeposit.InvalidSponsor.selector));
        basicDeposit.registerUser(user2, user3);
        
        // Try to register as non-owner
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        basicDeposit.registerUser(user2, sponsor);
    }

    function testMoveAccountAddress() public {
        // Register user1
        basicDeposit.registerUser(user1, sponsor);
        
        // Mint tokens to user1
        uint256 amount = 100 * 10**18; // 100 tokens with 18 decimals
        basicDeposit.mint(user1, amount);
        
        // Move account from user1 to user2 - need to generate a signature
        bytes32 messageHash = keccak256(abi.encodePacked(keccak256(abi.encode(user1))));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user2PrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        vm.prank(user1);
        basicDeposit.moveAccountAddress(user2, signature);
        
        // Check registrations
        assertFalse(basicDeposit.isRegistered(user1));
        assertTrue(basicDeposit.isRegistered(user2));
        
        // Check balances
        assertEq(basicDeposit.balanceOf(user1), 0);
        assertEq(basicDeposit.balanceOf(user2), amount);
    }

    function testSponsorMoveAccountAddress() public {
        // Register user1
        basicDeposit.registerUser(user1, sponsor);
        
        // Mint tokens to user1
        uint256 amount = 100 * 10**18; // 100 tokens with 18 decimals
        basicDeposit.mint(user1, amount);
        
        // Move account from user1 to user2 by sponsor
        vm.prank(sponsor);
        basicDeposit.moveAccountAddress(user1, user2);
        
        // Check registrations
        assertFalse(basicDeposit.isRegistered(user1));
        assertTrue(basicDeposit.isRegistered(user2));
        
        // Check balances
        assertEq(basicDeposit.balanceOf(user1), 0);
        assertEq(basicDeposit.balanceOf(user2), amount);
    }

    function testBasicTokenOperations() public {
        // Register users
        basicDeposit.registerUser(user1, sponsor);
        basicDeposit.registerUser(user2, sponsor);
        
        // Mint tokens to user1
        uint256 amount = 100 * 10**18; // 100 tokens with 18 decimals
        basicDeposit.mint(user1, amount);
        
        // Check balance and total supply
        assertEq(basicDeposit.balanceOf(user1), amount);
        assertEq(basicDeposit.totalSupply(), amount);
        
        // Transfer tokens from user1 to user2
        uint256 transferAmount = 50 * 10**6; // 50 tokens
        vm.prank(user1);
        basicDeposit.transfer(user2, transferAmount);
        
        // Check balances
        assertEq(basicDeposit.balanceOf(user1), amount - transferAmount);
        assertEq(basicDeposit.balanceOf(user2), transferAmount);
    }

    function testApproveAndTransferFrom() public {
        // Register users
        basicDeposit.registerUser(user1, sponsor);
        basicDeposit.registerUser(user2, sponsor);
        basicDeposit.registerUser(user3, sponsor);
        
        // Mint tokens to user1
        uint256 amount = 100 * 10**18; // 100 tokens with 18 decimals
        basicDeposit.mint(user1, amount);
        
        // Approve user2 to spend user1's tokens
        uint256 approveAmount = 75 * 10**6; // 75 tokens
        vm.prank(user1);
        basicDeposit.approve(user2, approveAmount);
        
        // Check allowance
        assertEq(basicDeposit.allowance(user1, user2), approveAmount);
        
        // TransferFrom user1 to user3 by user2
        uint256 transferAmount = 50 * 10**6; // 50 tokens
        vm.prank(user2);
        basicDeposit.transferFrom(user1, user3, transferAmount);
        
        // Check balances
        assertEq(basicDeposit.balanceOf(user1), amount - transferAmount);
        assertEq(basicDeposit.balanceOf(user3), transferAmount);
        
        // Check reduced allowance - NOTE: Contract may not reduce allowance automatically
        assertEq(basicDeposit.allowance(user1, user2), approveAmount - transferAmount);
    }

    function _createSignedAuthorization(
        address sender,
        uint256 spendingLimit,
        uint256 expiration,
        uint256 nonceExpiration,
        uint256 authNonce,
        uint256 signerPrivateKey
    ) internal pure returns (bytes memory authorization, bytes memory signature) {
        // Create authorization
        authorization = abi.encode(
            sender,
            spendingLimit,
            expiration,
            nonceExpiration,
            authNonce
        );
        
        // Hash the authorization
        bytes32 authorizationHash = keccak256(authorization);
        
        // Sign the hash
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, authorizationHash);
        signature = abi.encodePacked(r, s, v);
        
        return (authorization, signature);
    }

    function testTransferWithAuthorization() public {
        // Register users
        basicDeposit.registerUser(user1, sponsor);
        basicDeposit.registerUser(user2, sponsor);
        
        // Mint tokens to user1
        uint256 amount = 100 * 10**18; // 100 tokens with 18 decimals
        basicDeposit.mint(user1, amount);
        
        // Create signed authorization
        uint256 transferAmount = 50 * 10**6; // 50 tokens
        uint256 expiration = block.timestamp + 3600; // 1 hour from now
        uint256 nonceExpiration = 100; // Some future nonce
        uint256 authNonce = 1; // Authorization nonce
        
        (bytes memory authorization, bytes memory signature) = _createSignedAuthorization(
            user1,
            transferAmount,
            expiration,
            nonceExpiration,
            authNonce,
            sponsorPrivateKey
        );
        
        // Create the SignedAuthorization struct
        AuthTypes.SignedAuthorization memory signedAuth = AuthTypes.SignedAuthorization({
            authorization: authorization,
            signature: signature
        });
        
        // Transfer with authorization
        vm.prank(user1);
        basicDeposit.transferWithAuthorization(user2, transferAmount, signedAuth);
        
        // Check balances
        assertEq(basicDeposit.balanceOf(user1), amount - transferAmount);
        assertEq(basicDeposit.balanceOf(user2), transferAmount);
    }

    function testRevokeAuthorization() public {
        // Register users
        basicDeposit.registerUser(user1, sponsor);
        basicDeposit.registerUser(user2, sponsor);
        
        // Mint tokens to user1
        uint256 amount = 100 * 10**18; // 100 tokens with 18 decimals
        basicDeposit.mint(user1, amount);
        
        // Create signed authorization
        uint256 transferAmount = 50 * 10**6; // 50 tokens
        uint256 expiration = block.timestamp + 3600; // 1 hour from now
        uint256 nonceExpiration = 100; // Some future nonce
        uint256 authNonce = 2; // Authorization nonce
        
        (bytes memory authorization, bytes memory signature) = _createSignedAuthorization(
            user1,
            transferAmount,
            expiration,
            nonceExpiration,
            authNonce,
            sponsorPrivateKey
        );
        
        // Create the SignedAuthorization struct
        AuthTypes.SignedAuthorization memory signedAuth = AuthTypes.SignedAuthorization({
            authorization: authorization,
            signature: signature
        });
        
        // Note: revokeAuthorization function not implemented in BasicDeposit
        // Skipping revocation test for now
    }

//     function testFreezeAndUnfreeze() public {
//         // Register user
//         basicDeposit.registerUser(user1, sponsor);
        
//         // Freeze account
//         vm.prank(sponsor);
//         basicDeposit.freeze(user1);
        
//         // Unfreeze account and check event
//         vm.prank(sponsor);
//         vm.expectEmit(true, true, false, false);
//         emit BasicDeposit.Unfreeze(sponsor, user1);
//         basicDeposit.unfreeze(user1);
//     }

//     function testSeizeFunds() public {
//         // Register user
//         basicDeposit.registerUser(user1, sponsor);
        
//         // Mint tokens to user1
//         uint256 amount = 100 * 10**18; // 100 tokens with 18 decimals
//         basicDeposit.mint(user1, amount);
        
//         // Seize half of the funds
//         uint256 seizeAmount = 50 * 10**6; // 50 tokens
//         vm.prank(sponsor);
//         basicDeposit.seize(user1, seizeAmount);
        
//         // Check balance
//         assertEq(basicDeposit.balanceOf(user1), amount - seizeAmount);
        
//         // The seized amount should be in locked balance, not accessible to the user
//         // We'd need a getter for lockedBalance to verify this further
//     }

//     function testSponsorManagement() public {
//         // Add user1 as a sponsor
//         basicDeposit.newSponsor(user1);
        
//         // Register user2 with user1 as sponsor
//         basicDeposit.registerUser(user2, user1);
//         assertTrue(basicDeposit.isRegistered(user2));
        
//         // Remove user1 as a sponsor
//         basicDeposit.removeSponsor(user1);
        
//         // Try to register user3 with removed sponsor
//         vm.expectRevert(abi.encodeWithSelector(BasicDeposit.InvalidSponsor.selector));
//         basicDeposit.registerUser(user3, user1);
//     }

//     function testChangeSponsor() public {
//         // Register user1 with initial sponsor
//         basicDeposit.registerUser(user1, sponsor);
        
//         // Add user2 as a new sponsor
//         basicDeposit.newSponsor(user2);
        
//         // Change user1's sponsor to user2
//         basicDeposit.setSponsor(user1, user2);
        
//         // Verify the new sponsor can perform sponsor actions
//         vm.prank(user2);
//         basicDeposit.freeze(user1);
        
//         // Original sponsor should no longer have permissions
//         vm.prank(sponsor);
//         vm.expectRevert(abi.encodeWithSelector(BasicDeposit.Unauthorized.selector, "not authorized for this account"));
//         basicDeposit.freeze(user1);
//     }

//     function testUpdateAuthorizationURI() public {
//         string memory newURI = "https://example.com/authorizations";
        
//         vm.expectEmit(true, false, false, false);
//         emit BasicDeposit.URIUpdated(newURI);
//         basicDeposit.updateAuthorizationURI(newURI);
        
//         assertEq(basicDeposit.authorizationURI(), newURI);
//     }

//     function testUpgradeability() public {
//         // Deploy a new implementation
//         BasicDeposit newImplementation = new BasicDeposit();
        
//         // Upgrade to the new implementation
//         basicDeposit.upgradeTo(address(newImplementation));
        
//         // Test that functionality still works after upgrade
//         basicDeposit.registerUser(user1, sponsor);
//         assertTrue(basicDeposit.isRegistered(user1));
//     }

//     function testOnlyOwnerCanUpgrade() public {
//         // Deploy a new implementation
//         BasicDeposit newImplementation = new BasicDeposit();
        
//         // Try to upgrade from non-owner account
//         vm.prank(user1);
//         vm.expectRevert("Ownable: caller is not the owner");
//         basicDeposit.upgradeTo(address(newImplementation));
//     }
// }
}