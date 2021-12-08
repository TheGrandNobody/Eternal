//SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "../inheritances/OwnableEnhanced.sol";
import "../interfaces/IEternal.sol";
import "../interfaces/IEternalToken.sol";
import "../interfaces/IEternalTreasury.sol";
import "../interfaces/ILoyaltyGage.sol";
import "@traderjoe-xyz/core/contracts/traderjoe/interfaces/IJoeRouter02.sol";
import "@traderjoe-xyz/core/contracts/traderjoe/interfaces/IJoeFactory.sol";
import "@traderjoe-xyz/core/contracts/traderjoe/interfaces/IJoePair.sol";

/**
 * @dev Contract for the Eternal Fund
 * @author Nobody (me)
 * @notice The Eternal Fund contract holds all treasury logic
 */
 contract EternalTreasury is IEternalTreasury, OwnableEnhanced {

    IEternal private immutable eternalPlatform;
    IEternalToken private immutable eternal;
    IJoeFactory private immutable joeFactory;
    IJoeRouter02 private immutable joeRouter;

    mapping (address => uint256) private stakingBalances;
    mapping (address => uint256) private providedDeposits;
    mapping (address => uint256) private treasuryLiquidity;

    constructor (address _eternalPlatform, address _eternal) {
        eternalPlatform = IEternal(_eternalPlatform);
        eternal = IEternalToken(_eternal);
        IJoeRouter02 _joeRouter = IJoeRouter02(0x60aE616a2155Ee3d9A68541Ba4544862310933d4);
        joeRouter = _joeRouter;
        joeFactory = IJoeFactory(_joeRouter.factory());
    }

    function fundGage(address _gage, address user, address asset, uint256 userAmount, uint256 risk, uint256 bonus) external override {
        require(_msgSender() == address(eternalPlatform), "msg.sender must be the platform");
        require(joeFactory.getPair(address(eternal), asset) != address(0), "Unable to find pair on DEX");
        uint256 providedETRNL;
        uint256 providedAsset;
        uint256 liquidity;

        // Get the reserve ratios for the ETRNL-Asset pair
        (uint256 reserveA, uint256 reserveB,) = IJoePair(joeFactory.getPair(address(eternal), asset)).getReserves();
        (uint256 reserveETRNL, uint256 reserveAsset) = address(eternal) < asset ? (reserveA, reserveB) : (reserveB, reserveA);
        // Determine a reasonable minimum amount of ETRNL and Asset based on current reserves (with a tolerance of 0.5%)
        uint256 amountETRNL = joeRouter.quote(userAmount, reserveAsset, reserveETRNL);
        uint256 minAsset = joeRouter.quote(amountETRNL, reserveETRNL, reserveAsset);
        uint256 minETRNL = amountETRNL - (amountETRNL / 200);
        minAsset -= minAsset / 200;
        // Add liquidity to the ETRNL/Asset pair
        eternal.approve(address(joeRouter), amountETRNL);
        if (asset == joeRouter.WAVAX()) {
            (providedETRNL, providedAsset, liquidity) = joeRouter.addLiquidityAVAX{value: userAmount}(address(eternal), amountETRNL, minETRNL, minAsset, address(this), block.timestamp);
        } else {
            (providedETRNL, providedAsset, liquidity) = joeRouter.addLiquidity(address(eternal), asset, amountETRNL, userAmount, minETRNL, minAsset, address(this), block.timestamp);
        }

        providedDeposits[user] = providedAsset;
        treasuryLiquidity[asset] += liquidity;

        ILoyaltyGage(_gage).join(address(eternal), providedETRNL, risk);
        eternal.transfer(user, providedETRNL * bonus / (10 ** 4));
    }

    function stake(uint256 amount) {
        require(amount > 0, "Amount must be greater than 0");
        stakingBalances[_msgSender()] += amount;
        
    }
 }