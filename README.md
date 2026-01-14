# Token Metrics Vault - Technical Documentation

## 1. Project Overview & Philosophy
This project implements a **Next-Generation ERC-4626 Vault** designed for an environment where underlying yield sources are not always liquid.

Standard ERC-4626 vaults assume you can always withdraw assets immediately. in the real world (and specifically for this assignment), strategies like Staking or Real World Assets (RWAs) have **Lockup Periods**.

**The Solution**: This vault implements a **Hybrid Withdrawal System**:
- **Fast Path**: If the vault has floating cash ("Idle"), withdrawals are instant.
- **Slow Path (Queue)**: If liquidity is locked in strategies, withdrawals are queued via `requestWithdrawal`.

This ensures the vault remains **Solvent** (doesn't promise what it can't pay) and **Fair** (share price isn't manipulated by desperate withdrawals).

---

## 2. Smart Contract Deep Dive

### A. `TokenMetricsVault.sol` (The Core)
This is the main entry point for users. It manages accounting, strategies, and permissions.

#### 🏰 Core Accounting
- **`totalAssets()`**: 
    - *Why?* To calculate the share price (`assets / shares`).
    - *Logic*: It sums `Idle Cash` + `Strategy Balances` - `Pending Claims`.
    - *Note*: We subtract `_totalClaimableAssets` because those funds technically belong to users who already requested a withdrawal (burnt their shares), so they shouldn't count towards the *remaining* share price.

#### ⚙️ Strategy Management
- **`addStrategy(address)`**: Registers a new yield source.
- **`setAllocation(address, bps)`**: 
    - *Why?* To define portfolio diversification (e.g., 60% A, 40% B).
    - *Safety*: Enforces `maxAllocationBps` (Safety Cap) to prevent putting all eggs in one basket.
- **`rebalance()`**:
    - *Why?* The vault accepts deposits into Idle. Money sitting in Idle earns 0%.
    - *Logic*: This function calculates the target amount for each strategy based on allocations and pushes Idle funds into them. This is the "Engine" that puts capital to work.

#### 🚪 Withdrawal Logic (The Complex Part)
- **`withdraw()` (Standard)**:
    - *Logic*: Checks `Idle` balance. If sufficient -> pays out. If insufficient -> tries to withdraw from Strategies (if they are liquid). If still insufficient -> **REVERTS**.
    - *Why Revert?* To protect the vault. If we partially filled, it would be messy. If we force-withdrew from a locked strategy, it would fail.
- **`requestWithdrawal(assets)`**:
    - *Why?* Called when `withdraw()` fails due to lockups.
    - *Logic*: 
        1. **Burns Shares Immediately**: This "locks in" the user's value at the current share price. They are no longer exposed to future yield or loss.
        2. **Queues Request**: Adds an item to `withdrawalQueue`.
- **`replenishLiquidity(amount)`**:
    - *Why?* The Manager sees the queue piling up. They wait for a strategy to unlock (or find liquidity elsewhere) and call this to pull funds back into Idle specifically to satisfy the queue.
- **`claimWithdrawal()`**:
    - *Logic*: The user comes back later. If `replenishLiquidity` did its job, there is now enough Idle. The user claims their frozen assets.

### B. `HyperCoreStrategy.sol` (Stretch Goal)
This represents integration with the "HyperLiquid" ecosystem.
- **`deposit(amount)`**: 
    - *Logic*: Instead of just holding funds, it bridges them by calling `ICoreWriter.ensureAction(2, ...)`.
    - *Why?* `Action ID 2` is the specific instruction for "Deposit" in the HyperCore protocol. This proves the system can interact with specific external DeFi primitives.

### C. `MockStrategy.sol` (Testing Tool)
- **`setLockup(duration)`**: Allows us to *simulate* a locked staking contract during tests to verify the Queue logic works.
- **`simulateYield()`**: Magically increases the `totalAssets` of the strategy to test that the Vault's share price goes Up.

---

## 3. Deployment & Testing

### Directory Structure
- `src/`: Solidity contracts.
- `test/`: Foundry test suite.
- `script/`: Deployment scripts.

### How to Verify
1.  **Standard Tests**: `forge test` (Runs all 7 tests).
2.  **Specific Scenario**: `forge test --match-contract SpecificScenarioTest`
    - *What it tests*: The 60/40 Split, 10% Yield Gain, and Lockup/Queue flow.
3.  **HyperCore**: `forge test --match-contract HyperCoreTest`
    - *What it tests*: Verifies `Action ID 2` is emitted.

### Deployment
To deploy to a testnet:
```bash
forge script script/Deploy.s.sol --rpc-url <URL> --private-key <KEY> --broadcast
```
