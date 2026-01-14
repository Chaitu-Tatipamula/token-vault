// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

interface IStrategy {
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function totalAssets() external view returns (uint256);
}

/**
 * @title TokenMetricsVault
 * @notice An ERC-4626 compliant vault with multi-strategy routing and a withdrawal queue.
 * @dev Manages deposits, withdrawals, and capital allocation across multiple strategies.
 *      Tracks 'claimable' assets for queued withdrawals to ensure fair pricing.
 */
contract TokenMetricsVault is ERC4626, AccessControl, Pausable, ReentrancyGuard {
    using Math for uint256;

    /// @notice Role identifier for vault managers who can rebalance and set allocations.
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    struct StrategyInfo {
        bool isActive; /// @dev Whether the strategy is approved for use.
        uint256 allocationBps; /// @dev Target allocation in basis points (10000 = 100%).
    }

    /// @notice List of all added strategies.
    address[] public strategies;

    /// @notice Mapping of strategy address to configuration info.
    mapping(address => StrategyInfo) public strategyInfo;

    // --- Withdrawal Queue Structs ---
    struct WithdrawalRequest {
        uint256 shares; /// @dev Shares burned for this request.
        uint256 assets; /// @dev Assets expected (locked at request time).
        uint256 claimableAssets; /// @dev Amount currently available to claim.
        uint256 requestTime; /// @dev Timestamp when request was made.
        bool processed; /// @dev Whether the request is fully satisfied.
    }

    /// @notice Queue of withdrawal requests per user.
    mapping(address => WithdrawalRequest[]) public withdrawalQueue;

    /// @notice Amount of assets currently ready to be claimed by a specific user.
    mapping(address => uint256) public userClaimableAssets;

    // --- Events ---
    event StrategyAdded(address indexed strategy);
    event StrategyRemoved(address indexed strategy);
    event AllocationUpdated(address indexed strategy, uint256 newAllocation);
    event WithdrawalRequested(address indexed user, uint256 shares, uint256 assets);
    event WithdrawalClaimed(address indexed user, uint256 assets);
    event FundsRebalanced();
    event SharePriceSnapshot(uint256 timestamp, uint256 sharePrice, uint256 totalAssets, uint256 totalSupply);

    /// @notice Safety cap for maximum allocation to a single strategy (bps).
    uint256 public maxAllocationBps;

    /// @notice Private tracking of total assets reserved for queued withdrawals.
    uint256 private _totalClaimableAssets;

    /**
     * @notice Initializes the vault with an underlying asset and admin.
     * @param _asset The ERC20 underlying asset (e.g., USDC).
     * @param _admin The address granted DEFAULT_ADMIN_ROLE and MANAGER_ROLE.
     */
    constructor(IERC20 _asset, address _admin) ERC4626(_asset) ERC20("TokenMetrics Vault", "tmUSDC") {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(MANAGER_ROLE, _admin);
        maxAllocationBps = 9000; // Default 90%
    }

    /**
     * @notice Sets the maximum allocation allowed for any single strategy.
     * @param _bps The new maximum basis points (<= 10000).
     */
    function setMaxAllocation(uint256 _bps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_bps <= 10000, "Invalid BPS");
        maxAllocationBps = _bps;
    }

    /**
     * @notice Calculates the total managed assets.
     * @dev Sums idle cash and strategy balances, subtracting reserved claimable assets.
     * @return The total amount of assets controlled by the vault (excluding queued claims).
     */
    function totalAssets() public view override returns (uint256) {
        uint256 assets = IERC20(asset()).balanceOf(address(this));

        uint256 len = strategies.length;
        for (uint256 i = 0; i < len; i++) {
            if (strategyInfo[strategies[i]].isActive) {
                assets += IStrategy(strategies[i]).totalAssets();
            }
        }

        uint256 allClaimable = getTotalClaimable();
        if (assets >= allClaimable) {
            return assets - allClaimable;
        } else {
            return 0;
        }
    }

    /**
     * @notice Returns total assets reserved for pending withdrawals.
     */
    function getTotalClaimable() public view returns (uint256 total) {
        return _totalClaimableAssets;
    }

    // --- Strategy Management ---

    /**
     * @notice Adds a new strategy to the vault.
     * @param _strategy The address of the strategy contract.
     */
    function addStrategy(address _strategy) external onlyRole(MANAGER_ROLE) {
        require(!strategyInfo[_strategy].isActive, "Already active");
        strategies.push(_strategy);
        strategyInfo[_strategy] = StrategyInfo({isActive: true, allocationBps: 0});
        emit StrategyAdded(_strategy);
    }

    /**
     * @notice Updates the target allocation for a strategy.
     * @param _strategy The strategy address.
     * @param _bps Target allocation in basis points.
     */
    function setAllocation(address _strategy, uint256 _bps) external onlyRole(MANAGER_ROLE) {
        require(strategyInfo[_strategy].isActive, "Strategy not active");
        require(_bps <= maxAllocationBps, "Exceeds Safety Cap");
        strategyInfo[_strategy].allocationBps = _bps;
        emit AllocationUpdated(_strategy, _bps);
    }

    /**
     * @notice Rebalances vault assets across strategies according to allocations.
     * @dev Pushes idle funds to strategies where current balance < target.
     */
    function rebalance() external onlyRole(MANAGER_ROLE) {
        uint256 totalVaultAssets = totalAssets();
        uint256 idle = IERC20(asset()).balanceOf(address(this)) - _totalClaimableAssets;

        uint256 len = strategies.length;
        for (uint256 i = 0; i < len; i++) {
            address str = strategies[i];
            StrategyInfo memory info = strategyInfo[str];
            if (info.isActive && info.allocationBps > 0) {
                uint256 currentStratAssets = IStrategy(str).totalAssets();
                uint256 target = (totalVaultAssets * info.allocationBps) / 10000;

                if (currentStratAssets < target) {
                    uint256 diff = target - currentStratAssets;
                    // Cap deposit at available idle
                    uint256 amountToDeposit = idle >= diff ? diff : idle;

                    if (amountToDeposit > 0) {
                        IERC20(asset()).approve(str, amountToDeposit);
                        IStrategy(str).deposit(amountToDeposit);
                        idle -= amountToDeposit;
                    }
                }
            }
        }
        emit FundsRebalanced();
        _emitSnapshot();
    }

    // --- Withdrawal Queue ---

    /**
     * @notice Standard ERC-4626 withdraw. Reverts if insufficient liquid funds.
     * @dev Attempts to pull from strategies if idle is insufficient.
     */
    function withdraw(uint256 assets, address receiver, address owner) public override whenNotPaused returns (uint256) {
        uint256 idle = IERC20(asset()).balanceOf(address(this)) - _totalClaimableAssets;

        if (idle < assets) {
            uint256 needed = assets - idle;
            uint256 len = strategies.length;
            for (uint256 i = 0; i < len; i++) {
                if (needed == 0) break;
                address str = strategies[i];
                try IStrategy(str).withdraw(needed) {
                    uint256 pulled = IERC20(asset()).balanceOf(address(this)) - _totalClaimableAssets - idle;
                    if (pulled >= needed) {
                        needed = 0;
                    } else {
                        needed -= pulled;
                    }
                } catch {
                    // Continue to next strategy if this one fails/locks
                }
            }
            require(needed == 0, "Insufficient liquidity. Use requestWithdrawal.");
        }
        return super.withdraw(assets, receiver, owner);
    }

    /**
     * @notice Requests a withdrawal when liquidity is insufficient.
     * @dev Burns shares immediately to lock in value, then queues request.
     * @param assets Amount of assets requested.
     */
    function requestWithdrawal(uint256 assets) external nonReentrant whenNotPaused {
        uint256 shares = previewWithdraw(assets);
        _burn(msg.sender, shares);

        userClaimableAssets[msg.sender] += assets;
        _totalClaimableAssets += assets;

        withdrawalQueue[msg.sender].push(
            WithdrawalRequest({
                shares: shares, assets: assets, claimableAssets: assets, requestTime: block.timestamp, processed: false
            })
        );

        emit WithdrawalRequested(msg.sender, shares, assets);
    }

    /**
     * @notice Claims assets from a previously queued withdrawal.
     */
    function claimWithdrawal() external nonReentrant whenNotPaused {
        uint256 amount = userClaimableAssets[msg.sender];
        require(amount > 0, "Nothing to claim");

        uint256 idle = IERC20(asset()).balanceOf(address(this));
        require(idle >= amount, "Vault still illiquid");

        userClaimableAssets[msg.sender] = 0;
        _totalClaimableAssets -= amount;

        IERC20(asset()).transfer(msg.sender, amount);
        emit WithdrawalClaimed(msg.sender, amount);
    }

    /**
     * @notice Manager function to pull liquidity specifically to satisfy the queue.
     * @param amount Amount of liquidity to attempt to pull.
     */
    function replenishLiquidity(uint256 amount) external onlyRole(MANAGER_ROLE) {
        uint256 needed = amount;
        uint256 len = strategies.length;

        for (uint256 i = 0; i < len; i++) {
            if (needed == 0) break;
            address str = strategies[i];

            uint256 balanceBefore = IERC20(asset()).balanceOf(address(this));
            try IStrategy(str).withdraw(needed) {
                uint256 balanceAfter = IERC20(asset()).balanceOf(address(this));
                uint256 pulled = balanceAfter - balanceBefore;
                if (pulled >= needed) {
                    needed = 0;
                } else {
                    needed -= pulled;
                }
            } catch {}
        }
    }

    function pause() external onlyRole(MANAGER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(MANAGER_ROLE) {
        _unpause();
    }

    function _emitSnapshot() internal {
        uint256 price = 0;
        if (totalSupply() > 0) {
            price = convertToAssets(10 ** decimals());
        }
        emit SharePriceSnapshot(block.timestamp, price, totalAssets(), totalSupply());
    }

    // --- Overrides with Snapshot ---

    function deposit(uint256 assets, address receiver) public virtual override whenNotPaused returns (uint256) {
        uint256 ret = super.deposit(assets, receiver);
        _emitSnapshot();
        return ret;
    }

    function mint(uint256 shares, address receiver) public virtual override whenNotPaused returns (uint256) {
        uint256 ret = super.mint(shares, receiver);
        _emitSnapshot();
        return ret;
    }

    function redeem(uint256 shares, address receiver, address owner)
        public
        virtual
        override
        whenNotPaused
        returns (uint256)
    {
        uint256 ret = super.redeem(shares, receiver, owner);
        _emitSnapshot();
        return ret;
    }
}
