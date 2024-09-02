// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.2;

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./interface/ITMAISoulboundNFT.sol";
import "./utils/SignatureVerifier.sol";

contract TMAIPayment is Initializable, Ownable2StepUpgradeable {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public treasury;
    address public dao;
    address public stakingContract;
    uint256 public daoShare;
    address public admin;
    address public baseStableCoin;
    address public nftContract; // Address of the Soulbound NFT contract
    SignatureVerifier public signatureVerifier; // Address of the SignatureVerifier contract

    event RevenueDistributed(
        uint256 revenue,
        uint256 treasuryAmount,
        uint256 daoAmount
    );
    event TokensWithdrawn(address token, address to, uint256 amount);
    event SubscriptionCreated(
        address indexed user,
        string section,
        string planType,
        uint256 expiryDate
    );
    event SubscriptionUpgraded(
        address indexed user,
        string section,
        string newPlanType,
        uint256 newExpiryDate
    );

    function initialize(
        address _treasury,
        address _dao,
        address _staking,
        uint256 _daoShare,
        address _baseStableCoin,
        address _nftContract,
        address _signatureVerifier
    ) public initializer {
        require(
            _treasury != address(0),
            "Treasury address cannot be zero address"
        );
        require(_dao != address(0), "DAO address cannot be zero address");
        require(
            _staking != address(0),
            "Staking contract address cannot be zero address"
        );
        require(
            _baseStableCoin != address(0),
            "Base Stable Coin address cannot be zero address"
        );
        require(
            _nftContract != address(0),
            "NFT contract address cannot be zero address"
        );
        require(
            _signatureVerifier != address(0),
            "Signature verifier address cannot be zero address"
        );
        require(_daoShare <= 10000, "DAO Share cannot be greater than 10000");

        __Ownable2Step_init();
        treasury = _treasury;
        dao = _dao;
        stakingContract = _staking;
        daoShare = _daoShare;
        baseStableCoin = _baseStableCoin;
        nftContract = _nftContract;
        signatureVerifier = SignatureVerifier(_signatureVerifier);
    }

    // Process the payment and create or upgrade a subscription
    function processPayment(
        SignatureVerifier.Signature memory signature,
        bool isUpgrade
    ) external {
        SignatureVerifier.EncodedMessage memory message = signatureVerifier
            .verifySignature(signature);

        // Process payment in USDC from the user's address provided in the message
        require(
            IERC20Upgradeable(baseStableCoin).transferFrom(
                message.userAddress,
                address(this),
                message.usdcAmount
            ),
            "Payment failed"
        );

        if (isUpgrade) {
            // Upgrade the existing subscription
            ITMAISoulboundNFT(nftContract).upgradeNFT(
                message.userAddress,
                message.section,
                message.planType,
                message.expiryDate // Use the expiry date provided in the message
            );
            emit SubscriptionUpgraded(
                message.userAddress,
                message.section,
                message.planType,
                message.expiryDate
            );
        } else {
            // Create a new subscription
            ITMAISoulboundNFT(nftContract).mint(
                message.userAddress,
                message.section,
                message.planType,
                message.expiryDate // Use the expiry date provided in the message
            );
            emit SubscriptionCreated(
                message.userAddress,
                message.section,
                message.planType,
                message.expiryDate
            );
        }
    }

    function distributeRevenue() public onlyOwner {
        uint256 revenue = IERC20Upgradeable(baseStableCoin).balanceOf(
            address(this)
        );
        require(revenue > 0, "No Revenue to distribute");
        uint256 daoAmount = revenue.mul(daoShare).div(10000);
        uint256 treasuryAmount = revenue.sub(daoAmount);
        IERC20Upgradeable(baseStableCoin).safeTransfer(dao, daoAmount);
        IERC20Upgradeable(baseStableCoin).safeTransfer(
            treasury,
            treasuryAmount
        );
        emit RevenueDistributed(revenue, treasuryAmount, daoAmount);
    }

    function updateDAOShare(uint256 _share) public onlyOwner {
        require(_share <= 10000, "DAO Share cannot be greater than 10000");
        daoShare = _share;
    }

    function withdrawTokens(
        address _tokenAddress,
        uint256 _amount
    ) external onlyOwner {
        require(
            _tokenAddress != address(0),
            "Token address cannot be zero address"
        );
        require(
            _tokenAddress != baseStableCoin,
            "Cannot withdraw base stable coin"
        );
        IERC20Upgradeable(_tokenAddress).safeTransfer(msg.sender, _amount);
        emit TokensWithdrawn(_tokenAddress, msg.sender, _amount);
    }

    function updateDAO(address _dao) public onlyOwner {
        require(_dao != address(0), "DAO address cannot be zero address");
        dao = _dao;
    }

    function updateTreasury(address _treasury) public onlyOwner {
        require(
            _treasury != address(0),
            "Treasury address cannot be zero address"
        );
        treasury = _treasury;
    }

    // Allow updating the SignatureVerifier contract address
    function updateSignatureVerifier(
        address _signatureVerifier
    ) external onlyOwner {
        require(
            _signatureVerifier != address(0),
            "Signature verifier address cannot be zero address"
        );
        signatureVerifier = SignatureVerifier(_signatureVerifier);
    }
}
