//SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "../inheritances/OwnableEnhanced.sol";
import "../interfaces/IEternal.sol";
import "../interfaces/IEternalToken.sol";
import "../interfaces/IEternalTreasury.sol";

/**
 * @dev Contract for the Eternal Fund
 * @author Nobody (me)
 * @notice The Eternal Fund contract holds all treasury logic
 */
 contract EternalTreasury is IEternalTreasury, OwnableEnhanced {
    IEternal private immutable eternalPlatform;
    IEternalToken private immutable eternal;

    constructor (address _eternalPlatform, address _eternal) {
        eternalPlatform = IEternal(_eternalPlatform);
        eternal = IEternalToken(_eternal);
    }

    function fundGage() external override {
        require(_msgSender() == address(eternalPlatform), "msg.sender must be the platform");
    }
 }