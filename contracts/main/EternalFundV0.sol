//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@pangolindex/exchange-contracts/contracts/pangolin-core/interfaces/IPangolinFactory.sol";
import "@pangolindex/exchange-contracts/contracts/pangolin-periphery/interfaces/IPangolinRouter.sol";
import "../interfaces/IEternalToken.sol";
import "../interfaces/IEternalFundV0.sol";
import "../interfaces/IStakingRewards.sol";
import "../inheritances/OwnableEnhanced.sol";

contract EternalFundV0 is IEternalFundV0, OwnableEnhanced {

    // PangolinDex Router interface to swap tokens for AVAX and add liquidity
    IPangolinRouter private pangolinRouter;
    // Staking rewards interface for staking LP tokens and claiming liquidity rewards
    IStakingRewards private stakingRewards;
    // The address of the ETRNL/AVAX pair
    address private pangolinPair;
    // The pangolin reward token
    IERC20 private png;
    // The pangolin liquidity token
    IERC20 private pgl;
    // The ETRNL token
    IEternalToken private eternal;

    // Keeps track of accumulated, locked AVAX as a result of automatic liquidity provision
    uint256 private lockedAVAXBalance;
    // Keeps track of staked lp tokens 
    uint256 private totalStakedPGL;

    // Determines whether an auto-liquidity provision process is undergoing
    bool private undergoingSwap;
    // Determines whether the contract is tasked with providing liquidity using part of the transaction fees
    bool private autoLiquidityProvision;

    constructor (address _eternal) {
        // Initialize router
        pangolinRouter = IPangolinRouter(0xE54Ca86531e17Ef3616d22Ca28b0D458b6C89106);
        // Create pair address
        pangolinPair = IPangolinFactory(pangolinRouter.factory()).createPair(address(this), pangolinRouter.WAVAX());
        // Initialize Pangolin Staking Rewards
        stakingRewards = IStakingRewards(0x701e03fAD691799a8905043C0d18d2213BbCf2c7);
        // Inititalize Pangolin lp token
        pgl = IERC20(pangolinPair);
        // Initialize Pangolin reward token
        png = IERC20(0x60781C2586D68229fde47564546784ab3fACA982);
        // Initialize the Eternal Token
        eternal = IEternalToken(_eternal);
    }

/////–––««« Modifiers »»»––––\\\\\
    /**
     * Ensures the contract doesn't swap when it's already swapping (prevents it from getting caught in a circular liquidity event)
     */
    modifier haltsLiquidityProvision() {
        undergoingSwap = true;
        _;
        undergoingSwap = false;
    }

/////–––««« Variable state-inspection functions »»»––––\\\\\

    /**
     * @dev View the address of the ETRNL/AVAX pair on Pangolin
     */
    function viewPair() external view override returns(address) {
        return pangolinPair;
    }

/////–––««« Automatic liquidity provision functions »»»––––\\\\\

    /**
     * @dev Swaps a given amount of ETRNL for AVAX using PangolinDEX. (Used for auto-liquidity swaps)
     * @param amount The amount of ETRNL to be swapped for AVAX
     */
    function swapTokensForAVAX(uint256 amount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = pangolinRouter.WAVAX();

        eternal.approve(address(pangolinRouter), amount);
        pangolinRouter.swapExactTokensForAVAXSupportingFeeOnTransferTokens(amount, 0, path, address(this), block.timestamp);
    }

    /**
     * @dev Provides liquidity to the ETRNL/AVAX pair on pangolin for the EternalToken contract.
     * @param contractBalance The contract's ETRNL balance
     *
     * Requirements:
     * 
     * - Automatic liquidity provision must be enabled
     * - There cannot already be a liquidity swap in progress
     */
    function provideLiquidity(uint256 contractBalance) external override {
        require(_msgSender() == address(eternal), "Only callable by ETRNL contract");
        require(autoLiquidityProvision, "Auto-liquidity is disabled");
        require(!undergoingSwap, "A liquidity swap is in progress");

        _provideLiquidity(contractBalance);
    } 

    /**
     * @dev Converts half the contract's balance to AVAX and adds liquidity to the ETRNL/AVAX pair.
     * @param contractBalance The contract's ETRNL balance
     */
    function _provideLiquidity(uint256 contractBalance) private haltsLiquidityProvision() {
        // Split the contract's balance into two halves
        uint256 half = contractBalance / 2;
        uint256 amountETRNL = contractBalance - half;

        // Capture the initial balance to later compute the difference
        uint256 initialBalance = address(this).balance;
        // Swap half the contract's ETRNL balance to AVAX
        swapTokensForAVAX(half);
        // Compute the amount of AVAX received from the swap
        uint256 amountAVAX = address(this).balance - initialBalance;

        // Add liquidity to the ETRNL/AVAX pair
        eternal.approve(address(pangolinRouter), amountETRNL);
        pangolinRouter.addLiquidityAVAX{value: amountAVAX}(address(this), amountETRNL, 0, 0, address(this), block.timestamp);
        // Update the locked AVAX balance
        lockedAVAXBalance += address(this).balance;

        emit AutomaticLiquidityProvision(amountETRNL, contractBalance, amountAVAX);

        // Stake the LP tokens received
        uint256 amountPGL = pgl.balanceOf(address(this));
        stake(amountPGL);
    }

    /**
     * @dev Transfers locked AVAX that accumulates in the contract over time as a result of dust left over from automatic liquidity provision. (Owner and Fund only)
     * @param recipient The address to which the AVAX is to be sent
     */
    function withdrawLockedAVAX(address payable recipient) external override onlyFund() {
        require(recipient != address(0), "Recipient is the zero address");
        require(lockedAVAXBalance > 0, " Locked AVAX balance is 0");

        // Intermediate variable to prevent re-entrancy attacks
        uint256 amount = lockedAVAXBalance;
        lockedAVAXBalance = 0;
        recipient.transfer(amount);

        emit LockedAVAXTransferred(amount, recipient);
    }

    /**
     * @dev Determines whether the contract should automatically provide liquidity from part of the transaction fees. (Owner and Fund only)
     * @param value True if automatic liquidity provision is desired. False otherwise.
     */
    function setAutoLiquidityProvision(bool value) external override onlyOwnerAndFund() {
        autoLiquidityProvision = value;

        emit AutoLiquidityProvisionUpdated(value);
    }

/////–––««« Staking functions »»»––––\\\\\

    /**
     * @dev Stakes a given amount of PGL 
     */
    function stake(uint256 amount) public override onlyFund() {
        pgl.approve(address(stakingRewards), amount);
        stakingRewards.stake(amount);
        totalStakedPGL += amount;
    }

    /**
     * @dev Claims the PNG earned as a reward for staking lp tokens 
     */
    function claimReward() external override onlyFund() {
        uint256 pngBefore = png.balanceOf(address(this));
        stakingRewards.getReward();
        uint256 pngAfter = png.balanceOf(address(this));

        emit LPRewardsClaimed(pngAfter - pngBefore);
    }

    /**
     * @dev Transfers a given amount of PNG earned as lp-staking reward to a given address
     * @param amount The specified amount of PNG to be sent
     * @param recipient The specified address to send the PNG to
     *
     * Requirements
     *
     * - Amount cannot exceed the contract's total PNG balance
     */
    function withdrawLPReward(uint256 amount, address recipient) external override onlyFund() {
        uint256 pngBalance = png.balanceOf(address(this));
        require(amount <= pngBalance, "Amount exceeds PNG balance");

        png.transfer(recipient, amount);

        emit LPRewardsTransferred(amount, recipient);
    }

    /**
     * @dev Unstakes and transfers a given amount of staked PGL to a given address
     * @param amount The amount of PGL to be unstaked and withdrawn
     * @param recipient The destination to send the PGL to
     *
     * Requirements:
     *
     * - Amount cannot exceed the contract's total staked PGL balance
     */
    function withdrawStakedLP(uint256 amount, address recipient) external override onlyFund() {
        require(amount <= totalStakedPGL, "Amount exceeds staked balance");

        stakingRewards.withdraw(amount);
        totalStakedPGL -= amount;

        emit LPTokensUnstakedAndTransferred(amount, recipient);
    }
}