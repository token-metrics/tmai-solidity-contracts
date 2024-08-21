const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const { mineUpTo, mine, time } = require("@nomicfoundation/hardhat-network-helpers");
const { BigNumber } = require("moralis/common-core");

describe("TMAIStaking", function () {
  let staking;
  let token;
  let erc721;
  let owner;
  let addr1;
  let addr2;
  let addr3;
  let addr4;
  let addr5;
  let addr6;
  let uniswapUtility;

  const SUPPLY = ethers.parseUnits("100000000", 18);
  const START_BLOCK = 100;
  const BONUS_END_BLOCK = 200;
  const TOTAL_REWARDS = ethers.parseUnits("10000000", 18);

  describe("Deployment", function () {

    it("Should get signers", async function () {
      [owner, addr1, addr2, addr3, addr4, addr5, addr6] = await ethers.getSigners();
    });

    it("Should deploy mock contracts", async function () {
      const Token = await ethers.getContractFactory("ERC20Mock");
      token = await Token.deploy("Test Token", "TT", SUPPLY);
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

      await token.transfer(await staking.getAddress(), TOTAL_REWARDS);

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
      await staking.setUtilityContractAddress(await uniswapUtility.getAddress());
      expect(await staking.uniswapUtility()).to.equal(await uniswapUtility.getAddress());

      await expect(staking.connect(addr1).setUtilityContractAddress(addr2.address))
        .to.be.revertedWith("Ownable: caller is not the owner");
    });
  });

  describe("Staking and Reward Mechanics", function () {


    it("Should allow users to deposit tokens and update pool info", async function () {
      await token.transfer(addr1.address, ethers.parseUnits("1000", 18));
      await token.connect(addr1).approve(await staking.getAddress(), ethers.parseUnits("1000", 18));
      await staking.connect(addr1).deposit(ethers.parseUnits("1000", 18), 0, false);

      const userInfo = await staking.userInfo(0, addr1.address);
      expect(userInfo.amount).to.equal(ethers.parseUnits("1000", 18));

      const poolInfo = await staking.poolInfo(0);
      expect(poolInfo.totalStaked).to.equal(ethers.parseUnits("1000", 18));
    });

    it("Should calculate pending rewards correctly", async function () {

      await mineUpTo(START_BLOCK + 10);

      const pendingReward = await staking.pendingReward(addr1.address);
      expect(pendingReward).to.be.gt(0);
    });

    it("Should allow users to claim rewards", async function () {

      await staking.connect(addr1).claimReward();

      const userInfo = await staking.userInfo(0, addr1.address);
      expect(await token.balanceOf(addr1.address)).to.be.gt(0);
    });


    it("Should apply cooldown correctly before allowing withdrawal", async function () {

      await staking.connect(addr1).activateCooldown();

      const userInfo = await staking.userInfo(0, addr1.address);
      expect(userInfo.cooldown).to.be.true;

      await expect(staking.connect(addr1).withdraw(false)).to.be.revertedWith("withdraw: cooldown period");
    });

    it("Should allow users to withdraw their stake and rewards", async function () {

      // increase one week
      const secondsInWeek = (60 * 60 * 24 * 7) + 1;
      await time.increase(secondsInWeek);

      await staking.connect(addr1).withdraw(false);
      const userInfo = await staking.userInfo(0, addr1.address);
      expect(userInfo.amount).to.equal(0);
      expect(await token.balanceOf(addr1.address)).to.be.gt(ethers.parseUnits("1000", 18));
    });

  });

  describe("Staking Levels and Rewards", function () {

    it("Should calculate staking score correctly - addr1", async function () {

      await token.transfer(addr1.address, ethers.parseUnits("1000", 18));
      await token.connect(addr1).approve(await staking.getAddress(), ethers.parseUnits("1000", 18));
      await staking.connect(addr1).deposit(ethers.parseUnits("1000", 18), 0, false);

      // increase one week
      const secondsInWeek = (60 * 60 * 24 * 7) + 1;
      await time.increase(secondsInWeek);

      const stakingScoreAfterWeek = await staking.calculateStakingScore(addr1.address);
      expect(stakingScoreAfterWeek).to.equal(0);


      // increase one month
      const secondsInMonth = (60 * 60 * 24 * 30 * 1) + 1;
      await time.increase(secondsInMonth);

      const stakingScoreAfterMonth = await staking.calculateStakingScore(addr1.address);
      // console.log("Staking Score after month: ", stakingScoreAfterMonth);
      expect(stakingScoreAfterMonth).to.be.gt(0);

      // log curent timestamp
      const timestamp = await time.latest();
      // console.log("Current Timestamp: ", timestamp);

      const userInfo = await staking.userInfo(0, addr1.address);
      // console.log("User Info: ", userInfo);
    });

    it("Should assign correct level based on staking score - addr1", async function () {

      const level = await staking.getLevelForUser(addr1.address);
      // console.log("Level: ", level);
      expect(level).to.equal(0);
    });


    it("Should calculate staking score correctly - addr2", async function () {

      await token.transfer(addr2.address, ethers.parseUnits("1000", 18));
      await token.connect(addr2).approve(await staking.getAddress(), ethers.parseUnits("1000", 18));
      await staking.connect(addr2).deposit(ethers.parseUnits("1000", 18), 0, false);

      // increase one week
      const secondsInWeek = (60 * 60 * 24 * 7) + 1;
      await time.increase(secondsInWeek);

      const stakingScoreAfterWeek = await staking.calculateStakingScore(addr2.address);
      expect(stakingScoreAfterWeek).to.equal(0);


      // increase two months
      const secondsInMonth = (60 * 60 * 24 * 30 * 2) + 1;
      await time.increase(secondsInMonth);

      const stakingScoreAfterMonth = await staking.calculateStakingScore(addr2.address);
      // console.log("Staking Score after month: ", stakingScoreAfterMonth);
      expect(stakingScoreAfterMonth).to.be.gt(0);

      // log curent timestamp
      const timestamp = await time.latest();
      // console.log("Current Timestamp: ", timestamp);

      const userInfo = await staking.userInfo(0, addr2.address);
      // console.log("User Info: ", userInfo);
    });

    it("Should assign correct level based on staking score - addr2", async function () {

      const level = await staking.getLevelForUser(addr2.address);
      // console.log("Level: ", level);
      expect(level).to.equal(0);
    });


    it("Should calculate staking score correctly - addr3", async function () {

      await token.transfer(addr3.address, ethers.parseUnits("16000", 18));
      await token.connect(addr3).approve(await staking.getAddress(), ethers.parseUnits("16000", 18));
      await staking.connect(addr3).deposit(ethers.parseUnits("16000", 18), 0, false);


      // increase six months
      const secondsInMonth = (60 * 60 * 24 * 30 * 6) + 1;
      await time.increase(secondsInMonth);

      const stakingScoreAfterMonth = await staking.calculateStakingScore(addr3.address);
      // console.log("Staking Score after month: ", stakingScoreAfterMonth);
      expect(stakingScoreAfterMonth).to.equal("8000000000000000000000");

      // log curent timestamp
      const timestamp = await time.latest();
      // console.log("Current Timestamp: ", timestamp);

      const userInfo = await staking.userInfo(0, addr3.address);
      // console.log("User Info: ", userInfo);
    });

    it("Should assign correct level based on staking score - addr3", async function () {

      const level = await staking.getLevelForUser(addr3.address);
      // console.log("Level: ", level);
      expect(level).to.equal(3);
    });

    // it("Should apply APR limiter correctly", async function () {
    //   await token.transfer(addr1.address, ethers.parseUnits("1000", 18));
    //   await token.connect(addr1).approve(await staking.getAddress(), ethers.parseUnits("1000", 18));
    //   await staking.connect(addr1).deposit(ethers.parseUnits("1000", 18), 0, false);

    //   await time.advanceBlockTo(START_BLOCK + 10);
    //   const pendingReward = await staking.pendingReward(addr1.address);

    //   const cappedReward = await staking.calculateCappedRewards(addr1.address, pendingReward);
    //   expect(cappedReward).to.be.lte(pendingReward);
    // });
  });

  describe("APR Limiter Functionality", function () {

    const SECONDS_IN_MONTH = 60 * 60 * 24 * 30 * 1;

    it("Should calculate capped rewards correctly for Level 0 user", async function () {
      await token.transfer(addr4.address, ethers.parseUnits("1000", 18));
      await token.connect(addr4).approve(await staking.getAddress(), ethers.parseUnits("1000", 18));
      await staking.connect(addr4).deposit(ethers.parseUnits("1000", 18), 0, false);

      await time.increase(SECONDS_IN_MONTH);

      const userLevel = await staking.getLevelForUser(addr4.address);
      expect(userLevel).to.equal(0);  // Level 0

      const pendingReward = await staking.pendingReward(addr4.address);
      console.log("Pending Reward: ", pendingReward);

      const aprLimiter = await staking.aprLimiters(userLevel);
      const expectedCappedReward = BigInt(ethers.parseUnits("1000", 18)) * BigInt(aprLimiter) / BigInt(100);

      expect(pendingReward).to.be.lessThanOrEqual(expectedCappedReward);
    });

    it("Should calculate capped rewards correctly for Level 3 user", async function () {
      await token.transfer(addr5.address, ethers.parseUnits("16000", 18));
      await token.connect(addr5).approve(await staking.getAddress(), ethers.parseUnits("16000", 18));
      await staking.connect(addr5).deposit(ethers.parseUnits("16000", 18), 0, false);

      await time.increase(SECONDS_IN_MONTH * 6);

      const userLevel = await staking.getLevelForUser(addr5.address);
      expect(userLevel).to.equal(3);  // Level 3

      const pendingReward = await staking.pendingReward(addr5.address);
      console.log("Pending Reward: ", pendingReward);

      const aprLimiter = await staking.aprLimiters(userLevel);
      const expectedCappedReward = BigInt(ethers.parseUnits("16000", 18)) * BigInt(aprLimiter) / BigInt(100);

      expect(pendingReward).to.be.lessThanOrEqual(expectedCappedReward);
    });

    it("Should calculate capped rewards correctly for Level 3 user - at a very later time", async function () {

      await time.increase(SECONDS_IN_MONTH * 12);

      const userLevel = await staking.getLevelForUser(addr5.address);
      expect(userLevel).to.equal(4);  // Level 4

      const pendingReward = await staking.pendingReward(addr5.address);
      console.log("Pending Reward: ", pendingReward);

      const aprLimiter = await staking.aprLimiters(userLevel);
      const expectedCappedReward = BigInt(ethers.parseUnits("16000", 18)) * BigInt(aprLimiter) / BigInt(100);

      expect(pendingReward).to.be.lessThanOrEqual(expectedCappedReward);
    });

    it("Should ensure capped rewards are applied when claiming", async function () {

      const pendingReward = await staking.pendingReward(addr5.address);
      console.log("Pending Reward: ", pendingReward);

    
      await staking.connect(addr5).claimReward();

      const userLevel = await staking.getLevelForUser(addr5.address);
      const aprLimiter = await staking.aprLimiters(userLevel);
      const expectedCappedReward =  BigInt(ethers.parseUnits("16000", 18)) * BigInt(aprLimiter) / BigInt(100);

      // log token balance
      console.log("Token Balance: ", await token.balanceOf(addr5.address));
      expect(await token.balanceOf(addr5.address)).to.equal(expectedCappedReward);
    });

  });

  describe("Emergency Withdrawals", function () {
    it("Should allow the owner to perform emergency withdrawal", async function () {
      const balanceBefore = await token.balanceOf(owner.address);

      await staking.emergencyWithdraw(ethers.parseUnits("1000", 18));

      const balanceAfter = await token.balanceOf(owner.address);

      // expect the owner to have received the total rewards
      expect(balanceAfter - balanceBefore).to.equal(ethers.parseUnits("1000", 18));
    });
  });
});
