//SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

/**
 * @dev Eternal interface
 * @author Nobody (me)
 * @notice Methods are used for all gage-related functioning
 */
interface IEternalFactory {
    // Initiates a liquid gage involving an ETRNL liquidity pair
    function initiateEternalLiquidGage(address asset, uint256 amount) external returns(uint256);
    
    // Signals the deployment of a new gage
    event NewGage(uint256 id, address indexed gageAddress);
}