//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts@4.9.5/token/ERC20/presets/ERC20PresetMinterPauser.sol";

contract RobotsFarm is ERC20PresetMinterPauser{
    
    uint256 public maxSupply = 1e9*1e18;

    constructor() ERC20PresetMinterPauser("Robots.Farm", "RBF"){
    }

    function _afterTokenTransfer(address from, address to, uint256 amount)  override internal virtual {
        super._afterTokenTransfer(from,to,amount);
        require(totalSupply()<=maxSupply, "RobotsFarm: token limit reached");
    }
}