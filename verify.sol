pragma solidity ^0.8.8;

import "@openzeppelin/contracts@4.9.1/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts@4.9.1/access/Ownable.sol";

contract Verify is Ownable {
    using ECDSA for bytes32;
    address witness = 0xe3758CE5Cf72511E01F525c109016d496c4B6e3f;


    function verify(bytes memory data, uint256 timestamp, bytes memory signature) public view {
        require(timestamp>block.timestamp, "Signature expired");
        require(keccak256(data).toEthSignedMessageHash().recover(signature) == witness, "Signature verify failed");
    }

    function setWitness(address _witness) public virtual onlyOwner{
        witness=_witness;
    }

}