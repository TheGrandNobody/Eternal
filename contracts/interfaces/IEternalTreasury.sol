//SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

/**
 * @dev Eternal Treasury interface
 * @author Nobody (me)
 * @notice Methods are used for all treasury functions
 */
interface IEternalTreasury {
    // Provides liquidity for a given liquid gage and transfers instantaneous rewards to the receiver
    function fundEternalLiquidGage(address _gage, address user, address asset, uint256 amount, uint256 risk, uint256 bonus) external;
    // Used by gages to compute and distribute ETRNL liquid gage rewards appropriately
    function settleEternalLiquidGage(address receiver, uint256 id, bool winner) external;
    // Stake a given amount of ETRNL
    function stake(uint256 amount) external;
    // Unstake a given amount of ETRNL and withdraw any associated rewards in terms of the desired reserve asset
    function unstake(uint256 amount, address asset) external;
    // View the ETRNL/AVAX pair address
    function viewPair() external view returns(address);
    // Provides liquidity for the ETRNL/AVAX pair for the ETRNL token contract
    function provideLiquidity(uint256 contractBalance) external;
    // Allows the withdrawal of AVAX in the contract
    function withdrawAVAX(address payable recipient, uint256 amount) external;
    // Allows the withdrawal of an asset present in the contract
    function withdrawAsset(address asset, address recipient, uint256 amount) external;
    // Sets the address of the Eternal Factory contract
    function setEternalFactory(address newContract) external;
    // Sets the address of the Eternal Token contract
    function setEternalToken(address newContract) external;

    // Signals a disabling/enabling of the automatic liquidity provision
    event AutomaticLiquidityProvisionUpdated(bool value);
    // Signals that liquidity has been added to the ETRNL/WAVAX pair 
    event AutomaticLiquidityProvision(uint256 amountETRNL, uint256 totalSwappedETRNL, uint256 amountAVAX);
    // Signals that part of the locked AVAX balance has been cleared to a given address by decision of the DAO
    event AVAXTransferred(uint256 amount, address recipient);
    // Signals that some of an asset balance has been sent to a given address by decision of the DAO
    event AssetTransferred(address asset, uint256 amount, address recipient);
    // Signals that a user staked a given amount of ETRNL 
    event Stake(address user, uint256 amount);
    // Signals that a user unstaked a given amount of ETRNL
    event Unstake(address user, uint256 amount);
}