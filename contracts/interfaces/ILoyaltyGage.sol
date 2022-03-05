//SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "./IGage.sol";

/**
 * @dev Loyalty Gage interface
 * @author Nobody (me)
 * @notice Methods are used for all loyalty gage contracts
 */
interface ILoyaltyGage is IGage {
    // Initializes the loyalty gage
    function initialize(address rAsset, address dAsset, uint256 rAmount, uint256 dAmount, uint256 rRisk, uint256 dRisk) external;
    // View the gage's minimum target supply meeting the percent change condition
    function viewTarget() external view returns (uint256);
}