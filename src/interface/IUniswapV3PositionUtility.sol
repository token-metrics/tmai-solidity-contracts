// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.2;

interface IUniswapV3PositionUtility{

    function getTokenAmount (uint256 _tokenID) external view returns (uint256);

}