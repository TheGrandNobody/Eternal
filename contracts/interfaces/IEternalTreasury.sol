//SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

/**
 * @dev Eternal Treasury interface
 * @author Nobody (me)
 * @notice Methods are used for all treasury functions
 */
interface IEternalTreasury {
    
    function fundGage(address _gage, uint256 amount, uint256 risk) external ;
}