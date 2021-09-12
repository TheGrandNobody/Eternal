//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Gage.sol";
import "../interfaces/IGageV2.sol";

contract LoyaltyGage is Gage, IGageV2 {

    // Address of the stakeholder which pays the discount in a loyalty gage
    address public immutable creator;
    // Address of the stakeholder which benefits from the discount in a loyalty gage
    address public immutable buyer;

    constructor(uint256 _id, uint32 _users, address _creator, address _buyer) Gage(_id, _users) {
        creator = _creator;
        buyer = _buyer;
    }

    /**
     * @dev View the address of the creator
     * @return The address of the creator
     */
    function viewCreator() external view override returns (address){
        return creator;
    }

    /**
     * @dev View the address of the buyer
     * @return The address of the buyer
     */
    function viewBuyer() external view override returns (address) {
        return buyer;
    }
}