// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title CollateralVault
 * @notice Custodies the USDC staked into Kaffa markets. Funds can only be
 *         released by the one authorised Market contract — never by users,
 *         and never by the owner directly. Part of KEL-ENG-2026-SPEC-001.
 * @dev    TESTNET DEMO. Must be professionally audited before mainnet.
 */
contract CollateralVault is Ownable {
    using SafeERC20 for IERC20;

    /// The collateral asset (MockUSDC on testnet, real USDC on mainnet).
    /// `immutable` = fixed at deploy, can never be changed. (Spec §X.2)
    IERC20 public immutable usdc;

    /// The only address allowed to move funds out. Set once, then locked.
    address public market;

    event MarketSet(address indexed market);
    event PaidOut(address indexed to, uint256 amount);

    constructor(address _usdc) Ownable(msg.sender) {
        require(_usdc != address(0), "usdc address cannot be zero");
        usdc = IERC20(_usdc);
    }

    /// Only the authorised Market contract may call the guarded function.
    modifier onlyMarket() {
        require(msg.sender == market, "caller is not the Market");
        _;
    }

    /// Owner wires in the Market address ONCE. The `market == address(0)`
    /// check means it can never be re-pointed to a different contract later —
    /// a deliberate lock so nobody (not even you) can hijack the payout path.
    function setMarket(address _market) external onlyOwner {
        require(market == address(0), "market already set");
        require(_market != address(0), "market cannot be zero");
        market = _market;
        emit MarketSet(_market);
    }

    /// Release USDC to a recipient. Only the Market can trigger this.
    function payout(address to, uint256 amount) external onlyMarket {
        usdc.safeTransfer(to, amount);
        emit PaidOut(to, amount);
    }

    /// Anyone can read how much USDC the vault currently holds.
    function balance() external view returns (uint256) {
        return usdc.balanceOf(address(this));
    }
}