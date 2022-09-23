// SPDX-License-Identifier: Unlicensed

pragma solidity ^0.8.15;

import "./IDAO.sol";
import "./ISwapRouter.sol";
import "./ISwapFactory.sol";
import "./INFTsDividend.sol";
import "./IERC20.sol";
import "./Ownable.sol";
import "./SafeMath.sol";
import "./SwapHelper.sol";

contract KTBToken is Context, IERC20, Ownable {
    using SafeMath for uint256;

    string private _name;
    string private _symbol;
    uint256 private _decimals = 9;

    mapping(address => uint256) private _rOwned;
    mapping(address => uint256) private _tOwned;
    mapping(address => mapping(address => uint256)) private _allowances;

    mapping(address => bool) private _isExcludedFromFee;
    mapping(address => bool) private _isExcluded;
    address[] private _excluded;

    uint256 private constant MAX = ~uint256(0);
    uint256 private _tTotal;
    uint256 private _rTotal;
    uint256 private _tFeeTotal;

    mapping(address => bool) public blacklist;
    bool public isBlackOpen = true;

    // burn fee
    uint256 public burnFee = 300;
    // buy fee
    address public deadAddress = address(0xdead);
    uint256 public dividendFee = 200;
    uint256[] public levelsFees = [400, 200, 50];
    // sell fee
    uint256 public fundsFee = 200;
    uint256 public nftFee = 500;
    uint256 public liquidityFee = 500;

    address public daoAddress;
    address public usdtAddress;
    address public fundsAddress;
    address public nftDivAddress;

    SwapHelper public swapHelper;
    ISwapRouter public swapRouter;
    address public swapPair;

    bool inSwapAndLiquidity;
    bool public swapAndLiquidityEnabled = true;
    uint256 private _numTokensSellToAddToLiquidity;

    event SwapAndLiquidity(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );

    modifier lockTheSwap() {
        inSwapAndLiquidity = true;
        _;
        inSwapAndLiquidity = false;
    }

    constructor(
        address _daoAddress,
        address _nftDivAddress,
        address _fundsAddress,
        address _usdtAddress,
        address _routerAddress
    ) {
        _name = "KTB";
        _symbol = "KTB";
        _tTotal = 310000000 * 10**_decimals;
        _rTotal = (MAX - (MAX % _tTotal));
        _rOwned[_msgSender()] = _rTotal;
        _numTokensSellToAddToLiquidity = 30000 * 10**_decimals;

        daoAddress = _daoAddress;
        nftDivAddress = _nftDivAddress;
        fundsAddress = _fundsAddress;
        usdtAddress = _usdtAddress;

        ISwapRouter _swapRouter = ISwapRouter(_routerAddress);
        swapPair = ISwapFactory(_swapRouter.factory()).createPair(
            address(this),
            usdtAddress
        );
        swapRouter = _swapRouter;
        swapHelper = new SwapHelper(usdtAddress);

        excludeFromReward(swapPair);
        //exclude owner and this contract from fee
        _isExcludedFromFee[_msgSender()] = true;
        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromFee[deadAddress] = true;

        emit Transfer(address(0), _msgSender(), _tTotal);
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint256) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        if (_isExcluded[account]) return _tOwned[account];
        return tokenFromReflection(_rOwned[account]);
    }

    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender)
        public
        view
        override
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount)
        public
        override
        returns (bool)
    {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()].sub(
                amount,
                "ERC20: transfer amount exceeds allowance"
            )
        );
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue)
        public
        virtual
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].add(addedValue)
        );
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        virtual
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].sub(
                subtractedValue,
                "ERC20: decreased allowance below zero"
            )
        );
        return true;
    }

    function isExcludedFromReward(address account) public view returns (bool) {
        return _isExcluded[account];
    }

    function totalFees() public view returns (uint256) {
        return _tFeeTotal;
    }

    function tokenFromReflection(uint256 rAmount)
        public
        view
        returns (uint256)
    {
        require(
            rAmount <= _rTotal,
            "Amount must be less than total reflections"
        );
        uint256 currentRate = _getRate();
        return rAmount.div(currentRate);
    }

    function _getRate() private view returns (uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply.div(tSupply);
    }

    function _getCurrentSupply() private view returns (uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (
                _rOwned[_excluded[i]] > rSupply ||
                _tOwned[_excluded[i]] > tSupply
            ) return (_rTotal, _tTotal);
            rSupply = rSupply.sub(_rOwned[_excluded[i]]);
            tSupply = tSupply.sub(_tOwned[_excluded[i]]);
        }
        if (rSupply < _rTotal.div(_tTotal)) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }

    function excludeFromReward(address account) public onlyOwner {
        require(!_isExcluded[account], "Account is already excluded");
        if (_rOwned[account] > 0) {
            _tOwned[account] = tokenFromReflection(_rOwned[account]);
        }
        _isExcluded[account] = true;
        _excluded.push(account);
    }

    function includeInReward(address account) public onlyOwner {
        require(_isExcluded[account], "Account is already excluded");
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_excluded[i] == account) {
                _excluded[i] = _excluded[_excluded.length - 1];
                _tOwned[account] = 0;
                _isExcluded[account] = false;
                _excluded.pop();
                break;
            }
        }
    }

    function excludeFromFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = true;
    }

    function includeInFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = false;
    }

    function setBlacklist(address _address, bool _flag) external onlyOwner {
        blacklist[_address] = _flag;
    }

    function setIsBlackOpen(bool _open) external onlyOwner {
        isBlackOpen = _open;
    }

    function setDaoAddress(address _dao) external onlyOwner {
        daoAddress = _dao;
    }

    function setSwapAndLiquidityEnabled(bool _enabled) external onlyOwner {
        swapAndLiquidityEnabled = _enabled;
    }

    function setNumTokensSellToAddToLiquidity(uint256 _num) external onlyOwner {
        _numTokensSellToAddToLiquidity = _num;
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "ERC20: Transfer amount must be greater than zero");
        require(
            balanceOf(from) >= amount,
            "ERC20: transfer amount exceeds balance"
        );
        if (_isExcludedFromFee[from] || _isExcludedFromFee[to]) {
            uint256 rAmount = amount.mul(_getRate());
            _subValue(from, amount, rAmount);
            _addValue(to, amount, rAmount);
            emit Transfer(from, to, amount);
        } else {
            require(
                !blacklist[from] && !blacklist[to],
                "ERC20: the current user is in the blacklist and cannot be transferred"
            );
            if (from == swapPair || from == nftDivAddress) {
                _buyWithFee(from, to, amount);
            } else {
                _sellWithFee(from, to, amount);
            }
        }
    }

    function _buyWithFee(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        if (isBlackOpen) blacklist[recipient] = true;
        address[] memory relations = IDAO(daoAddress).getRelations(recipient);
        (
            uint256 tBurn,
            uint256 tDividend,
            uint256 tLevelsTotal,
            uint256[] memory tLevels,
            uint256 rBurn,
            uint256 rDividend,
            uint256 rLevelsTotal,
            uint256[] memory rLevels,
            uint256 rAmount
        ) = _buyFeeValues(tAmount, relations);
        // burn
        _addValue(deadAddress, tBurn, rBurn);
        emit Transfer(sender, deadAddress, tBurn);
        // dividend to all holders
        _rTotal = _rTotal.sub(rDividend);
        _tFeeTotal = _tFeeTotal.add(tDividend);
        // dividend to levels
        for (uint8 i = 0; i < relations.length; i++) {
            _addValue(relations[i], tLevels[i], rLevels[i]);
            emit Transfer(sender, relations[i], tLevels[i]);
        }
        // transfer finally
        _subValue(sender, tAmount, rAmount);
        uint256 tAddValue = _subMulti(
            tAmount,
            tBurn,
            tDividend,
            tLevelsTotal,
            0
        );
        _addValue(
            recipient,
            tAddValue,
            _subMulti(rAmount, rBurn, rDividend, rLevelsTotal, 0)
        );
        emit Transfer(sender, recipient, tAddValue);
    }

    function _sellWithFee(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
            uint256 tBurn,
            uint256 tFunds,
            uint256 tNftTotal,
            uint256 tLiquidity,
            uint256 rBurn,
            uint256 rFunds,
            uint256 rNftTotal,
            uint256 rLiquidity,
            uint256 rAmount
        ) = _sellFeeValues(tAmount);
        // take liquidity
        uint256 tokenBalance = balanceOf(address(this));
        bool overMinTokenBalance = tokenBalance >=
            _numTokensSellToAddToLiquidity;
        if (
            overMinTokenBalance &&
            !inSwapAndLiquidity &&
            swapAndLiquidityEnabled
        ) {
            tokenBalance = _numTokensSellToAddToLiquidity;
            swapAndLiquidity(tokenBalance);
        }
        // burn
        _addValue(deadAddress, tBurn, rBurn);
        emit Transfer(sender, deadAddress, tBurn);
        // funds
        _addValue(fundsAddress, tFunds, rFunds);
        emit Transfer(sender, fundsAddress, tFunds);
        // dividend to nft
        _addValue(nftDivAddress, tNftTotal, rNftTotal);
        emit Transfer(sender, nftDivAddress, tNftTotal);
        // nft distribute
        INFTsDividend(nftDivAddress).distributeDividends(tNftTotal);
        // liquidity fee
        _addValue(address(this), tLiquidity, rLiquidity);
        emit Transfer(sender, address(this), tLiquidity);
        // transfer finally
        _subValue(sender, tAmount, rAmount);
        uint256 tAddValue = _subMulti(
            tAmount,
            tBurn,
            tFunds,
            tNftTotal,
            tLiquidity
        );
        _addValue(
            recipient,
            tAddValue,
            _subMulti(rAmount, rBurn, rFunds, rNftTotal, rLiquidity)
        );
        emit Transfer(sender, recipient, tAddValue);
    }

    function _addValue(
        address user,
        uint256 tAmount,
        uint256 rAmount
    ) private {
        _rOwned[user] = _rOwned[user].add(rAmount);
        if (_isExcluded[user]) _tOwned[user] = _tOwned[user].add(tAmount);
    }

    function _subValue(
        address user,
        uint256 tAmount,
        uint256 rAmount
    ) private {
        _rOwned[user] = _rOwned[user].sub(rAmount);
        if (_isExcluded[user]) _tOwned[user] = _tOwned[user].sub(tAmount);
    }

    function _subMulti(
        uint256 amount,
        uint256 a,
        uint256 b,
        uint256 c,
        uint256 d
    ) private pure returns (uint256) {
        return amount.sub(a).sub(b).sub(c).sub(d);
    }

    function _buyRelationFees(
        uint256 currentRate,
        uint256 tAmount,
        address[] memory relations
    )
        private
        view
        returns (
            uint256 tLevelsTotal,
            uint256[] memory tLevels,
            uint256 rLevelsTotal,
            uint256[] memory rLevels
        )
    {
        tLevels = new uint256[](relations.length);
        rLevels = new uint256[](relations.length);
        for (uint8 i = 0; i < relations.length; i++) {
            uint256 idx = i;
            if (idx >= levelsFees.length) idx = levelsFees.length - 1;
            tLevels[i] = tAmount.mul(levelsFees[idx]).div(10000);
            tLevelsTotal = tLevelsTotal.add(tLevels[i]);
            rLevels[i] = tLevels[i].mul(currentRate);
            rLevelsTotal = rLevelsTotal.add(rLevels[i]);
        }
    }

    function _buyFeeValues(uint256 tAmount, address[] memory relations)
        private
        view
        returns (
            uint256 tBurn,
            uint256 tDividend,
            uint256 tLevelsTotal,
            uint256[] memory tLevels,
            uint256 rBurn,
            uint256 rDividend,
            uint256 rLevelsTotal,
            uint256[] memory rLevels,
            uint256 rAmount
        )
    {
        uint256 currentRate = _getRate();
        tBurn = tAmount.mul(burnFee).div(10000);
        rBurn = tBurn.mul(currentRate);
        tDividend = tAmount.mul(dividendFee).div(10000);
        rDividend = tDividend.mul(currentRate);
        (tLevelsTotal, tLevels, rLevelsTotal, rLevels) = _buyRelationFees(
            currentRate,
            tAmount,
            relations
        );
        rAmount = tAmount.mul(currentRate);
    }

    function _sellFeeValues(uint256 tAmount)
        private
        view
        returns (
            uint256 tBurn,
            uint256 tFunds,
            uint256 tNftTotal,
            uint256 tLiquidity,
            uint256 rBurn,
            uint256 rFunds,
            uint256 rNftTotal,
            uint256 rLiquidity,
            uint256 rAmount
        )
    {
        uint256 currentRate = _getRate();
        tBurn = tAmount.mul(burnFee).div(10000);
        rBurn = tBurn.mul(currentRate);
        tFunds = tAmount.mul(fundsFee).div(10000);
        rFunds = tFunds.mul(currentRate);
        tNftTotal = tAmount.mul(nftFee).div(10000);
        rNftTotal = tNftTotal.mul(currentRate);
        tLiquidity = tAmount.mul(liquidityFee).div(10000);
        rLiquidity = tLiquidity.mul(currentRate);
        rAmount = tAmount.mul(currentRate);
    }

    function swapAndLiquidity(uint256 contractTokenBalance)
        private
        lockTheSwap
    {
        // split the contract balance into halves
        uint256 half = contractTokenBalance.div(2);
        uint256 otherHalf = contractTokenBalance.sub(half);
        uint256 initialBalance = IERC20(usdtAddress).balanceOf(address(this));
        // swap tokens for USDT
        swapTokensForUsdtToSelf(half);
        uint256 newBalance = IERC20(usdtAddress).balanceOf(address(this)).sub(
            initialBalance
        );
        // add liquidity to swap
        addLiquidity(otherHalf, newBalance);
        emit SwapAndLiquidity(half, newBalance, otherHalf);
    }

    function swapTokensForUsdtToSelf(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = usdtAddress;
        _approve(address(this), address(swapRouter), tokenAmount);
        swapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of USDT
            path,
            address(swapHelper), // use the helper to receive
            block.timestamp
        );
        // transfer back to the current contract
        swapHelper.transferToOwner();
    }

    function addLiquidity(uint256 tokenAmount, uint256 usdtAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(swapRouter), tokenAmount);
        IERC20(usdtAddress).approve(address(swapRouter), usdtAmount);
        // add the liquidity
        swapRouter.addLiquidity(
            address(this),
            usdtAddress,
            tokenAmount,
            usdtAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            owner(),
            block.timestamp
        );
    }
}
