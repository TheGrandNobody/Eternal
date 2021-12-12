//SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

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
    // Allows the withdrawal of AVAX in the contract
    function withdrawAVAX(address payable recipient, uint256 amount) external;
    // Allows the withdrawal of an asset present in the contract
    function withdrawAsset(address asset, address recipient, uint256 amount) external;

    // Signals a disabling/enabling of the automatic liquidity provision
    event AutomaticLiquidityProvisionUpdated(bool value);
    // Signals that liquidity has been added to the ETRNL/WAVAX pair 
    event AutomaticLiquidityProvision(uint256 amountETRNL, uint256 totalSwappedETRNL, uint256 amountAVAX);
    // Signals that part of the locked AVAX balance has been cleared to a given address
    event AVAXTransferred(uint256 amount, address recipient);
    // Signals that some of an asset balance has been sent to a given address
    event AssetTransferred(address asset, uint256 amount, address recipient);
}