//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @dev Eternal Token V0 interface
 * @author Nobody
 * @notice Methods are used for the DAO-governed section of Eternal
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
    function setRate(uint8 newRate, Rate rate) external;

    // Enables/Disables automatic liquidity provision
    function setAutoLiquidityProvision(bool value) external;

    // Allows the withdrawal of AVAX locked in the contract over time
    function withdrawLockedAVAX(address payable recipient) external;

    // Signals a change of value of a given rate in the Eternal Token contract
    event UpdateRate(uint256 oldRate, uint256 newRate, Rate rate);
    // Signals a disabling/enabling of the automatic liquidity provision
    event AutoLiquidityProvisionUpdated(bool value);
    // Signals that liquidity has been added to the ETRNL/WAVAX pair 
    event AutomaticLiquidityProvision(uint256 amountETRNL, uint256 totalSwappedETRNL, uint256 amountAVAX);

}
