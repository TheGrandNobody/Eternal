//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./IGage.sol";

/**
 * @dev Gage V2 interface
 * @author Nobody (me)
 * @notice Methods are used for all gage contracts
 */
interface IGageV2 is IGage {
    // View the distributor of the loyalty gage (usually token distributor)
    function viewDistributor() external view returns (address);
    // View the receiver in the loyalty gage (usually the user)
    function viewReceiver() external view returns (address);
    // View the gage's percent change in supply condition
    function viewPercent() external view returns (uint256);
    // View the whether the gage's deposit is inflationary or deflationary
    function viewInflationary() external view returns (bool);
}