const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const { encodeAbiParameters, keccak256 } = require("viem");

describe("TMAIPayment", function () {
    let paymentContract;
    let mockUSDC, mockUSDT, mockNFT, mockSignatureVerifier;
    let owner, dao, treasury, user, minter;

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


        it("Should deploy TMAIStaking contract", async function () {

            const mockStakingAddress = "0x0000000000000000000000000000000000000001"
            // Deploy the TMAIPayment contract
            const TMAIPaymentFactory = await ethers.getContractFactory("TMAIPayment");
            paymentContract = await upgrades.deployProxy(TMAIPaymentFactory, [
                treasury.address,
                dao.address,
                mockStakingAddress, // Staking contract (set to mock address for testing)
                2000, // DAO share (20%)
                await mockUSDC.getAddress(),
                await mockNFT.getAddress(),
                await mockSignatureVerifier.getAddress()
            ]);

        });


    });

    describe("Check Initial Configuration", function () {
        it("Should set the correct USDC address", async function () {
            expect(await paymentContract.baseStableCoin()).to.equal(await mockUSDC.getAddress());
        });

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

    describe("Process Payment and Subscription Management", function () {
        it("Should process a payment and create a new subscription", async function () {
            // Create a valid signature for the payment
            const encodedMessage = encodeAbiParameters(
                [{ name: "userAddress", type: "address" },
                 { name: "section", type: "string" },
                 { name: "planType", type: "string" },
                 { name: "expiryDate", type: "uint256" },
                 { name: "usdcAmount", type: "uint256" },
                 { name: "validity", type: "uint256" },
                ],
                [user.address, "analytics", "premium", 30 * 24 * 60 * 60, ethers.parseUnits("100", 6), await ethers.provider.getBlockNumber() + 10]
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

            // // Process the payment and create the subscription
            await paymentContract.connect(user).processPayment(signatureData, false);

            const tokenId = await mockNFT.userToTokenId(user.address, "analytics");
            expect(await mockNFT.ownerOf(tokenId)).to.equal(user.address);
        });

        it("Should upgrade an existing subscription", async function () {
            // First, create a subscription
            const encodedMessage = encodeAbiParameters(
                [{ name: "userAddress", type: "address" },
                 { name: "section", type: "string" },
                 { name: "planType", type: "string" },
                 { name: "expiryDate", type: "uint256" },
                 { name: "usdcAmount", type: "uint256" },
                 { name: "validity", type: "uint256" },
                ],
                [user.address, "data-api", "basic", 30 * 24 * 60 * 60, ethers.parseUnits("100", 6), await ethers.provider.getBlockNumber() + 10]
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
                 { name: "section", type: "string" },
                 { name: "planType", type: "string" },
                 { name: "expiryDate", type: "uint256" },
                 { name: "usdcAmount", type: "uint256" },
                 { name: "validity", type: "uint256" },
                ],
                [user.address, "data-api", "premium", 60 * 24 * 60 * 60, ethers.parseUnits("150", 6), await ethers.provider.getBlockNumber() + 10]
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

            const tokenId = await mockNFT.userToTokenId(user.address, "data-api");
            const planDetails = await mockNFT.tokenIdToPlanDetails(tokenId);
            expect(planDetails.planType).to.equal("premium");
            expect(planDetails.expiryDate).to.be.closeTo((await ethers.provider.getBlock()).timestamp + 60 * 24 * 60 * 60, 10);
        });
    });

    describe("Revenue Distribution and Admin Functions", function () {
        it("Should distribute revenue between treasury and DAO", async function () {

            const paymentContractBalance = await mockUSDC.balanceOf(await paymentContract.getAddress());
            const treasuryShare = paymentContractBalance * BigInt(80) / BigInt(100);
            const daoShare = paymentContractBalance - BigInt(treasuryShare);

            await expect(paymentContract.distributeRevenue()).to.emit(paymentContract, "RevenueDistributed").withArgs(paymentContractBalance, treasuryShare, daoShare);


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

        it("Should not allow withdrawal of the base stablecoin", async function () {
            await expect(paymentContract.withdrawTokens(await mockUSDC.getAddress(), ethers.parseUnits("500", 6)))
                .to.be.revertedWith("Cannot withdraw base stable coin");
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
