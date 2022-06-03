// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
// rinkeby 0x997d16a9e1b7e2bF81CD613eb9d3261Ed87df079
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
contract StakingRewards is Ownable, ReentrancyGuard{
    

    IERC20 public AQLToken;

    // address of treasury
    address payable public treasury;
    // address of rewards pool
    address payable public rewardsPool;

    //constructor variables 
    string public name;
    string public symbol;

    // Total supply of AQL locked
    uint256 public supply;


    struct Stake {
            uint256 amount;
            uint256 start;
            uint256 end;
            bool isFixed;
        }
    
    mapping(address => Stake) public stakes;
    mapping(address => uint256) public AQLPower;

    // time constants
    uint256 public constant WEEK = 7 days;
    uint256 public constant MIN_LOCK = (4 * WEEK);
    uint256 public constant MAX_LOCK = (104 * WEEK) - 1;

    uint256 public constant MIN_WEEKS = 5;
    uint256 public constant MAX_WEEKS = 105;

    constructor (address _token, address _treasury, address _rewardsPool){
        AQLToken = IERC20(_token);
        treasury = payable(_treasury);
        rewardsPool = payable(_rewardsPool);
        name = 'Aqualis Token';
        symbol = 'AQL';
    }

    //stakeTokens

    function deposit(uint256 _amount, uint256 _weeks, bool _isFixed) external nonReentrant{
        require(_weeks <= MAX_WEEKS, "can lock for 105 weeks max");
        require(_weeks >= MIN_WEEKS, "can lock for 5 weeks min");        
        require(_amount > 0, "amount must be greater than 0");
        uint256 lockTime = _weeks * WEEK;
        Stake memory _stake = stakes[msg.sender];

        require(_stake.amount == 0, "stake already exists");
        _deposit(msg.sender, _amount, lockTime, _isFixed, _stake);

        //calculate reward
        calculateReward(msg.sender);
    }

    function _deposit(address _for, uint256 _amount, uint256 _lockTime, bool _isFixed, Stake memory _prevStake) private nonReentrant{
        uint256 _supplyBefore = supply;
        supply = _supplyBefore + _amount;
        //store previous stake
        uint256 _start = block.timestamp;
        if (_prevStake.start != 0){
            _start = _prevStake.start;
        }
        Stake memory _newStake = Stake({ amount: _prevStake.amount, start: _start, end: _prevStake.end,isFixed: _prevStake.isFixed });
        _newStake.amount = _newStake.amount + _amount;
        _newStake.isFixed = _isFixed;
        // for adding option to increase stake amount later
        if (_lockTime != 0) {
            _newStake.end = block.timestamp + _lockTime;
        }
        stakes[_for] = _newStake;

        if (_amount != 0) {
            AQLToken.transferFrom(msg.sender, address(this), _amount);
        }
    }




    //unstakeTokens

    function withdraw() external nonReentrant {
        Stake memory _stake = stakes[msg.sender];

        require(block.timestamp >= _stake.end, "stake not expired");
        require(_stake.isFixed == false, "stake is in fixed mode");
        uint256 _amount = _stake.amount;

        _unlock(_stake, _amount);
        AQLToken.transfer(msg.sender, _amount);
        calculateReward(msg.sender);

    }

    function _unlock(Stake memory _stake, uint256 _withdrawAmount) private {

        uint256 _stakedAmount = _stake.amount;
        require(_withdrawAmount <= _stakedAmount, "not enough");

        //_stake.end should remain the same if we do partial withdraw
        _stake.end = _stakedAmount == _withdrawAmount ? 0 : _stake.end;
        _stake.amount = _stakedAmount - _withdrawAmount;
        stakes[msg.sender] = _stake;

        uint256 _supplyBefore = supply;
        supply = _supplyBefore - _withdrawAmount;

    }

    

    //earlyUnstake
    function earlyWithdraw(uint256 _amount) external nonReentrant {
        Stake memory _stake= stakes[msg.sender];

        require(_amount> 0, "bad amount");
        require(block.timestamp < _stake.end, "lock expires earlier!");
        

        // prevent mutated memory in _unlock() function as it will be used in fee calculation afterward
        uint256 _prevLockEnd = _stake.end;
        _unlock(_stake, _amount);

        // ceil the week by adding 1 week first
        uint256 remainingWeeks = (_prevLockEnd + WEEK - block.timestamp) / WEEK;

        // caculate penalty
        uint256 _penaltyPercentage = remainingWeeks*3/10;
        uint256 _penalty =  _amount-(_amount/100*_penaltyPercentage);

        // split penalty into three parts
        uint256 _feeToBurn = _penalty/2;
        uint256 _reward = _penalty/100*40;
        uint256 _treasuryFee = _penalty/10;

        calculateReward(msg.sender);
        // transfer one part of the penalty to treasury
        AQLToken.transfer(treasury, _treasuryFee);
        // transfer one part of the penalty to rewards pool
        AQLToken.transfer(rewardsPool, _reward);
        // transfer remaining back to owner
        AQLToken.transfer(msg.sender, _amount - _penalty);
        //burn
        AQLToken.transfer(address(0), _feeToBurn);

    }
    //switchStakingMode(fixed vs variable)
    function switchStakingMode(bool _isFixed) external nonReentrant{
        require(stakes[msg.sender].amount != 0, 'stake doesnt exist');
        require(stakes[msg.sender].end> block.timestamp, 'stake expired');
        require(stakes[msg.sender].isFixed != _isFixed, 'mode already the same');
        
        if (stakes[msg.sender].isFixed == false){
            stakes[msg.sender].isFixed = true;
        } else {
             uint256 _lockTime = (stakes[msg.sender].end - stakes[msg.sender].start);
             stakes[msg.sender].start = block.timestamp;
             stakes[msg.sender].end = block.timestamp + _lockTime;
             stakes[msg.sender].isFixed = false;
        }
        calculateReward(msg.sender);


    }

    //calculate rewards
    function calculateAQP( uint256 _amount, uint256 _weeks)public pure returns(uint256){
        uint256 _bonus = 102**(_weeks);
        uint256 _aqp = _amount*_bonus/(100**_weeks);
        return _aqp;
    }

    function calculateReward(address _user) public nonReentrant returns(uint256) {
        require(stakes[_user].amount != 0, 'stake doesnt exist');
        require(stakes[_user].end > block.timestamp, 'stake expired');
        uint256 reward;
        uint256 _amount = stakes[_user].amount;
        if (stakes[_user].isFixed == false){
            uint256 _weeksRemaining = (stakes[_user].end - block.timestamp);
            reward = calculateAQP(_amount, _weeksRemaining);
        } else{
            uint256 _weeksTotal = (stakes[_user].end - stakes[_user].start);
            reward = calculateAQP(_amount, _weeksTotal);
        }
        AQLPower[_user] = reward;
        return reward;
    }

    //access AQP 
    function getAQP(address _address) public returns(uint256){
        calculateReward(msg.sender);
        return AQLPower[_address];
    }




}

