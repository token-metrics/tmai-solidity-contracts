const { ethers, upgrades } = require("hardhat");

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);

    // Define the token address
    const tokenAddress = "0xD68325eAB47fAA4Be498917ECf1F840d39aD7414"; // Replace with your actual token address

    // Deploy the TMAIVesting contract
    const TMAIVesting = await ethers.getContractFactory("TMAIVesting");
    const tmaiVesting = await upgrades.deployProxy(TMAIVesting, [tokenAddress], { initializer: 'initialize' });

    await tmaiVesting.waitForDeployment();

    console.log("TMAIVesting deployed to:", tmaiVesting.target);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
