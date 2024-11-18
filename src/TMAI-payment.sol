// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./interface/ITMAISoulboundNFT.sol";
import "./utils/SignatureVerifier.sol";

contract TMAIPayment is Initializable, Ownable2StepUpgradeable, PausableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public treasury;
    address public dao;
    uint256 public daoShare;
    address public nftContract; // Address of the Soulbound NFT contract
    SignatureVerifier public signatureVerifier; // Address of the SignatureVerifier contract

    mapping(address => bool) public allowedTokens; // Mapping to track allowed payment tokens
    mapping(address => uint256) public nonces; // Track each user’s transaction count

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
    event TokenEnabled(address token);
    event TokenDisabled(address token);

    // Initialize contract with required addresses
    function initialize(
        address _treasury,
        address _dao,
        uint256 _daoShare,
        address _nftContract,
        address _signatureVerifier
    ) public initializer {
        require(
            _treasury != address(0),
            "Treasury address cannot be zero address"
        );
        require(_dao != address(0), "DAO address cannot be zero address");
        require(
            _nftContract != address(0),
            "NFT contract address cannot be zero address"
        );
        require(
            _signatureVerifier != address(0),
            "Signature verifier address cannot be zero address"
        );
        require(_daoShare <= 10000, "DAO Share cannot be greater than 100 percent");

        __Ownable2Step_init();
        __Pausable_init();
        treasury = _treasury;
        dao = _dao;
        daoShare = _daoShare;
        nftContract = _nftContract;
        signatureVerifier = SignatureVerifier(_signatureVerifier);
    }

    // Process the payment and create or upgrade a subscription
    function processPayment(
        SignatureVerifier.Signature memory signature,
        bool isUpgrade
    ) external whenNotPaused {
        SignatureVerifier.PaymentMessage memory message = signatureVerifier
            .verifyPaymentSignature(signature);

        // Ensure the nonce matches the current nonce for the user
        require(message.nonce == nonces[message.userAddress], "Invalid nonce");

        // Ensure the token is allowed for payments
        require(allowedTokens[message.token], "Token not allowed");

        // Process payment in the specified token from the user's address
        require(
            IERC20Upgradeable(message.token).transferFrom(
                message.userAddress,
                address(this),
                message.tokenAmount
            ),
            "Payment failed"
        );

        if (isUpgrade) {
            // Upgrade the existing subscription
            ITMAISoulboundNFT(nftContract).upgradeNFT(
                message.userAddress,
                message.section,
                message.planType,
                message.expiryDate
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
                message.expiryDate
            );
            emit SubscriptionCreated(
                message.userAddress,
                message.section,
                message.planType,
                message.expiryDate
            );
        }

        // Increment nonce after successful processing
        nonces[message.userAddress]++;
    }

    // Distribute revenue from payments to treasury and DAO
    function distributeRevenue(address token) public onlyOwner {
        uint256 revenue = IERC20Upgradeable(token).balanceOf(address(this));
        require(revenue > 0, "No revenue to distribute");

        uint256 daoAmount = revenue * daoShare / 10000;
        uint256 treasuryAmount = revenue - daoAmount;

        IERC20Upgradeable(token).safeTransfer(dao, daoAmount);
        IERC20Upgradeable(token).safeTransfer(treasury, treasuryAmount);

        emit RevenueDistributed(revenue, treasuryAmount, daoAmount);
    }

    // Update DAO share
    function updateDAOShare(uint256 _share) public onlyOwner {
        require(_share <= 10000, "DAO share cannot be greater than 100 percent");
        daoShare = _share;
    }

    // Withdraw tokens from the contract
    function withdrawTokens(address token, uint256 _amount) external onlyOwner {
        require(token != address(0), "Token address cannot be zero address");
        IERC20Upgradeable(token).safeTransfer(msg.sender, _amount);
        emit TokensWithdrawn(token, msg.sender, _amount);
    }

    // Update DAO address
    function updateDAO(address _dao) public onlyOwner {
        require(_dao != address(0), "DAO address cannot be zero address");
        dao = _dao;
    }

    // Update Treasury address
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

    // Enable a token for payments
    function enableToken(address token) external onlyOwner {
        require(token != address(0), "Token address cannot be zero address");
        allowedTokens[token] = true;
        emit TokenEnabled(token);
    }

    // Disable a token for payments
    function disableToken(address token) external onlyOwner {
        require(token != address(0), "Token address cannot be zero address");
        allowedTokens[token] = false;
        emit TokenDisabled(token);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
