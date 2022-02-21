//SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "../inheritances/OwnableEnhanced.sol";
import "../interfaces/IEternalFactory.sol";
import "../interfaces/IEternalTreasury.sol";
import "../interfaces/IEternalStorage.sol";
import "../interfaces/ILoyaltyGage.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@traderjoe-xyz/core/contracts/traderjoe/interfaces/IJoeRouter02.sol";
import "@traderjoe-xyz/core/contracts/traderjoe/interfaces/IJoeFactory.sol";
import "@traderjoe-xyz/core/contracts/traderjoe/interfaces/IJoePair.sol";
import "@traderjoe-xyz/core/contracts/traderjoe/interfaces/IWAVAX.sol";

/**
 * @title Contract for the Eternal Treasury
 * @author Nobody (me)
 * @notice The Eternal Treasury contract holds all treasury logic
 */
 contract EternalTreasury is IEternalTreasury, OwnableEnhanced {

/////–––««« Variables: Interfaces, Addresses and Hashes »»»––––\\\\\

    // The Trader Joe router interface
    IJoeRouter02 public immutable joeRouter;
    // The Trader Joe factory interface
    IJoeFactory public immutable joeFactory;
    // The Eternal shared storage interface
    IEternalStorage public immutable eternalStorage;
    // The Eternal factory interface
    IEternalFactory private eternalFactory;
    // The Eternal token interface
    IERC20 private eternal;
    // The keccak256 hash of this contract's address
    bytes32 public immutable entity;

/////–––««« Variables: Hidden Mappings »»»––––\\\\\
/**
    // The amount of ETRNL staked by any given individual user, converted to the "reserve" number space for fee distribution
    mapping (address => uint256) reserveBalances

    // The amount of ETRNL staked by any given individual user, converted to the regular number space (raw number, no fees)
    mapping (address => uint256) stakedBalances

    // The amount of a given asset provided by a user in a liquid gage of said asset
    mapping (address => mapping (address => uint256)) amountProvided

    // The amount of liquidity tokens provided for a given ETRNL/Asset pair
    mapping (address => mapping (address => uint256)) liquidityProvided
*/

/////–––««« Variables: Automatic Liquidity Provision »»»––––\\\\\

    // Determines whether the contract is tasked with providing liquidity using part of the transaction fees
    bytes32 public immutable autoLiquidityProvision;
    // Determines whether an auto-liquidity provision process is undergoing
    bool private undergoingSwap;

/////–––««« Variables: Gaging & Staking »»»––––\\\\\

    // The total number of ETRNL staked by users 
    bytes32 public immutable totalStakedBalances;
    // Used to increase or decrease everyone's accumulated fees
    bytes32 public immutable reserveStakedBalances;
    // The (percentage) fee rate applied to any gage-reward computations not using ETRNL (x 10 ** 5)
    bytes32 public immutable feeRate;

    // Allows contract to receive AVAX tokens
    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

/////–––««« Constructors & Initializers »»»––––\\\\\

    constructor (address _eternalStorage, address _eternal, address _eternalFactory) {
        // Set initial storage, token and factory interfaces
        eternalStorage = IEternalStorage(_eternalStorage);
        eternal = IERC20(_eternal);
        eternalFactory = IEternalFactory(_eternalFactory);

        // Initialize the Trader Joe router and factory
        IJoeRouter02 _joeRouter = IJoeRouter02(0x60aE616a2155Ee3d9A68541Ba4544862310933d4);
        joeRouter = _joeRouter;
        IJoeFactory _joeFactory = IJoeFactory(_joeRouter.factory());
        joeFactory = _joeFactory;

        // Initialize keccak256 hashes
        entity = keccak256(abi.encodePacked(address(this)));
        autoLiquidityProvision = keccak256(abi.encodePacked("autoLiquidityProvision"));
        totalStakedBalances = keccak256(abi.encodePacked("totalStakedBalances"));
        reserveStakedBalances = keccak256(abi.encodePacked("reserveStakedBalances"));
        feeRate = keccak256(abi.encodePacked("feeRate"));
    }

    function initialize(address _fund) external onlyAdmin {
        // Set initial staking balances
        uint256 totalStake = eternal.balanceOf(address(this));
        eternalStorage.setUint(entity, totalStakedBalances, totalStake);
        eternalStorage.setUint(entity, reserveStakedBalances, (totalStake * (10 ** 15)));
        eternalStorage.setUint(entity, keccak256(abi.encodePacked("stakedBalances", address(this))), totalStake);
        eternalStorage.setUint(entity, keccak256(abi.encodePacked("reserveBalances", address(this))), totalStake * (10 ** 15));
        eternalStorage.setBool(entity, autoLiquidityProvision, true);
        
        // Set initial feeRate
        eternalStorage.setUint(entity, feeRate, 500);

        attributeFundRights(_fund);
    }

/////–––««« Modifiers »»»––––\\\\\

    /**
     * Ensures the contract doesn't affect its AVAX balance when swapping (prevents it from getting caught in a circular liquidity event).
     */
    modifier haltsActivity() {
        undergoingSwap = true;
        _;
        undergoingSwap = false;
    }

    /**
     * Reverts if activity is halted (a liquidity swap is in progress)
     */
    modifier activityHalted() {
        require(!undergoingSwap, "A liquidity swap is in progress");
        _;
    }

/////–––««« Variable state-inspection functions »»»––––\\\\\

    /**
     * @notice View the address of the ETRNL/AVAX pair on Trader Joe.
     * @return The address of the ETRNL/AVAX pair
     */
    function viewPair() external view override returns (address) {
        return joeFactory.getPair(joeRouter.WAVAX(), address(eternal));
    }

    /**
     * @notice View whether a liquidity swap is currently in progress.
     * @return True if a liquidity swap is in progress, else false
     */
    function viewUndergoingSwap() external view override returns (bool) {
        return undergoingSwap;
    }

/////–––««« Reserve Utility functions »»»––––\\\\\

    /**
     * @notice Converts a given staked amount to the "reserve" number space.
     * @param amount The specified staked amount
     * @return The reserve number space of the staked amount
     */
    function convertToReserve(uint256 amount) public view override returns (uint256) {
        uint256 currentRate = eternalStorage.getUint(entity, reserveStakedBalances) / eternalStorage.getUint(entity, totalStakedBalances);
        return amount * currentRate;
    }

    /**
     * @notice Converts a given reserve amount to the regular number space (staked).
     * @param reserveAmount The specified reserve amount
     * @return The regular number space value of the reserve amount
     */
    function convertToStaked(uint256 reserveAmount) public view override returns (uint256) {
        uint256 currentRate = eternalStorage.getUint(entity, reserveStakedBalances) / eternalStorage.getUint(entity, totalStakedBalances);
        return reserveAmount / currentRate;
    }

    /**
     * @notice Computes the equivalent of an asset to an other asset and the minimum amount of the two needed to provide liquidity.
     * @param asset The first specified asset, which we want to convert 
     * @param otherAsset The other specified asset
     * @param amountAsset The amount of the first specified asset
     * @param uncertainty The minimum loss to deduct from each minimum in case of price changes
     * @return minOtherAsset The minimum amount of otherAsset needed to provide liquidity (not given if uncertainty = 0)
     * @return minAsset The minimum amount of Asset needed to provide liquidity (not given if uncertainty = 0)
     * @return amountOtherAsset The equivalent in otherAsset of the given amount of asset
     */
    function computeMinAmounts(address asset, address otherAsset, uint256 amountAsset, uint256 uncertainty) public view override returns (uint256 minOtherAsset, uint256 minAsset, uint256 amountOtherAsset) {
        // Get the reserve ratios for the Asset-otherAsset pair
        (uint256 reserveAsset, uint256 reserveOtherAsset) = _fetchPairReserves(asset, otherAsset);
        // Determine a reasonable minimum amount of asset and otherAsset based on current reserves (with a tolerance =  1 / uncertainty)
        amountOtherAsset = joeRouter.quote(amountAsset, reserveAsset, reserveOtherAsset);
        if (uncertainty != 0) {
            minAsset = joeRouter.quote(amountOtherAsset, reserveOtherAsset, reserveAsset);
            minAsset -= minAsset / uncertainty;
            minOtherAsset = amountOtherAsset - (amountOtherAsset / uncertainty);
        }
    }
    
    /**
     * @notice View the liquidity reserves of a given asset pair on Trader Joe.
     * @param asset The first asset of the specified pair
     * @param otherAsset The second asset of the specified pair
     * @return reserveAsset The reserve amount of the first asset
     * @return reserveOtherAsset The reserve amount of the second asset
     */
    function _fetchPairReserves(address asset, address otherAsset) private view returns (uint256 reserveAsset, uint256 reserveOtherAsset) {
        (uint256 reserveA, uint256 reserveB,) = IJoePair(joeFactory.getPair(asset, otherAsset)).getReserves();
        (reserveAsset, reserveOtherAsset) = asset < otherAsset ? (reserveA, reserveB) : (reserveB, reserveA);
    }

    /**
     * @notice Removes liquidity provided by a liquid gage, for a given ETRNL-Asset pair.
     * @param rAsset The address of the specified asset
     * @param providedAsset The amount of the asset which was provided as liquidity
     * @param receiver The address of the liquid gage's receiver
     * @return The amount of ETRNL and Asset obtained from removing liquidity
     */
    function _removeLiquidity(address rAsset, uint256 providedAsset, address receiver) private returns (uint256, uint256) {
        (uint256 minETRNL, uint256 minAsset,) = computeMinAmounts(rAsset, address(eternal), providedAsset, 100);
        uint256 liquidity = eternalStorage.getUint(entity, keccak256(abi.encodePacked("liquidity", receiver, rAsset)));
        require(IERC20(joeFactory.getPair(rAsset, address(eternal))).approve(address(joeRouter), liquidity), "Approve failed");
        return joeRouter.removeLiquidity(address(eternal), rAsset, liquidity, minETRNL/4, minAsset/4, address(this), block.timestamp);
    }

    /**
     * @notice Swaps a given amount of tokens for another
     * @param amountAsset The specified amount of tokens
     * @param asset The address of the asset being swapped
     * @param otherAsset The address of the asset being received
     * @return minOtherAsset The minimum amount of tokens received from the swap with a 1% uncertainty
     */
    function _swapTokens(uint256 amountAsset, address asset, address otherAsset) private returns (uint256 minOtherAsset) {
        address[] memory path = new address[](2);
        path[0] = asset;
        path[1] = otherAsset;

        // Calculate the minimum amount of the other asset to receive (with a tolerance of 1%)
        (uint256 reserveOtherAsset, uint256 reserveAsset) = _fetchPairReserves(otherAsset, asset);
        minOtherAsset = joeRouter.getAmountOut(amountAsset, reserveAsset, reserveOtherAsset);
        minOtherAsset -= minOtherAsset / 100;

        // Swap the asset for the other asset
        require(IERC20(asset).approve(address(joeRouter), amountAsset), "Approve failed");
        if (asset == joeRouter.WAVAX()) {
            joeRouter.swapExactAVAXForTokensSupportingFeeOnTransferTokens{value : amountAsset}(minOtherAsset, path, address(this), block.timestamp);
        } else {
            require(IERC20(asset).approve(address(joeRouter), amountAsset), "Approve failed");
            if (otherAsset == joeRouter.WAVAX()) {
                joeRouter.swapExactTokensForAVAXSupportingFeeOnTransferTokens(amountAsset, minOtherAsset, path, address(this), block.timestamp);
            } else {
                joeRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(amountAsset, minOtherAsset, path, address(this), block.timestamp);
            }
        }
    }

    /**
     * @notice Buys ETRNL using a given gage's fee, computes the earnings from this gage and updates all stakers' balances accordingly.
     * @param eternalRewards The amount of the gage's deposit earned if the gage closed in favor of the treasury
     * @param eternalFee The gaging fee taken from this gage
     * @param rAsset The address of the receiver's deposited asset and of the rewards
     */
    function _distributeFees(uint256 eternalRewards, uint256 eternalFee, address rAsset) private {
        uint256 totalTreasuryBalance = eternalStorage.getUint(entity, totalStakedBalances);
        // Compute the total returns earned through this gage
        uint256 totalEarnings = eternalRewards + _swapTokens(eternalFee, rAsset, address(eternal));
        // Compute the divisor by which we must divide the staked balances
        uint256 divisor = (totalEarnings + totalTreasuryBalance) * (10 ** 18) / totalTreasuryBalance;
        // Dividing the reserve staked balances by (100% + x%) is the equivalent of increasing the true balances by x%
        eternalStorage.setUint(entity, reserveStakedBalances, eternalStorage.getUint(entity, reserveStakedBalances) * (10 ** 18) / divisor);
    }

    /**
     * @notice Adds or subtracts a given amount from the treasury's reserves for a given user.
     * @param user The address of the specified user
     * @param amount The actual amount of ETRNL being subtracted/added to the reserves
     * @param reserveAmount The reserve amount of ETRNL being subtracted/added to the reserves
     * @param add Whether the amount is to be added or subtracted to the reserves
     * 
     * Requirements:
     *
     * - Only callable by Eternal contracts
     */
    function updateReserves(address user, uint256 amount, uint256 reserveAmount, bool add) public override {
        bytes32 sender = keccak256(abi.encodePacked(_msgSender()));
        bytes32 _entity = keccak256(abi.encodePacked(address(eternalStorage)));
        require(_msgSender() == eternalStorage.getAddress(_entity, sender), "msg.sender must be from Eternal");
        _updateReserves(user, amount, reserveAmount, add);
    }

    /**
     * @notice Adds or subtracts a given amount from the treasury's reserves for a given user.
     * @param user The address of the specified user
     * @param amount The actual amount of ETRNL being subtracted/added to the reserves
     * @param reserveAmount The reserve amount of ETRNL being subtracted/added to the reserves
     * @param add Whether the amount is to be added or subtracted to the reserves
     */
    function _updateReserves(address user, uint256 amount, uint256 reserveAmount, bool add) private {
        bytes32 reserveBalances = keccak256(abi.encodePacked("reserveBalances", user));
        bytes32 stakedBalances = keccak256(abi.encodePacked("stakedBalances", user));
        if (add) {
            eternalStorage.setUint(entity, reserveBalances, eternalStorage.getUint(entity, reserveBalances) + reserveAmount);
            eternalStorage.setUint(entity, stakedBalances, eternalStorage.getUint(entity, stakedBalances) + amount);
            eternalStorage.setUint(entity, reserveStakedBalances, eternalStorage.getUint(entity, reserveStakedBalances) + reserveAmount);
            eternalStorage.setUint(entity, totalStakedBalances, eternalStorage.getUint(entity, totalStakedBalances) + amount);
        } else {
            // Reward user with percentage of fees proportional to the amount he is withdrawing
            reserveAmount = amount * eternalStorage.getUint(entity, reserveBalances) / eternalStorage.getUint(entity, stakedBalances);
            eternalStorage.setUint(entity, reserveBalances, eternalStorage.getUint(entity, reserveBalances) - reserveAmount);
            eternalStorage.setUint(entity, stakedBalances, eternalStorage.getUint(entity, stakedBalances) - amount);
            eternalStorage.setUint(entity, reserveStakedBalances, eternalStorage.getUint(entity, reserveStakedBalances) - reserveAmount);
            eternalStorage.setUint(entity, totalStakedBalances, eternalStorage.getUint(entity, totalStakedBalances) - amount);
        }
    }

/////–––««« Gage-logic functions »»»––––\\\\\

    /**
     * @notice Funds a given liquidity gage with ETRNL, provides liquidity using ETRNL and the receiver's asset and transfers a bonus to the receiver.
     * @param gage The address of the specified liquidity gage
     * @param receiver The address of the receiver
     * @param asset The address of the asset provided by the receiver
     * @param userAmount The amount of the asset provided by the receiver
     * @param rRisk The treasury's (distributor) risk percentage 
     * @param dRisk The receiver's bonus percentage
     * 
     * Requirements:
     *
     * - Only callable by the Eternal Platform
     */
    function fundEternalLiquidGage(address gage, address receiver, address asset, uint256 userAmount, uint256 rRisk, uint256 dRisk) external payable override {
        // Checks
        require(_msgSender() == address(eternalFactory), "msg.sender must be the platform");

        // Compute minimum amounts and the amount of ETRNL needed to provide liquidity
        uint256 providedETRNL;
        uint256 providedAsset;
        uint256 liquidity;
        (uint256 minETRNL, uint256 minAsset, uint256 amountETRNL) = computeMinAmounts(asset, address(eternal), userAmount, 100);
        
        // Add liquidity to the ETRNL/Asset pair
        require(eternal.approve(address(joeRouter), amountETRNL), "Approve ETRNL failed");
        if (asset == joeRouter.WAVAX() && msg.value > 0) {
            (providedETRNL, providedAsset, liquidity) = joeRouter.addLiquidityAVAX{value: msg.value}(address(eternal), amountETRNL, minETRNL, minAsset, address(this), block.timestamp);
        } else {
            require(IERC20(asset).approve(address(joeRouter), userAmount), "Approve asset failed");
            (providedETRNL, providedAsset, liquidity) = joeRouter.addLiquidity(address(eternal), asset, amountETRNL, userAmount, minETRNL, minAsset, address(this), block.timestamp);
        }
        
        // Save the true amount provided as liquidity by the receiver and the actual liquidity amount
        eternalStorage.setUint(entity, keccak256(abi.encodePacked("amountProvided", receiver, asset)), providedAsset);
        eternalStorage.setUint(entity, keccak256(abi.encodePacked("liquidity", receiver, asset)), liquidity);
        
        // Initialize the liquid gage, update the treasury's reserves and transfer the user's instant reward
        ILoyaltyGage(gage).initialize(asset, address(eternal), userAmount, providedETRNL, rRisk, dRisk);
        {
            uint256 outflownETRNL = providedETRNL + (providedETRNL * dRisk / (10 ** 4));
            _updateReserves(address(this), outflownETRNL, convertToReserve(outflownETRNL), false);
        }
        require(eternal.transfer(receiver, providedETRNL * dRisk / (10 ** 4)), "Failed to transfer bonus");
    }

    /**
     * @notice Settles a given ETRNL liquid gage.
     * @param winner Whether the gage closed in favor of the receiver or not
     * @param gageAddress The address of the specified liquid gage
     * @param receiver The address of the receiver for this liquid gage
     * @return eternalRewards The amount of the gage's deposit earned if the gage closed in favor of the treasury
     * @return eternalFee The gaging fee taken from this gage
     * @return rAsset The address of the receiver's deposited asset
     */
    function _settleLiquidGage(bool winner, address gageAddress, address receiver) private returns (uint256, uint256, address) {
        // Fetch the liquid gage data
        (address rAsset,, uint256 rRisk) = ILoyaltyGage(gageAddress).viewUserData(receiver);
        (,uint256 dAmount, uint256 dRisk) = ILoyaltyGage(gageAddress).viewUserData(address(this));
        uint256 providedAsset = eternalStorage.getUint(entity, keccak256(abi.encodePacked("amountProvided", receiver, rAsset)));

        // Remove the liquidity for this gage
        (uint256 amountETRNL, uint256 amountAsset) = _removeLiquidity(rAsset, providedAsset, receiver);

        // Compute and transfer the net gage deposit + any rewards due to the receiver
        uint256 eternalRewards = amountETRNL > dAmount ? amountETRNL - dAmount : 0;
        uint256 eternalFee = eternalStorage.getUint(entity, feeRate) * amountAsset / (10 ** 5);
        if (winner) {
            // Update the treasury's reserves
            _updateReserves(address(this), amountETRNL * dRisk / (10 ** 4), convertToReserve(amountETRNL * dRisk / (10 ** 4)), false);
            // Transfer the user's second bonus
            require(eternal.transfer(receiver, amountETRNL * dRisk / (10 ** 4)), "Failed to transfer ETRNL reward");
            // Compute the net liquidity rewards left to distribute to stakers
            //solhint-disable-next-line reentrancy
            eternalRewards -= eternalRewards * dRisk / (10 ** 4);
        } else {
            // Update the treasury's reserves
            uint256 amountReceived = eternalRewards == 0 ? amountETRNL : dAmount;
             _updateReserves(address(this), amountReceived, convertToReserve(amountReceived), true);
            // Compute the net liquidity rewards + gage deposit left to distribute to staker
            //solhint-disable-next-line reentrancy
            eternalFee += amountAsset * rRisk / (10 ** 4);
        }
        if (rAsset != joeRouter.WAVAX()) {
            require(IERC20(rAsset).transfer(receiver, amountAsset - eternalFee), "Failed to transfer ERC20 reward");
        } else {
            IWAVAX(rAsset).withdraw(amountAsset);
            (bool success, ) = payable(receiver).call{value: amountAsset - eternalFee}("");
            require(success, "Failed to transfer AVAX reward");
        }
        // Update the receiver's liquid gage limit
        eternalStorage.setBool(keccak256(abi.encodePacked(address(eternalFactory))), keccak256(abi.encodePacked("inLiquidGage", receiver, rAsset)), false);

        return (eternalRewards, eternalFee, rAsset);
    }

    /**
     * @notice Settles a given ETRNL gage.
     * @param receiver The address of the receiver
     * @param id The id of the specified gage
     * @param winner Whether the gage closed in favor of the receiver or not
     *
     * Requirements:
     *
     * - Only callable by an Eternal-deployed gage
     */
    function settleGage(address receiver, uint256 id, bool winner) external override activityHalted {
        // Checks
        bytes32 factory = keccak256(abi.encodePacked(address(eternalFactory)));
        address gageAddress = eternalStorage.getAddress(factory, keccak256(abi.encodePacked("gages", id)));
        require(_msgSender() == gageAddress, "msg.sender must be the gage");

        // Compute/Distribute rewards and take fees for the gage
        (uint256 eternalRewards, uint256 eternalFee, address rAsset) = _settleLiquidGage(winner, gageAddress, receiver);

        // Update staker's fees w.r.t the gage fee, gage rewards and liquidity rewards and buy ETRNL with the fee
        // Fees and rewards are both calculated in terms of ETRNL
        _distributeFees(eternalRewards, eternalFee, rAsset);
    }

/////–––««« Staking-logic functions »»»––––\\\\\

    /**
     * @notice Stakes a given amount of ETRNL into the treasury.
     * @param amount The specified amount of ETRNL being staked
     * 
     * Requirements:
     * 
     * - Staked amount must be greater than 0
     */
    function stake(uint256 amount) external override {
        require(amount > 0, "Amount must be greater than 0");

        require(eternal.transferFrom(_msgSender(), address(this), amount), "Transfer failed");

        // Update user/total staked and reserve balances
        _updateReserves(_msgSender(), amount, convertToReserve(amount), true);
    }

    /**
     * @notice Unstakes a user's given amount of ETRNL and transfers the user's accumulated rewards proportional to that amount (in ETRNL).
     * @param amount The specified amount of ETRNL being unstaked
     * 
     * Requirements:
     *
     * - Amount being unstaked cannot be greater than the user's staked balance
     */
    function unstake(uint256 amount) external override {
        bytes32 stakedBalances = keccak256(abi.encodePacked("stakedBalances", _msgSender()));
        uint256 stakedBalance = eternalStorage.getUint(entity, stakedBalances);
        require(amount <= stakedBalance , "Amount exceeds staked balance");
     
        bytes32 reserveBalances = keccak256(abi.encodePacked("reserveBalances", _msgSender()));
        uint256 reserveBalance = eternalStorage.getUint(entity, reserveBalances);
        // Reward user with percentage of fees proportional to the amount he is withdrawing
        uint256 reserveAmount = amount * reserveBalance / stakedBalance;
        // Update user/total staked and reserve balances
        _updateReserves(_msgSender(), amount, reserveAmount, false);

        require(eternal.transfer(_msgSender(), convertToStaked(reserveAmount)), "Transfer failed");
    }

/////–––««« Automatic liquidity provision functions »»»––––\\\\\

    /**
     * @notice Provides liquidity to the ETRNL/AVAX pair on Trader Joe for the EternalToken contract.
     * @param contractBalance The contract's ETRNL balance
     *
     * Requirements:
     * 
     * - There cannot already be a liquidity swap in progress
     * - Automatic liquidity provision must be enabled
     * - Caller can only be the Eternal Token contract
     */
    function provideLiquidity(uint256 contractBalance) external override activityHalted {
        require(_msgSender() == address(eternal), "Only callable by ETRNL contract");
        require(eternalStorage.getBool(entity, autoLiquidityProvision), "Auto-liquidity is disabled");

        _provideLiquidity(contractBalance);
    } 

    /**
     * @notice Converts half the contract's balance to AVAX and adds liquidity to the ETRNL/AVAX pair.
     * @param contractBalance The contract's ETRNL balance
     */
    function _provideLiquidity(uint256 contractBalance) private haltsActivity {
        // Split the contract's balance into two halves
        uint256 amountETRNL = contractBalance - (contractBalance / 2);
        // Capture the initial balance to later compute the difference
        uint256 initialBalance = address(this).balance;
        // Swap half the contract's ETRNL balance to AVAX
        _swapTokens(amountETRNL, address(eternal), joeRouter.WAVAX());
        // Compute the amount of AVAX received from the swap
        uint256 amountAVAX = address(this).balance - initialBalance;
        uint256 minAVAX;
        uint256 minETRNL;
        // Determine a reasonable minimum amount of ETRNL and AVAX
        (minAVAX, minETRNL, amountAVAX) = computeMinAmounts(address(eternal), joeRouter.WAVAX(), amountETRNL, 100);
        eternal.approve(address(joeRouter), amountETRNL);
        // Add the liquidity and update the total liquidity tracker
        (,,uint256 liquidity) = joeRouter.addLiquidityAVAX{value: amountAVAX}(address(eternal), amountETRNL, minETRNL, minAVAX, address(this), block.timestamp);
        bytes32 totalLiquidity = keccak256(abi.encodePacked("liquidityProvided", address(this), joeRouter.WAVAX()));
        uint256 currentLiquidity = eternalStorage.getUint(entity, totalLiquidity);
        eternalStorage.setUint(entity, totalLiquidity, currentLiquidity + liquidity);
    }

/////–––««« Fund-only functions »»»––––\\\\\

    /**
     * @notice Transfers a given amount of AVAX from the contract to an address. (Fund only)
     * @param recipient The address to which the AVAX is to be sent
     * @param amount The specified amount of AVAX to transfer
     * 
     * Requirements:
     * 
     * - Only callable by the Eternal Fund
     * - A liquidity swap should not be in progress
     * - The contract's balance must have enough funds to accomodate the withdrawal
     */
    function withdrawAVAX(address recipient, uint256 amount) external override onlyFund activityHalted {
        require(amount < address(this).balance, "Insufficient balance");

        emit AVAXTransferred(amount, recipient);
        (bool success, ) = payable(recipient).call{value: amount}("");
        require(success, "Failed to transfer AVAX");
    }

    /**
     * @notice Transfers a given amount of a token from the contract to an address. (Fund only)
     * @param asset The address of the asset being withdrawn
     * @param recipient The address to which the ETRNL is to be sent
     * @param amount The specified amount of ETRNL to transfer
     *
     * Requirements:
     *
     * - Only callable by the Eternal Fund
     */
    function withdrawAsset(address asset, address recipient, uint256 amount) external override onlyFund {
        emit AssetTransferred(asset, amount, recipient);
        require(IERC20(asset).transfer(recipient, amount), "Asset withdrawal failed");
    }

    /**
     * @notice Updates the address of the Eternal Factory contract.
     * @param newContract The new address for the Eternal Factory contract
     *
     * Requirements:
     *
     * - Only callable by the Eternal Fund
     */
    function setEternalFactory(address newContract) external onlyFund {
        eternalFactory = IEternalFactory(newContract);
    }

    /**
     * @notice Updates the address of the Eternal Token contract.
     * @param newContract The new address for the Eternal Token contract
     *
     * Requirements:
     *
     * - Only callable by the Eternal Fund
     */
    function setEternalToken(address newContract) external onlyFund {
        eternal = IERC20(newContract);
    }
 }