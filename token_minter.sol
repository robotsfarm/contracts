//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./IERC20Minter.sol";
import "./verify.sol";

contract RobotsFarmMinter is Verify{
    
    IERC20Minter public token;
    mapping(address => uint256) public payed;

    uint256 public hardLimit = 10*1e6*1e18;
    uint256 public minted;
    constructor(address _token){
        token = IERC20Minter(_token);
    }

    function setHardLimit(uint256 _hardLimit) public virtual onlyOwner{
        hardLimit = _hardLimit;
    }

    function mint(address account, uint256 value, uint256 timestamp, bytes calldata signature) public  virtual {
        verify(abi.encode(address(this), block.chainid, "mint",  account, value, timestamp), timestamp, signature);
        require(value>payed[account], "Minter: amount less than payed");
        uint256 diff = value-payed[account];
        minted+=diff;
        token.mint(account, diff);
        payed[account]=value;
        require(minted<=hardLimit, "Minter: limit reached");
    }
}