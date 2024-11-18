// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

/**
 * @title TMAIVesting
 */
contract TMAIVesting is
    Initializable,
    Ownable2StepUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    struct VestingSchedule {
        bool initialized;
        // beneficiary of tokens after they are released
        address beneficiary;
        // cliff period in seconds
        uint256 cliff;
        // start time of the vesting period
        uint256 start;
        // duration of the vesting period in seconds
        uint256 duration;
        // duration of a slice period for the vesting in seconds
        uint256 slicePeriodSeconds;
        // whether or not the vesting is revocable
        bool revocable;
        // total amount of tokens to be released at the end of the vesting
        uint256 amountTotal;
        // amount of tokens to be released at the start of the vesting
        uint256 initialUnlock;
        // amount of tokens released
        uint256 released;
        // whether or not the vesting has been revoked
        bool revoked;
    }

    // address of the ERC20 token
    IERC20Upgradeable private _token;

    bytes32[] private _vestingSchedulesIds;
    mapping(bytes32 => uint256) private _userVestingScheduleId;
    mapping(bytes32 => VestingSchedule) private _vestingSchedules;
    uint256 private _vestingSchedulesTotalAmount;
    mapping(address => uint256) private _holdersVestingCount;

    event Released(address indexed user, uint256 indexed amount);
    event Revoked(address indexed user, bytes32 indexed vestingId);

    /**
     * @dev Reverts if the vesting schedule does not exist or has been revoked.
     */
    modifier onlyIfVestingScheduleNotRevoked(bytes32 vestingScheduleId) {
        require(_vestingSchedules[vestingScheduleId].initialized);
        require(!_vestingSchedules[vestingScheduleId].revoked);
        _;
    }

    /**
     * @dev Creates a vesting contract.
     * @param token_ address of the ERC20 token contract
     */
    function initialize(
        address token_
    ) external initializer {
        require(token_ != address(0x0));
        __Ownable2Step_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        _token = IERC20Upgradeable(token_);
    }

    /**
     * @dev Returns the number of vesting schedules associated to a beneficiary.
     * @return the number of vesting schedules
     */
    function getVestingSchedulesCountByBeneficiary(
        address _beneficiary
    ) external view returns (uint256) {
        return _holdersVestingCount[_beneficiary];
    }

    /**
     * @dev Returns the vesting schedule id at the given index.
     * @return the vesting id
     */
    function getVestingIdAtIndex(
        uint256 index
    ) external view returns (bytes32) {
        require(
            index < getVestingSchedulesCount(),
            "TMAIVesting: index out of bounds"
        );
        return _vestingSchedulesIds[index];
    }

    /**
     * @notice Returns the vesting schedule information for a given holder and index.
     * @return the vesting schedule structure information
     */
    function getVestingScheduleByAddressAndIndex(
        address holder,
        uint256 index
    ) external view returns (VestingSchedule memory) {
        return
            getVestingSchedule(
                computeVestingScheduleIdForAddressAndIndex(holder, index)
            );
    }

    /**
     * @notice Returns the total amount of vesting schedules.
     * @return the total amount of vesting schedules
     */
    function getVestingSchedulesTotalAmount() external view returns (uint256) {
        return _vestingSchedulesTotalAmount;
    }

    /**
     * @dev Returns the address of the ERC20 token managed by the vesting contract.
     */
    function getToken() external view returns (address) {
        return address(_token);
    }


    /**
     * @dev Send tokens to multiple accounts efficiently
     */
    function multisendToken(
        address[] memory recipients,
        uint256[] memory values
    ) external {
        require(
            recipients.length == values.length,
            "Arrays must be the same length"
        );
        uint256 total = 0;
        for (uint256 i = 0; i < recipients.length; i++) {
            total = total + values[i];
        }
        _token.safeTransferFrom(msg.sender, address(this), total);
        for (uint256 i = 0; i < recipients.length; i++) {
            _token.safeTransfer(recipients[i], values[i]);
        }
    }

    /**
     * @notice Creates a new vesting schedule with multiple address.
     * @param _to Arrays of address of the beneficiary to whom vested tokens are transferred
     * @param _start start time of the vesting period
     * @param _cliff duration in seconds of the cliff in which tokens will begin to vest
     * @param _duration duration in seconds of the period in which the tokens will vest
     * @param _slicePeriodSeconds duration of a slice period for the vesting in seconds
     * @param _revocable whether the vesting is revocable or not
     * @param _amount Array of total amount of tokens to be released at the end of the vesting
     * @param _initialUnlock Array of amount of tokens to be released at the start of the vesting
     */
    function addUserDetails(
        address[] memory _to,
        uint256[] memory _amount,
        uint256[] memory _initialUnlock,
        uint256 _start,
        uint256 _cliff,
        uint256 _duration,
        uint256 _slicePeriodSeconds,
        bool _revocable
    ) external onlyOwner returns (bool) {
        require(
            _to.length == _amount.length && _to.length == _initialUnlock.length,
            "Invalid data"
        );
        for (uint256 i = 0; i < _to.length; i++) {
            require(_to[i] != address(0), "Invalid address");
            createVestingSchedule(
                _to[i],
                _start,
                _cliff,
                _duration,
                _slicePeriodSeconds,
                _revocable,
                _amount[i],
                _initialUnlock[i],
                0
            );
        }
        return true;
    }


    /**
     * @notice Creates a new vesting schedule for a beneficiary.
     * @param _beneficiary address of the beneficiary to whom vested tokens are transferred
     * @param _start start time of the vesting period
     * @param _cliff duration in seconds of the cliff in which tokens will begin to vest
     * @param _duration duration in seconds of the period in which the tokens will vest
     * @param _slicePeriodSeconds duration of a slice period for the vesting in seconds
     * @param _revocable whether the vesting is revocable or not
     * @param _amount total amount of tokens to be released at the end of the vesting
     * @param _initialUnlock amount of tokens to be released at the start of the vesting
     */
    function createVestingSchedule(
        address _beneficiary,
        uint256 _start,
        uint256 _cliff,
        uint256 _duration,
        uint256 _slicePeriodSeconds,
        bool _revocable,
        uint256 _amount,
        uint256 _initialUnlock,
        uint256 _released
    ) public nonReentrant onlyOwner {
        require(
            this.getWithdrawableAmount() >= _amount - _released,
            "TMAIVesting: cannot create vesting schedule because not sufficient tokens"
        );
        require(
            _beneficiary != address(0),
            "TMAIVesting: beneficiary is the zero address"
        );
        require(_duration > 0, "TMAIVesting: duration must be > 0");
        require(_amount > 0, "TMAIVesting: amount must be > 0");
        require(
            _slicePeriodSeconds >= 1,
            "TMAIVesting: slicePeriodSeconds must be >= 1"
        );

        // Calculate the initial release amount
        uint256 _initialRelease = _amount * _initialUnlock / 100;

        // Ensure that the initial release and already released tokens do not exceed the total amount
        require(
            _initialRelease + _released <= _amount,
            "TMAIVesting: initial release and released tokens exceed total amount"
        );

        bytes32 vestingScheduleId = this.computeNextVestingScheduleIdForHolder(
            _beneficiary
        );

        require(
            !_vestingSchedules[vestingScheduleId].initialized,
            "TMAIVesting: vesting schedule already exists"
        );

        uint256 cliff = _start + _cliff;

        _vestingSchedules[vestingScheduleId] = VestingSchedule(
            true,
            _beneficiary,
            cliff,
            _start,
            _duration,
            _slicePeriodSeconds,
            _revocable,
            _amount,
            _initialUnlock,
            _released + _initialRelease,
            false
        );

        // Update the total amount of tokens allocated for vesting
        _vestingSchedulesTotalAmount = _vestingSchedulesTotalAmount + _amount;

        _userVestingScheduleId[vestingScheduleId] = _vestingSchedulesIds.length;
        _vestingSchedulesIds.push(vestingScheduleId);
        uint256 currentVestingCount = _holdersVestingCount[_beneficiary];
        _holdersVestingCount[_beneficiary] = currentVestingCount + 1;

        if (_initialRelease > 0) {
            _token.safeTransfer(_beneficiary, _initialRelease);
        }
    }

    /**
     * @notice Revokes the vesting schedule for given identifier.
     * @param vestingScheduleId the vesting schedule identifier
     */
    function revoke(
        bytes32 vestingScheduleId
    )
        external
        onlyOwner
        nonReentrant
        onlyIfVestingScheduleNotRevoked(vestingScheduleId)
    {
        VestingSchedule storage vestingSchedule = _vestingSchedules[
            vestingScheduleId
        ];
        require(
            vestingSchedule.revocable,
            "TMAIVesting: vesting is not revocable"
        );
        uint256 vestedAmount = _computeReleasableAmount(vestingSchedule);
        if (vestedAmount > 0) {
            _release(vestingScheduleId, vestedAmount);
        }
        uint256 unreleased = vestingSchedule.amountTotal - 
            vestingSchedule.released;
        _vestingSchedulesTotalAmount = _vestingSchedulesTotalAmount - 
            unreleased;
        vestingSchedule.revoked = true;

        bytes32 element = _vestingSchedulesIds[
            _vestingSchedulesIds.length - 1
        ];
        uint256 tempVestingId = _userVestingScheduleId[vestingScheduleId];
        _vestingSchedulesIds[tempVestingId] = element;
        _userVestingScheduleId[element] = tempVestingId;
        _vestingSchedulesIds.pop();

        emit Revoked(vestingSchedule.beneficiary, vestingScheduleId);
    }

    /**
     * @notice Withdraw the specified amount if possible.
     * @param amount the amount to withdraw
     */
    function withdraw(uint256 amount) external nonReentrant onlyOwner {
        require(
            this.getWithdrawableAmount() >= amount,
            "TMAIVesting: not enough withdrawable funds"
        );
        _token.safeTransfer(owner(), amount);
    }

    /**
     * @notice Release vested amount of tokens.
     * @param vestingScheduleId the vesting schedule identifier
     * @param amount the amount to release
     */
    function release(
        bytes32 vestingScheduleId,
        uint256 amount
    ) public nonReentrant onlyIfVestingScheduleNotRevoked(vestingScheduleId) {
        _release(vestingScheduleId, amount);
    }

    function _release(bytes32 vestingScheduleId, uint256 amount) internal {
        VestingSchedule storage vestingSchedule = _vestingSchedules[
            vestingScheduleId
        ];
        uint256 vestedAmount = _computeReleasableAmount(vestingSchedule);
        require(
            vestedAmount >= amount,
            "TMAIVesting: cannot release tokens, not enough vested tokens"
        );
        vestingSchedule.released = vestingSchedule.released + amount;
        _vestingSchedulesTotalAmount = _vestingSchedulesTotalAmount - amount;
        _token.safeTransfer(vestingSchedule.beneficiary, amount);
        emit Released(vestingSchedule.beneficiary, amount);
    }

    /**
     * @dev Returns the number of vesting schedules managed by this contract.
     * @return the number of vesting schedules
     */
    function getVestingSchedulesCount() public view returns (uint256) {
        return _vestingSchedulesIds.length;
    }

    /**
     * @notice Computes the vested amount of tokens for the given vesting schedule identifier.
     * @return the vested amount
     */
    function computeReleasableAmount(
        bytes32 vestingScheduleId
    )
        public
        view
        onlyIfVestingScheduleNotRevoked(vestingScheduleId)
        returns (uint256)
    {
        VestingSchedule memory vestingSchedule = _vestingSchedules[
            vestingScheduleId
        ];
        return _computeReleasableAmount(vestingSchedule);
    }

    /**
     * @notice Returns the vesting schedule information for a given identifier.
     * @return the vesting schedule structure information
     */
    function getVestingSchedule(
        bytes32 vestingScheduleId
    ) public view returns (VestingSchedule memory) {
        return _vestingSchedules[vestingScheduleId];
    }

    /**
     * @dev Returns the amount of tokens that can be withdrawn by the owner.
     * @return the amount of tokens
     */
    function getWithdrawableAmount() external view returns (uint256) {
        return _token.balanceOf(address(this)) - _vestingSchedulesTotalAmount;
    }

    /**
     * @dev Computes the next vesting schedule identifier for a given holder address.
     */
    function computeNextVestingScheduleIdForHolder(
        address holder
    ) external view returns (bytes32) {
        return
            computeVestingScheduleIdForAddressAndIndex(
                holder,
                _holdersVestingCount[holder]
            );
    }

    /**
     * @dev Returns the last vesting schedule for a given holder address.
     */
    function getLastVestingScheduleForHolder(
        address holder
    ) external view returns (VestingSchedule memory) {
        return
            _vestingSchedules[
                computeVestingScheduleIdForAddressAndIndex(
                    holder,
                    _holdersVestingCount[holder] - 1
                )
            ];
    }

    /**
     * @dev Computes the vesting schedule identifier for an address and an index.
     */
    function computeVestingScheduleIdForAddressAndIndex(
        address holder,
        uint256 index
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(holder, index));
    }

    /**
     * @dev Computes the releasable amount of tokens for a vesting schedule.
     * @return the amount of releasable tokens
     */
    function _computeReleasableAmount(
        VestingSchedule memory vestingSchedule
    ) internal view returns (uint256) {
        uint256 currentTime = block.timestamp;
        if ((currentTime < vestingSchedule.cliff) || vestingSchedule.revoked) {
            return 0;
        } else if (
            currentTime >= vestingSchedule.start + vestingSchedule.duration
        ) {
            return vestingSchedule.amountTotal - vestingSchedule.released;
        } else {
            uint256 timeFromStart = currentTime - vestingSchedule.start;
            uint256 secondsPerSlice = vestingSchedule.slicePeriodSeconds;
            uint256 vestedSlicePeriods = timeFromStart / secondsPerSlice;
            uint256 vestedSeconds = vestedSlicePeriods * secondsPerSlice;
            uint256 vestedAmount = vestingSchedule
                .amountTotal
                *vestedSeconds
                /vestingSchedule.duration;
            vestedAmount = vestedAmount - vestingSchedule.released;
            return vestedAmount;
        }
    }

    function viewUserVestingDetailsIndex(
        bytes32 _vestingScheduleId
    ) public view returns (uint256) {
        return _userVestingScheduleId[_vestingScheduleId];
    }

    function resetRevokeIDs(
        bytes32[] memory _vestingIds,
        uint256[] memory _vestingIndex
    ) external onlyOwner {
        for (uint256 i = 0; i < _vestingIds.length; i++) {
            _userVestingScheduleId[_vestingIds[i]] = _vestingIndex[i];
        }
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
