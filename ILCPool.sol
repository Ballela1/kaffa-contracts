// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ILCPool
 * @notice The pre-funded Insurance Loss Coverage reserve. Anyone can seed it
 *         with USDC; only the authorised Market contract can pay coverage out.
 *         The pool balance is publicly readable so reviewers and the GRA can
 *         verify the floor is really funded. Part of KEL-ENG-2026-SPEC-001.
 * @dev    TESTNET DEMO. Must be professionally audited before mainnet.
 */
contract ILCPool is Ownable {
    using SafeERC20 for IERC20;

    /// The collateral asset — locked at deploy. (Spec §X.2)
    IERC20 public immutable usdc;

    /// The only address allowed to pay coverage out. Set once, then locked.
    address public market;

    event MarketSet(address indexed market);
    event PoolSeeded(address indexed from, uint256 amount, uint256 poolBalanceAfter);
    event CoveragePaid(address indexed to, uint256 amount, uint256 poolBalanceAfter);

    constructor(address _usdc) Ownable(msg.sender) {
        require(_usdc != address(0), "usdc address cannot be zero");
        usdc = IERC20(_usdc);
    }

    modifier onlyMarket() {
        require(msg.sender == market, "caller is not the Market");
        _;
    }

    /// Owner wires in the Market address ONCE, then it's locked forever.
    function setMarket(address _market) external onlyOwner {
        require(market == address(0), "market already set");
        require(_market != address(0), "market cannot be zero");
        market = _market;
        emit MarketSet(_market);
    }

    /// Anyone can add USDC to the reserve. Caller must `approve` this contract
    /// on the USDC token first (standard ERC-20 two-step). This is the
    /// credibility anchor — the floor is pre-funded, visible before any trade.
    function seed(uint256 amount) external {
        require(amount > 0, "amount must be > 0");
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        emit PoolSeeded(msg.sender, amount, usdc.balanceOf(address(this)));
    }

    /// Pay loss coverage to a trader. Only the Market can trigger this.
    function payCoverage(address to, uint256 amount) external onlyMarket {
        usdc.safeTransfer(to, amount);
        emit CoveragePaid(to, amount, usdc.balanceOf(address(this)));
    }

    /// Anyone can read the current reserve balance — the ILC proof.
    function balance() external view returns (uint256) {
        return usdc.balanceOf(address(this));
    }
}