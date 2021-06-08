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

    // Enables/Disables automatic liquidity provision
    function setAutoLiquidityProvision(bool value) external;

    // Signals a change of value of a given rate in the Eternal Token contract
    event UpdateRate(uint8 oldRate, uint8 newRate, Rate rate);
    // Signals a disabling/enabling of the automatic liquidity provision
    event AutoLiquidityProvisionUpdated(bool value);
    // Signals that liquidity has been added to the ETRNL/WAVAX pair 
    event AutomaticLiquidityProvision(uint64 amountETRNL, uint64 totalSwappedETRNL, uint256 amountAVAX,);

}
