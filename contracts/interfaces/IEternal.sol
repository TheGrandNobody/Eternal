//SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

/**
 * @dev Eternal interface
 * @author Nobody (me)
 * @notice Methods are used for all gage-related functioning
 */
interface IEternal {
    // Initiates a liquid gage involving an ETRNL liquidity pair
    function initiateEternalLiquidGage() external returns(uint256);
    // Deposit an asset to the platform
    function deposit(address asset, address user, uint256 amount, uint256 id) external;
    // Withdraw an asset from the platform
    function withdraw(address user, uint256 id, bool winner) external;
    // Set the fee rate of the platform
    function setFeeRate(uint256 newRate) external;
    // Set the time-constant used in calculating the percent change condition
    function setTimeConstant(uint256 newConstant) external;
    
    // Signals the deployment of a new gage
    event NewGage(uint256 id, address indexed gageAddress);
    // Signals an update of the gage fee rate
    event FeeRateUpdated(uint256 oldRate, uint256 newRate);
    // Signals an update of the time-constant
    event TimeConstantUpdated(uint256 oldConstant, uint256 newConstant);
}