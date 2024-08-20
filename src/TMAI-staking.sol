// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.2;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";
import "./interface/IERC721.sol";
import "./interface/uniswap/IUniswapV3Factory.sol";
import "./interface/IUniswapV3PositionUtility.sol";
import "@arbitrum/nitro-contracts/src/precompiles/ArbSys.sol";

contract TMAIStaking is
    Initializable,
    Ownable2StepUpgradeable,
    IERC721ReceiverUpgradeable
{
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

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

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        bool cooldown;
        uint256 cooldowntimestamp;
    }

    struct PoolInfo {
        IERC20Upgradeable lpToken;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 accTokenPerShare;
        uint256 totalStaked;
    }

    struct StakeInfo {
        uint256 amount;
        uint256 timestamp;
        uint256 withdrawTime;
        uint256 tokenId;
        bool isERC721;
    }

    struct HighestStaker {
        uint256 deposited;
        address addr;
    }

    IERC20Upgradeable public token;
    address public governanceAddress;
    IUniswapV3PositionUtility public uniswapUtility;
    IERC721 public erc721Token;

    uint256 public bonusEndBlock;
    uint256 public tokenPerBlock;
    uint256 public constant SECONDS_IN_DAY = 86400;
    uint256 public constant SECONDS_IN_WEEK = 604800;
    uint256 public constant SECONDS_IN_MONTH = 30 * SECONDS_IN_DAY;
    uint256 public constant DEFAULT_POOL = 0;
    address public constant ARBSYS_ADDRESS =
        0x0000000000000000000000000000000000000064;

    PoolInfo[] public poolInfo;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    mapping(address => StakeInfo[]) public userStakeInfo;
    uint256 public totalAllocPoint;
    uint256 public startBlock;
    uint256 public totalRewards;
    uint256 public maxPerBlockReward;

    mapping(uint256 => HighestStaker[]) public highestStakerInPool;
    mapping(address => bool) public isAllowedContract;
    mapping(address => uint256) public unClaimedReward;
    mapping(address => mapping(address => bool)) public lpTokensStatus;
    bool private isFirstDepositInitialized;
    mapping(address => bool) public eligibleDistributionAddress;
    mapping(Level => uint256) public levelMultipliers;
    mapping(Level => uint256) public aprLimiters;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );
    event EmergencyNFTWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 indexed tokenId
    );
    event AddPool(address indexed token0, address indexed token1);
    event DistributeReward(uint256 indexed rewardAmount);
    event RestakedReward(address _userAddress, uint256 indexed _amount);
    event ClaimedReward(address _userAddress, uint256 indexed _amount);
    event WhitelistDepositContract(
        address indexed _contractAddress,
        bool indexed _value
    );
    event SetGovernanceAddress(address indexed _governanceAddress);
    event SetUtilityContractAddress(
        IUniswapV3PositionUtility indexed _uniswapUtility
    );
    event Set(uint256 indexed _allocPoint, bool _withUpdate);
    event ReduceReward(
        uint256 indexed _rewardAmount,
        uint256 indexed _newPerBlockReward
    );

    function initialize(
        IERC20Upgradeable _token,
        uint256 _startBlock,
        uint256 _bonusEndBlock,
        uint256 _totalRewards
    ) external initializer {
        require(address(_token) != address(0), "Zero Address");
        __Ownable2Step_init();
        token = _token;
        bonusEndBlock = _bonusEndBlock;
        startBlock = _startBlock;
        totalRewards = _totalRewards;
        maxPerBlockReward = totalRewards.div(bonusEndBlock.sub(startBlock));
        tokenPerBlock = totalRewards.div(bonusEndBlock.sub(startBlock));
        add(100, _token);
        _setLevelMultipliers();
        _setAPRLimiters();
    }

    function getLevelFromStakingScore(
        uint256 stakingScore
    ) public pure returns (Level) {
        if (stakingScore >= 500_000 ether) {
            return Level.Level9;
        } else if (stakingScore >= 250_000 ether) {
            return Level.Level8;
        } else if (stakingScore >= 125_000 ether) {
            return Level.Level7;
        } else if (stakingScore >= 63_000 ether) {
            return Level.Level6;
        } else if (stakingScore >= 32_000 ether) {
            return Level.Level5;
        } else if (stakingScore >= 16_000 ether) {
            return Level.Level4;
        } else if (stakingScore >= 8_000 ether) {
            return Level.Level3;
        } else if (stakingScore >= 4_000 ether) {
            return Level.Level2;
        } else if (stakingScore >= 2_000 ether) {
            return Level.Level1;
        } else {
            return Level.Level0;
        }
    }

    function _setLevelMultipliers() internal {
        levelMultipliers[Level.Level0] = 1000;
        levelMultipliers[Level.Level1] = 1025;
        levelMultipliers[Level.Level2] = 1050;
        levelMultipliers[Level.Level3] = 1087;
        levelMultipliers[Level.Level4] = 1163;
        levelMultipliers[Level.Level5] = 1313;
        levelMultipliers[Level.Level6] = 1625;
        levelMultipliers[Level.Level7] = 2000;
        levelMultipliers[Level.Level8] = 2500;
        levelMultipliers[Level.Level9] = 3000;
    }

    function _setAPRLimiters() internal {
        aprLimiters[Level.Level0] = 100;
        aprLimiters[Level.Level1] = 100;
        aprLimiters[Level.Level2] = 100;
        aprLimiters[Level.Level3] = 200;
        aprLimiters[Level.Level4] = 200;
        aprLimiters[Level.Level5] = 300;
        aprLimiters[Level.Level6] = 300;
        aprLimiters[Level.Level7] = 400;
        aprLimiters[Level.Level8] = 400;
        aprLimiters[Level.Level9] = 500;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function add(uint256 _allocPoint, IERC20Upgradeable _lpToken) internal {
        uint256 blockNumber = ArbSys(ARBSYS_ADDRESS).arbBlockNumber();
        uint256 lastRewardBlock = blockNumber > startBlock
            ? blockNumber
            : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accTokenPerShare: 0,
                totalStaked: 0
            })
        );
    }

    function set(uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint
            .sub(poolInfo[DEFAULT_POOL].allocPoint)
            .add(_allocPoint);
        poolInfo[DEFAULT_POOL].allocPoint = _allocPoint;
        emit Set(_allocPoint, _withUpdate);
    }

    function addUniswapVersion3(
        IERC721 _erc721Token,
        address _token0,
        address _token1,
        uint24 fee,
        bool _withUpdate
    ) public onlyOwner {
        require(address(_erc721Token) != address(0), "Zero Address");
        require(_token0 != address(0), "Zero Address");
        require(_token1 != address(0), "Zero Address");
        require(
            IUniswapV3Factory(_erc721Token.factory()).getPool(
                _token0,
                _token1,
                fee
            ) != address(0),
            "Pair not created"
        );

        erc721Token = _erc721Token;

        if (_withUpdate) {
            updatePool();
        }
        lpTokensStatus[_token0][_token1] = true;
        lpTokensStatus[_token1][_token0] = true;

        emit AddPool(_token0, _token1);
    }

    function whitelistDepositContract(
        address _contractAddress,
        bool _value
    ) external onlyOwner {
        isAllowedContract[_contractAddress] = _value;
        emit WhitelistDepositContract(_contractAddress, _value);
    }

    function setGovernanceAddress(
        address _governanceAddress
    ) external onlyOwner {
        governanceAddress = _governanceAddress;
        emit SetGovernanceAddress(_governanceAddress);
    }

    function setUtilityContractAddress(
        IUniswapV3PositionUtility _uniswapUtility
    ) external onlyOwner {
        uniswapUtility = _uniswapUtility;
        emit SetUtilityContractAddress(_uniswapUtility);
    }

    function getMultiplier(
        uint256 _from,
        uint256 _to
    ) public view returns (uint256) {
        if (_to <= bonusEndBlock) {
            return _to.sub(_from);
        } else if (_from >= bonusEndBlock) {
            return _to.sub(_from);
        } else {
            return bonusEndBlock.sub(_from).add(_to.sub(bonusEndBlock));
        }
    }

    function getUpdatedAccTokenPerShare() internal view returns (uint256) {
        PoolInfo storage pool = poolInfo[DEFAULT_POOL];
        uint256 accTokenPerShare = pool.accTokenPerShare;
        uint256 lpSupply = pool.totalStaked;
        uint256 PoolEndBlock = ArbSys(ARBSYS_ADDRESS).arbBlockNumber();
        if (PoolEndBlock > bonusEndBlock) {
            PoolEndBlock = bonusEndBlock;
        }
        if (PoolEndBlock > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(
                pool.lastRewardBlock,
                PoolEndBlock
            );
            uint256 tokenReward = multiplier
                .mul(tokenPerBlock)
                .mul(pool.allocPoint)
                .div(totalAllocPoint);
            accTokenPerShare = accTokenPerShare.add(
                tokenReward.mul(1e12).div(lpSupply)
            );
        }
        return accTokenPerShare;
    }

    function pendingReward(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[DEFAULT_POOL][_user];

        uint256 accTokenPerShare = getUpdatedAccTokenPerShare();

        uint256 multiplier = getStakingMultiplier(_user);
        uint256 pending = unClaimedReward[_user]
            .add(
                user.amount.mul(accTokenPerShare).div(1e12).sub(user.rewardDebt)
            )
            .mul(multiplier)
            .div(1000);

        return calculateCappedRewards(_user, pending);
    }

    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool();
        }
    }

    function updatePool() public {
        PoolInfo storage pool = poolInfo[DEFAULT_POOL];
        uint256 PoolEndBlock = ArbSys(ARBSYS_ADDRESS).arbBlockNumber();
        if (PoolEndBlock > bonusEndBlock) {
            PoolEndBlock = bonusEndBlock;
        }
        if (PoolEndBlock <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.totalStaked;
        if (lpSupply == 0) {
            pool.lastRewardBlock = PoolEndBlock;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, PoolEndBlock);
        uint256 tokenReward = multiplier
            .mul(tokenPerBlock)
            .mul(pool.allocPoint)
            .div(totalAllocPoint);
        pool.accTokenPerShare = pool.accTokenPerShare.add(
            tokenReward.mul(1e12).div(lpSupply)
        );
        pool.lastRewardBlock = PoolEndBlock;
    }

    function transferNFTandGetAmount(
        uint256 _tokenId
    ) internal returns (uint256) {
        uint256 _amount;
        address _token0;
        address _token1;

        (, , _token0, _token1, , , , , , , , ) = erc721Token.positions(
            _tokenId
        );

        require(lpTokensStatus[_token0][_token1], "LP token not added");
        require(lpTokensStatus[_token1][_token0], "LP token not added");
        _amount = uniswapUtility.getTokenAmount(_tokenId);
        erc721Token.safeTransferFrom(
            address(msg.sender),
            address(this),
            _tokenId
        );

        return _amount;
    }

    function deposit(
        uint256 _amount,
        uint256 _tokenId,
        bool _isERC721
    ) external {
        PoolInfo storage pool = poolInfo[DEFAULT_POOL];
        UserInfo storage user = userInfo[DEFAULT_POOL][msg.sender];

        if (_isERC721) {
            _amount = transferNFTandGetAmount(_tokenId);
        } else {
            pool.lpToken.safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
        }

        updatePool();
        if (user.amount > 0) {
            uint256 pending = user
                .amount
                .mul(pool.accTokenPerShare)
                .div(1e12)
                .sub(user.rewardDebt);
            if (pending > 0) {
                unClaimedReward[msg.sender] = unClaimedReward[msg.sender].add(
                    pending
                );
            }
        }
        if (_amount > 0) {
            user.amount = user.amount.add(_amount);
            userStakeInfo[msg.sender].push(
                StakeInfo({
                    amount: _amount,
                    timestamp: block.timestamp,
                    withdrawTime: 0,
                    tokenId: _tokenId,
                    isERC721: _isERC721
                })
            );
        }
        user.rewardDebt = user.amount.mul(pool.accTokenPerShare).div(1e12);
        pool.totalStaked = pool.totalStaked.add(_amount);
        addHighestStakedUser(user.amount, msg.sender);
        emit Deposit(msg.sender, DEFAULT_POOL, _amount);
    }

    function calculateStakingScore(
        address _user
    ) public view returns (uint256) {
        StakeInfo[] storage stakes = userStakeInfo[_user];
        uint256 totalStakingScore = 0;
        uint256 currentTime = block.timestamp;

        for (uint256 i = 0; i < stakes.length; i++) {
            uint256 duration = currentTime.sub(stakes[i].timestamp);
            if (duration > SECONDS_IN_MONTH) {
                // Calculate the effective duration in months
                uint256 effectiveDuration = duration.div(SECONDS_IN_MONTH);

                // Cap the effective duration at 12 months
                if (effectiveDuration > 12) {
                    effectiveDuration = 12;
                }

                // Calculate the staking score for this stake
                uint256 stakeScore = stakes[i]
                    .amount
                    .mul(effectiveDuration)
                    .div(12);
                totalStakingScore = totalStakingScore.add(stakeScore);
            }
        }

        return totalStakingScore;
    }

    function withdraw(bool _withStake) external {
        UserInfo storage user = userInfo[DEFAULT_POOL][msg.sender];
        if (user.cooldown == false) {
            user.cooldown = true;
            user.cooldowntimestamp = block.timestamp;
            return;
        } else {
            require(
                block.timestamp >= user.cooldowntimestamp.add(SECONDS_IN_WEEK),
                "withdraw: cooldown period"
            );
            user.cooldown = false;
            user.cooldowntimestamp = 0;
            _withdraw(_withStake);
        }
    }

    function _withdraw(bool _withStake) internal {
        PoolInfo storage pool = poolInfo[DEFAULT_POOL];
        UserInfo storage user = userInfo[DEFAULT_POOL][msg.sender];
        uint256 _amount = user.amount;
        require(user.amount >= _amount, "withdraw: not good");
        if (_withStake) {
            restakeReward();
        } else {
            claimReward();
        }
        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accTokenPerShare).div(1e12);
        pool.totalStaked = pool.totalStaked.sub(_amount);
        pool.lpToken.safeTransfer(msg.sender, _amount);
        removeHighestStakedUser( user.amount, msg.sender);
        emit Withdraw(msg.sender, DEFAULT_POOL, _amount);
    }

    function restakeReward() public {
        updatePool();
        PoolInfo storage pool = poolInfo[DEFAULT_POOL];
        UserInfo storage user = userInfo[DEFAULT_POOL][msg.sender];
        uint256 multiplier = getStakingMultiplier(msg.sender);
        uint256 pending = unClaimedReward[msg.sender]
            .add(
                user.amount.mul(pool.accTokenPerShare).div(1e12).sub(
                    user.rewardDebt
                )
            )
            .mul(multiplier)
            .div(1000);
        uint256 cappedPending = calculateCappedRewards(msg.sender, pending);
        if (cappedPending > 0) {
            user.amount = user.amount.add(cappedPending);
            unClaimedReward[msg.sender] = 0;
            user.rewardDebt = user.amount.mul(pool.accTokenPerShare).div(1e12);
            pool.totalStaked = pool.totalStaked.add(cappedPending);
            emit RestakedReward(msg.sender, cappedPending);
        }
    }

    function claimReward() public {
        updatePool();
        PoolInfo storage pool = poolInfo[DEFAULT_POOL];
        UserInfo storage user = userInfo[DEFAULT_POOL][msg.sender];
        uint256 multiplier = getStakingMultiplier(msg.sender);
        uint256 pending = unClaimedReward[msg.sender]
            .add(
                user.amount.mul(pool.accTokenPerShare).div(1e12).sub(
                    user.rewardDebt
                )
            )
            .mul(multiplier)
            .div(1000);
        if (pending > 0) {
            safeTokenTransfer(msg.sender, pending);
            unClaimedReward[msg.sender] = 0;
            emit ClaimedReward(msg.sender, pending);
        }
        user.rewardDebt = user.amount.mul(pool.accTokenPerShare).div(1e12);
    }

    function addHighestStakedUser(uint256 _amount, address user) private {
        HighestStaker[] storage highestStaker = highestStakerInPool[
            DEFAULT_POOL
        ];
        bool userExists = false;
        for (uint256 i = 0; i < highestStaker.length; i++) {
            if (highestStaker[i].addr == user) {
                highestStaker[i].deposited = _amount;
                userExists = true;
                break;
            }
        }
        if (!userExists) {
            if (highestStaker.length < 100) {
                highestStaker.push(HighestStaker(_amount, user));
            } else if (highestStaker[0].deposited < _amount) {
                highestStaker[0] = HighestStaker(_amount, user);
            }
        }
        quickSort(0, highestStaker.length - 1);
    }

    function checkHighestStaker(address user) external view returns (bool) {
        HighestStaker[] storage higheststaker = highestStakerInPool[
            DEFAULT_POOL
        ];
        uint256 i = 0;
        // Applied the loop to check the user in the highest staker list.
        for (i; i < higheststaker.length; i++) {
            if (higheststaker[i].addr == user) {
                // If user is exists in the list then we return true otherwise false.
                return true;
            }
        }
        return false;
    }

    function getStakerList() public view returns (HighestStaker[] memory) {
        return highestStakerInPool[DEFAULT_POOL];
    }

    function quickSort(uint256 left, uint256 right) internal {
        HighestStaker[] storage arr = highestStakerInPool[DEFAULT_POOL];
        if (left >= right) return;
        uint256 divtwo = 2;
        uint256 p = arr[(left + right) / divtwo].deposited; // p = the pivot element
        uint256 i = left;
        uint256 j = right;
        while (i < j) {
            while (arr[i].deposited < p) ++i;
            while (arr[j].deposited > p) --j;
            if (arr[i].deposited > arr[j].deposited) {
                (arr[i].deposited, arr[j].deposited) = (
                    arr[j].deposited,
                    arr[i].deposited
                );
                (arr[i].addr, arr[j].addr) = (arr[j].addr, arr[i].addr);
            } else ++i;
        }
        if (j > left) quickSort(left, j - 1);
        quickSort(j + 1, right);
    }

    function removeHighestStakedUser(uint256 _amount, address user) private {
        HighestStaker[] storage highestStaker = highestStakerInPool[
            DEFAULT_POOL
        ];
        for (uint256 i = 0; i < highestStaker.length; i++) {
            if (highestStaker[i].addr == user) {
                delete highestStaker[i];
                if (_amount > 0) {
                    addHighestStakedUser(_amount, user);
                }
                return;
            }
        }
        quickSort(0, highestStaker.length - 1);
    }

    function emergencyWithdraw(uint256 _amount) public onlyOwner {
        PoolInfo storage pool = poolInfo[DEFAULT_POOL];
        pool.lpToken.safeTransfer(address(msg.sender), _amount);
        emit EmergencyWithdraw(msg.sender, DEFAULT_POOL, _amount);
    }

    function emergencyNFTWithdraw(uint256[] memory _tokenIds) public onlyOwner {
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            erc721Token.safeTransferFrom(
                address(this),
                address(msg.sender),
                _tokenIds[i]
            );
            emit EmergencyNFTWithdraw(msg.sender, DEFAULT_POOL, _tokenIds[i]);
        }
    }

    function safeTokenTransfer(address _to, uint256 _amount) internal {
        uint256 tokenBal = token.balanceOf(address(this));
        if (_amount > tokenBal) {
            token.transfer(_to, tokenBal);
        } else {
            token.transfer(_to, _amount);
        }
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external override returns (bytes4) {
        return IERC721ReceiverUpgradeable.onERC721Received.selector;
    }

    function whitelistDistributionAddress(
        address _distributorAddress,
        bool _value
    ) external onlyOwner {
        require(_distributorAddress != address(0), "zero address");
        eligibleDistributionAddress[_distributorAddress] = _value;
    }

    function decreaseRewardRate(uint256 _amount) external {
        require(eligibleDistributionAddress[msg.sender], "Not eligible");
        updatePool();
        uint256 _startBlock = poolInfo[0].lastRewardBlock >= bonusEndBlock
            ? bonusEndBlock
            : poolInfo[0].lastRewardBlock;
        uint256 _totalBlocksLeft = bonusEndBlock.sub(_startBlock);
        require(_totalBlocksLeft > 0, "Distribution Closed");

        uint256 _totalRewardsLeft = maxPerBlockReward.mul(_totalBlocksLeft);
        require(_totalRewardsLeft > _amount, "Not enough rewards");

        uint256 _decreasedPerBlockReward = _totalRewardsLeft
            .sub(_amount)
            .mul(1e12)
            .div(_totalBlocksLeft)
            .div(1e12);
        maxPerBlockReward = _decreasedPerBlockReward;
        tokenPerBlock = _decreasedPerBlockReward.mul(1e12).div(
            poolInfo[0].accTokenPerShare
        );
        safeTokenTransfer(msg.sender, _amount);
        emit ReduceReward(_amount, maxPerBlockReward);
    }

    function distributeAdditionalReward(uint256 _rewardAmount) external {
        require(eligibleDistributionAddress[msg.sender], "Not eligible");
        token.safeTransferFrom(
            address(msg.sender),
            address(this),
            _rewardAmount
        );
        updatePool();
        uint256 _startBlock = poolInfo[0].lastRewardBlock >= bonusEndBlock
            ? bonusEndBlock
            : poolInfo[0].lastRewardBlock;
        uint256 blockLeft = bonusEndBlock.sub(_startBlock);
        require(blockLeft > 0, "Distribution Closed");

        if (!isFirstDepositInitialized) {
            totalRewards = totalRewards.add(_rewardAmount);
            maxPerBlockReward = totalRewards.div(blockLeft);
        } else {
            maxPerBlockReward = _rewardAmount
                .add(maxPerBlockReward.mul(blockLeft))
                .mul(1e12)
                .div(blockLeft)
                .div(1e12);
        }
        tokenPerBlock = blockLeft
            .mul(maxPerBlockReward)
            .mul(1e12)
            .div(blockLeft)
            .div(poolInfo[0].accTokenPerShare);
        emit DistributeReward(_rewardAmount);
    }

    function getLevelForUser(address _user) public view returns (Level) {
        return getLevelFromStakingScore(calculateStakingScore(_user));
    }

    function getStakingMultiplier(
        address _user
    ) public view returns (uint256) {
        uint256 stakingScore = calculateStakingScore(_user);
        return levelMultipliers[getLevelFromStakingScore(stakingScore)];
    }

    function calculateCappedRewards(
        address _user,
        uint256 pending
    ) public view returns (uint256) {
        UserInfo storage user = userInfo[DEFAULT_POOL][_user];
        Level userLevel = getLevelForUser(_user);
        uint256 aprLimiter = aprLimiters[userLevel];
        uint256 cappedRewards = user.amount.mul(aprLimiter).div(100);
        return pending > cappedRewards ? cappedRewards : pending;
    }
}