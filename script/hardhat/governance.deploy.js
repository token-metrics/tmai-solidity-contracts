// scripts/deploy.js
const { ethers, upgrades } = require("hardhat");

async function main() {
  // Declare variables at the top
  let Timelock, timelock, GovernorAlpha, governorAlpha;
  const adminAddress = "0x532d1069A649f2C0F6e34DB598f10082b0296f20"; // Replace with the admin address
  const TMAIAddress = "0xD68325eAB47fAA4Be498917ECf1F840d39aD7414"; // Replace with the TMAI token address
  const baseStableCoinAddress = "0x5ae17567F14e28723815904326eFe5a20Ba25Fa9"; // Replace with the stablecoin address
  const signatureVerifierAddress = "0x6E4155d06c962533A53f973d025c2F30bc93B0B4"; // Replace with the signature verifier address
  const quorumPercentage = "10"; // Quorum percentage
  const yesVoteThresholdPercentage = 10; // Yes vote threshold percentage
//   const timelockDelay = 0 * 24 * 60 * 60; // 0 days delay
  const timelockDelay = 2 * 60; // 2 minutes delay

  // Deploy the Timelock contract
  Timelock = await ethers.getContractFactory("Timelock");
  timelock = await Timelock.deploy(adminAddress, timelockDelay);
  await timelock.waitForDeployment();
  console.log("Timelock deployed to:", timelock.target);

  // Deploy the GovernorAlpha contract
  GovernorAlpha = await ethers.getContractFactory("GovernorAlpha");
  governorAlpha = await upgrades.deployProxy(GovernorAlpha, [
    timelock.target,
    TMAIAddress,
    baseStableCoinAddress,
    signatureVerifierAddress,
    quorumPercentage,
    yesVoteThresholdPercentage
  ]);
  await governorAlpha.waitForDeployment();
  console.log("GovernorAlpha deployed to:", governorAlpha.target);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });