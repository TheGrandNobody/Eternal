//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IGage.sol";

/**
 * @dev Gage V2 interface
 * @author Nobody (me)
 * @notice Methods are used for all gage contracts
 */
interface IGageV2 is IGage {
    // View the creator of the loyalty gage (usually token distributor)
    function viewCreator() external view returns (address);
    // View the buyer in the loyalty gage (usually the user)
    function viewBuyer() external view returns (address);
}