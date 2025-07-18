// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.13;

import {LockManagerBase} from "./base/LockManagerBase.sol";
import {ILockManager, LockManagerSettings} from "./interfaces/ILockManager.sol";

/// @title LockManagerNative
/// @author Aragon X 2025
/// @notice Helper contract acting as the vault for locked tokens used to vote on multiple plugins and proposals.
contract LockManagerNative is ILockManager, LockManagerBase {
    /// @notice Thrown when msg.value doesn't match with the requested `_amount` of tokens to lock
    error IncomingBalanceMismatch(uint256 requested, uint256 actual);

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

    /// @inheritdoc LockManagerBase
    function _incomingTokenBalance() internal view virtual override returns (uint256) {
        return msg.value;
    }

    /// @inheritdoc LockManagerBase
    function _doLockTransfer(uint256 _amount) internal virtual override {
        if (_incomingTokenBalance() != _amount) {
            revert IncomingBalanceMismatch({requested: _amount, actual: _incomingTokenBalance()});
        }
    }

    /// @inheritdoc LockManagerBase
    function _doUnlockTransfer(address _recipient, uint256 _amount) internal virtual override {
        payable(_recipient).transfer(_amount);
    }
}
