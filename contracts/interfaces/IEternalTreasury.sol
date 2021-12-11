//SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

/**
 * @dev Eternal Treasury interface
 * @author Nobody (me)
 * @notice Methods are used for all treasury functions
 */
interface IEternalTreasury {
    function fundLiquidityGage(address _gage, address user, address asset, uint256 amount, uint256 risk, uint256 bonus) external ;
    function stake(uint256 amount) external;
    function unstake(uint256 amount) external;

    event Stake(address user, uint256 amount);
    event Unstake(address user, uint256 amount);
}