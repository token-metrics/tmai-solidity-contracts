require("dotenv").config();
require("@nomicfoundation/hardhat-chai-matchers");
require("@nomiclabs/hardhat-etherscan");
require("@nomicfoundation/hardhat-ethers");
require("@openzeppelin/hardhat-upgrades");

// Testnet
const { TEST_PRIVATE_KEY} = process.env;
// Mainnet
const { DEPLOYER_PRIVATE_KEY, ARBISCAN_API_KEY, ARBITRUM_RPC_URL } = process.env;

module.exports = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
    },
    arbitrumOne: {
      url: ARBITRUM_RPC_URL,
      accounts: [DEPLOYER_PRIVATE_KEY],
    },
  },
  etherscan: {
    apiKey: {
      arbitrumOne: ARBISCAN_API_KEY,
    }
  },
  solidity: {
    compilers: [
      {
        version: "0.8.2",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.8.19",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  paths: {
    sources: "./src",
    tests: "./test/hardhat",
    scripts: "./script/hardhat",
  },
};