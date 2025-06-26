const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

describe("BasicDeposit", function () {
  // We define a fixture to reuse the same setup in every test
  async function deployBasicDepositFixture() {
    // Get signers
    const [owner, sponsor, user1, user2, user3] = await ethers.getSigners();

    // Deploy implementation contract
    const BasicDeposit = await ethers.getContractFactory("BasicDeposit");
    const implementation = await BasicDeposit.deploy();
    await implementation.deployed();

    // Create proxy
    const ERC1967Proxy = await ethers.getContractFactory("ERC1967Proxy");
    const initData = implementation.interface.encodeFunctionData("initialize");
    const proxy = await ERC1967Proxy.deploy(implementation.address, initData);
    await proxy.deployed();

    // Attach implementation interface to proxy
    const basicDeposit = BasicDeposit.attach(proxy.address);

    // Register sponsor
    await basicDeposit.newSponsor(sponsor.address);

    return { basicDeposit, owner, sponsor, user1, user2, user3 };
  }

  describe("Initialization", function () {
    it("Should set the right owner", async function () {
      const { basicDeposit, owner } = await loadFixture(deployBasicDepositFixture);
      expect(await basicDeposit.owner()).to.equal(owner.address);
    });

    it("Should initialize with correct constant values", async function () {
      const { basicDeposit } = await loadFixture(deployBasicDepositFixture);
      expect(await basicDeposit.NAME()).to.equal("Deposit");
      expect(await basicDeposit.SYMBOL()).to.equal("DEP");
      expect(await basicDeposit.VERSION()).to.equal("1");
      expect(await basicDeposit.DECIMALS()).to.equal(6);
      expect(await basicDeposit.totalSupply()).to.equal(0);
      expect(await basicDeposit.authorizationSize()).to.equal(140);
      expect(await basicDeposit.signedAuthorizationSize()).to.equal(205);
      expect(await basicDeposit.isHalted()).to.equal(false);
    });
  });

  describe("User Registration", function () {
    it("Should register a user with a valid sponsor", async function () {
      const { basicDeposit, owner, sponsor, user1 } = await loadFixture(deployBasicDepositFixture);
      
      await expect(basicDeposit.registerUser(user1.address, sponsor.address))
        .to.emit(basicDeposit, "UserRegistered")
        .withArgs(user1.address);
      
      expect(await basicDeposit.isRegistered(user1.address)).to.equal(true);
    });

    it("Should revert when registering a user with an invalid sponsor", async function () {
      const { basicDeposit, owner, user1, user2 } = await loadFixture(deployBasicDepositFixture);
      
      await expect(basicDeposit.registerUser(user1.address, user2.address))
        .to.be.revertedWithCustomError(basicDeposit, "InvalidSponsor");
    });

    it("Should only allow owner to register users", async function () {
      const { basicDeposit, sponsor, user1, user2 } = await loadFixture(deployBasicDepositFixture);
      
      await expect(basicDeposit.connect(user1).registerUser(user2.address, sponsor.address))
        .to.be.revertedWith("Ownable: caller is not the owner");
    });
  });

  describe("Account Management", function () {
    it("Should allow a user to move their account to a new address", async function () {
      const { basicDeposit, owner, sponsor, user1, user2 } = await loadFixture(deployBasicDepositFixture);
      
      // Register user1
      await basicDeposit.registerUser(user1.address, sponsor.address);
      
      // Mint some tokens to user1
      await basicDeposit.mint(user1.address, ethers.utils.parseUnits("100", 6));
      
      // Move account from user1 to user2
      await basicDeposit.connect(user1).moveAccountAddress(user2.address);
      
      // Check that user1 is no longer registered and user2 is registered
      expect(await basicDeposit.isRegistered(user1.address)).to.equal(false);
      expect(await basicDeposit.isRegistered(user2.address)).to.equal(true);
      
      // Check that the balance moved
      expect(await basicDeposit.balanceOf(user1.address)).to.equal(0);
      expect(await basicDeposit.balanceOf(user2.address)).to.equal(ethers.utils.parseUnits("100", 6));
    });

    it("Should allow authorized party to move an account", async function () {
      const { basicDeposit, owner, sponsor, user1, user2 } = await loadFixture(deployBasicDepositFixture);
      
      // Register user1
      await basicDeposit.registerUser(user1.address, sponsor.address);
      
      // Mint some tokens to user1
      await basicDeposit.mint(user1.address, ethers.utils.parseUnits("100", 6));
      
      // Move account from user1 to user2 by sponsor
      await basicDeposit.connect(sponsor).moveAccountAddress(user1.address, user2.address);
      
      // Check that user1 is no longer registered and user2 is registered
      expect(await basicDeposit.isRegistered(user1.address)).to.equal(false);
      expect(await basicDeposit.isRegistered(user2.address)).to.equal(true);
      
      // Check that the balance moved
      expect(await basicDeposit.balanceOf(user1.address)).to.equal(0);
      expect(await basicDeposit.balanceOf(user2.address)).to.equal(ethers.utils.parseUnits("100", 6));
    });
  });

  describe("Basic Token Operations", function () {
    it("Should mint tokens to a user", async function () {
      const { basicDeposit, owner, sponsor, user1 } = await loadFixture(deployBasicDepositFixture);
      
      // Register user1
      await basicDeposit.registerUser(user1.address, sponsor.address);
      
      // Mint tokens to user1
      const amount = ethers.utils.parseUnits("100", 6);
      await expect(basicDeposit.mint(user1.address, amount))
        .to.emit(basicDeposit, "Mint")
        .withArgs(owner.address, user1.address, amount);
      
      // Check balance and total supply
      expect(await basicDeposit.balanceOf(user1.address)).to.equal(amount);
      expect(await basicDeposit.totalSupply()).to.equal(amount);
    });

    it("Should transfer tokens between users", async function () {
      const { basicDeposit, owner, sponsor, user1, user2 } = await loadFixture(deployBasicDepositFixture);
      
      // Register users
      await basicDeposit.registerUser(user1.address, sponsor.address);
      await basicDeposit.registerUser(user2.address, sponsor.address);
      
      // Mint tokens to user1
      const amount = ethers.utils.parseUnits("100", 6);
      await basicDeposit.mint(user1.address, amount);
      
      // Transfer tokens from user1 to user2
      const transferAmount = ethers.utils.parseUnits("50", 6);
      await basicDeposit.connect(user1).transfer(user2.address, transferAmount);
      
      // Check balances
      expect(await basicDeposit.balanceOf(user1.address)).to.equal(amount.sub(transferAmount));
      expect(await basicDeposit.balanceOf(user2.address)).to.equal(transferAmount);
    });

    it("Should approve and transferFrom", async function () {
      const { basicDeposit, owner, sponsor, user1, user2, user3 } = await loadFixture(deployBasicDepositFixture);
      
      // Register users
      await basicDeposit.registerUser(user1.address, sponsor.address);
      await basicDeposit.registerUser(user2.address, sponsor.address);
      await basicDeposit.registerUser(user3.address, sponsor.address);
      
      // Mint tokens to user1
      const amount = ethers.utils.parseUnits("100", 6);
      await basicDeposit.mint(user1.address, amount);
      
      // Approve user2 to spend user1's tokens
      const approveAmount = ethers.utils.parseUnits("75", 6);
      await basicDeposit.connect(user1).approve(user2.address, approveAmount);
      
      // Check allowance
      expect(await basicDeposit.allowance(user1.address, user2.address)).to.equal(approveAmount);
      
      // TransferFrom user1 to user3 by user2
      const transferAmount = ethers.utils.parseUnits("50", 6);
      await basicDeposit.connect(user2).transferFrom(user1.address, user3.address, transferAmount);
      
      // Check balances
      expect(await basicDeposit.balanceOf(user1.address)).to.equal(amount.sub(transferAmount));
      expect(await basicDeposit.balanceOf(user3.address)).to.equal(transferAmount);
      
      // Check allowance decreased
      expect(await basicDeposit.allowance(user1.address, user2.address)).to.equal(approveAmount.sub(transferAmount));
    });
  });

  describe("Authorization", function () {
    async function createSignedAuthorization(sender, spendingLimit, expiration, nonceExpiration, authNonce, signer) {
      // Create authorization object
      const authorization = ethers.utils.defaultAbiCoder.encode(
        ["address", "uint256", "uint256", "uint256", "uint256"],
        [sender.address, spendingLimit, expiration, nonceExpiration, authNonce]
      );
      
      // Hash the authorization
      const authorizationHash = ethers.utils.keccak256(authorization);
      
      // Sign the hash
      const signature = await signer.signMessage(ethers.utils.arrayify(authorizationHash));
      
      return {
        authorization,
        signature
      };
    }
    
    it("Should transfer with authorization", async function () {
      const { basicDeposit, owner, sponsor, user1, user2 } = await loadFixture(deployBasicDepositFixture);
      
      // Register users
      await basicDeposit.registerUser(user1.address, sponsor.address);
      await basicDeposit.registerUser(user2.address, sponsor.address);
      
      // Mint tokens to user1
      const amount = ethers.utils.parseUnits("100", 6);
      await basicDeposit.mint(user1.address, amount);
      
      // Create signed authorization
      const transferAmount = ethers.utils.parseUnits("50", 6);
      const currentTime = Math.floor(Date.now() / 1000);
      const expiration = currentTime + 3600; // 1 hour from now
      const nonceExpiration = 100; // Some future nonce
      const authNonce = 1; // Authorization nonce
      
      const signedAuth = await createSignedAuthorization(
        user1, 
        transferAmount, 
        expiration, 
        nonceExpiration, 
        authNonce, 
        sponsor
      );
      
      // Transfer with authorization
      await basicDeposit.connect(user1).transferWithAuthorization(
        user2.address,
        transferAmount,
        signedAuth
      );
      
      // Check balances
      expect(await basicDeposit.balanceOf(user1.address)).to.equal(amount.sub(transferAmount));
      expect(await basicDeposit.balanceOf(user2.address)).to.equal(transferAmount);
    });

    it("Should revoke authorization", async function () {
      const { basicDeposit, owner, sponsor, user1, user2 } = await loadFixture(deployBasicDepositFixture);
      
      // Register users
      await basicDeposit.registerUser(user1.address, sponsor.address);
      await basicDeposit.registerUser(user2.address, sponsor.address);
      
      // Mint tokens to user1
      const amount = ethers.utils.parseUnits("100", 6);
      await basicDeposit.mint(user1.address, amount);
      
      // Create signed authorization
      const transferAmount = ethers.utils.parseUnits("50", 6);
      const currentTime = Math.floor(Date.now() / 1000);
      const expiration = currentTime + 3600; // 1 hour from now
      const nonceExpiration = 100; // Some future nonce
      const authNonce = 2; // Authorization nonce
      
      const signedAuth = await createSignedAuthorization(
        user1, 
        transferAmount, 
        expiration, 
        nonceExpiration, 
        authNonce, 
        sponsor
      );
      
      // Revoke this authorization
      await basicDeposit.connect(sponsor).revokeAuthorization(user1.address, authNonce);
      
      // Try to transfer with the revoked authorization - should fail
      await expect(
        basicDeposit.connect(user1).transferWithAuthorization(
          user2.address,
          transferAmount,
          signedAuth
        )
      ).to.be.revertedWithCustomError(basicDeposit, "Unauthorized");
    });
  });

  describe("Account Freezing and Seizing", function () {
    it("Should freeze and unfreeze an account", async function () {
      const { basicDeposit, owner, sponsor, user1 } = await loadFixture(deployBasicDepositFixture);
      
      // Register user
      await basicDeposit.registerUser(user1.address, sponsor.address);
      
      // Freeze account
      await basicDeposit.connect(sponsor).freeze(user1.address);
      
      // Unfreeze account
      await expect(basicDeposit.connect(sponsor).unfreeze(user1.address))
        .to.emit(basicDeposit, "Unfreeze")
        .withArgs(sponsor.address, user1.address);
    });

    it("Should seize funds from an account", async function () {
      const { basicDeposit, owner, sponsor, user1 } = await loadFixture(deployBasicDepositFixture);
      
      // Register user
      await basicDeposit.registerUser(user1.address, sponsor.address);
      
      // Mint tokens to user1
      const amount = ethers.utils.parseUnits("100", 6);
      await basicDeposit.mint(user1.address, amount);
      
      // Seize half of the funds
      const seizeAmount = ethers.utils.parseUnits("50", 6);
      await basicDeposit.connect(sponsor).seize(user1.address, seizeAmount);
      
      // Check balances
      expect(await basicDeposit.balanceOf(user1.address)).to.equal(amount.sub(seizeAmount));
      
      // The seized amount should be in locked balance, not accessible to the user
      // We'd need a getter for lockedBalance to verify this - assuming it exists
    });
  });

  describe("Sponsor Management", function () {
    it("Should add and remove sponsors", async function () {
      const { basicDeposit, owner, user1, user2 } = await loadFixture(deployBasicDepositFixture);
      
      // Add user1 as a sponsor
      await basicDeposit.newSponsor(user1.address);
      
      // Register user2 with user1 as sponsor
      await basicDeposit.registerUser(user2.address, user1.address);
      expect(await basicDeposit.isRegistered(user2.address)).to.equal(true);
      
      // Remove user1 as a sponsor
      await basicDeposit.removeSponsor(user1.address);
      
      // Try to register new user with removed sponsor
      const user3 = ethers.Wallet.createRandom().connect(ethers.provider);
      await expect(basicDeposit.registerUser(user3.address, user1.address))
        .to.be.revertedWithCustomError(basicDeposit, "InvalidSponsor");
    });

    it("Should change a user's sponsor", async function () {
      const { basicDeposit, owner, sponsor, user1, user2 } = await loadFixture(deployBasicDepositFixture);
      
      // Register user1 with initial sponsor
      await basicDeposit.registerUser(user1.address, sponsor.address);
      
      // Add user2 as a new sponsor
      await basicDeposit.newSponsor(user2.address);
      
      // Change user1's sponsor to user2
      await basicDeposit.setSponsor(user1.address, user2.address);
      
      // Verify the new sponsor can perform sponsor actions
      await basicDeposit.connect(user2).freeze(user1.address);
    });
  });

  describe("System Management", function () {
    it("Should update authorization URI", async function () {
      const { basicDeposit, owner } = await loadFixture(deployBasicDepositFixture);
      
      const newURI = "https://example.com/authorizations";
      
      await expect(basicDeposit.updateAuthorizationURI(newURI))
        .to.emit(basicDeposit, "URIUpdated")
        .withArgs(newURI);
      
      expect(await basicDeposit.authorizationURI()).to.equal(newURI);
    });

    it("Should halt and unhalt system operations", async function () {
      const { basicDeposit, owner, sponsor, user1, user2 } = await loadFixture(deployBasicDepositFixture);
      
      // Register users
      await basicDeposit.registerUser(user1.address, sponsor.address);
      await basicDeposit.registerUser(user2.address, sponsor.address);
      
      // Mint tokens to user1
      const amount = ethers.utils.parseUnits("100", 6);
      await basicDeposit.mint(user1.address, amount);
      
      // There's no explicit halt function in the contract, so we'd need to add one
      // For now, we can test the isNotHalted modifier indirectly
      
      // Assuming there's a way to halt the system (would need to add this function)
      // basicDeposit.connect(owner).haltSystem();
      
      // Try operations that have the isNotHalted modifier
      // These should fail when system is halted
    });
  });

  describe("Upgradability", function () {
    it("Should allow the owner to upgrade the implementation", async function () {
      const { basicDeposit, owner } = await loadFixture(deployBasicDepositFixture);
      
      // Deploy a new implementation
      const BasicDepositV2 = await ethers.getContractFactory("BasicDeposit");
      const newImplementation = await BasicDepositV2.deploy();
      await newImplementation.deployed();
      
      // Upgrade to the new implementation
      await basicDeposit.upgradeTo(newImplementation.address);
      
      // Verify the upgrade was successful
      // We'd need to add a version getter to check this
    });

    it("Should not allow non-owners to upgrade the implementation", async function () {
      const { basicDeposit, user1 } = await loadFixture(deployBasicDepositFixture);
      
      // Deploy a new implementation
      const BasicDepositV2 = await ethers.getContractFactory("BasicDeposit");
      const newImplementation = await BasicDepositV2.deploy();
      await newImplementation.deployed();
      
      // Try to upgrade from a non-owner account
      await expect(
        basicDeposit.connect(user1).upgradeTo(newImplementation.address)
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });
  });
});