// SPDX-License-Identifier: MIT
pragma solidity 0.8.2;

interface ITMAISoulboundNFT {
    function mint(
        address to,
        string memory section,
        string memory planType,
        uint256 duration
    ) external;

    function burn(uint256 tokenId) external;

    function upgradeNFT(
        address user,
        string memory section,
        string memory newPlanType,
        uint256 newDuration
    ) external;
}