// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// Minimal mock ERC4626 vault for testing
contract MockERC4626 is IERC4626 {
    using SafeERC20 for IERC20;

    IERC20 private immutable _asset;
    string private _name;
    string private _symbol;
    uint8 private _decimals;

    mapping(address => uint256) private _shares;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalShares;

    constructor(IERC20 asset_, string memory name_, string memory symbol_) {
        _asset = asset_;
        _name = name_;
        _symbol = symbol_;
        _decimals = 18;
    }

    function asset() external view returns (address) {
        return address(_asset);
    }

    function totalAssets() public view returns (uint256) {
        return _asset.balanceOf(address(this));
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        uint256 total = totalAssets();
        return total == 0 ? assets : assets * _totalShares / total;
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        uint256 total = totalAssets();
        return _totalShares == 0 ? shares : shares * total / _totalShares;
    }

    function maxDeposit(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function previewDeposit(uint256 assets) external view returns (uint256) {
        return convertToShares(assets);
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        shares = convertToShares(assets);
        _asset.safeTransferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function maxMint(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function previewMint(uint256 shares) external view returns (uint256) {
        return convertToAssets(shares);
    }

    function mint(uint256 shares, address receiver) external returns (uint256 assets) {
        assets = convertToAssets(shares);
        _asset.safeTransferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function maxWithdraw(address owner) external view returns (uint256) {
        return _shares[owner] == 0 ? 0 : convertToAssets(_shares[owner]);
    }

    function previewWithdraw(uint256 assets) external view returns (uint256) {
        return convertToShares(assets);
    }

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
        shares = convertToShares(assets);
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
        _burn(owner, shares);
        _asset.safeTransfer(receiver, assets);
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    function maxRedeem(address owner) external view returns (uint256) {
        return _shares[owner];
    }

    function previewRedeem(uint256 shares) external view returns (uint256) {
        return convertToAssets(shares);
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
        assets = convertToAssets(shares);
        _burn(owner, shares);
        _asset.safeTransfer(receiver, assets);
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    // ---- ERC-20 (shares) ----

    function name() external view returns (string memory) { return _name; }
    function symbol() external view returns (string memory) { return _symbol; }
    function decimals() external view returns (uint8) { return _decimals; }
    function totalSupply() external view returns (uint256) { return _totalShares; }
    function balanceOf(address account) external view returns (uint256) { return _shares[account]; }

    function transfer(address to, uint256 amount) external returns (bool) {
        _shares[msg.sender] -= amount;
        _shares[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }
    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }
    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (msg.sender != from) {
            _spendAllowance(from, msg.sender, amount);
        }
        _shares[from] -= amount;
        _shares[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }


    function _mint(address to, uint256 amount) internal {
        _shares[to] += amount;
        _totalShares += amount;
    }

    function _burn(address from, uint256 amount) internal {
        _shares[from] -= amount;
        _totalShares -= amount;
    }

    function _spendAllowance(address owner, address spender, uint256 amount) internal {
        uint256 current = _allowances[owner][spender];
        if (current != type(uint256).max) {
            _allowances[owner][spender] = current - amount;
        }
    }

    /// Test helper: add assets to vault to simulate yield
    function simulateYield(uint256 assets) external {
        _asset.safeTransferFrom(msg.sender, address(this), assets);
    }
}
