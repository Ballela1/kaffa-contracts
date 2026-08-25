// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// OpenZeppelin v5 audited ERC-20 base. Remix resolves this import automatically.
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockUSDC
 * @notice Test-only USDC stand-in for the Kaffa ILC demo on Base Sepolia.
 *         Mirrors real USDC semantics: 6 decimals, ERC-20 transfer/approve.
 *         NOT for mainnet. On mainnet, the real Circle USDC address is used
 *         instead (see KEL-ENG-2026-SPEC-001 §X.2 — address binding).
 * @dev    `mint` is intentionally open so anyone can fund test wallets on the
 *         testnet faucet-style. This is acceptable ONLY because the token is
 *         worthless play money. Never ship an open mint to mainnet.
 */
contract MockUSDC is ERC20 {
    uint8 private constant _DECIMALS = 6;

    constructor() ERC20("Mock USD Coin", "USDC") {
        // Seed the deployer with 1,000,000 test USDC (1_000_000 * 10^6).
        _mint(msg.sender, 1_000_000 * 10 ** _DECIMALS);
    }

    /// @notice USDC uses 6 decimals, not the ERC-20 default of 18.
    function decimals() public pure override returns (uint8) {
        return _DECIMALS;
    }

    /**
     * @notice Mint test USDC to any address. Testnet convenience only.
     * @param to     recipient wallet
     * @param amount raw units at 6 decimals (e.g. 10_000 USDC = 10_000_000_000)
     */
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}