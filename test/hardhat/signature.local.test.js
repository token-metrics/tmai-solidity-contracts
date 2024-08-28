const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const { encodeAbiParameters, keccak256 } = require("viem");

describe("SignatureVerifier", function () {
  let signatureVerifier;
  let owner;
  let addr1;
  let addr2;


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

  describe("Signature Verification", function () {
    let encodedMessage;
    let messageHash;
    let signature;

    it("Should create a valid signature", async function () {
      // Encode the message using viem's encodeAbiParameters
      encodedMessage = encodeAbiParameters(
        [{ name: "userAddress", type: "address" },
         { name: "section", type: "string" },
         { name: "planType", type: "string" },
         { name: "expiryDate", type: "uint256" },
         { name: "usdcAmount", type: "uint256" },
         { name: "validity", type: "uint256" },
        ],
        [addr1.address, "analytics", "premium", 30 * 24 * 60 * 60, ethers.parseUnits("100", 6), await ethers.provider.getBlockNumber() + 10]
      );

      // Hash the encoded message
      messageHash = keccak256(encodedMessage);

      // Sign the message hash
      signature = await owner.signMessage(ethers.getBytes(messageHash));
    });


    it("Should verify the signature successfully", async function () {
      const signatureData = {
        encodedMessage: encodedMessage,
        messageHash: messageHash,
        signature: signature,
      };

      const decodedMessage = await signatureVerifier.verifySignature(signatureData);

      // Verify the decoded message content
      expect(decodedMessage.userAddress).to.equal(addr1.address);
      expect(decodedMessage.section).to.equal("analytics");
      expect(decodedMessage.planType).to.equal("premium");
      expect(decodedMessage.expiryDate).to.equal(30 * 24 * 60 * 60);
      expect(decodedMessage.usdcAmount).to.equal(ethers.parseUnits("100", 6));
    });

    it("Should fail verification with an incorrect signer", async function () {

        // Sign the message hash
      let fakeSignature = await addr1.signMessage(ethers.getBytes(messageHash));

      const signatureData = {
        encodedMessage: encodedMessage,
        messageHash: messageHash,
        signature: fakeSignature,
      };

      await expect(signatureVerifier.verifySignature(signatureData))
        .to.be.revertedWith("Invalid signer");
    });

    it("Should fail verification for an expired message", async function () {
        let expiredEncodedMessage = encodeAbiParameters(
            [{ name: "userAddress", type: "address" },
             { name: "section", type: "string" },
             { name: "planType", type: "string" },
             { name: "expiryDate", type: "uint256" },
             { name: "usdcAmount", type: "uint256" },
             { name: "validity", type: "uint256" },
            ],
            [addr1.address, "analytics", "premium", 30 * 24 * 60 * 60, ethers.parseUnits("100", 6), await ethers.provider.getBlockNumber() - 1]
          );

      const expiredMessageHash = keccak256(expiredEncodedMessage);
      const expiredSignature = await owner.signMessage(ethers.getBytes(expiredMessageHash));

      const signatureData = {
        encodedMessage: expiredEncodedMessage,
        messageHash: expiredMessageHash,
        signature: expiredSignature,
      };

      await expect(signatureVerifier.verifySignature(signatureData))
        .to.be.revertedWith("Message is expired");
    });
  });
});
