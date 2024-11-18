// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./interface/ITMAISoulboundNFT.sol";

contract TMAISoulboundNFT is
    Initializable,
    ERC721Upgradeable,
    OwnableUpgradeable
{
    struct PlanDetails {
        string section;
        string planType;
        uint256 expiryDate;
    }

    address public minter;
    string public baseURI; // Base URI for constructing token URIs

    uint256 private _tokenIdCounter;
    mapping(address => mapping(string => uint256)) public userToTokenId; // user -> section -> tokenId
    mapping(uint256 => PlanDetails) public tokenIdToPlanDetails;

    event SubscriptionCreated(
        address indexed user,
        uint256 tokenId,
        string section,
        string planType,
        uint256 expiryDate
    );
    event SubscriptionBurned(uint256 tokenId, address indexed user);
    event BaseURISet(string baseURI);
    event SubscriptionUpgraded(
        uint256 tokenId,
        string newPlanType,
        uint256 newExpiryDate
    );

    function initialize() public initializer {
        __ERC721_init("SoulboundNFT", "SBT");
        __Ownable_init();

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
        string memory section,
        string memory planType,
        uint256 duration
    ) external onlyMinterOrOwner {
        // Check if the user has an active NFT and burn it if expired
        uint256 existingTokenId = userToTokenId[to][section];
        if (existingTokenId !=0 && _isExpired(existingTokenId)) {
            _burn(existingTokenId);
            emit SubscriptionBurned(existingTokenId, to);
        }

        _tokenIdCounter += 1;
        uint256 tokenId = _tokenIdCounter;
        uint256 expiryDate = block.timestamp + duration;

        _mint(to, tokenId);

        PlanDetails memory plan = PlanDetails({
            section: section,
            planType: planType,
            expiryDate: expiryDate
        });

        tokenIdToPlanDetails[tokenId] = plan;
        userToTokenId[to][section] = tokenId;

        emit SubscriptionCreated(to, tokenId, section, planType, expiryDate);
    }

    // Burn an existing NFT
    function burn(uint256 tokenId) external onlyOwner {
        address owner = ownerOf(tokenId);
        string memory section = tokenIdToPlanDetails[tokenId].section;
        _burn(tokenId);
        delete tokenIdToPlanDetails[tokenId];
        delete userToTokenId[owner][section];

        emit SubscriptionBurned(tokenId, owner);
    }

    // Upgrade an NFT's plan details (planType and expiryDate)
    function upgradeNFT(
        address user,
        string memory section,
        string memory newPlanType,
        uint256 newDuration
    ) external onlyMinterOrOwner {
        uint256 tokenId = userToTokenId[user][section];
        require(tokenId != 0, "User does not own an NFT for this section");

        PlanDetails storage plan = tokenIdToPlanDetails[tokenId];
        require(!_isExpired(tokenId), "Cannot upgrade an expired NFT");

        plan.planType = newPlanType;
        plan.expiryDate = block.timestamp + newDuration;

        emit SubscriptionUpgraded(tokenId, newPlanType, plan.expiryDate);
    }

    // Set the base URI for constructing token URIs
    function setBaseURI(string memory _baseURI) external onlyOwner {
        baseURI = _baseURI;
        emit BaseURISet(_baseURI);
    }

    function hasActiveNFT(
        address user,
        string memory section
    ) external view returns (bool) {
        uint256 tokenId = userToTokenId[user][section];
        if (tokenId == 0) {
            return false; // User does not own an NFT for this section
        }
        PlanDetails memory plan = tokenIdToPlanDetails[tokenId];
        return block.timestamp <= plan.expiryDate; // Check if the NFT is active
    }

    function _isExpired(uint256 tokenId) internal view returns (bool) {
        return block.timestamp > tokenIdToPlanDetails[tokenId].expiryDate;
    }

    function getUserPlanDetails(
        address user,
        string memory section
    ) external view returns (PlanDetails memory) {
        uint256 tokenId = userToTokenId[user][section];
        require(tokenId != 0, "User does not own an NFT for this section");
        return tokenIdToPlanDetails[tokenId];
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        PlanDetails memory plan = tokenIdToPlanDetails[tokenId];
        return
            string(abi.encodePacked(baseURI, plan.section, "/", plan.planType));
    }

    function grantMinterRole(address _minter) external onlyOwner {
        minter = _minter;
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
}
