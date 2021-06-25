//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @dev ETRNL interface
 * @author Nobody (me)
 * @notice Methods are used for the DAO-governed section of Eternal and the gaging platform
 */
interface IEternalToken is IERC20, IERC20Metadata {

    // Holds all the different types of rates
    enum Rate {
        Liquidity,
        Funding,
        Redistribution,
        Burn
    }
    
    // Sets the value of any given rate
    function setRate(Rate rate, uint8 newRate) external;
    // Sets the liquidity threshold to a given value
    function setLiquidityThreshold(uint64 value) external;
    // Designates a new Eternal DAO address
    function designateFund(address fund) external;

    // Signals a change of value of a given rate in the Eternal Token contract
    event UpdateRate(uint256 oldRate, uint256 newRate, Rate rate);
    // Signals a change of value of the token liquidity threshold
    event UpdateLiquidityThreshold(uint64 oldThreshold, uint64 newThreshold);
}