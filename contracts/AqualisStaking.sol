// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/Address.sol";



contract AqualisStaking is Ownable, ReentrancyGuard{
        string public name;
        string public symbol;
        address treasury;
        address rewardsPool;

        //Aqualis token address
        uint256 public constant WEEK = 7 days;
        uint256 public constant MIN_LOCK = (4 * WEEK);
        uint256 public constant MAX_LOCK = (104 * WEEK) - 1;

        //address for AQL token
        address public token;
        // Total supply of AQ locked
        uint256 public supply;

        struct Stake {
            uint256 amount;
            uint256 end;
            bool isFixed;
        }
        

        mapping(address => Stake) public stakes;
        mapping(address => uint256) public AQLPower;



        constructor ( address _token, address _treasury, address _rewardsPool){
            token = _token;
            treasury = _treasury;
            rewardsPool = _rewardsPool;
            name = 'Aqualis Token';
            symbol = 'AQL';
        }

    function _depositFor(
        address _for,
        uint256 _amount,
        uint256 _unlockTime,
        bool _isFixed,
        Stake memory _prevLocked
        ) internal {

        if (_amount != 0) {
            token.safeTransferFrom(msg.sender, address(this), _amount);
        }

        // Update supply
        uint256 _supplyBefore = supply;
        supply = _supplyBefore + _amount;

        // Store _prevLocked
        Stake memory _newLocked = Stake({ amount: _prevLocked.amount, end: _prevLocked.end, isFixed: _prevLocked.isFixed });

        // Adding new lock to existing lock, or if lock is expired
        // - creating a new one
        _newLocked.amount = _newLocked.amount + _amount;

        if (_unlockTime != 0) {
        _newLocked.end = _unlockTime;
        }
        _newLocked.isFixed = _isFixed;
        stakes[_for] = _newLocked;

        
   
    }
    //(1+0.02)^(number of weeks)
    function calculateAQP( uint256 _amount, uint256 _weeks)public pure{
        uint256 _bonus = 102**(_weeks);
        uint256 _aqp = _amount*_bonus/(100**_weeks);
        return _aqp;
    }

    function switchStakeMode(bool _isFixed) external {
        stakes[msg.sender].isFixed = _isFixed;
    }


    function depositFor(address _for, uint256 _amount, bool _isFixed) external nonReentrant {

        Stake memory _stake = Stake({ amount: stakes[_for].amount, end: stakes[_for].end, isFixed: stakes[_for].isFixed });

        require(_amount > 0, "bad _amount");
        require(_stake.amount > 0, "!lock existed");
        require(_stake.end > block.timestamp, "lock expired. please withdraw");

        _depositFor(_for, _amount, 0, _isFixed, _stake);
    }


    function _unlock(Stake memory _stake, uint256 _withdrawAmount) internal {

        uint256 _stakedAmount = SafeCast.toUint256(_stake.amount);
        require(_withdrawAmount <= _stakedAmount, "not enough");

        Stake memory _prevStake = Stake({ end: _stake.end, amount: _stake.amoun, isFixed: _stake.isFixed });
        //_stake.end should remain the same if we do partially withdraw
        _stake.end = _stakedAmount == _withdrawAmount ? 0 : _stake.end;
        _stake.amount = SafeCast.toInt128(int256(_stakedAmount - _withdrawAmount));
        stakes[msg.sender] = _stake;

        uint256 _supplyBefore = supply;
        supply = _supplyBefore - _withdrawAmount;

        
        
    }

    function withdraw() external nonReentrant {
        Stake memory _stake = stakes[msg.sender];

        require(block.timestamp >= _stake.end, "stake not expired");

        uint256 _amount = SafeCast.toUint256(_stake.amount);

        _unlock(_stake, _amount);

        token.safeTransfer(msg.sender, _amount);

    }

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


        // transfer one part of the penalty to treasury
        token.safeTransfer(treasury, _treasuryFee);
        // transfer one part of the penalty to rewards pool
        token.safeTransfer(rewardsPool, _reward);
        // transfer remaining back to owner
        token.safeTransfer(msg.sender, _amount - _penalty);

    }


    

}



