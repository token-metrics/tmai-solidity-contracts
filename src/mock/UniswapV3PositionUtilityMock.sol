// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

contract UniswapV3PositionUtilityMock {
    function getTokenAmount(uint256 tokenId) public pure returns (uint256) {
        // Mock function to return a fixed token amount based on the tokenId
        return tokenId * 1000;
    }
}
