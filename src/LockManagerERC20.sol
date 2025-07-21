// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.13;

import {LockManagerBase} from "./base/LockManagerBase.sol";
import {ILockManager} from "./interfaces/ILockManager.sol";
import {LockManagerSettings} from "./interfaces/ILockManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title LockManagerERC20
/// @author Aragon X 2025
/// @notice Helper contract acting as the vault for locked tokens used to vote on multiple plugins and proposals.
contract LockManagerERC20 is ILockManager, LockManagerBase {
    /// @notice The address of the token contract used to determine the voting power
    IERC20 private immutable tokenAddr;

    /// @notice If applicable, the address of the underlying token from which "token" originates. Zero otherwise.
    /// @dev This is relevant in cases where the main token can experience swift deviations in supply, whereas the underlying token is much more stable
    IERC20 private immutable underlyingTokenAddr;

    /// @param _settings The operation mode of the contract (plugin mode)
    /// @param _token The address of the token contract that users can lock
    /// @param _underlyingToken If applicable, the address of the contract from which `token` originates. This is relevant for LP tokens whose supply may experience swift changes.
    constructor(LockManagerSettings memory _settings, IERC20 _token, IERC20 _underlyingToken)
        LockManagerBase(_settings)
    {
        tokenAddr = _token;
        underlyingTokenAddr = _underlyingToken;
    }

    /// @inheritdoc ILockManager
    function token() public view virtual returns (address _token) {
        return address(tokenAddr);
    }

    /// @inheritdoc ILockManager
    function underlyingToken() public view virtual returns (address) {
        if (address(underlyingTokenAddr) == address(0)) {
            return address(tokenAddr);
        }
        return address(underlyingTokenAddr);
    }

    // Overrides

    /// @inheritdoc LockManagerBase
    function _transfer(address _recipient, uint256 _amount) internal virtual override {
        tokenAddr.transfer(_recipient, _amount);
    }

    /// @inheritdoc LockManagerBase
    function _lock() internal virtual override {
        uint256 _allowance = tokenAddr.allowance(msg.sender, address(this));
        if (_allowance == 0) {
            revert NoBalance();
        }

        tokenAddr.transferFrom(msg.sender, address(this), _allowance);
        lockedBalances[msg.sender] += _allowance;
        emit BalanceLocked(msg.sender, _allowance);
    }
}
