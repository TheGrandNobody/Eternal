pragma solidity ^0.8.0;

contract EternalFundV0 {

    function execute(address addr) public returns(bool) {
        bytes memory data = abi.encodePacked(true, uint256(6));
        (bool success, bytes memory _data) = addr.call(abi.encodeWithSignature("yield(bool, uint256)", data));

        return success;
    }

}