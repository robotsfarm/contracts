pragma solidity ^0.8.8;

import "@openzeppelin/contracts@4.9.1/access/Ownable.sol";

contract robotsStaking is Ownable {
    
    uint256 public perUnit;
    uint256 public rate;
    uint256 public pool;
    uint256 public totalAmount;
    uint256 public totalReward;


    struct stake {
        uint256 staked;
        uint256 reward;
        uint256 rewardsPerUnitPaid;
    }

    mapping(address=>stake) public stakes;
    
    uint256 public updateTime;
    

    uint256 denominator = 1e18;

    constructor(uint256 _rate, uint256 _pool){
        updateTime = block.timestamp;
        rate = _rate;
        pool = _pool;
    }

    function setRate(uint256 _rate) public onlyOwner{
        tick(msg.sender);
        require(_rate!=0);
        rate = _rate;
    }

    function setPool(uint256 _pool) public onlyOwner{
        require(_pool>totalReward);
        tick(msg.sender);
        pool = _pool;
    }
    function emission() internal view returns(uint256){
        return min((block.timestamp - updateTime)*(pool-totalReward)/rate, pool-totalReward);
    }

    function min(uint256 a, uint256 b) internal pure returns(uint256){
        if (a>b){
            return b;
        }else{
            return a;
        }
    }


    function tick(address account) internal  virtual  {
        if (totalAmount>0){
            uint256 tmpEmission = emission();
            totalReward += tmpEmission;
            perUnit += tmpEmission*denominator/totalAmount;
            stakes[account].reward +=  stakes[account].staked*(perUnit - stakes[account].rewardsPerUnitPaid)/denominator;
            stakes[account].rewardsPerUnitPaid = perUnit;
        }
        updateTime = block.timestamp;
    }

    function addStake(address account, uint256 amount) internal{
        stakes[account].staked+=amount;
        totalAmount+=amount;
    }


    function removeStake(address account, uint256 amount) internal{
        stakes[account].staked-=amount;
        totalAmount-=amount;
    }

    function balance(address account) internal  view returns(uint256) {
        if (totalAmount==0){
            return stakes[account].reward;
        }
        uint256 tmpEmission = emission();
        uint256 tmpPerUnit = perUnit + tmpEmission*denominator/totalAmount;
        return stakes[account].reward + stakes[account].staked*(tmpPerUnit - stakes[account].rewardsPerUnitPaid)/denominator;
    }

}
