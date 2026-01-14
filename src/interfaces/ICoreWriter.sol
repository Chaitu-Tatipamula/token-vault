// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ICoreWriter
 * @notice Interface for HyperLiquid's CoreWriter contract.
 * @dev Handles interactions with the HyperEVM native bridge and core actions.
 */
interface ICoreWriter {
    /**
     * @notice Executes a specific action on the HyperCore L1/L2 bridge.
     * @param actionId The ID of the action to execute (e.g., 2 for HLP Deposit).
     * @param params ABI-encoded parameters specific to the action ID.
     */
    function ensureAction(uint256 actionId, bytes calldata params) external payable;
}
