require("dotenv").config();
require("@nomicfoundation/hardhat-chai-matchers");
require("@nomicfoundation/hardhat-verify");
require("@nomicfoundation/hardhat-ethers");
require("@openzeppelin/hardhat-upgrades");

// Testnet
const { TEST_PRIVATE_KEY } = process.env;
// Mainnet
const { DEPLOYER_PRIVATE_KEY, BASE_RPC_URL, BASESCAN_API_KEY, SEPOLIA_RPC_URL, ETHERSCAN_API_KEY } = process.env;

module.exports = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
    },

    // Mainnet
    base: {
      url: BASE_RPC_URL,
      accounts: [DEPLOYER_PRIVATE_KEY],
    },

    // Testnet
    sepolia: {
      url: SEPOLIA_RPC_URL,
      accounts: [TEST_PRIVATE_KEY],
    },
    baseSepolia: {
      url: "https://sepolia.base.org",
      accounts: [TEST_PRIVATE_KEY],
    },
  },


  etherscan: {
    apiKey: {
      base: BASESCAN_API_KEY,
      baseSepolia: BASESCAN_API_KEY,
      sepolia: ETHERSCAN_API_KEY,
    },

    customChains: [
      {
        network: "baseSepolia",
        chainId: 84532,
        urls: {
          apiURL: "https://api-sepolia.basescan.org/api",
          browserURL: "https://sepolia.basescan.org/",
        },
      },
      {
        network: "base",
        chainId: 8453,
        urls: {
          apiURL: "https://api.basescan.org/api",
          browserURL: "https://basescan.org/",
        },
      },
    ],
  },


  solidity: {
    compilers: [
      {
        version: "0.8.20",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      }
    ],
  },


  paths: {
    sources: "./src",
    tests: "./test/hardhat",
    scripts: "./script/hardhat",
  },
};