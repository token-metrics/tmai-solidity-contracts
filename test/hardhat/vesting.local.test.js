const { expect } = require("chai");
const { upgrades, ethers } = require("hardhat");
const { time } = require('@nomicfoundation/hardhat-network-helpers');

describe("Vesting", function () {

    let signers;
    let token;
    let vesting;

    describe("Deployment", function () {

        it("Should get signers", async function () {
            signers = await ethers.getSigners();
        });

        it("Should deploy Token contract", async function () {
            const Token = await ethers.getContractFactory("TMAIToken");
            token = await upgrades.deployProxy(Token, [signers[0].address]);
        });

        it("Should deploy Vesting contract", async function () {
            const Vesting = await ethers.getContractFactory("TMAIVesting");
            vesting = await upgrades.deployProxy(Vesting, [await token.getAddress(), "120"]);

            await token.transfer(await vesting.getAddress(), 10000000000);
        });
    });

    describe("Check Initial Configuration", function () {

        it("Should check token address", async function () {
            expect(await vesting.getToken()).to.equal(await token.getAddress());
        });

        it("Should check correct owner", async function () {
            expect(await vesting.owner()).to.equal(signers[0].address);
        });

        it("Should set transfer ownership", async function () {
            await vesting.transferOwnership(signers[1].address);
            await vesting.connect(signers[1]).acceptOwnership();
            expect(await vesting.owner()).to.equal(signers[1].address);

            // Transfer back to original owner
            await vesting.connect(signers[1]).transferOwnership(signers[0].address);
            await vesting.connect(signers[0]).acceptOwnership();
        });

    });

    describe("Check airdrop", function () {
        it("Should airdrop tokens", async function () {
            await token.approve(await vesting.getAddress(), 60000);
            await vesting.multisendToken([signers[1].address, signers[2].address], [10000, 20000]);
            expect(await token.balanceOf(signers[1].address)).to.equal(10000n);
            expect(await token.balanceOf(signers[2].address)).to.equal(20000n);
        });
    });

    describe("Create Vesting", function () {
        it("Should revert if non-owner tries to create vesting", async function () {
            await expect(vesting.connect(signers[1]).createVestingSchedule(signers[1].address, 1000, 10, 1000, 1, true, 100, 10, 0)).to.be.revertedWith("Ownable: caller is not the owner");
        });

        it("Should revert if contract don't have enough tokens", async function () {
            await expect(vesting.createVestingSchedule(signers[3].address, 1000, 10, 1000, 1, true, 20000000000, 10, 0)).to.be.revertedWith("TMAIVesting: cannot create vesting schedule because not sufficient tokens");
        });

        it("Should create single vesting schedule", async function () {

            const balanceBefore = await token.balanceOf(signers[3].address);

            await vesting.createVestingSchedule(signers[3].address, 1000, 10, 1000, 1, true, 100, 10, 0);
            expect(await vesting.getVestingSchedulesCount()).to.equal(1);

            const balanceAfter = await token.balanceOf(signers[3].address);

            expect(balanceAfter).to.equal(balanceBefore + 10n);
        });

        it("Should create multiple vesting schedules", async function () {
            await vesting.addUserDetails([signers[1].address, signers[2].address, signers[3].address], [100, 100, 100], [0, 0, 0], 1000, 10, 1000, 1, true);
            expect(await vesting.getVestingSchedulesCount()).to.be.equal(4);
        });
    });

    describe("Claim vesting", function () {

        let tmpTime;

        beforeEach(async function () {
            tmpTime = await time.latest();
            await vesting.addUserDetails([signers[1].address, signers[2].address, signers[3].address], [10000, 10000, 10000], [0, 0, 0], tmpTime, 400, 1000, 1, true);
        });

        it("Should show correct claimable amount in get function", async function () {
            await time.increaseTo(tmpTime + 390);
            let vestingId = await vesting.getVestingIdAtIndex(4);
            expect(await vesting.computeReleasableAmount(vestingId)).to.be.equal(0);

            await time.increase(10);
            expect(await vesting.computeReleasableAmount(vestingId)).to.be.equal(4000);

        });

    });
});
