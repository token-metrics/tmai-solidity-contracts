// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ITMAISoulboundNFT {
    function mint(
        address to,
        uint8 section,
        uint8 planType,
        uint256 duration
    ) external;

    function burn(uint256 tokenId) external;

    function upgradeNFT(
        address user,
        uint8 section,
        uint8 newPlanType,
        uint256 newDuration
    ) external;
}