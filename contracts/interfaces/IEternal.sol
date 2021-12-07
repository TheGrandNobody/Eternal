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
    function deposit(address asset, address user, uint256 amount, uint256 id, uint256 risk) external;
    // Withdraw an asset from the platform
    function withdraw(address user, uint256 id, bool winner) external;
    // Set the fee rate of the platform
    function setFeeRate(uint256 newRate) external;
    // Set the time constant used in calculating the percent change condition
    function setTimeConstant(uint256 newConstant) external;
    // Set the risk constant used in calculating the treasury's risk
    function setRiskConstant(uint256 newConstant) external;
    // Set the minimum estimate of tokens transacted in 24h
    function setBaseline(uint256 newBaseline) external;
    // View the address of a gage for a given id
    function viewGageAddress(uint256 id) external returns(address);
    // View the address of ETRNL
    function viewETRNL() external returns(address);
    
    // Signals the deployment of a new gage
    event NewGage(uint256 id, address indexed gageAddress);
    // Signals an update of the gage fee rate
    event FeeRateUpdated(uint256 oldRate, uint256 newRate);
    // Signals an update of the time constant
    event TimeConstantUpdated(uint256 oldConstant, uint256 newConstant);
    // Signals an update of the risk constant
    event RiskConstantUpdated(uint256 oldConstant, uint256 newConstant);
    // Signals an update of the baseline
    event BaselineUpdated(uint256 oldBaseline, uint256 newBaseline);
}