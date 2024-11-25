const { ethers, upgrades } = require("hardhat");

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);

    // Define the token address
    const tokenAddress = "0x1EA9b385738aD3ACc9813048F42C2f310FF43472"; // Replace with your actual token address

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
