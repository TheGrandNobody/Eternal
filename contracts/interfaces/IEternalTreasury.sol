//SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

/**
 * @dev Eternal Treasury interface
 * @author Nobody (me)
 * @notice Methods are used for all treasury functions
 */
interface IEternalTreasury {
    // Provides liquidity for a given liquid gage and transfers instantaneous rewards to the receiver
    function fundEternalLiquidGage(address _gage, address user, address asset, uint256 amount, uint256 risk, uint256 bonus) external payable;
    // Used by gages to compute and distribute ETRNL liquid gage rewards appropriately
    function settleGage(address payable receiver, uint256 id, bool winner) external;
    // Stake a given amount of ETRNL
    function stake(uint256 amount) external;
    // Unstake a given amount of ETRNL and withdraw staking rewards proportional to the amount (in ETRNL)
    function unstake(uint256 amount) external;
    // View the ETRNL/AVAX pair address
    function viewPair() external view returns(address);
    // View whether a liquidity swap is in progress
    function viewUndergoingSwap() external view returns(bool);
    // Provides liquidity for the ETRNL/AVAX pair for the ETRNL token contract
    function provideLiquidity(uint256 contractBalance) external;
    // Computes the minimum amount of two assets needed to provide liquidity given one asset amount
    function computeMinAmounts(address asset, address otherAsset, uint256 amountAsset, uint256 uncertainty) external view returns(uint256 minOtherAsset, uint256 minAsset, uint256 amountOtherAsset);
    // Converts a given staked amount into the reserve number space
    function convertToReserve(uint256 amount) external view returns(uint256);
    // Converts a given reserve amount into the regular number space (staked)
    function convertToStaked(uint256 reserveAmount) external view returns(uint256);
    // Allows the withdrawal of AVAX in the contract
    function withdrawAVAX(address payable recipient, uint256 amount) external;
    // Allows the withdrawal of an asset present in the contract
    function withdrawAsset(address asset, address recipient, uint256 amount) external;

    // Signals a disabling/enabling of the automatic liquidity provision
    event AutomaticLiquidityProvisionUpdated(bool value);
    // Signals that liquidity has been added to the ETRNL/WAVAX pair 
    event AutomaticLiquidityProvision(uint256 amountETRNL, uint256 totalSwappedETRNL, uint256 amountAVAX);
    // Signals that part of the locked AVAX balance has been cleared to a given address by decision of the DAO
    event AVAXTransferred(uint256 amount, address recipient);
    // Signals that some of an asset balance has been sent to a given address by decision of the DAO
    event AssetTransferred(address asset, uint256 amount, address recipient);
    // Signals that a user staked a given amount of ETRNL 
    event Stake(address indexed user, uint256 amount);
    // Signals that a user unstaked a given amount of ETRNL
    event Unstake(address indexed user, uint256 amount);
}