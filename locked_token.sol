//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.8;

import "@openzeppelin/contracts@4.9.1/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import "./staking_math.sol";
import "./verify.sol";
import "./IERC20Minter.sol";


interface RBFToken is IERC20Minter {
    function totalSupply() external view returns(uint256);
    function maxSupply() external view returns(uint256);
}

contract RobotsFarmLocked is ERC20PresetMinterPauser, robotsStaking, Verify{

    struct user{
        uint256 stakeBoost;
        uint256 stakeBoostExpire;
        uint256 payed;
    }
 
    mapping(address=>user) public users;


    address public penaltyPool = 0xB0D13326b9A23052251Df7d7eb19e25e087459FE;

    uint256 boostOffset = 1000;
    uint256 maxBoost = 10000;
    uint256 boostLimit = 2000;
    uint256 public fee = 10**15;

    uint256 maxStakeBoost = 250;

    RBFToken public token;

    constructor(address _token) ERC20PresetMinterPauser("Robots.Farm Locked","LRBF") robotsStaking(1000000,0){
        token = RBFToken(_token);
    }
    function transferFrom(address from, address to, uint256 amount) override public virtual returns(bool) {
        require(false, "Transfer is unavailable");
    }
    function transfer(address to, uint256 amount) override public virtual returns(bool) {
        require(false, "Transfer is unavailable");
    }

    function boost(address account) public view returns(uint256){
        if (users[account].stakeBoostExpire>block.timestamp){
            return (users[account].stakeBoost+boostOffset);
        }else{
            return boostOffset;
        }
    }

    function updateStake(address account) internal virtual {
        tick(account);
        removeStake(account,stakes[account].staked);
        addStake(account,balanceOf(account)*boost(account));
        pool=totalSupply()+totalReward;
    }

    function _afterTokenTransfer(address from, address to, uint256 amount) override internal  virtual {
        super._afterTokenTransfer(from, to, amount);
        require(token.totalSupply()+totalSupply() <= token.maxSupply());
        updateStake(to);
        updateStake(from);
    }

    function available(address account) public view returns(uint256){
        return  min(balance(account) - users[account].payed, balanceOf(account));
    }

    function claim() public virtual {
        tick(msg.sender);
        uint256 value = min(stakes[msg.sender].reward - users[msg.sender].payed, balanceOf(msg.sender));
        require(value>0);
        users[msg.sender].payed+=value;
        token.mint(msg.sender, value);
        _burn(msg.sender, value);
    }

    function setBoostFee(uint256 _fee) public virtual onlyOwner{
        fee = _fee;
    }

    function setBoostLimit(uint256 _limit) public virtual onlyOwner{
        require(_limit <= maxBoost);
        boostLimit = _limit;
    }

    function setPenaltyPool(address _penaltyPool) public virtual onlyOwner{
        penaltyPool = _penaltyPool;
    }

    function setStakeBoost(address account, uint256 value, uint256 expire, uint256 timestamp, bytes calldata signature) public  virtual payable {
        verify(abi.encode(address(this), block.chainid, "setStakeBoost",  account, value, expire, timestamp), timestamp, signature);
        require(value <= boostLimit, "RobotsStaking: above max boost");
        require(msg.value==fee, "RobotsStaking: value!=fee");
        payable(penaltyPool).transfer(msg.value);
        users[account].stakeBoost = value;
        users[account].stakeBoostExpire = expire;
        updateStake(account);
    }


}