const { ethers, upgrades } = require("hardhat");

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);

    // Define the signer address
    const signerAddress = "0xf72CAd40DA5B2F2Bc54d65e9CCB5C0ebA96d789a"; // Replace with your actual signer address

    // Deploy the SignatureVerifier contract
    const SignatureVerifier = await ethers.getContractFactory("SignatureVerifier");
    const signatureVerifier = await upgrades.deployProxy(SignatureVerifier, [signerAddress], { initializer: 'initialize' });

    await signatureVerifier.waitForDeployment();

    console.log("SignatureVerifier deployed to:", signatureVerifier.target);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    }); 