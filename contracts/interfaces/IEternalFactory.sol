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
    // Sets the address of the Eternal Treasury contract
    function setEternalTreasury(address newContract) external;
    // Sets the address of the Eternal Token contract
    function setEternalToken(address newContract) external;
    
    // Signals the deployment of a new gage
    event NewGage(uint256 id, address indexed gageAddress);
}