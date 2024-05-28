//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.8;

import "@openzeppelin/contracts@4.9.1/token/ERC20/presets/ERC20PresetMinterPauser.sol";

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

import "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";

import "./staking_math.sol";
import "./verify.sol";
import "./IERC20Minter.sol";


contract RobotsStaking  is robotsStaking, Verify {
    IERC20Minter public rewardToken;
    IERC20Minter public rewardTokenLocked;
    IUniswapV2Pair public lpToken;
    IUniswapV2Router02 public router;

    uint256 public unlockedRatio = 50;

    bool public closed = false;

    struct user{
        uint256 lpTokens;
        uint256 stakeBoost;
        uint256 payed;
        uint256 ageWeightedSum;
        uint256 stakeBoostExpire;
    }
 
    mapping(address=>user) public users;

    address public penaltyPool = 0xB0D13326b9A23052251Df7d7eb19e25e087459FE;


    uint256 boostOffset = 1000;
    uint256 maxBoost = 10000;
    uint256 boostLimit = 2000;
    uint256 maxPenalty = 100;

    uint256 public fee = 10**15;

    constructor(address _rewardToken, address _rewardTokenLocked, address _lpToken, address _router, uint256 _rate, uint256 _pool) robotsStaking(_rate, _pool){
        rewardToken = IERC20Minter(_rewardToken);
        rewardTokenLocked = IERC20Minter(_rewardTokenLocked);
        lpToken = IUniswapV2Pair(_lpToken);
        router = IUniswapV2Router02(_router);
    }

    function setClosed(bool _closed) public virtual onlyOwner{
        closed = _closed;
    }

    function setUnlockedRatio(uint256 _ratio) public virtual onlyOwner{
        require(_ratio<=1000);
        unlockedRatio = _ratio;
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



    function boost(address account) public view returns(uint256){
        if (users[account].stakeBoostExpire>block.timestamp){
            return (users[account].stakeBoost+boostOffset);
        }else{
            return boostOffset;
        }
    }

    function updateStake(address account) public virtual {
        tick(account);
        removeStake(account, stakes[account].staked);
        addStake(account, users[account].lpTokens*boost(account));
    }

   function add(uint256 value, address to) public virtual {
        require(value>0);
        require(!closed);
        lpToken.transferFrom(msg.sender, address(this), value);
        users[to].lpTokens+=value;
        users[to].ageWeightedSum+=value*block.timestamp;
        updateStake(to);
   } 


    function _remove(address account, uint256 value) internal virtual {
        users[account].ageWeightedSum-=value*stakeAge(account);
        users[account].lpTokens-=value;
        updateStake(account);
    }

    function emergencyWithdraw(uint256 value) public virtual {
        require(closed);
        require(users[msg.sender].lpTokens>=value);
        users[msg.sender].lpTokens-=value;
        lpToken.transfer(msg.sender, value);
    }

    function remove(uint256 value) public virtual {
        require(value>0);
        require(value<=users[msg.sender].lpTokens);

        uint256 penalty = value*penaltyPromille(msg.sender)/1000;
        if (penalty>0){
            lpToken.transfer(penaltyPool, penalty);
        }
        lpToken.transfer(msg.sender, value-penalty);
  
        _remove(msg.sender, value);
    }

    function removeStakeLiquidity(uint256 value) public virtual{
        require(value>0);
        require(value<=users[msg.sender].lpTokens);

        uint256 penalty = value*penaltyPromille(msg.sender)/1000;
        if (penalty>0){
            lpToken.transfer(penaltyPool, penalty);
        }

        uint256 output = value - penalty;
        lpToken.approve(address(router), output);
        router.removeLiquidity(lpToken.token0(),lpToken.token1(), output, 0, 0, msg.sender, block.timestamp+1000);

        _remove(msg.sender, value);
    }

    function removeStakeLiquidityETH(uint256 value) public virtual{
        require(value>0);
        require(value<=users[msg.sender].lpTokens);

        uint256 penalty = value*penaltyPromille(msg.sender)/1000;
        if (penalty>0){
            lpToken.transfer(penaltyPool, penalty);
        }

        uint256 output = value - penalty;

        lpToken.approve(address(router), output);
        
        address token = lpToken.token0();
        if (token == router.WETH()){
            token = lpToken.token1();
        }
        
        router.removeLiquidityETH(token, output, 0, 0, msg.sender, block.timestamp+1000);

        _remove(msg.sender, value);
    }

    function stakeAge(address account) public view returns(uint256){
        if (users[account].lpTokens==0){
            return 0;
        }
        return users[account].ageWeightedSum/users[account].lpTokens;
    }

    function penaltyPromille(address account) public view returns(uint256){
        uint256 age = block.timestamp - stakeAge(account);
        uint256 duration = 12 hours;
        if (age > duration){
            return 0;
        }
        return maxPenalty - age * maxPenalty / duration;
    }   

    function available(address account) public view returns(uint256, uint256, uint256){
        uint256 x = balance(account) - users[account].payed;
        return (x, x*unlockedRatio/1000, x*(1000-unlockedRatio)/1000);
    }

    function claim() public virtual {
        tick(msg.sender);
        uint256 value = stakes[msg.sender].reward - users[msg.sender].payed;
        require(value>0);
        users[msg.sender].payed+=value;
        uint256 unlockedValue = value*unlockedRatio/1000;

        rewardToken.mint(msg.sender, unlockedValue);
        rewardTokenLocked.mint(msg.sender, value-unlockedValue);
   }
}



contract StakingHelper {
    IUniswapV2Router02 public router;

    uint256 public uniqueStakers;
    mapping(address => bool) stakers;

    constructor(address _router){ 
        router = IUniswapV2Router02(_router);
    }

    function sqrt(uint256 x) internal pure returns (uint256) {
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }

    function solve(uint256 a0, uint256 b0, uint256 a, uint256 b) public pure returns(uint256){
        uint256 u = sqrt(a0*b*a/b0);
        if (u>a){
            return u - a;
        }
        return 0;
    }

    function _countStakers() internal virtual {
        if (!stakers[msg.sender]){
            uniqueStakers++;
            stakers[msg.sender]=true;
        }
    }

    function _addStakeLiquidityBalanced(address tokenA, uint256 tokenAamount, address tokenB, uint256 tokenBamount, uint256 deadline, address staking) internal {

        IUniswapV2Pair pair = IUniswapV2Pair(IUniswapV2Factory(router.factory()).getPair(tokenA,tokenB));

        (uint reserveA, uint reserveB,) = pair.getReserves();
        if (pair.token0()!=tokenA){
            (reserveA, reserveB) = (reserveB, reserveA);
        }

        address[] memory path = new address[](2);

        uint256 a = solve(tokenAamount+reserveA,tokenBamount+reserveB, reserveA,reserveB);
        uint256 b = solve(tokenBamount+reserveB,tokenAamount+reserveA, reserveB,reserveA);

   
        if (a > 0) {
            path[0]=tokenA;
            path[1]=tokenB;
            IERC20(tokenA).approve(address(router), a);
            router.swapExactTokensForTokens(a, 0, path, address(this), deadline);
        } else if (b > 0) {
            path[1]=tokenA;
            path[0]=tokenB;
            IERC20(tokenB).approve(address(router), b);
            router.swapExactTokensForTokens(b, 0, path, address(this), deadline);
    }

        
        uint256 balancedTokenAamount = IERC20(tokenA).balanceOf(address(this));
        uint256 balancedTokenBamount = IERC20(tokenB).balanceOf(address(this));

        IERC20(tokenA).approve(address(router), balancedTokenAamount);
        IERC20(tokenB).approve(address(router), balancedTokenBamount);

        router.addLiquidity(tokenA, tokenB, balancedTokenAamount, balancedTokenBamount, 0, 0, address(this), block.timestamp+1000);
        
        pair.approve(staking, pair.balanceOf(address(this)));
        RobotsStaking(staking).add(pair.balanceOf(address(this)), msg.sender);

        pair.transfer(msg.sender, pair.balanceOf(address(this)));
        require(pair.balanceOf(address(this))==0);

        _countStakers();

    }

    function addStakeLiquidity(address tokenA,  uint256 tokenAamount,  address tokenB, uint256 tokenBamount,uint256 deadline, address staking) public virtual {
        
        IERC20(tokenA).transferFrom(msg.sender, address(this), tokenAamount);
        IERC20(tokenB).transferFrom(msg.sender, address(this), tokenBamount);
    
        _addStakeLiquidityBalanced(tokenA, tokenAamount, tokenB, tokenBamount, deadline, staking); 

        IERC20(tokenA).transfer(msg.sender, IERC20(tokenA).balanceOf(address(this)));
        IERC20(tokenB).transfer(msg.sender, IERC20(tokenB).balanceOf(address(this)));
        payable(msg.sender).transfer(address(this).balance);
        
        require(IERC20(tokenA).balanceOf(address(this))==0);
        require(IERC20(tokenB).balanceOf(address(this))==0);
        require(address(this).balance==0);

    }
    
    function addStakeLiquidityETH(address tokenA, uint256 tokenAamount, uint256 deadline, address staking) public virtual payable  {
        

        IERC20(tokenA).transferFrom(msg.sender, address(this), tokenAamount);
        address tokenB = router.WETH();

        IWETH(tokenB).deposit{value:msg.value}();

        _addStakeLiquidityBalanced(tokenA, tokenAamount, tokenB, msg.value, deadline, staking); 

        IERC20(tokenA).transfer(msg.sender, IERC20(tokenA).balanceOf(address(this)));


        IERC20(tokenB).approve(tokenB, IERC20(tokenB).balanceOf(address(this)));
        IWETH(tokenB).withdraw(IERC20(tokenB).balanceOf(address(this)));

        payable(msg.sender).transfer(address(this).balance);        
        require(IERC20(tokenA).balanceOf(address(this))==0);
        require(IERC20(tokenB).balanceOf(address(this))==0);
        require(address(this).balance==0);
    }

    receive() external payable {}
    fallback() external payable {}
}



