// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./interface/ITMAISoulboundNFT.sol";

contract TMAISoulboundNFT is
    Initializable,
    ERC721Upgradeable,
    OwnableUpgradeable,
    PausableUpgradeable
{
    using Strings for uint256;

    struct PlanDetails {
        Product product;
        PlanType planType;
        uint256 expiryDate;
    }

    address public minter;
    string public baseURI; // Base URI for constructing token URIs

    uint256 private _tokenIdCounter;
    mapping(address => mapping(Product => uint256)) public userToTokenId; // user -> product -> tokenId
    mapping(uint256 => PlanDetails) public tokenIdToPlanDetails;

    uint256 public totalNFTsInCirculation; // New variable to track NFTs in circulation

    event SubscriptionCreated(
        address indexed user,
        uint256 tokenId,
        Product product,
        PlanType planType,
        uint256 expiryDate
    );
    event SubscriptionBurned(uint256 tokenId, address indexed user);
    event BaseURISet(string baseURI);
    event SubscriptionUpgraded(
        uint256 tokenId,
        PlanType newPlanType,
        uint256 newExpiryDate
    );
    event MinterRoleGranted(address account);
    event MinterRoleRevoked(address account);

    // Define valid plan types
    enum PlanType {
        Basic,
        Advanced,
        Premium,
        VIP,
        Enterprise
    }

    // Define valid products
    enum Product {
        TradingBot,
        DataAPI,
        AnalyticsPlatform
    }

    function initialize() public initializer {
        __ERC721_init("TMAI Soulbound NFT", "TMAI");
        __Ownable_init();
        __Pausable_init();

        minter = msg.sender;
    }

    modifier onlyMinterOrOwner() {
        require(
            minter == msg.sender || owner() == msg.sender,
            "Not authorized"
        );
        _;
    }

    // Mint a new NFT, automatically burn the old one if expired
    function mint(
        address to,
        Product product,
        PlanType planType,
        uint256 duration
    ) external onlyMinterOrOwner whenNotPaused {
        // Check if the user has an active NFT and burn it if expired
        uint256 existingTokenId = userToTokenId[to][product];
        if (existingTokenId != 0 && _isExpired(existingTokenId)) {
            _burn(existingTokenId);
            emit SubscriptionBurned(existingTokenId, to);
            totalNFTsInCirculation--; // Decrement on burn
        }

        _tokenIdCounter += 1;
        uint256 tokenId = _tokenIdCounter;
        uint256 expiryDate = block.timestamp + duration;

        _mint(to, tokenId);
        totalNFTsInCirculation++; // Increment on mint

        PlanDetails memory plan = PlanDetails({
            product: product,
            planType: planType,
            expiryDate: expiryDate
        });

        tokenIdToPlanDetails[tokenId] = plan;
        userToTokenId[to][product] = tokenId;

        emit SubscriptionCreated(to, tokenId, product, planType, expiryDate);
    }

    // Burn an existing NFT
    function burn(uint256 tokenId) external onlyOwner whenNotPaused {
        address owner = ownerOf(tokenId);
        Product product = tokenIdToPlanDetails[tokenId].product;
        _burn(tokenId);
        delete tokenIdToPlanDetails[tokenId];
        delete userToTokenId[owner][product];

        emit SubscriptionBurned(tokenId, owner);
        totalNFTsInCirculation--; // Decrement on burn
    }

    // Upgrade an NFT's plan details (planType and expiryDate)
    function upgradeNFT(
        address user,
        Product product,
        PlanType newPlanType,
        uint256 newDuration
    ) external onlyMinterOrOwner {
        uint256 tokenId = userToTokenId[user][product];
        require(tokenId != 0, "User does not own an NFT for this product");

        PlanDetails storage plan = tokenIdToPlanDetails[tokenId];
        require(!_isExpired(tokenId), "Cannot upgrade an expired NFT");

        // Check for redundant upgrade
        uint256 newExpiryDate = block.timestamp + newDuration;
        require(
            plan.planType != newPlanType || plan.expiryDate != newExpiryDate,
            "Redundant upgrade: new values are the same as existing"
        );

        plan.planType = newPlanType;
        plan.expiryDate = newExpiryDate;

        emit SubscriptionUpgraded(tokenId, newPlanType, newExpiryDate);
    }

    // Set the base URI for constructing token URIs
    function setBaseURI(string memory _baseURI) external onlyOwner {
        baseURI = _baseURI;
        emit BaseURISet(_baseURI);
    }

    function hasActiveNFT(
        address user,
        Product product
    ) external view returns (bool) {
        uint256 tokenId = userToTokenId[user][product];
        if (tokenId == 0) {
            return false; // User does not own an NFT for this product
        }
        PlanDetails memory plan = tokenIdToPlanDetails[tokenId];
        return block.timestamp <= plan.expiryDate; // Check if the NFT is active
    }

    function _isExpired(uint256 tokenId) internal view returns (bool) {
        return block.timestamp > tokenIdToPlanDetails[tokenId].expiryDate;
    }

    function getUserPlanDetails(
        address user,
        Product product
    ) external view returns (PlanDetails memory) {
        uint256 tokenId = userToTokenId[user][product];
        require(tokenId != 0, "User does not own an NFT for this product");
        return tokenIdToPlanDetails[tokenId];
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        PlanDetails memory plan = tokenIdToPlanDetails[tokenId];

        // Convert enum values to strings
        string memory product = uint256(plan.product).toString();
        string memory planType = uint256(plan.planType).toString();

        return string(abi.encodePacked(baseURI, product, "/", planType, ".json"));
    }

    function grantMinterRole(address account) external onlyOwner {
        minter = account;
        emit MinterRoleGranted(account);
    }

    function revokeMinterRole() external onlyOwner {
        require(minter != address(0), "Minter role is already revoked");
        address previousMinter = minter;
        minter = address(0);
        emit MinterRoleRevoked(previousMinter);
    }

    // Prevent transfers by anyone other than the owner (contract owner)
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override {
        require(
            from == address(0) || to == address(0) || msg.sender == owner(),
            "Soulbound tokens are non-transferable"
        );
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    // Add functions to pause and unpause the contract
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
