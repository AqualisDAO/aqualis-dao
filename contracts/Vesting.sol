// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
contract Vesting is Ownable, ReentrancyGuard{

    IERC20 public AQLToken;

    uint256 public supply;

    struct Holder {
            uint256 amount;
            uint256 start;
            uint256 balance;
        }
    
    struct VestingSchedule {
        uint256 start;
        uint256 cliff;
        uint256 vestingTime;
        uint256 percentage;
        uint256 released;
        uint256 total;
        uint256 slice;
        
    }

    mapping (uint256 => VestingSchedule) vestingSchedules;
    mapping (address => uint256) beneficiaries;
    


    constructor (address _token, uint256 _supply){
        AQLToken = IERC20(_token);
        supply = _supply;
    }

    function createVestingSchedule(uint256 _cliff, uint256 _vestingTime, uint256 _percentage, uint256 _id, uint256 _amount, uint256 _slice) external onlyOwner {
        require(_vestingTime > 0, "TokenVesting: duration must be > 0");
        require(_percentage > 0, "TokenVesting: amount must be > 0");
        VestingSchedule memory newSchedule = VestingSchedule({start: block.timestamp, cliff: _cliff, vestingTime: _vestingTime, percentage:_percentage, released: 0, total: _amount, slice: _slice});
        vestingSchedules[_id] = newSchedule;
    }

    function computeReleasableAmount(uint256 vestingScheduleId)
        public
        view
        returns(uint256){
        VestingSchedule storage vestingSchedule = vestingSchedules[vestingScheduleId];
        return _computeReleasableAmount(vestingSchedule);
    }

    function _computeReleasableAmount(VestingSchedule memory vestingSchedule)
    internal
    view
    returns(uint256){
        uint256 currentTime =block.timestamp;
        if (currentTime < vestingSchedule.cliff) {
            return 0;
        } else if (currentTime >= vestingSchedule.start + vestingSchedule.vestingTime) {
            return vestingSchedule.total - vestingSchedule.released;
        } else {
            uint256 timeFromStart = block.timestamp - vestingSchedule.start;
            uint secondsPerSlice = vestingSchedule.slice;
            uint256 vestedSlicePeriods = timeFromStart - secondsPerSlice;
            uint256 vestedSeconds = vestedSlicePeriods*secondsPerSlice;
            uint256 vestedAmount = vestingSchedule.total* vestedSeconds/vestingSchedule.vestingTime;
            vestedAmount = vestedAmount-vestingSchedule.released;
            return vestedAmount;
        }
    }

    function release(
        uint256 vestingScheduleId,
        uint256 amount
    )
        public
        nonReentrant{
        VestingSchedule storage vestingSchedule = vestingSchedules[vestingScheduleId];
        bool isBeneficiary = beneficiaries[msg.sender] != 0;
        bool isOwner = msg.sender == owner();
        require(
            isBeneficiary || isOwner,
            "TokenVesting: only beneficiary and owner can release vested tokens"
        );
        uint256 vestedAmount = _computeReleasableAmount(vestingSchedule);
        require(vestedAmount >= amount, "TokenVesting: cannot release tokens, not enough vested tokens");
        vestingSchedule.released = vestingSchedule.released+amount;
        address payable beneficiaryPayable = payable(msg.sender);
        supply = supply-amount;
        AQLToken.transfer(beneficiaryPayable, amount);
    }

    /**
     * @dev The contract should be able to receive Eth.
     */
    receive() external payable virtual {}




    





}