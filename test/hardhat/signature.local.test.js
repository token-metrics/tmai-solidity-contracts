const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const { encodeAbiParameters, keccak256 } = require("viem");

describe("SignatureVerifier", function () {
  let signatureVerifier;
  let owner;
  let addr1;
  let addr2;

  // Enum mappings for plan types and products
  const PlanType = {
    Basic: 0,
    Advanced: 1,
    Premium: 2,
    VIP: 3,
    Enterprise: 4,
  };

  const Product = {
    TradingBot: 0,
    DataAPI: 1,
    AnalyticsPlatform: 2,
  };


  describe("Deployment", function () {

    it("Should get signers", async function () {
      [owner, addr1, addr2] = await ethers.getSigners();
    });

    it("Should deploy the SignatureVerifier contract", async function () {
      const SignatureVerifier = await ethers.getContractFactory("SignatureVerifier");
      signatureVerifier = await upgrades.deployProxy(SignatureVerifier, [owner.address]);
      await signatureVerifier.waitForDeployment();
    });

    it("Should initialize the signer address correctly", async function () {
      expect(await signatureVerifier.signerAddress()).to.equal(owner.address);
    });
  });

  describe("Payment Signature Verification", function () {
    let encodedMessage;
    let messageHash;
    let signature;
    let nonce = 0;

    it("Should create a valid payment signature", async function () {
      // Encode the message using viem's encodeAbiParameters
      encodedMessage = encodeAbiParameters(
        [{ name: "userAddress", type: "address" },
        { name: "product", type: "uint8" },
        { name: "planType", type: "uint8" },
        { name: "expiryDate", type: "uint256" },
        { name: "token", type: "address" },
        { name: "tokenAmount", type: "uint256" },
        { name: "validity", type: "uint256" },
        { name: "nonce", type: "uint256" }],
        [addr1.address, Product.AnalyticsPlatform, PlanType.Premium, 30 * 24 * 60 * 60, addr2.address, ethers.parseUnits("100", 6), await ethers.provider.getBlockNumber() + 10, nonce]
      );

      // Hash the encoded message
      messageHash = keccak256(encodedMessage);

      // Sign the message hash
      signature = await owner.signMessage(ethers.getBytes(messageHash));
    });

    it("Should verify the payment signature successfully", async function () {
      const signatureData = {
        encodedMessage: encodedMessage,
        messageHash: messageHash,
        signature: signature,
      };

      const decodedMessage = await signatureVerifier.verifyPaymentSignature(signatureData);

      // Verify the decoded message content
      expect(decodedMessage.userAddress).to.equal(addr1.address);
      expect(decodedMessage.product).to.equal(Product.AnalyticsPlatform);
      expect(decodedMessage.planType).to.equal(PlanType.Premium);
      expect(decodedMessage.expiryDate).to.equal(30 * 24 * 60 * 60);
      expect(decodedMessage.tokenAmount).to.equal(ethers.parseUnits("100", 6));
      expect(decodedMessage.nonce).to.equal(nonce);
    });

    it("Should fail payment verification with an incorrect signer", async function () {
      // Sign the message hash
      let fakeSignature = await addr1.signMessage(ethers.getBytes(messageHash));

      const signatureData = {
        encodedMessage: encodedMessage,
        messageHash: messageHash,
        signature: fakeSignature,
      };

      await expect(signatureVerifier.verifyPaymentSignature(signatureData))
        .to.be.revertedWith("Invalid signer");
    });

    it("Should fail payment verification for an expired message", async function () {
      let expiredEncodedMessage = encodeAbiParameters(
        [{ name: "userAddress", type: "address" },
        { name: "product", type: "uint8" },
        { name: "planType", type: "uint8" },
        { name: "expiryDate", type: "uint256" },
        { name: "token", type: "address" },
        { name: "tokenAmount", type: "uint256" },
        { name: "validity", type: "uint256" },
        { name: "nonce", type: "uint256" }],
        [addr1.address, Product.AnalyticsPlatform, PlanType.Premium, 30 * 24 * 60 * 60, addr2.address, ethers.parseUnits("100", 6), await ethers.provider.getBlockNumber() - 1, nonce]
      );

      const expiredMessageHash = keccak256(expiredEncodedMessage);
      const expiredSignature = await owner.signMessage(ethers.getBytes(expiredMessageHash));

      const signatureData = {
        encodedMessage: expiredEncodedMessage,
        messageHash: expiredMessageHash,
        signature: expiredSignature,
      };

      await expect(signatureVerifier.verifyPaymentSignature(signatureData))
        .to.be.revertedWith("Message is expired");
    });
  });

  describe("Governance Signature Verification", function () {
    let encodedMessage;
    let messageHash;
    let signature;

    it("Should create a valid governance signature", async function () {
      // Encode the governance message using viem's encodeAbiParameters
      encodedMessage = encodeAbiParameters(
        [{ name: "userAddress", type: "address" },
        { name: "proposalId", type: "uint256" },
        { name: "averageBalance", type: "uint256" },
        { name: "support", type: "bool" },
        { name: "totalTokenHolders", type: "uint256" },
        { name: "validity", type: "uint256" }],
        [addr1.address, 1, ethers.parseUnits("1000", 18), true, 100, await ethers.provider.getBlockNumber() + 10]
      );

      // Hash the encoded message
      messageHash = keccak256(encodedMessage);

      // Sign the message hash
      signature = await owner.signMessage(ethers.getBytes(messageHash));
    });

    it("Should verify the governance signature successfully", async function () {
      const signatureData = {
        encodedMessage: encodedMessage,
        messageHash: messageHash,
        signature: signature,
      };

      const decodedMessage = await signatureVerifier.verifyGovernanceSignature(signatureData);

      // Verify the decoded message content
      expect(decodedMessage.userAddress).to.equal(addr1.address);
      expect(decodedMessage.proposalId).to.equal(1);
      expect(decodedMessage.support).to.equal(true);
      expect(decodedMessage.averageBalance).to.equal(ethers.parseUnits("1000", 18));
      expect(decodedMessage.totalTokenHolders).to.equal(100);
    });

    it("Should fail governance verification with an incorrect signer", async function () {
      // Sign the message hash
      let fakeSignature = await addr1.signMessage(ethers.getBytes(messageHash));

      const signatureData = {
        encodedMessage: encodedMessage,
        messageHash: messageHash,
        signature: fakeSignature,
      };

      await expect(signatureVerifier.verifyGovernanceSignature(signatureData))
        .to.be.revertedWith("Invalid signer");
    });

    it("Should fail governance verification for an expired message", async function () {
      let expiredEncodedMessage = encodeAbiParameters(
        [{ name: "userAddress", type: "address" },
        { name: "proposalId", type: "uint256" },
        { name: "averageBalance", type: "uint256" },
        { name: "support", type: "bool" },
        { name: "totalTokenHolders", type: "uint256" },
        { name: "validity", type: "uint256" }],
        [addr1.address, 1, ethers.parseUnits("1000", 18), true, 100, await ethers.provider.getBlockNumber() - 1]
      );

      const expiredMessageHash = keccak256(expiredEncodedMessage);
      const expiredSignature = await owner.signMessage(ethers.getBytes(expiredMessageHash));

      const signatureData = {
        encodedMessage: expiredEncodedMessage,
        messageHash: expiredMessageHash,
        signature: expiredSignature,
      };

      await expect(signatureVerifier.verifyGovernanceSignature(signatureData))
        .to.be.revertedWith("Message is expired");
    });
  });
});
