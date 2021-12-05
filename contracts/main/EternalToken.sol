//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "../interfaces/IEternalToken.sol";
import "../interfaces/IEternalLiquidity.sol";
import "../inheritances/OwnableEnhanced.sol";

/**
 * @title Contract for the Eternal Token (ETRNL)
 * @author Nobody (me)
 * (credits to OpenZeppelin for initial framework and RFI for figuring out by far the most efficient way of implementing reward-distributing tokens)
 * @notice The Eternal Token contract holds all the deflationary, burn, reflect, funding and auto-liquidity provision mechanics
 */
contract EternalToken is IEternalToken, OwnableEnhanced {

    // Keeps track of all reward-excluded addresses
    address[] private excludedAddresses;

    // The reflected balances used to track reward-accruing users' total balances
    mapping (address => uint256) private reflectedBalances;
    // The true balances used to track non-reward-accruing addresses' total balances
    mapping (address => uint256) private trueBalances;
    // Keeps track of whether an address is excluded from rewards
    mapping (address => bool) private isExcludedFromRewards;
    // Keeps track of whether an address is excluded from transfer fees
    mapping (address => bool) private isExcludedFromFees;
    // Keeps track of how much an address allows any other address to spend on its behalf
    mapping (address => mapping (address => uint256)) private allowances;
    // The Eternal automatic liquidity provider interface
    IEternalLiquidity public eternalLiquidity;

    // The total ETRNL supply after taking reflections into account
    uint256 private totalReflectedSupply;
    // Threshold at which the contract swaps its ETRNL balance to provide liquidity (0.1% of total supply by default)
    uint256 private tokenLiquidityThreshold;
    // The true total ETRNL supply 
    uint256 private totalTokenSupply;

    // All fees accept up to three decimal points
    // The percentage of the fee, taken at each transaction, that is stored in the EternalFund
    uint16 private fundingRate;
    // The percentage of the fee, taken at each transaction, that is burned
    uint16 private burnRate;
    // The percentage of the fee, taken at each transaction, that is redistributed to holders
    uint16 private redistributionRate;
    // The percentage of the fee taken at each transaction, that is used to auto-lock liquidity
    uint16 private liquidityProvisionRate;

    /**
     * @dev Initialize supplies and routers and create a pair. Mints total supply to the contract deployer. 
     * Exclude some addresses from fees and/or rewards. Sets initial rate values.
     */
    constructor () {

        // The largest possible number in a 256-bit integer
        uint256 max = ~uint256(0);

        // Initialize total supplies, liquidity threshold and transfer total supply to the owner
        totalTokenSupply = (10**10) * (10**9);
        totalReflectedSupply = (max - (max % totalTokenSupply));
        tokenLiquidityThreshold = totalTokenSupply / 1000;
        reflectedBalances[admin()] = totalReflectedSupply;

        // Exclude the owner from rewards and fees
        excludeFromReward(admin());
        isExcludedFromFees[admin()] = true;

        // Exclude this contract from rewards and fees
        excludeFromReward(address(this));
        isExcludedFromFees[address(this)] = true;

        // Exclude the burn address from rewards
        isExcludedFromRewards[address(0)];

        // Set initial rates for fees
        fundingRate = 500;
        burnRate = 500;
        redistributionRate = 5000;
        liquidityProvisionRate = 1500;
    }

/////–––««« Variable state-inspection functions »»»––––\\\\\

    /**
     * @dev View the name of the token. 
     * @return The token name
     */
    function name() external pure override returns (string memory) {
        return "Eternal Token";
    }

    /**
     * @dev View the token ticker.
     * @return The token ticker
     */
    function symbol() external pure override returns (string memory) {
        return "ETRNL";
    }

    /**
     * @dev View the maximum number of decimals for the Eternal token.
     * @return The number of decimals
     */
    function decimals() external pure override returns (uint8) {
        return 9;
    }
    
    /**
     * @dev View the total supply of the Eternal token.
     * @return Returns the total ETRNL supply.
     */
    function totalSupply() external view override returns (uint256){
        return totalTokenSupply;
    }

    /**
     * @dev View the balance of a given user's address.
     * @param account The address of the user
     * @return The balance of the account
     */
    function balanceOf(address account) public view override returns (uint256){
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
    function allowance(address owner, address spender) external view override returns (uint256){
        return allowances[owner][spender];
    }

    /**
     * @dev View whether a given wallet or contract's address is excluded from transaction fees.
     * @param account The wallet or contract's address
     * @return Whether the account is excluded from transaction fees.
     */
    function isExcludedFromFee(address account) external view override returns (bool) {
        return isExcludedFromFees[account];
    }

    /**
     * @dev View whether a given wallet or contract's address is excluded from rewards.
     * @param account The wallet or contract's address
     * @return Whether the account is excluded from rewards.
     */
    function isExcludedFromReward(address account) external view override returns (bool) {
        return isExcludedFromRewards[account];
    }

    /**
     * @dev Computes the current rate used to inter-convert from the mathematically reflected space to the "true" or total space.
     * @return The ratio of net reflected ETRNL to net total ETRNL
     */
    function getReflectionRate() public view override returns (uint256) {
        (uint256 netReflectedSupply, uint256 netTokenSupply) = getNetSupplies();
        return netReflectedSupply / netTokenSupply;
    }

    /**
     * @dev View the current total fee rate
     */
    function viewTotalRate() external view override returns(uint256) {
        return fundingRate + burnRate + redistributionRate + liquidityProvisionRate;
    }

/////–––««« IERC20/ERC20 functions »»»––––\\\\\
    
    /**
     * @dev Increases the allowance for a given spender address by a given amount.
     * @param spender The address whom we are increasing the allowance for
     * @param addedValue The amount by which we increase the allowance
     * @return True if the increase in allowance is successful
     */
    function increaseAllowance(address spender, uint256 addedValue) external virtual returns (bool) {
        _approve(_msgSender(), spender, (allowances[_msgSender()][spender] + addedValue));

        return true;
    }
    
    /**
     * @dev Decreases the allowance for a given spender address by a given amount.
     * @param spender The address whom we are decrease the allowance for
     * @param subtractedValue The amount by which we decrease the allowance
     * @return True if the decrease in allowance is successful
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) external virtual returns (bool) {
        _approve(_msgSender(), spender, (allowances[_msgSender()][spender] - subtractedValue));

        return true;
    }

    /**
     * @dev Tranfers a given amount of ETRNL to a given receiver address.
     * @param recipient The destination to which the ETRNL are to be transferred
     * @param amount The amount of ETRNL to be transferred
     * @return True if the transfer is successful.
     */
    function transfer(address recipient, uint256 amount) external override returns (bool){
        _transfer(_msgSender(), recipient, amount);

        return true;
    }

    /**
     * @dev Sets the allowance for a given address to a given amount.
     * @param spender The address of whom we are changing the allowance for
     * @param amount The amount we are changing the allowance to
     * @return True if the approval is successful.
     */
    function approve(address spender, uint256 amount) external override returns (bool){
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
    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "Not enough allowance");
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
    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "Approve from the zero address");
        require(spender != address(0), "Approve to the zero address");

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
    function _transfer(address sender, address recipient, uint256 amount) private {
        uint256 balance = balanceOf(sender);
        require(balance >= amount, "Transfer amount exceeds balance");
        require(sender != address(0), "Transfer from the zero address");
        require(recipient != address(0), "Transfer to the zero address");
        require(amount > 0, "Transfer amount must exceed zero");

        // We only take fees if both the sender and recipient are susceptible to fees
        bool takeFee = (!isExcludedFromFees[sender] && !isExcludedFromFees[recipient]);

        (uint256 reflectedAmount, uint256 netReflectedTransferAmount, uint256 netTransferAmount) = getValues(amount, takeFee);

        // Always update the reflected balances of sender and recipient
        reflectedBalances[sender] -= reflectedAmount;
        reflectedBalances[recipient] += netReflectedTransferAmount;

        // Update true balances for any non-reward-accruing accounts 
        trueBalances[sender] = isExcludedFromRewards[sender] ? (trueBalances[sender] - amount) : trueBalances[sender]; 
        trueBalances[recipient] = isExcludedFromRewards[recipient] ? (trueBalances[recipient] + netTransferAmount) : trueBalances[recipient]; 

        // Adjust the total reflected supply for the new fees
        // If the sender or recipient are excluded from fees, we ignore the fee altogether
        if (takeFee) {
            // Perform a burn based on the burn rate 
            _burn(address(this), amount * burnRate / 1000, reflectedAmount * burnRate / 1000);
            // Redistribute based on the redistribution rate 
            totalReflectedSupply -= reflectedAmount * redistributionRate / 1000;
            // Store ETRNL away in the EternalFund based on the funding rate
            reflectedBalances[fund()] += reflectedAmount * fundingRate / 1000;
            // Provide liqudity to the ETRNL/AVAX pair on Pangolin based on the liquidity provision rate
            storeLiquidityFunds(sender, amount * liquidityProvisionRate / 1000, reflectedAmount * liquidityProvisionRate / 1000);
        }

        emit Transfer(sender, recipient, netTransferAmount);
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
    function burn(uint256 amount) external returns (bool) {
        address sender = _msgSender();
        require(sender != address(0), "Burn from the zero address");
        uint256 balance = balanceOf(sender);
        require(balance >= amount, "Burn amount exceeds balance");

        // Subtract the amounts from the sender before so we can reuse _burn elsewhere
        uint256 reflectedAmount;
        (,reflectedAmount,) = getValues(amount, !isExcludedFromFees[sender]);
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
    function _burn(address sender, uint256 amount, uint256 reflectedAmount) private {
        // Send tokens to the 0x0 address
        reflectedBalances[address(0)] += reflectedAmount;
        trueBalances[address(0)] += amount;

        // Update supplies accordingly
        totalTokenSupply -= amount;
        totalReflectedSupply -= reflectedAmount;

        emit Transfer(sender, address(0), amount);
    }

/////–––««« Reward-redistribution functions »»»––––\\\\\

    /**
     * @dev Translates a given reflected sum of ETRNL into the true amount of ETRNL it represents based on the current reserve rate.
     * @param reflectedAmount The specified reflected sum of ETRNL
     * @return The true amount of ETRNL representing by its reflected amount
     */
    function convertFromReflectedToTrueAmount(uint256 reflectedAmount) private view returns(uint256) {
        uint256 currentRate =  getReflectionRate();

        return reflectedAmount / currentRate;
    }

    /**
     * @dev Compute the reflected and net reflected transferred amounts and the net transferred amount from a given amount of ETRNL.
     * @param trueAmount The specified amount of ETRNL
     * @return The reflected amount, the net reflected transfer amount, the actual net transfer amount, and the total reflected fees
     */
    function getValues(uint256 trueAmount, bool takeFee) private view returns (uint256, uint256, uint256) {

        uint256 feeRate = takeFee ? (liquidityProvisionRate + burnRate + fundingRate + redistributionRate) : 0;

        // Calculate the total fees and transfered amount after fees
        uint256 totalFees = (trueAmount * feeRate) / 100000;
        uint256 netTransferAmount = trueAmount - totalFees;

        // Calculate the reflected amount, reflected total fees and reflected amount after fees
        uint256 currentRate = getReflectionRate();
        uint256 reflectedAmount = trueAmount * currentRate;
        uint256 reflectedTotalFees = totalFees * currentRate;
        uint256 netReflectedTransferAmount = reflectedAmount - reflectedTotalFees;
        
        return (reflectedAmount, netReflectedTransferAmount, netTransferAmount);
    }

    /**
     * @dev Computes the net reflected and total token supplies (adjusted for non-reward-accruing accounts).
     * @return The adjusted reflected supply and adjusted total token supply
     */
    function getNetSupplies() private view returns(uint256, uint256) {
        uint256 netReflectedSupply = totalReflectedSupply;
        uint256 netTokenSupply = totalTokenSupply;  

        for (uint256 i = 0; i < excludedAddresses.length; i++) {
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
     * @dev Updates the contract's balance regarding the liquidity provision fee for a given transaction's amount.
     * If the contract's balance threshold is reached, also initiates automatic liquidity provision.
     * @param sender The address of whom the ETRNL is being transferred from
     * @param amount The amount of ETRNL being transferred
     * @param reflectedAmount The reflected amount of ETRNL being transferred
     */
    function storeLiquidityFunds(address sender, uint256 amount, uint256 reflectedAmount) private {
        // Update the contract's balance to account for the liquidity provision fee
        reflectedBalances[address(this)] += reflectedAmount;
        trueBalances[address(this)] += amount;
        
        // Check whether the contract's balance threshold is reached; if so, initiate a liquidity swap
        uint256 contractBalance = balanceOf(address(this));
        if ((contractBalance >= tokenLiquidityThreshold) && (sender != eternalLiquidity.viewPair())) {
            _transfer(address(this), address(eternalLiquidity), contractBalance);
            eternalLiquidity.provideLiquidity(contractBalance);
        }
    }

/////–––««« Owner/Fund-only functions »»»––––\\\\\

    /**
     * @dev Excludes a given wallet or contract's address from accruing rewards. (Admin and Fund only)
     * @param account The wallet or contract's address
     *
     * Requirements:
     * – Account must not already be excluded from rewards.
     */
    function excludeFromReward(address account) public onlyAdminAndFund() {
        require(!isExcludedFromRewards[account], "Account is already excluded");
        if(reflectedBalances[account] > 0) {
            // Compute the true token balance from non-empty reflected balances and update it
            // since we must use both reflected and true balances to make our reflected-to-total ratio even
            trueBalances[account] =  convertFromReflectedToTrueAmount(reflectedBalances[account]);
        }
        isExcludedFromRewards[account] = true;
        excludedAddresses.push(account);
    }

    /**
     * @dev Allows a given wallet or contract's address to accrue rewards. (Admin and Fund only)
     * @param account The wallet or contract's address
     *
     * Requirements:
     * – Account must not already be accruing rewards.
     */
    function includeInReward(address account) external onlyAdminAndFund() {
        require(isExcludedFromRewards[account], "Account is already included");
        for (uint i = 0; i < excludedAddresses.length; i++) {
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
     * @dev Sets the value of a given rate to a given rate type. (Admin and Fund only)
     * @param rate The type of the specified rate
     * @param newRate The specified new rate value
     *
     * Requirements:
     *
     * - Rate type must be either Liquidity, Funding, Redistribution or Burn
     * - Rate value must be positive
     * - The sum of all rates cannot exceed 25 percent
     */
    function setRate(Rate rate, uint16 newRate) external override onlyAdminAndFund() {
        require((uint(rate) >= 0 && uint(rate) <= 3), "Invalid rate type");
        require(newRate >= 0, "The new rate must be positive");

        uint256 oldRate;

        if (rate == Rate.Liquidity) {
            require((newRate + fundingRate + redistributionRate + burnRate) <= 25000, "Total rate exceeds 25%");
            oldRate = liquidityProvisionRate;
            liquidityProvisionRate = newRate;
        } else if (rate == Rate.Funding) {
            require((liquidityProvisionRate + newRate + redistributionRate + burnRate) <= 25000, "Total rate exceeds 25%");
            oldRate = fundingRate;
            fundingRate = newRate;
        } else if (rate == Rate.Redistribution) {
            require((liquidityProvisionRate + fundingRate + newRate + burnRate) <=25000, "Total rate exceeds 25%");
            oldRate = redistributionRate;
            redistributionRate = newRate;
        } else {
            require((liquidityProvisionRate + fundingRate + redistributionRate + newRate) <= 25000, "Total rate exceeds 25%");
            oldRate = burnRate;
            burnRate = newRate;
        }

        emit UpdateRate(oldRate, newRate, rate);
    }

    /**
     * @dev Updates the threshold of ETRNL at which the contract provides liquidity to a given value.
     * @param value The new token liquidity threshold
     */
    function setLiquidityThreshold(uint256 value) external override onlyFund() {
        uint256 oldThreshold = tokenLiquidityThreshold;
        tokenLiquidityThreshold = value;

        emit UpdateLiquidityThreshold(oldThreshold, tokenLiquidityThreshold);
    }

    /**
     * @dev Updates the address of the Eternal Liquidity contract
     * @param newContract The new address for the Eternal Liquidity contract
     */
    function setEternalLiquidity(address newContract) external override onlyAdminAndFund() {
        address oldContract = address(eternalLiquidity);
        eternalLiquidity = IEternalLiquidity(newContract);

        emit UpdateEternalLiquidity(oldContract, newContract);
    }

    /**
     * @dev Attributes a given address to the Eternal Fund variable in this contract. (Admin and Fund only)
     * @param _fund The specified address of the designated fund
     */
    function designateFund(address _fund) external override onlyAdminAndFund() {
        isExcludedFromFees[fund()] = false;
        isExcludedFromFees[_fund] = true;
        attributeFundRights(_fund);
    }
}