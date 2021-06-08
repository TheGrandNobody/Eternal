//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "./interfaces/IEternalTokenV0.sol";
import "@pangolindex/exchange-contracts/contracts/pangolin-core/interfaces/IPangolinFactory.sol";
import "@pangolindex/exchange-contracts/contracts/pangolin-periphery/interfaces/IPangolinRouter.sol";

/**
 * @title Contract for the Eternal Token (ETRNL)
 * @author Nobody (credits to OpenZeppelin for the IERC20 and IERC20Metadata interfaces)
 * @notice The Eternal Token contract holds all the deflationary, burn, reflect, funding and auto-liquidity provision mechanics
 */
contract EternalTokenV0 is Context, IERC20, IERC20Metadata, IEternalTokenV0, Ownable {

    // Keeps track of how much an address allows any other address to spend on its behalf
    mapping (address => mapping (address => uint64)) private allowances;
    // The reflected balances used to track reward-accruing users' total balances
    mapping (address => uint256) private reflectedBalances;
    // The true balances used to track non-reward-accruing addresses' total balances
    mapping (address => uint64) private trueBalances;
    // Keeps track of whether an address is excluded from rewards
    mapping (address => bool) private isExcludedFromRewards;
    // Keeps track of whether an address is excluded from transfer fees
    mapping (address => bool) private isExcludedFromFees;

    // Keeps track of all reward-excluded addresses
    address[] private excludedAddresses;

    // Determines whether an auto-liquidity provision process is undergoing
    bool private undergoingSwap;
    // Determines whether the contract should provide liquidity using part of the transaction fees
    bool private autoLiquidityProvision;

    // Keeps track of accumulated, locked AVAX as a result of automatic liquidity provision
    uint256 private lockedAVAXBalance;
    // The total ETRNL supply after taking reflections into account
    uint256 private totalReflectedSupply;
    // The true total ETRNL supply 
    uint64 private totalTokenSupply = (10**10) * (10**9);
    // Threshold at which the contract swaps its ETRNL balance to provide liquidity (0.1% of total supply by default)
    uint64 private tokenLiquidityThreshold = totalTokenSupply / 1000;
    // The percentage of the total fee rate used to auto-lock liquidity
    uint8 private liquidityProvisionRate;
    // The percentage of the total fee rate stored in the EternalFund
    uint8 private fundingRate;
    // The percentage of the total fee rate that is burned
    uint8 private burnRate;
    // The percentage of the total fee rate redistributed to holders
    uint8 private redistributionRate;

    // PangolinDex Router interface to swap tokens for AVAX and add liquidity
    IPangolinRouter internal immutable pangolinRouter;
    // The address of the ETRNL/AVAX pair
    address internal immutable pangolinPair;

    modifier haltLiquidityProvision {
        undergoingSwap = true;
        _;
        undergoingSwap = false;
    }

    /**
     * @dev Sets the token ticker and token name. Mints the total supply to the contract deployer.
     */
    constructor () {

        // The largest possible number in a 256-bit integer
        uint256 max = ~uint256(0);

        // Initialize name, ticker symbol and total supply
        totalReflectedSupply = (max - (max % totalTokenSupply));
        reflectedBalances[_msgSender()] = totalTokenSupply;

        // Create pair address
        IPangolinRouter _pangolinRouter = IPangolinRouter(0xE54Ca86531e17Ef3616d22Ca28b0D458b6C89106);
        pangolinPair = IPangolinFactory(_pangolinRouter.factory()).createPair(address(this), _pangolinRouter.WAVAX());

        // Initialize Pangolin Router
        pangolinRouter = _pangolinRouter;

        // Exclude the owner from rewards and fees
        excludeFromReward(owner());
        isExcludedFromFees[owner()] = true;

        // Exclude this contract from rewards and fees
        excludeFromReward(address(this));
        isExcludedFromFees[address(this)] = true;

        // Exclude the burn address from rewards
        isExcludedFromRewards[address(0)];
    }

    /**
     * @dev The name of the token. 
     * @return The token name
     */
    function name() external pure override returns (string memory) {
        return "Eternal Token";
    }

    /**
     * @dev View the token ticker
     * @return The token symbol
     */
    function symbol() external pure override returns (string memory) {
        return "ETRNL";
    }

    /**
     * @dev View the maximum number of decimals for the Eternal token
     * @return The number of decimals
     */
    function decimals() external pure override returns (uint8) {
        return 9;
    }
    
    /**
     * @dev View the total supply of the Eternal token.
     * @return Returns the total ETRNL supply.
     */
    function totalSupply() external view override returns (uint64){
        return totalTokenSupply;
    }

    /**
     * @dev Sets the value of a given rate of a given rate type (Owner only)
     * @param newRate The specified new rate value
     * @param rate The type of the specified rate
     *
     * Requirements:
     *
     * - Rate type must be either Liquidity, Funding, Redistribution or Burn
     * - Rate value must be positive
     * - The sum of all rates cannot exceed 25 percent
     */
    function setRate(uint8 newRate, Rate rate) external onlyOwner {
        require((uint8(rate) >= 0 && uint8(rate) <= 3), "EternalTokenV0::setRate(): Invalid rate type");
        require(newRate >= 0, "EternalTokenV0::setRate(): The new rate must be positive.");

        uint8 oldRate;

        if (rate == Rate.Liquidity) {
            require((newRate + fundingRate + redistributionRate + burnRate) < 25, "EternalTokenV0::setRate(): Total rate exceeds 25%");
            oldRate = liquidityProvisionRate;
            liquidityProvisionRate = newRate;
        } else if (rate == Rate.Funding) {
            require((liquidityProvisionRate + newRate + redistributionRate + burnRate) < 25, "EternalTokenV0::setRate(): Total rate exceeds 25%");
            oldRate = fundingRate;
            fundingRate = newRate;
        } else if (rate == Rate.Redistribution) {
            require((liquidityProvisionRate + fundingRate + newRate + burnRate) < 25, "EternalTokenV0::setRate(): Total rate exceeds 25%");
            oldRate = redistributionRate;
            redistributionRate = newRate;
        } else {
            require((liquidityProvisionRate + fundingRate + redistributionRate + newRate) < 25, "EternalTokenV0::setRate(): Total rate exceeds 25%");
            oldRate = burnRate;
            burnRate = newRate;
        }

        emit UpdateRate(oldRate, newRate, rate);
    }

    /**
     * @dev Determines whether the contract should automatically provide liquidity from part of the transaction fees. (Owner only)
     * @param value True if automatic liquidity provision is desired. False otherwise.
     */
    function setAutoLiquidityProvision(bool value) external onlyOwner {
        autoLiquidityProvision = value;
        emit AutoLiquidityProvisionUpdated(value);
    }

    /**
     * @dev View the balance of a given user's address.
     * @param account The address of the user
     * @return The balance of the account
     */
    function balanceOf(address account) public view override returns (uint64){
        if (isExcludedFromRewards[account]) {
            return trueBalances[account];
        }
        return convertFromReflectedToTrueAmount(reflectedBalances[account]);
    }

    /**
     * @dev View the allowance of a given owner address for a given spender address.
     * @param owner The address of whom we are checking the allowance of
     * @param spender The address of whom we are checking the allowance for
     * @return The allowance of the owner for the spender
     */
    function allowance(address owner, address spender) external view override returns (uint64){
        return allowances[owner][spender];
    }
    
    /**
     * @dev View whether a given wallet or contract's address is excluded from transaction fees.
     * @param account The wallet or contract's address
     * @return Whether the account is excluded from transaction fees.
     */
    function isExcludedFromFee(address account) external view returns (bool) {
        return isExcludedFromFees[account];
    }

    /**
     * @dev View whether a given wallet or contract's address is excluded from rewards.
     * @param account The wallet or contract's address
     * @return Whether the account is excluded from rewards.
     */
    function isExcludedFromReward(address account) external view returns (bool) {
        return isExcludedFromRewards[account];
    }
    
    /**
     * @dev Excludes a given wallet or contract's address from accruing rewards. (Owner only)
     * @param account The wallet or contract's address
     *
     * Requirements:
     * – Account must not already be excluded from rewards.
     */
    function excludeFromReward(address account) public onlyOwner() {
        require(!isExcludedFromRewards[account], "EternalTokenV0::excludeFromReward(): Account is already excluded");
        if(reflectedBalances[account] > 0) {
            // Compute the true token balance from non-empty reflected balances and update it
            // since we must use both reflected and true balances to make our reflected-to-total ratio even
            trueBalances[account] =  convertFromReflectedToTrueAmount(reflectedBalances[account]);
        }
        isExcludedFromRewards[account] = true;
        excludedAddresses.push(account);
    }

    /**
     * @dev Allows a given wallet or contract's address to accrue rewards. (Owner only)
     * @param account The wallet or contract's address
     *
     * Requirements:
     * – Account must not already be accruing rewards.
     */
    function includeInReward(address account) external onlyOwner() {
        require(isExcludedFromRewards[account], "EternalTokenV0::includeInReward(): Account is already included");
        for (uint32 i = 0; i < excludedAddresses.length; i++) {
            if (excludedAddresses[i] == account) {
                // Swap last address with current address we want to include so that we can delete it
                excludedAddresses[i] = excludedAddresses[excludedAddresses.length - 1];
                // Set its deposit liabilities to 0 since we use the reserve balance for reward-accruing addresses
                trueBalances[account] = 0;
                excludedAddresses.pop();
                isExcludedFromRewards[account] = false;
                break;
            }
        }
    }
    
    /**
     * @dev Increases the allowance for a given spender address by a given amount.
     * @param spender The address whom we are increasing the allowance for
     * @param addedValue The amount by which we increase the allowance
     * @return True if the increase in allowance is successful
     */
    function increaseAllowance(address spender, uint64 addedValue) external virtual returns (bool) {
        _approve(_msgSender(), spender, (allowances[_msgSender()][spender] + addedValue));
        return true;
    }
    
    /**
     * @dev Decreases the allowance for a given spender address by a given amount.
     * @param spender The address whom we are decrease the allowance for
     * @param subtractedValue The amount by which we decrease the allowance
     * @return True if the decrease in allowance is successful
     */
    function decreaseAllowance(address spender, uint64 subtractedValue) external virtual returns (bool) {
        _approve(_msgSender(), spender, (allowances[_msgSender()][spender] - subtractedValue));
        return true;
    }
    
    /**
     * @dev Translates a given amount of ETRNL into its reflected sum variant (with the transfer fee deducted if specified).
     * @param amount The specified amount of ETRNL
     * @param deductTransferFee Boolean – True if we deduct the transfer fee from the reflected sum variant. False otherwise.
     * @return The reflected amount proportional to the given amount of ETRNL if False, else the fee-adjusted variant of said reflected amount
     *
     * Requirements:
     * 
     * - Given ETRNL amount cannot be greater than the total token supply
     */
    function convertFromTrueToReflectedAmount(uint64 amount, bool deductTransferFee) public view returns(uint256) {
        require(amount <= totalTokenSupply, "EternalTokenV0::convertFromTrueToReflectedAmount(): Amount must be less than total token supply");
        if (!deductTransferFee) {
            (uint256 reflectedAmount,,,) = getValues(amount);
            return reflectedAmount;
        } else {
            (,uint256 netReflectedTransferAmount,,) = getValues(amount);
            return netReflectedTransferAmount;
        }
    }

    /**
     * @dev Translates a given reflected sum of ETRNL into the true amount of ETRNL it represents based on the current reserve rate.
     * @param reflectedAmount The specified reflected sum of ETRNL
     * @return The true amount of ETRNL representing by its reflected amount
     * Requirements:
     * 
     * - Given reflected ETRNL amount cannot be greater than the total reflected token supply
     */
    function convertFromReflectedToTrueAmount(uint256 reflectedAmount) public view returns(uint64) {
        require(reflectedAmount <= totalReflectedSupply, "EternalTokenV0::convertFromReflectedToTrueAmount(): Amount must be less than total reflected supply");
        uint256 currentRate =  getReflectionRate();
        return reflectedAmount / currentRate;
    }

    /**
     * @dev Compute the reflected and net reflected transferred amounts and the net transferred amount from a given amount of ETRNL
     * @param trueAmount The specified amount of ETRNL
     * @return The reflected amount, the net reflected transfer amount, the actual net transfer amount, and the total reflected fees
     */
    function getValues(uint64 trueAmount) private view returns (uint256, uint256, uint64) {

        // Calculate the total fees and transfered amount after fees
        uint64 totalFees = (trueAmount * (liquidityProvisionRate + burnRate + fundingRate + redistributionRate)) / 100;
        uint64 netTransferAmount = trueAmount - totalFees;

        // Calculate the reflected amount, reflected total fees and reflected amount after fees
        uint256 currentRate = getReflectionRate();
        uint256 reflectedAmount = trueAmount * currentRate;
        uint256 reflectedTotalFees = totalFees * currentRate;
        uint256 netReflectedTransferAmount = reflectedAmount - reflectedTotalFees;
        
        return (reflectedAmount, netReflectedTransferAmount, netTransferAmount);
    }

    /**
     * @dev Computes the current rate used to inter-convert from the mathematically reflected space to the "true" or total space
     * @return The ratio of net reflected ETRNL to net total ETRNL
     */
    function getReflectionRate() private view returns(uint256) {
        (uint256 netReflectedSupply, uint64 netTokenSupply) = getNetSupplies();
        return netReflectedSupply / netTokenSupply;
    }

    /**
     * @dev Computes the net reflected and total token supplies (adjusted for non-reward-accruing accounts)
     * @return The adjusted reflected supply and adjusted total token supply
     */
    function getNetSupplies() private view returns(uint256, uint64) {
        uint256 netReflectedSupply = totalReflectedSupply;
        uint64 netTokenSupply = totalTokenSupply;  

        for (uint32 i = 0; i < excludedAddresses.length; i++) {
            // Failsafe for non-reward-accruing accounts owning too many tokens (highly unlikely; nonetheless possible)
            if (reflectedBalances[excludedAddresses[i]] > netReflectedSupply || trueBalances[excludedAddresses[i]] > netTokenSupply) {
                return (totalReflectedSupply, totalTokenSupply);
            }
            // Subtracting each excluded account from both supplies yields the adjusted supplies
            netReflectedSupply -= reflectedBalances[excludedAddresses[i]];
            netTokenSupply -= trueBalances[excludedAddresses[i]];
        }
        // In case there are no tokens left in circulation for reward-accruing accounts
        if (netTokenSupply == 0 || netReflectedSupply < (totalReflectedSupply / totalTokenSupply)){
            return (totalReflectedSupply, totalTokenSupply);
        }

        return (netReflectedSupply, netTokenSupply);
    }

    /**
     * @dev Tranfers a given amount of ETRNL to a given receiver address.
     * @param recipient The destination to which the ETRNL are to be transferred
     * @param amount The amount of ETRNL to be transferred
     * @return True if the transfer is successful.
     */
    function transfer(address recipient, uint64 amount) external override returns (bool){
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /**
     * @dev Sets the allowance for a given address to a given amount.
     * @param spender The address of whom we are changing the allowance for
     * @param amount The amount we are changing the allowance to
     * @return True if the approval is successful.
     */
    function approve(address spender, uint64 amount) external override returns (bool){
        _approve(_msgSender(), spender, amount);
        return true;
    }

    /**
     * @dev Transfers a given amount of ETRNL for a given sender address to a given recipient address.
     * @param sender The address whom we withdraw the ETRNL from
     * @param recipient The address which shall receive the ETRNL
     * @param amount The amount of ETRNL which is being transferred
     * @return True if the transfer and approval are both successful.
     *
     * Requirements:
     * 
     * - The caller must be allowed to spend (at least) the given amount on the sender's behalf
     */
    function transferFrom(address sender, address recipient, uint64 amount) external override returns (bool) {
        _transfer(sender, recipient, amount);

        uint64 currentAllowance = allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "EternalTokenV0::transferFrom(): Transfer amount exceeds allowance");
        _approve(sender, _msgSender(), currentAllowance - amount);

        return true;
    }

    /**
     * @dev Sets the allowance of a given owner address for a given spender address to a given amount.
     * @param owner The adress of whom we are changing the allowance of
     * @param spender The address of whom we are changing the allowance for
     * @param amount The amount which we change the allowance to
     *
     * Requirements:
     * 
     * - Approve amount must be less than or equal to the actual total token supply
     * - Owner and spender cannot be the zero address
     */
    function _approve(address owner, address spender, uint64 amount) private {
        require(amount <= totalTokenSupply, "EternalTokenV0::_approve(): Cannot approve more than the total supply");
        require(owner != address(0), "EternalTokenV0::_approve(): Approve from the zero address");
        require(spender != address(0), "EternalTokenV0::_approve(): Approve to the zero address");

        allowances[owner][spender] = amount;

        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Transfers a given amount of ETRNL from a given sender's address to a given recipient's address.
     * Bottleneck for what transfer equation to use.
     * @param sender The address of whom the ETRNL will be transferred from
     * @param recipient The address of whom the ETRNL will be transferred to
     * @param amount The amount of ETRNL to be transferred
     * 
     * Requirements:
     * 
     * - Sender or recipient cannot be the zero address
     * - Transferred amount must be greater than zero
     */
    function _transfer(address sender, address recipient, uint64 amount) private {
        require(sender != address(0), "EternalTokenV0::_transfer(): Transfer from the zero address");
        require(recipient != address(0), "EternalTokenV0::_transfer(): Transfer to the zero address");
        require(amount > 0, "EternalTokenV0::_transfer(): Transfer amount must be greater than zero");

        (uint256 reflectedAmount, uint256 netReflectedTransferAmount, uint64 netTransferAmount) = getValues(amount);

        // Always update the reflected balances of sender and recipient
        reflectedBalances[sender] -= reflectedAmount;
        reflectedBalances[recipient] += netReflectedTransferAmount;

        // Update true balances for any non-reward-accruing accounts 
        trueBalances[sender] = isExcludedFromRewards[sender] ? (trueBalances[sender] - amount) : trueBalances[sender]; 
        trueBalances[recipient] = isExcludedFromRewards[recipient] ? (trueBalances[recipient] + netTransferAmount) : trueBalances[recipient]; 

        // Adjust the total reflected supply for the new fees
        // If the sender or recipient are excluded from fees, we ignore the fee altogether
        if (!isExcludedFromFees[sender] && !isExcludedFromFees[recipient]) {
            // Perform a burn based on the burn rate 
            _burn(address(this), amount * burnRate / 100, reflectedAmount * burnRate / 100);
            // Redistribute based on the redistribution rate 
            totalReflectedSupply -= reflectedAmount * redistributionRate / 100;
            // Store ETRNL away in the EternalFund based on the funding rate
            storeFunds(reflectedAmount * fundingRate / 100);
            // Provide liqudity to the ETRNL/AVAX pair on Pangolin based on the liquidity provision rate
            storeLiquidityFunds(amount, reflectedAmount);
        }

        emit Transfer(sender, recipient, netTransferAmount);
    }

    /**
     * @dev Updates the contract's balance regarding the liquidity provision fee for a given transaction's amount.
     * If the contract's balance threshold is reached, also initiates automatic liquidity provision.
     * @param sender The address of whom the ETRNL is being transferred from
     * @param amount The amount of ETRNL being transferred
     * @param reflectedAmount The reflected amount of ETRNL being transferred
     */
    function storeLiquidityFunds(address sender, uint64 amount, uint256 reflectedAmount) private {
        // Update the contract's balance to account for the liquidity provision fee
        reflectedBalances[address(this)] += reflectedAmount * liquidityProvisionRate / 100;
        trueBalances[address(this)] += amount * liquidityProvisionRate / 100;
        
        // Check whether the contract's balance threshold is reached; if so, initiate a liquidity swap
        uint64 contractBalance = balanceOf(address(this));
        if (contractBalance >= tokenLiquidityThreshold) {
            provideLiquidity(sender, contractBalance);
        }
    }

    /**
     * @dev Provides liquidity to the ETRNL/AVAX pair on pangolin.
     * @param sender The address of the account transferring ETRNL for the specific transaction where this method was called
     * @param contractBalance The contract's ETRNL balance
     *
     * Requirements:
     * 
     * - Automatic liquidity provision must be enabled
     * - There cannot already be a liquidity swap in progress
     * - The sender address cannot be the ETRNL/AVAX pangolin pair address
     */
    function provideLiquidity(address sender, uint64 contractBalance) private {
        require(autoLiquidityProvision, "EternalTokenV0::provideLiquidity(): Automatic liquidity provision is disabled");
        require(!undergoingSwap, "EternalTokenV0::provideLiquidity(): A liquidity swap is already in progress");
        require(sender != pangolinPair, "EternalTokenV0::provideLiquidity(): Sender cannot be the pair address");

        _provideLiquidity(contractBalance);
    }

    /**
     * @dev Converts half the contract's balance to AVAX and adds liquidity to the ETRNL/AVAX pair.
     * @param contractBalance The contract's ETRNL balance
     */
    function _provideLiquidity(uint64 contractBalance) private haltLiquidityProvision {
        // Split the contract's balance into two halves
        uint64 half = contractBalance / 2;
        uint64 amountETRNL = contractBalance - half;

        // Capture the initial balance to later compute the difference
        uint64 initialBalance = address(this).balance;
        // Swap half the contract's ETRNL balance to AVAX
        swapTokensForAVAX(half);
        // Compute the amount of AVAX received from the swap
        uint64 amountAVAX = address(this).balance - initialBalance;

        addLiquidity(amountETRNL, contractBalance, amountAVAX);
    }

    /**
     * @dev Sends a given amount of ETRNL to the Eternal Fund.
     * @param amount The specified amount of ETRNL
     * @param reflectedAmount The reflected specified amount of ETRNL
     */
    function storeFunds(uint64 amount, uint256 reflectedAmount) private {
        
    }
    
    /**
     * @dev Burns a given amount of ETRNL.
     * @param amount The amount of ETRNL being burned
     * @return True if the burn is successful
     *
     * Requirements:
     * 
     * - Cannot burn from the burn address
     * - Burn amount cannot be greater than the msgSender's balance
     */
    function burn(uint64 amount) external returns (bool) {

        address sender = _msgSender();
        require(sender != address(0), "EternalTokenV0::burn(): Burn from the zero address");

        uint64 balance = balanceOf(sender);
        require(balance >= amount, "EternalTokenV0::burn(): Burn amount exceeds balance");

        // Subtract the amounts from the sender before so we can reuse _burn elsewhere
        uint256 reflectedAmount = convertFromTrueToReflectedAmount(amount, false);
        reflectedBalances[sender] -= reflectedAmount;
        trueBalances[sender] = isExcludedFromRewards[sender] ? (trueBalances[sender] - amount) : trueBalances[sender];

        _burn(sender, amount, reflectedAmount);
        return true;
    }
    
    /**
     * @dev Burns the specified amount of ETRNL for a given sender by sending them to the 0x0 address.
     * @param sender The specified address burning ETRNL
     * @param amount The amount of ETRNL being burned
     * @param reflectedAmount The reflected equivalent of ETRNL being burned
     */
    function _burn(address sender, uint64 amount, uint256 reflectedAmount) private {
        // Send tokens to the 0x0 address
        reflectedBalances[address(0)] += reflectedAmount;
        trueBalances[address(0)] += amount;

        // Update supplies accordingly
        totalTokenSupply -= amount;
        totalReflectedSupply -= reflectedAmount;

        emit Transfer(sender, address(0), amount);
    }

    /**
     * @dev Swaps a given amount of ETRNL for AVAX using PangolinDEX. (Used for auto-liquidity swaps)
     * @param amount The amount of ETRNL to be swapped for AVAX
     */
    function swapTokensForAVAX(uint64 amount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = pangolinRouter.WAVAX();

        _approve(address(this), address(pangolinRouter), amount);

        pangolinRouter.swapExactTokensForAVAXSupportingFeeOnTransferTokens(amount, 0, path, address(this), block.timestamp);
    }
    
    /**
     * @dev Adds liquidity to the ETRNL/AVAX pair for a given amount of ETRNL and AVAX tokens.
     * @param amountETRNL The specified amount of ETRNL
     * @param amountAVAX The specified amount of AVAX 
     */
    function addLiquidity(uint64 amountETRNL, uint64 contractBalance, uint64 amountAVAX) private {
        _approve(address(this), address(pangolinRouter), amountETRNL);

        pangolinRouter.addLiquidityAVAX{value: amountAVAX}(address(this), amountETRNL, 0, 0, address(this), block.timestamp);
        
        // Update the locked AVAX balance
        lockedAVAXBalance += address(this).balance;

        emit AutomaticLiquidityProvision(amountETRNL, contractBalance, amountAVAX);
    }

    /**
     * @dev Transfers locked AVAX that accumulates in the contract over time as a result of dust left over from automatic liquidity provision. (Owner only)
     * @param recipient The address to which the AVAX is to be sent
     */
    function withdrawLockedAVAX(address payable recipient) onlyOwner {
        require(recipient != address(0), "EternalTokenV0::withdrawLockedAVAX(): Recipient cannot be the zero address");
        require(lockedAVAXBalance > 0, "EternalTokenV0:: withdrawLockedAVAX(): Locked AVAX balance must be greater than 0");

        // Intermediate variable to prevent re-entrancy attacks
        uint256 amount = lockedAVAXBalance;
        lockedAVAXBalance = 0;
        recipient.transfer(amount)
    }
    
    // Allows contract to receive AVAX tokens from Pangolin
    receive() external payable {}
}