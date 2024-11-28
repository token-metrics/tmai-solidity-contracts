const { ethers, upgrades } = require("hardhat");

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);

    // Define the necessary addresses
    const treasuryAddress = "0x532d1069A649f2C0F6e34DB598f10082b0296f20"; // Replace with your actual treasury address
    const daoAddress = "0xd6aC61adC3aF34A9797EE49F9c81F2535823d112"; // Replace with your actual DAO address
    const nftContractAddress = "0x7d31B6251997cda4DDF54CC1a39655Bca9094575"; // Replace with your actual NFT contract address
    const signatureVerifierAddress = "0x6E4155d06c962533A53f973d025c2F30bc93B0B4"; // Replace with your actual SignatureVerifier contract address
    const daoShare = 5000; // Example DAO share (50%)

    // Deploy the TMAIPayment contract
    const TMAIPayment = await ethers.getContractFactory("TMAIPayment");
    const tmaiPayment = await upgrades.deployProxy(TMAIPayment, [treasuryAddress, daoAddress, daoShare, nftContractAddress, signatureVerifierAddress], { initializer: 'initialize' });

    await tmaiPayment.waitForDeployment();

    console.log("TMAIPayment deployed to:", tmaiPayment.target);

    // Attach the nft contract and make a transaction to set the payment contract address
    const nftContract = await ethers.getContractAt("TMAISoulboundNFT", nftContractAddress);
    await nftContract.grantMinterRole(tmaiPayment.target);
    console.log("Minter role granted to TMAIPayment contract");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    }); 