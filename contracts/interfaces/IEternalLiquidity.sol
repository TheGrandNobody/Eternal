//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @dev ETRNL interface
 * @author Nobody (me)
 * @notice Methods are used for the DAO-governed section of Eternal and the gaging platform
 */
interface IEternalLiquidity {

    // View the ETRNL/AVAX pair address
    function viewPair() external view returns(address);
    // Enables/Disables automatic liquidity provision
    function setAutoLiquidityProvision(bool value) external;
    // Provides liquidity for the ETRNL/AVAX pair for the ETRNL token contract
    function provideLiquidity(uint256 contractBalance) external;
    // Allows the withdrawal of AVAX locked in the contract over time
    function withdrawLockedAVAX(address payable recipient) external;

    // Signals a disabling/enabling of the automatic liquidity provision
    event AutomaticLiquidityProvisionUpdated(bool value);
    // Signals that liquidity has been added to the ETRNL/WAVAX pair 
    event AutomaticLiquidityProvision(uint256 amountETRNL, uint256 totalSwappedETRNL, uint256 amountAVAX);
    // Signals that the locked AVAX balance has been cleared to a given address
    event LockedAVAXTransferred(uint256 amount, address recipient);
}