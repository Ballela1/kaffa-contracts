// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface ICollateralVault {
    function payout(address to, uint256 amount) external;
}

interface IILCPool {
    function payCoverage(address to, uint256 amount) external;
}

/**
 * @title Market
 * @notice A single YES/NO prediction market with Insurance Loss Coverage.
 *         Stakes are custodied in the CollateralVault; ILC premiums fund the
 *         ILCPool; losers are topped up to an 80% floor on settlement.
 *         Part of KEL-ENG-2026-SPEC-001.
 *
 * SCOPE (KEL-ENG-2026 — deliberate):
 *   Supports BINARY (two-outcome, YES/NO) markets ONLY.
 *   Range and multiple-choice markets are OUT OF SCOPE for this contract and
 *   require a separate N-outcome design (per-outcome pools + generalised
 *   payout math). The ILC mechanic itself is identical across all market
 *   types — a loser is topped up to floorBps of their stake regardless of the
 *   number of outcomes — so this binary contract demonstrates the full ILC
 *   innovation. Multi-outcome is a planned post-audit extension, not a rewrite.
 *
 * @dev    TESTNET DEMO. Must be professionally audited before mainnet.
 *         Single-market design for demo legibility; production uses a factory.
 */
contract Market is Ownable {
    using SafeERC20 for IERC20;

    enum Outcome { UNRESOLVED, YES, NO }

    IERC20 public immutable usdc;
    ICollateralVault public immutable vault;
    IILCPool public immutable pool;

    string  public question;
    uint256 public immutable floorBps;      // 8000 = 80% loss floor
    uint256 public constant PREMIUM_BPS = 500;  // 5% of stake funds the pool

    Outcome public outcome;                  // starts UNRESOLVED
    bool    public resolved;

    // Per-trader stake on each side.
    mapping(address => uint256) public stakeYes;
    mapping(address => uint256) public stakeNo;
    // Track whether a trader has already claimed, so they can't double-claim.
    mapping(address => bool) public claimed;

    uint256 public totalYes;   // total staked on YES (net of premium)
    uint256 public totalNo;    // total staked on NO  (net of premium)

    event MarketCreated(string question, uint256 floorBps);
    event PositionOpened(address indexed trader, Outcome side, uint256 stake, uint256 premium);
    event MarketResolved(Outcome winningOutcome);
    event WinningsClaimed(address indexed trader, uint256 payout);
    event ILCCoverageClaimed(
        address indexed trader,
        uint256 grossLoss,
        uint256 covered,
        uint256 floorBps,
        uint256 poolBalanceAfter
    );

    constructor(
        address _usdc,
        address _vault,
        address _pool,
        string memory _question,
        uint256 _floorBps
    ) Ownable(msg.sender) {
        require(_usdc != address(0) && _vault != address(0) && _pool != address(0), "zero address");
        require(_floorBps <= 10000, "floor > 100%");
        usdc     = IERC20(_usdc);
        vault    = ICollateralVault(_vault);
        pool     = IILCPool(_pool);
        question = _question;
        floorBps = _floorBps;
        emit MarketCreated(_question, _floorBps);
    }

    /// Open a position on YES or NO by staking `amount` of USDC.
    /// Trader must `approve` this Market on the USDC token first.
    /// The stake (net of premium) goes to the Vault; the premium goes to the Pool.
    function openPosition(Outcome side, uint256 amount) external {
        require(!resolved, "market resolved");
        require(side == Outcome.YES || side == Outcome.NO, "bad side");
        require(amount > 0, "amount must be > 0");

        uint256 premium = (amount * PREMIUM_BPS) / 10000;
        uint256 net     = amount - premium;

        // Pull the full amount from the trader in one transfer.
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        // Forward the net stake to the Vault and the premium to the Pool.
        usdc.safeTransfer(address(vault), net);
        usdc.safeTransfer(address(pool), premium);

        if (side == Outcome.YES) {
            stakeYes[msg.sender] += net;
            totalYes += net;
        } else {
            stakeNo[msg.sender] += net;
            totalNo += net;
        }
        emit PositionOpened(msg.sender, side, net, premium);
    }

    /// Owner resolves the market to the winning outcome. (Demo: admin oracle.)
    function resolve(Outcome winningOutcome) external onlyOwner {
        require(!resolved, "already resolved");
        require(winningOutcome == Outcome.YES || winningOutcome == Outcome.NO, "bad outcome");
        outcome  = winningOutcome;
        resolved = true;
        emit MarketResolved(winningOutcome);
    }

    /// After resolution, each trader calls claim() once.
    /// Winners get their stake back plus a pro-rata share of the losing pool.
    /// Losers get ILC coverage: topped up to floorBps of their lost stake.
    function claim() external {
        require(resolved, "not resolved");
        require(!claimed[msg.sender], "already claimed");
        claimed[msg.sender] = true;

        uint256 myYes = stakeYes[msg.sender];
        uint256 myNo  = stakeNo[msg.sender];
        require(myYes > 0 || myNo > 0, "no position");

        bool yesWon = (outcome == Outcome.YES);
        uint256 myWin  = yesWon ? myYes : myNo;   // stake on the winning side
        uint256 myLoss = yesWon ? myNo  : myYes;  // stake on the losing side

        // WINNINGS: winning stake back + pro-rata share of the losers' pot.
        if (myWin > 0) {
            uint256 winPool  = yesWon ? totalYes : totalNo;   // total winning stake
            uint256 losePool = yesWon ? totalNo  : totalYes;  // total losing stake
            uint256 share    = winPool > 0 ? (losePool * myWin) / winPool : 0;
            uint256 payout   = myWin + share;
            vault.payout(msg.sender, payout);
            emit WinningsClaimed(msg.sender, payout);
        }

        // ILC COVERAGE: topped up to the floor on the losing stake.
        if (myLoss > 0) {
            uint256 covered = (myLoss * floorBps) / 10000;   // e.g. 80% of loss
            pool.payCoverage(msg.sender, covered);
            emit ILCCoverageClaimed(
                msg.sender,
                myLoss,
                covered,
                floorBps,
                usdc.balanceOf(address(pool))
            );
        }
    }
}