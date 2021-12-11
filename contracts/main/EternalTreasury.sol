//SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "../inheritances/OwnableEnhanced.sol";
import "../interfaces/IEternal.sol";
import "../interfaces/IEternalToken.sol";
import "../interfaces/IEternalTreasury.sol";
import "../interfaces/ILoyaltyGage.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@traderjoe-xyz/core/contracts/traderjoe/interfaces/IJoeRouter02.sol";
import "@traderjoe-xyz/core/contracts/traderjoe/interfaces/IJoeFactory.sol";
import "@traderjoe-xyz/core/contracts/traderjoe/interfaces/IJoePair.sol";

/**
 * @dev Contract for the Eternal Treasury
 * @author Nobody (me)
 * @notice The Eternal Treasury contract holds all treasury logic
 */
 contract EternalTreasury is IEternalTreasury, OwnableEnhanced {

    struct TreasuryNote {
        uint256 amountProvided;      // The amount of a given asset provided by the user in a liquid gage
        uint256 savedFees;           // The amount of fees in a given asset collected by the user
        uint256 balanceSnapshot;     // The treasury's balance for a given asset when the collected fees were last calculated
    }

    IEternal private immutable eternalPlatform;
    IEternalToken private immutable eternal;
    IJoeFactory private immutable joeFactory;
    IJoeRouter02 private immutable joeRouter;

    // The amount of ETRNL staked by any given individual user
    mapping (address => uint256) private stakedBalances;
    // Holds all user data related to gaging and staking rewards
    mapping (address => mapping(address => TreasuryNote)) private treasuryFiles;
    // Holds all addresses of tokens held by the treasury
    address[] private tokenTreasury;

    // The total number of ETRNL staked by users 
    uint256 private totalStakedBalances;
    // The amount by which the treasury's stake is reduced (x 10 ** 4)
    uint256 private treasuryShare;

    constructor (address _eternalPlatform, address _eternal) {
        eternalPlatform = IEternal(_eternalPlatform);
        eternal = IEternalToken(_eternal);
        IJoeRouter02 _joeRouter = IJoeRouter02(0x60aE616a2155Ee3d9A68541Ba4544862310933d4);
        joeRouter = _joeRouter;
        joeFactory = IJoeFactory(_joeRouter.factory());

        // Initialize the treasury share
        treasuryShare = 5000;
    }

    /**
     * @dev Funds a given liquidity gage with ETRNL, provides liquidity using ETRNL and the receiver's asset and transfers a bonus to the receiver
     * @param gage The address of the specified liquidity gage
     * @param receiver The address of the receiver
     * @param asset The address of the asset provided by the receiver
     * @param userAmount The amount of the asset provided by the receiver
     * @param risk The treasury's (distributor) risk percentage 
     * @param bonus The receiver's bonus percentage
     * 
     * Requirements:
     *
     * - Only callable by the Eternal Platform
     * - Does not work with non-existent liquidity pairs
     */
    function fundLiquidityGage(address gage, address receiver, address asset, uint256 userAmount, uint256 risk, uint256 bonus) external override {
        require(_msgSender() == address(eternalPlatform), "msg.sender must be the platform");
        require(joeFactory.getPair(address(eternal), asset) != address(0), "Unable to find pair on DEX");

        uint256 providedETRNL;
        uint256 providedAsset;

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
            (providedETRNL, providedAsset,) = joeRouter.addLiquidityAVAX{value: userAmount}(address(eternal), amountETRNL, minETRNL, minAsset, address(this), block.timestamp);
        } else {
            (providedETRNL, providedAsset,) = joeRouter.addLiquidity(address(eternal), asset, amountETRNL, userAmount, minETRNL, minAsset, address(this), block.timestamp);
        }

        TreasuryNote storage note = treasuryFiles[receiver][asset];
        note.amountProvided = providedAsset;

        ILoyaltyGage(gage).join(address(eternal), providedETRNL, risk);
        eternal.transfer(receiver, providedETRNL * bonus / (10 ** 4));
    }

    /**
     * @dev Stakes a given amount of ETRNL into the treasury
     * @param amount The specified amount of ETRNL being staked
     * 
     * Requirements:
     * 
     * - Staked amount must be greater than 0
     */
    function stake(uint256 amount) external override {
        require(amount > 0, "Amount must be greater than 0");

        eternal.transferFrom(_msgSender(), address(this), amount);
        emit Stake(_msgSender(), amount);

        stakedBalances[_msgSender()] += amount;
        totalStakedBalances += amount;
    }

    /**
     * @dev Unstakes a user's given amount of ETRNL and transfers the user's accumulated rewards
     * @param amount The specified amount of ETRNL being unstaked
     */
    function unstake(uint256 amount) external override {
        require(amount <= stakedBalances[_msgSender()] , "Amount exceeds staked balance");

        emit Unstake(_msgSender(), amount);

        stakedBalances[_msgSender()] -= amount;
        totalStakedBalances -= amount;

        eternal.transfer(_msgSender(), amount);
    }

    function updateTreasuryFiles(address user) private {
        TreasuryNote storage note;
        uint256 netTreasuryShare = (eternal.balanceOf(address(this)) - totalStakedBalances) * treasuryShare / (10 ** 4);
        uint256 feeShare = stakedBalances[user] * (10 ** 9) / (totalStakedBalances + netTreasuryShare);

        for (uint256 i = 0; i < tokenTreasury.length; i++) {
            uint256 treasuryBalance = IERC20(tokenTreasury[i]).balanceOf(address(this));
            note = treasuryFiles[user][tokenTreasury[i]];
            if (stakedBalances[user] > 0) { 
                note.savedFees += feeShare * sub(treasuryBalance, note.balanceSnapshot) / (10 ** 9);
            }
            note.balanceSnapshot = treasuryBalance;
        }

    }
 }