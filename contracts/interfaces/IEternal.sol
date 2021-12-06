//SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

/**
 * @dev Eternal interface
 * @author Nobody (me)
 * @notice Methods are used for all gage-related functioning
 */
interface IEternal {
    // Initiates a standard gage
    function initiateLiquidGage(address user, bool inflationary) external returns(uint256);
    // Deposit an asset to the platform
    function deposit(address asset, address user, uint256 amount, uint256 id) external;
    // Withdraw an asset from the platform
    function withdraw(address user, uint256 id, bool winner) external;
    // Set the fee rate of the platform
    function setFeeRate(uint256 newRate) external;
    
    event NewGage(uint256 id, address indexed gageAddress);
    event FeeRateChanged(uint256 oldRate, uint256 newRate);
}