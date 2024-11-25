const { ethers, upgrades } = require("hardhat");

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);

    // Deploy the TMAISoulboundNFT contract
    const TMAISoulboundNFT = await ethers.getContractFactory("TMAISoulboundNFT");
    const tmaiSoulboundNFT = await upgrades.deployProxy(TMAISoulboundNFT, [], { initializer: 'initialize' });

    await tmaiSoulboundNFT.waitForDeployment();

    console.log("TMAISoulboundNFT deployed to:", tmaiSoulboundNFT.target);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });