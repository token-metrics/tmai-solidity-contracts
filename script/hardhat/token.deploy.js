const { ethers } = require("hardhat");

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deployer", deployer.address);

    const allocationContract = deployer.address;

    const TMAITokenContract = await ethers.getContractFactory("TMAIToken");

    const tmaitoken = await upgrades.deployProxy(
        TMAITokenContract,
        [
            allocationContract
        ],
        { unsafeAllowLinkedLibraries: true }
    );

    await tmaitoken.waitForDeployment();

    console.log("TMAI Token is deployed on: ", tmaitoken.target);

}

main();