// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

contract UniswapV3FactoryMock {
    mapping(address => mapping(address => mapping(uint24 => address))) public pools;

    function createPool(address token0, address token1, uint24 fee) public returns (address pool) {
        pool = address(uint160(uint256(keccak256(abi.encodePacked(token0, token1, fee)))));
        pools[token0][token1][fee] = pool;
        pools[token1][token0][fee] = pool;
    }

    function getPool(address token0, address token1, uint24 fee) external view returns (address) {
        return pools[token0][token1][fee];
    }
}
