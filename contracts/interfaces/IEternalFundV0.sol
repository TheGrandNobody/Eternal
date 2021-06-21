//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @dev ETRNL interface
 * @author Nobody (me)
 * @notice Methods are used for the DAO-governed section of Eternal and the gaging platform
 */
interface IEternalFundV0 {

    // View the ETRNL/AVAX pair address
    function viewPair() external view returns(address);
    // Enables/Disables automatic liquidity provision
    function setAutoLiquidityProvision(bool value) external;
    // Provides liquidity for the ETRNL/AVAX pair for the ETRNL token contract
    function provideLiquidity(uint256 contractBalance) external;
    // Stakes a given amount of lp tokens
    function stake(uint256 amount) external;
    // Claims the reward for staking lp tokens
    function claimReward() external;
    // Withdraws a give amount of staked lp tokens to a given address
    function withdrawStakedLP(uint256 amount, address recipient) external;
    // Withdraws a given amount of rewards from lp token-staking to a given address
    function withdrawLPReward(uint256 amount, address recipient) external;
    // Allows the withdrawal of AVAX locked in the contract over time
    function withdrawLockedAVAX(address payable recipient) external;

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