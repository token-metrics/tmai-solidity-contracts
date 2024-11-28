const { ethers } = require("hardhat");

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deployer", deployer.address);

    const USDC = await ethers.getContractFactory("ERC20Mock");

    const usdc = await USDC.deploy("mUSDC", "mUSDC", "1000000000000000000000000");

    await usdc.waitForDeployment();

    console.log("TMAI Token is deployed on: ", usdc.target);

}

main();