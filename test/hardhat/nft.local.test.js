const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("TMAISoulboundNFT", function () {
  let soulboundNFT;
  let owner;
  let minter;
  let addr1;
  let addr2;

  before(async function () {
    [owner, minter, addr1, addr2] = await ethers.getSigners();
  });

  describe("Deployment", function () {
    it("Should deploy the TMAISoulboundNFT contract", async function () {
      const TMAISoulboundNFT = await ethers.getContractFactory("TMAISoulboundNFT");
      soulboundNFT = await upgrades.deployProxy(TMAISoulboundNFT, []);
      await soulboundNFT.waitForDeployment();

      // Grant minter role to the minter address
      await soulboundNFT.grantMinterRole(minter.address);
    });

    it("Should set the correct owner", async function () {
      expect(await soulboundNFT.owner()).to.equal(owner.address);
    });

    it("Should grant the MINTER_ROLE to the minter", async function () {
      expect(await soulboundNFT.minter()).to.equal(minter.address);
    });
  });

  describe("Minting and Burning NFTs", function () {
    it("Should mint a new NFT", async function () {
      await soulboundNFT.connect(minter).mint(addr1.address, "analytics", "premium", 365 * 24 * 60 * 60); // 1 year

      const tokenId = await soulboundNFT.userToTokenId(addr1.address, "analytics");
      expect(await soulboundNFT.ownerOf(tokenId)).to.equal(addr1.address);

      const planDetails = await soulboundNFT.getUserPlanDetails(addr1.address, "analytics");
      expect(planDetails.planType).to.equal("premium");
    });

    it("Should burn an existing NFT", async function () {
      const tokenId = await soulboundNFT.userToTokenId(addr1.address, "analytics");
      await soulboundNFT.connect(owner).burn(tokenId);

      await expect(soulboundNFT.ownerOf(tokenId)).to.be.revertedWith("ERC721: invalid token ID");
    });

    it("Should mint a new NFT after burning the old one", async function () {
      await soulboundNFT.connect(minter).mint(addr1.address, "analytics", "basic", 30 * 24 * 60 * 60); // 1 month

      const tokenId = await soulboundNFT.userToTokenId(addr1.address, "analytics");
      expect(await soulboundNFT.ownerOf(tokenId)).to.equal(addr1.address);

      const planDetails = await soulboundNFT.getUserPlanDetails(addr1.address, "analytics");
      expect(planDetails.planType).to.equal("basic");
    });
  });

  describe("Upgrading NFTs", function () {
    it("Should upgrade an NFT's plan details", async function () {
      await soulboundNFT.connect(minter).upgradeNFT(addr1.address, "analytics", "premium", 90 * 24 * 60 * 60); // 3 months

      const tokenId = await soulboundNFT.userToTokenId(addr1.address, "analytics");
      const planDetails = await soulboundNFT.tokenIdToPlanDetails(tokenId);

      expect(planDetails.planType).to.equal("premium");
      expect(planDetails.expiryDate).to.be.closeTo((await ethers.provider.getBlock()).timestamp + 90 * 24 * 60 * 60, 10); // +/- 10 seconds
    });

    it("Should not upgrade an expired NFT", async function () {
      const tokenId = await soulboundNFT.userToTokenId(addr1.address, "analytics");

      // Simulate the passage of time to expire the NFT
      await ethers.provider.send("evm_increaseTime", [90 * 24 * 60 * 60 + 1]); // Expire the NFT
      await ethers.provider.send("evm_mine");

      await expect(soulboundNFT.connect(minter).upgradeNFT(addr1.address, "analytics", "vip", 365 * 24 * 60 * 60))
        .to.be.revertedWith("Cannot upgrade an expired NFT");
    });
  });

  describe("Metadata URI Management", function () {
    it("Should set and retrieve the correct metadata URI", async function () {
      await soulboundNFT.connect(owner).setBaseURI("ipfs://QmeSjSinHpPnmXmspMjwiXyN6zS4E9zccariGR3jxcaWtq/");

      const tokenId = await soulboundNFT.userToTokenId(addr1.address, "analytics");
      const tokenURI = await soulboundNFT.tokenURI(tokenId);

      expect(tokenURI).to.equal("ipfs://QmeSjSinHpPnmXmspMjwiXyN6zS4E9zccariGR3jxcaWtq/analytics/premium");
    });
  });

  describe("Non-Transferability", function () {
    it("Should prevent transferring NFTs by non-owner", async function () {
      const tokenId = await soulboundNFT.userToTokenId(addr1.address, "analytics");

      await expect(
        soulboundNFT.connect(addr1).transferFrom(addr1.address, addr2.address, tokenId)
      ).to.be.revertedWith("Soulbound tokens are non-transferable");
    });
  });
});