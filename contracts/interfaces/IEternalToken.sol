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
    function setRate(uint8 newRate, Rate rate) external;
    // Enables/Disables automatic liquidity provision
    function setAutoLiquidityProvision(bool value) external;
    // Claims the PNG gained as a reward for staking PGL tokens on PangolinDEX
    function claimPNG() external;
    // Withdraws the staked lp tokens from PangolinDEX
    function withdrawStakedPGL(uint256 amount, address recipient) external;
    // Withdraws PNG earned as a reward from lp token-staking
    function withdrawClaimedPNG(uint256 amount, address recipient) external;
    // Allows the withdrawal of AVAX locked in the contract over time
    function withdrawLockedAVAX(address payable recipient) external;
    // Designates a new Eternal DAO address
    function designateFund(address fund) external;

    // Signals a change of value of a given rate in the Eternal Token contract
    event UpdateRate(uint256 oldRate, uint256 newRate, Rate rate);
    // Signals a disabling/enabling of the automatic liquidity provision
    event AutoLiquidityProvisionUpdated(bool value);
    // Signals that liquidity has been added to the ETRNL/WAVAX pair 
    event AutomaticLiquidityProvision(uint256 amountETRNL, uint256 totalSwappedETRNL, uint256 amountAVAX);
    // Signals that the locked AVAX balance has been cleared to a given address
    event LockedAVAXTransferred(uint256 amount, address recipient);
    // Signals that lp tokens were staked to the PangolinDEX
    event LPTokensStaked(uint256 amount);
    // Signals that lp tokens were withdrawn to a given address
    event LPTokensUnstakedAndTransferred(uint256 amount, address recipient);
    // Signals that lp rewards were claimed 
    event LPRewardsClaimed(uint256 amount);
    // Signals that lp rewards were transferred to a given address
    event LPRewardsTransferred(uint256 amount, address recipient);

}