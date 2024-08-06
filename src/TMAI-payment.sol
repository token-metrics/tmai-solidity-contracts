// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.2;

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";



contract TMAIPayment is
    Initializable,
    Ownable2StepUpgradeable
{
    using SafeMathUpgradeable for uint;
	using SafeERC20 for IERC20;

    address public treasury;
    address public dao;
    address public stakingContract;
    uint public daoShare;
    address public admin;
    address public baseStableCoin; 

    event RevenueDistributed(uint revenue, uint treasuryAmount, uint daoAmount);
    event TokensWithdrawn(address token, address to, uint amount);


    function initialize(address _treasury, address _dao, address _staking, uint _daoShare, address _baseStableCoin) public initializer {
        require(_treasury != address(0), "Treasury address can not be zero address");
        require(_dao != address(0), "DAO address can not be zero address");
        require(_staking != address(0), "Staking contract address can not be zero address");
        require(_baseStableCoin != address(0), "Base Stable Coin address can not be zero address");
        require(daoShare <= 10000, "DAO Share cannot be greater than 10000");
        __Ownable2Step_init();
        treasury = _treasury;
        dao = _dao;
        stakingContract = _staking;
        daoShare = _daoShare;
        baseStableCoin = _baseStableCoin;

    }

    function distributeRevenue() public onlyOwner {
        uint revenue = IERC20(baseStableCoin).balanceOf(address(this));
        require(revenue > 0, "No Revenue to distribute");
        uint daoAmount = revenue.mul(daoShare).div(10000);
        uint treasuryAmount = revenue.sub(daoAmount);
        IERC20(baseStableCoin).safeTransfer(dao, daoAmount);
        IERC20(baseStableCoin).safeTransfer(treasury, treasuryAmount);
        emit RevenueDistributed(revenue, treasuryAmount, daoAmount);

    }

    function updateDAOShare(uint _share) public onlyOwner {
        require(daoShare <= 10000, "DAO Share cannot be greater than 10000");
        daoShare = _share;
    }

    function withdrawTokens( address _tokenAddress, uint256 _amount) external onlyOwner {
        require(_tokenAddress != address(0), "Token address can not be zero address");
        require(_tokenAddress != baseStableCoin);
        IERC20(_tokenAddress).safeTransfer(msg.sender, _amount);
        emit TokensWithdrawn(_tokenAddress, msg.sender, _amount);
    }

    function updateDAO(address _dao) public onlyOwner {
        require(_dao !=address(0), "DAO address cannot be zero address");
        dao = _dao;
    }

    function updateTreasury(address _treasury) public onlyOwner {
        require(_treasury !=address(0), "Treasury address cannot be zero address");
        treasury = _treasury;
    }


}
