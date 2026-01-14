// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ICoreWriter} from "../interfaces/ICoreWriter.sol";

contract MockHyperCore is ICoreWriter {
    event ActionExecuted(uint256 actionId, bytes params);

    function ensureAction(
        uint256 actionId,
        bytes calldata params
    ) external payable override {
        emit ActionExecuted(actionId, params);
    }
}
