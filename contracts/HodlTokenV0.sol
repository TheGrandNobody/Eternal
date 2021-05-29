//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@pangolindex/exchange-contracts/contracts/pangolin-core/interfaces/IPangolinFactory.sol";
import "@pangolindex/exchange-contracts/contracts/pangolin-periphery/interfaces/IPangolinRouter.sol";

/**
 * @title Contract for the HODL Token (HODLS)
 * @author Nobody (credits to OpenZeppelin for the IERC20 and IERC20Metadata interfaces)
 * @notice The HODL Token contract holds 
 */
contract HodlTokenV0 is IERC20, IERC20Metadata, Ownable {

    mapping (address => mapping (address => uint256)) private allowances;
    mapping (address => uint256) private reserveBalances;
    mapping (address => uint256) private liabilities;
    mapping (address => bool) private isExcludedFromReflections;
    mapping (address => bool) private isExcludedFromFee;

    address[] private excluded;

    uint256 private constant MAX = ~uint256(0);
    uint256 private totalTokenSupply;
    uint256 private liquefactionRate;
    uint256 private burnRate;

    string private tokenName;
    string private tokenTicker;

    IPangolinRouter public immutable pangolinRouter;
    address public immutable pangolinPair;

    /**
     * @dev Sets the token ticker and token name. Mints the total supply to the contract deployer.
     */
    constructor () {
        // Initialize name, ticker symbol and total supply
        tokenName = "HODL Token";
        tokenTicker = "HODLS";
        totalTokenSupply = 10**10 * 10**9;

        reserveBalances[msg.sender] = totalTokenSupply;


        // Create pair address
        IPangolinRouter _pangolinRouter = IPangolinRouter(0xE54Ca86531e17Ef3616d22Ca28b0D458b6C89106);
        pangolinPair = IPangolinFactory(_pangolinRouter.factory()).createPair(address(this), _pangolinRouter.WAVAX());

        // Initialize Pangolin Router
        pangolinRouter = _pangolinRouter;
    }

    /**
     * @dev Returns the name of the token. 
     */
    function name() public view override returns (string memory) {
        return tokenName;
    }

    /**
     * @dev Returns the token ticker.
     */
    function symbol() public view override returns (string memory) {
        return tokenTicker;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     */
    function decimals() public pure override returns (uint8) {
        return 9;
    }
    
    /**
     * @dev Returns the total supply of the HODL token.
     */
    function totalSupply() external view override returns (uint256){
        return totalTokenSupply;
    }

    /**
     * @dev Returns the balance of a given user's address.
     * @param account The address of the user
     */
    function balanceOf(address account) external view override returns (uint256){
        if (isExcludedFromReflections[account]) {
            return liabilities[account];
        }
        return tokenFromReflection(reserveBalances[account]);
    }

    /**
     * @dev Returns the allowance of a given owner address for a given spender address.
     * @param owner The address of whom we are checking the allowance of
     * @param spender The address of whom we are checking the allowance for
     */
    function allowance(address owner, address spender) external view override returns (uint256){
        return allowances[owner][spender];
    }
    
    /**
     * @dev Returns whether a given wallet or contract's address is excluded from reflection fees.
     * @param account The wallet or contract's address
     */
    function isExcludedFromReflection(address account) public view returns (bool) {
        return isExcludedFromReflections[account];
    }
    
    /**
     * @dev Increases the allowance for a given spender address by a given amount
     * @param spender The address whom we are increasing the allowance for
     * @param addedValue The amount by which we increase the allowance
     */
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(msg.sender, spender, (allowances[msg.sender][spender] + addedValue));
        return true;
    }
    
    /**
     * @dev Decreases the allowance for a given spender address by a given amount
     * @param spender The address whom we are decrease the allowance for
     * @param subtractedValue The amount by which we decrease the allowance
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(msg.sender, spender, (allowances[_msgSender()][spender] - subtractedValue));
        return true;
    }

    /**
     * @dev Tranfers a given amount of HODLS to a given receiver address. Returns True if successful.
     * @param recipient The destination to which the HODLS are to be transferred
     * @param amount The amount of HODLS to be transferred
     */
    function transfer(address recipient, uint256 amount) external override returns (bool){
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    /**
     * @dev Sets the allowance for a given address to a given amount. Returns True if successful.
     * @param spender The address of whom we are changing the allowance for
     * @param amount The amount we are changing the allowance to
     */
    function approve(address spender, uint256 amount) external override returns (bool){
        _approve(msg.sender, spender, amount);
        return true;
    }

    /**
     * @dev Transfers a given amount of HODLS for a given sender address to a given recipient address.
     * @param sender The address whom we withdraw the HODLS from
     * @param recipient The address which shall receive the HODLS
     * @param amount The amount of HODLS which is being transferred
     */
    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = allowances[sender][msg.sender];
        require(currentAllowance >= amount, "HodlTokenV0::transferFrom(): transfer amount exceeds allowance");
        _approve(sender, msg.sender, currentAllowance - amount);

        return true;
    }

    /**
     * @dev Sets the allowance of a given owner address for a given spender address to a given amount.
     * @param owner The adress of whom we are changing the allowance of
     * @param spender The address of whom we are changing the allowance for
     * @param amount The amount which we change the allowance to
     */
    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "HodlTokenV0::_approve(): approve from the zero address");
        require(spender != address(0), "HodlTokenV0::_approve(): approve to the zero address");

        allowances[owner][spender] = amount;

        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Transfers a given amount of HODLS from a given sender's address to a given recipient's address.
     * Bottleneck for what transfer equation to use.
     * @param sender The address of whom the HODLS will be transferred from
     * @param recipient The address of whom the HODLS will be transferred to
     * @param amount The amount of HODLS to be transferred
     */
    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "HodlTokenV0::_transfer(): transfer from the zero address");
        require(recipient != address(0), "HodlTokenV0::_transfer(): transfer to the zero address");
        require(amount > 0, "HodlTokenV0::_transfer(): transfer amount must be greater than zero");

        if (isExcludedFromReflections[sender] && !isExcludedFromReflections[recipient]) {
            _transferFromExcluded(sender, recipient, amount);
        } else if (!isExcludedFromReflections[sender] && isExcludedFromReflections[recipient]) {
            _transferToExcluded(sender, recipient, amount);
        } else if (!isExcludedFromReflections[sender] && !isExcludedFromReflections[recipient]) {
            _transferStandard(sender, recipient, amount);
        } else if (isExcludedFromReflections[sender] && isExcludedFromReflections[recipient]) {
            _transferBothExcluded(sender, recipient, amount);
        } else {
            _transferStandard(sender, recipient, amount);
        }
    }

    /**
     * @dev Swaps a given amount of HODLS for AVAX using PangolinDEX. (Used for auto-liquidity swaps)
     * @param amount The amount of HODLS to be swapped for AVAX
     */
    function swapTokensForAVAX(uint256 amount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = pangolinRouter.WAVAX();

        _approve(address(this), address(pangolinRouter), amount);

        pangolinRouter.swapExactTokensForAVAXSupportingFeeOnTransferTokens(amount, 0, path, address(this), block.timestamp);
    }
    
    // Allows contract to receive AVAX tokens from Pangolin
    receive() external payable {}
}