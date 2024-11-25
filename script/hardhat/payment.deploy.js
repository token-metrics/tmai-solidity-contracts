const { ethers, upgrades } = require("hardhat");

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);

    // Define the necessary addresses
    const treasuryAddress = "0x532d1069A649f2C0F6e34DB598f10082b0296f20"; // Replace with your actual treasury address
    const daoAddress = "0xd6aC61adC3aF34A9797EE49F9c81F2535823d112"; // Replace with your actual DAO address
    const nftContractAddress = "0xb7f2e16aD9Aa8845C4C2a7BdBbAc239FA261820f"; // Replace with your actual NFT contract address
    const signatureVerifierAddress = "0x7Fe5271a3369725712170560f5D448AF1eC1e514"; // Replace with your actual SignatureVerifier contract address
    const daoShare = 5000; // Example DAO share (50%)

    // Deploy the TMAIPayment contract
    const TMAIPayment = await ethers.getContractFactory("TMAIPayment");
    const tmaiPayment = await upgrades.deployProxy(TMAIPayment, [treasuryAddress, daoAddress, daoShare, nftContractAddress, signatureVerifierAddress], { initializer: 'initialize' });

    await tmaiPayment.waitForDeployment();

    console.log("TMAIPayment deployed to:", tmaiPayment.target);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    }); 