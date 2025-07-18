// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.13;

import {LockManagerBase} from "./base/LockManagerBase.sol";
import {ILockManager, LockManagerSettings} from "./interfaces/ILockManager.sol";

/// @title LockManagerNative
/// @author Aragon X 2025
/// @notice Helper contract acting as the vault for locked tokens used to vote on multiple plugins and proposals.
contract LockManagerNative is ILockManager, LockManagerBase {
    /// @param _settings The operation mode of the contract (plugin mode)
    constructor(LockManagerSettings memory _settings) LockManagerBase(_settings) {}

    // Overrides

    /// @inheritdoc ILockManager
    function token() public view virtual returns (address _token) {
        /// @dev Returning address(0) as there is no token
    }

    /// @inheritdoc ILockManager
    function underlyingToken() public view virtual returns (address _underlyingToken) {
        /// @dev Returning address(0) as there is no token
    }

    // Internal overrides

    function _transfer(address _recipient, uint256 _amount) internal virtual override {
        payable(_recipient).transfer(_amount);
    }

    function _lock() internal virtual override {
        uint256 _lockedValue = msg.value;
        if (_lockedValue == 0) {
            revert NoBalance();
        }

        lockedBalances[msg.sender] += _lockedValue;
        emit BalanceLocked(msg.sender, _lockedValue);
    }
}
