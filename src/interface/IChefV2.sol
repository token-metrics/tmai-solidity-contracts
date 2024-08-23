// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

interface ChefInterface{

     enum Level {
        Level0,
        Level1,
        Level2,
        Level3,
        Level4,
        Level5,
        Level6,
        Level7,
        Level8,
        Level9
    }


    function checkHighestStaker(address user) external view returns (bool);
    
    // function stakingScoreAndMultiplier(
    //     address _userAddress,
    //     uint256 _stakedAmount
    // )
    //     external
    //     view
    //     returns (
    //         uint256,
    //         uint256,
    //         uint256
    //     );

    function getStakingMultiplier(
        address _user
    ) external view returns (uint256);

    function calculateStakingScore(
        address _user
    ) external view returns (uint256) ;
    
    function depositWithUserAddress(
        uint256 _amount,
        uint256 _vault,
        address _userAddress
    ) external;

    function userInfo(uint256 _pid, address _userAddress) external view returns (uint256, uint256, bool, uint256);

    function distributeExitFeeShare(uint256 _amount) external;
    
    function distributeAdditionalReward(uint256 _rewardAmount) external;

     function getLevelForUser(address _user) external view returns (Level);

}