const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const { encodeAbiParameters, keccak256 } = require("viem");

describe("TMAIPayment", function () {
    let paymentContract;
    let mockUSDC, mockUSDT, mockNFT, mockSignatureVerifier;
    let owner, dao, treasury, user, minter;

    // Enum mappings for plan types and products
    const PlanType = {
        Basic: 0,
        Advanced: 1,
        Premium: 2,
        VIP: 3,
    };

    const Product = {
        TradingBot: 0,
        DataAPI: 1,
        AnalyticsPlatform: 2,
    };


    describe("Deployment", function () {

        it("Should get signers", async function () {
            [owner, dao, treasury, user, minter] = await ethers.getSigners();
        });

        it("Should deploy mock contracts", async function () {
            // Deploy mock USDC (ERC20)
            const MockERC20 = await ethers.getContractFactory("ERC20Mock");
            mockUSDC = await MockERC20.deploy("Mock USDC", "mUSDC", 6);
            await mockUSDC.mint(user.address, ethers.parseUnits("10000", 6)); // Mint 10000 USDC for user

            // Deploy mock Soulbound NFT contract
            const MockNFT = await ethers.getContractFactory("TMAISoulboundNFT");
            mockNFT = await upgrades.deployProxy(MockNFT, []);
            await mockNFT.waitForDeployment();

            // Deploy mock SignatureVerifier contract
            const MockSignatureVerifier = await ethers.getContractFactory("SignatureVerifier");
            mockSignatureVerifier = await upgrades.deployProxy(MockSignatureVerifier, [minter.address]);
            await mockSignatureVerifier.waitForDeployment();
        });

        it("Should deploy TMAIPayment contract", async function () {

            // Deploy the TMAIPayment contract
            const TMAIPaymentFactory = await ethers.getContractFactory("TMAIPayment");
            paymentContract = await upgrades.deployProxy(TMAIPaymentFactory, [
                treasury.address,
                dao.address,
                2000,  // DAO share (20%)
                await mockNFT.getAddress(),
                await mockSignatureVerifier.getAddress()
            ]);
        });
    });

    describe("Check Initial Configuration", function () {
        it("Should set the correct owner", async function () {
            expect(await paymentContract.owner()).to.equal(owner.address);
        });

        it("Should set the correct DAO and treasury addresses", async function () {
            expect(await paymentContract.dao()).to.equal(await dao.getAddress());
            expect(await paymentContract.treasury()).to.equal(await treasury.getAddress());
        });
        it("Should add the Payment contract as a minter in the NFT contract", async function () {
            await mockNFT.grantMinterRole(await paymentContract.getAddress());
            expect(await mockNFT.minter()).to.equal(await paymentContract.getAddress());
        });
    });

    describe("Token Management", function () {
        it("Should allow owner to enable and disable tokens", async function () {
            await paymentContract.enableToken(await mockUSDC.getAddress());
            expect(await paymentContract.allowedTokens(await mockUSDC.getAddress())).to.be.true;

            await paymentContract.disableToken(await mockUSDC.getAddress());
            expect(await paymentContract.allowedTokens(await mockUSDC.getAddress())).to.be.false;
        });
    });

    describe("Process Payment and Subscription Management", function () {
        it("Should process a payment and create a new subscription", async function () {
            // Enable USDC as a valid payment token
            await paymentContract.enableToken(await mockUSDC.getAddress());

            // Create a valid signature for the payment
            const encodedMessage = encodeAbiParameters(
                [{ name: "userAddress", type: "address" },
                { name: "product", type: "uint8" },
                { name: "planType", type: "uint8" },
                { name: "expiryDate", type: "uint256" },
                { name: "token", type: "address" },
                { name: "tokenAmount", type: "uint256" },
                { name: "validity", type: "uint256" },
                { name: "nonce", type: "uint256" }],
                [user.address, Product.AnalyticsPlatform, PlanType.Premium, 30 * 24 * 60 * 60, await mockUSDC.getAddress(), ethers.parseUnits("100", 6), await ethers.provider.getBlockNumber() + 10, 0]
            );
            const messageHash = keccak256(encodedMessage);
            const signature = await minter.signMessage(ethers.getBytes(messageHash));

            const signatureData = {
                encodedMessage: encodedMessage,
                messageHash: messageHash,
                signature: signature
            };

            // Approve USDC spending
            await mockUSDC.connect(user).approve(await paymentContract.getAddress(), ethers.parseUnits("100", 6));

            // Process the payment and create the subscription
            await paymentContract.connect(user).processPayment(signatureData, false);

            const tokenId = await mockNFT.userToTokenId(user.address, Product.AnalyticsPlatform);
            expect(await mockNFT.ownerOf(tokenId)).to.equal(user.address);

            const planDetails = await mockNFT.getUserPlanDetails(user.address, Product.AnalyticsPlatform);
            expect(planDetails.planType).to.equal(PlanType.Premium);
        });

        it("Should upgrade an existing subscription", async function () {
            // First, create a subscription
            const encodedMessage = encodeAbiParameters(
                [{ name: "userAddress", type: "address" },
                { name: "product", type: "uint8" },
                { name: "planType", type: "uint8" },
                { name: "expiryDate", type: "uint256" },
                { name: "token", type: "address" },
                { name: "tokenAmount", type: "uint256" },
                { name: "validity", type: "uint256" },
                { name: "nonce", type: "uint256" }],
                [user.address, Product.DataAPI, PlanType.Basic, 30 * 24 * 60 * 60, await mockUSDC.getAddress(), ethers.parseUnits("100", 6), await ethers.provider.getBlockNumber() + 10, 1]
            );
            const messageHash = keccak256(encodedMessage);
            const signature = await minter.signMessage(ethers.getBytes(messageHash));

            const signatureData = {
                encodedMessage: encodedMessage,
                messageHash: messageHash,
                signature: signature
            };

            await mockUSDC.connect(user).approve(await paymentContract.getAddress(), ethers.parseUnits("100", 6));
            await paymentContract.connect(user).processPayment(signatureData, false);

            // Now, upgrade the subscription
            const upgradeEncodedMessage = encodeAbiParameters(
                [{ name: "userAddress", type: "address" },
                { name: "product", type: "uint8" },
                { name: "planType", type: "uint8" },
                { name: "expiryDate", type: "uint256" },
                { name: "token", type: "address" },
                { name: "tokenAmount", type: "uint256" },
                { name: "validity", type: "uint256" },
                { name: "nonce", type: "uint256" }],
                [user.address, Product.DataAPI, PlanType.Premium, 60 * 24 * 60 * 60, await mockUSDC.getAddress(), ethers.parseUnits("150", 6), await ethers.provider.getBlockNumber() + 10, 2]
            );
            const upgradeMessageHash = keccak256(upgradeEncodedMessage);
            const upgradeSignature = await minter.signMessage(ethers.getBytes(upgradeMessageHash));

            const upgradeSignatureData = {
                encodedMessage: upgradeEncodedMessage,
                messageHash: upgradeMessageHash,
                signature: upgradeSignature
            };

            await mockUSDC.connect(user).approve(await paymentContract.getAddress(), ethers.parseUnits("150", 6));

            await paymentContract.connect(user).processPayment(upgradeSignatureData, true);

            const tokenId = await mockNFT.userToTokenId(user.address, Product.DataAPI);
            const planDetails = await mockNFT.tokenIdToPlanDetails(tokenId);
            expect(planDetails.planType).to.equal(PlanType.Premium);
            expect(planDetails.expiryDate).to.be.closeTo((await ethers.provider.getBlock()).timestamp + 60 * 24 * 60 * 60, 10);
        });

        it("Should not allow replaying a nonce", async function () {
            // Create a valid signature for the payment
            const encodedMessage = encodeAbiParameters(
                [{ name: "userAddress", type: "address" },
                { name: "product", type: "uint8" },
                { name: "planType", type: "uint8" },
                { name: "expiryDate", type: "uint256" },
                { name: "token", type: "address" },
                { name: "tokenAmount", type: "uint256" },
                { name: "validity", type: "uint256" },
                { name: "nonce", type: "uint256" }],
                [user.address, Product.AnalyticsPlatform, PlanType.Premium, 30 * 24 * 60 * 60, await mockUSDC.getAddress(), ethers.parseUnits("100", 6), await ethers.provider.getBlockNumber() + 10, 3]
            );
            const messageHash = keccak256(encodedMessage);
            const signature = await minter.signMessage(ethers.getBytes(messageHash));

            const signatureData = {
                encodedMessage: encodedMessage,
                messageHash: messageHash,
                signature: signature
            };

            // Approve USDC spending
            await mockUSDC.connect(user).approve(await paymentContract.getAddress(), ethers.parseUnits("100", 6));

            // Process the payment and create the subscription
            await paymentContract.connect(user).processPayment(signatureData, false);

            // Try to replay the same payment
            await expect(paymentContract.connect(user).processPayment(signatureData, false)).to.be.revertedWith("Invalid nonce");
        });
    });

    describe("Revenue Distribution and Admin Functions", function () {
        it("Should distribute revenue between treasury and DAO", async function () {

            const paymentContractBalance = await mockUSDC.balanceOf(await paymentContract.getAddress());
            const treasuryShare = paymentContractBalance * BigInt(80) / BigInt(100);
            const daoShare = paymentContractBalance - BigInt(treasuryShare);

            await expect(paymentContract.distributeRevenue(await mockUSDC.getAddress())).to.emit(paymentContract, "RevenueDistributed").withArgs(paymentContractBalance, treasuryShare, daoShare);

            expect(await mockUSDC.balanceOf(await treasury.getAddress())).to.equal(treasuryShare);
            expect(await mockUSDC.balanceOf(await dao.getAddress())).to.equal(daoShare);
        });

        it("Should allow owner to update DAO share", async function () {
            await paymentContract.updateDAOShare(2500); // 25%
            expect(await paymentContract.daoShare()).to.equal(2500);
        });

        it("Should allow owner to update the SignatureVerifier contract address", async function () {
            const newSignatureVerifier = await upgrades.deployProxy(
                await ethers.getContractFactory("SignatureVerifier"),
                [minter.address]
            );
            await paymentContract.updateSignatureVerifier(await newSignatureVerifier.getAddress());
            expect(await paymentContract.signatureVerifier()).to.equal(await newSignatureVerifier.getAddress());
        });
    });

    describe("Withdraw Functions", function () {

        it("Should allow owner to withdraw tokens", async function () {
            // Deploy a mock token (non-USDC) to test the withdraw functionality
            const MockToken = await ethers.getContractFactory("ERC20Mock");
            const mockOtherToken = await MockToken.deploy("Mock Token", "MKT", 18);
            await mockOtherToken.mint(await paymentContract.getAddress(), ethers.parseUnits("500", 18)); // Mint 500 MKT for paymentContract

            // Withdraw the tokens to the owner
            await expect(paymentContract.withdrawTokens(await mockOtherToken.getAddress(), ethers.parseUnits("500", 18)))
                .to.emit(paymentContract, "TokensWithdrawn")
                .withArgs(await mockOtherToken.getAddress(), owner.address, ethers.parseUnits("500", 18));

            // expect(await mockOtherToken.balanceOf(owner.address)).to.equal(ethers.parseUnits("500", 18));
        });

        it("Should allow owner to update DAO and Treasury addresses", async function () {
            const newDAO = ethers.Wallet.createRandom().address;
            const newTreasury = ethers.Wallet.createRandom().address;

            await paymentContract.updateDAO(newDAO);
            await paymentContract.updateTreasury(newTreasury);

            expect(await paymentContract.dao()).to.equal(newDAO);
            expect(await paymentContract.treasury()).to.equal(newTreasury);
        });
    });
});
