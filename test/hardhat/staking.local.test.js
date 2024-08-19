const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("TMAIStaking", function () {
  let staking;
  let token;
  let erc721;
  let owner;
  let addr1;
  let addr2;
  let addr3;
  let uniswapUtility;

  const REWARD_AMOUNT = ethers.parseUnits("1000000", 18);
  const START_BLOCK = 100;
  const BONUS_END_BLOCK = 200;
  const TOTAL_REWARDS = ethers.parseUnits("100000", 18);

  describe("Deployment", function () {

    it("Should get signers", async function () {
      [owner, addr1, addr2, addr3] = await ethers.getSigners();
    });

    it("Should deploy mock contracts", async function () {
      const Token = await ethers.getContractFactory("ERC20Mock");
      token = await Token.deploy("Test Token", "TT", REWARD_AMOUNT);
      await token.waitForDeployment();

      const ERC721Mock = await ethers.getContractFactory("ERC721Mock");
      erc721 = await ERC721Mock.deploy("Test NFT", "TNFT");
      await erc721.waitForDeployment();

      const UniswapV3PositionUtility = await ethers.getContractFactory("UniswapV3PositionUtilityMock");
      uniswapUtility = await UniswapV3PositionUtility.deploy();
      await uniswapUtility.waitForDeployment();
    });

    it("Should deploy TMAIStaking contract", async function () {

      const TMAIStaking = await ethers.getContractFactory("TMAIStakingMock");

      staking = await upgrades.deployProxy(TMAIStaking, [
        await token.getAddress(),
        START_BLOCK,
        BONUS_END_BLOCK,
        TOTAL_REWARDS
      ]);
      await staking.waitForDeployment();

      await token.transfer(staking.address, TOTAL_REWARDS);

    });

  });

  describe("Check Initial Configuration", function () {
    it("Should set the correct token address", async function () {
      expect(await staking.token()).to.equal(await token.getAddress());
    });

    it("Should set the correct owner", async function () {
      expect(await staking.owner()).to.equal(owner.address);
    });

    it("Should initialize the staking contract with the correct values", async function () {
      expect(await staking.bonusEndBlock()).to.equal(BONUS_END_BLOCK);
      expect(await staking.startBlock()).to.equal(START_BLOCK);
      expect(await staking.totalRewards()).to.equal(TOTAL_REWARDS);
    });
  });

  describe("Governance and Utility Contract", function () {
    it("Should allow only the owner to set governance address", async function () {
      await staking.setGovernanceAddress(addr1.address);
      expect(await staking.governanceAddress()).to.equal(addr1.address);

      await expect(staking.connect(addr1).setGovernanceAddress(addr2.address))
        .to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("Should allow only the owner to set the utility contract address", async function () {
      await staking.setUtilityContractAddress(uniswapUtility.address);
      expect(await staking.uniswapUtility()).to.equal(uniswapUtility.address);

      await expect(staking.connect(addr1).setUtilityContractAddress(addr2.address))
        .to.be.revertedWith("Ownable: caller is not the owner");
    });
  });

  describe("Pool and Token Management", function () {
    it("Should add a new pool", async function () {
      await staking.add(100, token.address);
      expect(await staking.poolLength()).to.equal(2); // Default pool + new pool
    });

    it("Should whitelist a deposit contract", async function () {
      await staking.whitelistDepositContract(addr1.address, true);
      expect(await staking.isAllowedContract(addr1.address)).to.be.true;

      await expect(staking.connect(addr1).whitelistDepositContract(addr2.address, true))
        .to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("Should distribute additional rewards", async function () {
      await staking.whitelistDistributionAddress(addr1.address, true);
      await token.transfer(addr1.address, ethers.utils.parseUnits("10000", 18));
      await token.connect(addr1).approve(staking.address, ethers.utils.parseUnits("10000", 18));
      await staking.connect(addr1).distributeAdditionalReward(ethers.utils.parseUnits("10000", 18));

      expect(await staking.totalRewards()).to.equal(ethers.utils.parseUnits("110000", 18));
    });
  });

  describe("Staking and Reward Mechanics", function () {
    beforeEach(async function () {
      await staking.add(100, token.address);
    });

    it("Should allow users to deposit tokens and update pool info", async function () {
      await token.transfer(addr1.address, ethers.utils.parseUnits("1000", 18));
      await token.connect(addr1).approve(staking.address, ethers.utils.parseUnits("1000", 18));
      await staking.connect(addr1).deposit(ethers.utils.parseUnits("1000", 18), 0, false);

      const userInfo = await staking.userInfo(0, addr1.address);
      expect(userInfo.amount).to.equal(ethers.utils.parseUnits("1000", 18));

      const poolInfo = await staking.poolInfo(0);
      expect(poolInfo.totalStaked).to.equal(ethers.utils.parseUnits("1000", 18));
    });

    it("Should calculate pending rewards correctly", async function () {
      await token.transfer(addr1.address, ethers.utils.parseUnits("1000", 18));
      await token.connect(addr1).approve(staking.address, ethers.utils.parseUnits("1000", 18));
      await staking.connect(addr1).deposit(ethers.utils.parseUnits("1000", 18), 0, false);

      await time.advanceBlockTo(START_BLOCK + 10);

      const pendingReward = await staking.pendingReward(addr1.address);
      expect(pendingReward).to.be.gt(0);
    });

    it("Should allow users to claim rewards", async function () {
      await token.transfer(addr1.address, ethers.utils.parseUnits("1000", 18));
      await token.connect(addr1).approve(staking.address, ethers.utils.parseUnits("1000", 18));
      await staking.connect(addr1).deposit(ethers.utils.parseUnits("1000", 18), 0, false);

      await time.advanceBlockTo(START_BLOCK + 10);
      await staking.connect(addr1).claimReward();

      const userInfo = await staking.userInfo(0, addr1.address);
      expect(await token.balanceOf(addr1.address)).to.be.gt(0);
    });

    it("Should allow users to withdraw their stake and rewards", async function () {
      await token.transfer(addr1.address, ethers.utils.parseUnits("1000", 18));
      await token.connect(addr1).approve(staking.address, ethers.utils.parseUnits("1000", 18));
      await staking.connect(addr1).deposit(ethers.utils.parseUnits("1000", 18), 0, false);

      await time.advanceBlockTo(START_BLOCK + 10);
      await staking.connect(addr1).withdraw(false);

      const userInfo = await staking.userInfo(0, addr1.address);
      expect(userInfo.amount).to.equal(0);
      expect(await token.balanceOf(addr1.address)).to.be.gt(ethers.utils.parseUnits("1000", 18));
    });

    it("Should apply cooldown correctly before allowing withdrawal", async function () {
      await token.transfer(addr1.address, ethers.utils.parseUnits("1000", 18));
      await token.connect(addr1).approve(staking.address, ethers.utils.parseUnits("1000", 18));
      await staking.connect(addr1).deposit(ethers.utils.parseUnits("1000", 18), 0, false);

      await time.advanceBlockTo(START_BLOCK + 10);

      await staking.connect(addr1).withdraw(false);
      await expect(staking.connect(addr1).withdraw(false)).to.be.revertedWith("withdraw: cooldown period");

      await time.increase(time.duration.weeks(1));

      await staking.connect(addr1).withdraw(false);
      const userInfo = await staking.userInfo(0, addr1.address);
      expect(userInfo.amount).to.equal(0);
    });
  });

  describe("NFT Staking", function () {
    beforeEach(async function () {
      await staking.addUniswapVersion3(erc721.address, token.address, token.address, 3000, true);
    });

    it("Should allow users to deposit NFTs", async function () {
      await erc721.mint(addr1.address, 1);
      await erc721.connect(addr1).approve(staking.address, 1);

      await staking.connect(addr1).deposit(0, 1, true);

      const userInfo = await staking.userInfo(0, addr1.address);
      expect(userInfo.amount).to.be.gt(0);

      const poolInfo = await staking.poolInfo(0);
      expect(poolInfo.totalStaked).to.be.gt(0);
    });

    it("Should handle NFT withdrawals correctly", async function () {
      await erc721.mint(addr1.address, 1);
      await erc721.connect(addr1).approve(staking.address, 1);

      await staking.connect(addr1).deposit(0, 1, true);
      await time.advanceBlockTo(START_BLOCK + 10);

      await staking.connect(addr1).withdraw(true);

      expect(await erc721.ownerOf(1)).to.equal(addr1.address);
    });
  });

  describe("Emergency Withdrawals", function () {
    it("Should allow the owner to perform emergency withdrawal", async function () {
      await token.transfer(staking.address, ethers.utils.parseUnits("1000", 18));

      await staking.emergencyWithdraw(ethers.utils.parseUnits("1000", 18));

      expect(await token.balanceOf(owner.address)).to.equal(ethers.utils.parseUnits("1000", 18));
    });

    it("Should allow the owner to perform emergency NFT withdrawal", async function () {
      await erc721.mint(addr1.address, 1);
      await erc721.connect(addr1).approve(staking.address, 1);

      await staking.connect(addr1).deposit(0, 1, true);
      await staking.emergencyNFTWithdraw([1]);

      expect(await erc721.ownerOf(1)).to.equal(owner.address);
    });
  });

  describe("Staking Levels and Rewards", function () {
    it("Should calculate staking score correctly", async function () {
      await token.transfer(addr1.address, ethers.utils.parseUnits("1000", 18));
      await token.connect(addr1).approve(staking.address, ethers.utils.parseUnits("1000", 18));
      await staking.connect(addr1).deposit(ethers.utils.parseUnits("1000", 18), 0, false);

      await time.increase(time.duration.weeks(10));
      const stakingScore = await staking.calculateStakingScore(addr1.address);

      expect(stakingScore).to.be.gt(0);
    });

    it("Should assign correct level based on staking score", async function () {
      await token.transfer(addr1.address, ethers.utils.parseUnits("1000", 18));
      await token.connect(addr1).approve(staking.address, ethers.utils.parseUnits("1000", 18));
      await staking.connect(addr1).deposit(ethers.utils.parseUnits("1000", 18), 0, false);

      await time.increase(time.duration.weeks(10));

      const level = await staking.getLevelForUser(addr1.address);
      expect(level).to.be.gte(0);
    });

    it("Should apply APR limiter correctly", async function () {
      await token.transfer(addr1.address, ethers.utils.parseUnits("1000", 18));
      await token.connect(addr1).approve(staking.address, ethers.utils.parseUnits("1000", 18));
      await staking.connect(addr1).deposit(ethers.utils.parseUnits("1000", 18), 0, false);

      await time.advanceBlockTo(START_BLOCK + 10);
      const pendingReward = await staking.pendingReward(addr1.address);

      const cappedReward = await staking.calculateCappedRewards(addr1.address, pendingReward);
      expect(cappedReward).to.be.lte(pendingReward);
    });
  });
});
