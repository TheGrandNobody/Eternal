//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @dev Eternal Token V0 interface
 * @author Nobody
 * @notice Methods are used for the DAO-governed section of Eternal
 */
interface IEternalTokenV0 {

    // Holds all the different types of rates
    enum Rate {
        Liquidity,
        Funding,
        Redistribution,
        Burn
    }

    // Sets the value of any given rate
    function setRate(uint8 newRate, Rate rate) external;

    // Signals a change of value of a given rate in the Eternal Token contract
    event UpdateRate(uint8 oldRate, uint8 newRate, Rate rate);

}
