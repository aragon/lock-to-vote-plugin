// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.13;

import {LockManagerBase} from "./base/LockManagerBase.sol";
import {ILockManager} from "./interfaces/ILockManager.sol";
import {LockManagerSettings} from "./interfaces/ILockManager.sol";
import {ILockToApprove} from "./interfaces/ILockToApprove.sol";
import {ILockToVote} from "./interfaces/ILockToVote.sol";
import {IMajorityVoting} from "./interfaces/IMajorityVoting.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title LockManagerERC20Rebase
/// @author Aragon X 2025
/// @notice Helper contract acting as the vault for locked rebasing tokens
/// used to vote on multiple plugins and proposals. It ensures accrued yield is fairly distributed.
contract LockManagerERC20Rebasing is ILockManager, LockManagerBase {
    /// @notice The address of the rebasing token contract
    IERC20 private immutable tokenAddr;

    /// @notice Mapping from an address to the number of shares it owns.
    mapping(address => uint256) private shares;

    /// @notice Total number of shares distributed among all depositors.
    uint256 public totalShares;

    /// @param _settings The operation mode of the contract (plugin mode)
    /// @param _token The address of the rebasing token contract that users can lock
    ///     This is relevant for LP tokens whose supply may experiment swift changes.
    constructor(LockManagerSettings memory _settings, IERC20 _token) LockManagerBase(_settings) {
        tokenAddr = _token;
    }

    /// @inheritdoc ILockManager
    function token() public view virtual returns (address) {
        return address(tokenAddr);
    }

    /// @notice Returns the amount of shares owned by _account
    function getLockedBalance(address _account) public view override(ILockManager, LockManagerBase) returns (uint256) {
        return shares[_account];
    }

    /// @notice Converts a number of shares into the corresponding amount of the token.
    /// @param _shareAmount The amount of shares to convert.
    /// @return The equivalent token amount.
    function sharesToTokenBalance(uint256 _shareAmount) public view returns (uint256) {
        if (totalShares == 0) {
            return _shareAmount;
        }
        // assets = (shares * totalTokenAmount) / totalShares
        return (_shareAmount * tokenAddr.balanceOf(address(this))) / totalShares;
    }

    // Locking overrides

    /// @inheritdoc LockManagerBase
    function _lock(uint256 _amountToLock) internal virtual override {
        if (_amountToLock == 0) {
            revert NoBalance();
        }

        // Get the contract's token balance before the new deposit.
        uint256 _currentManagerBalance = tokenAddr.balanceOf(address(this));

        uint256 sharesToMint;
        if (totalShares == 0 || _currentManagerBalance == 0) {
            // If this is the first deposit, shares minted are 1:1 with the amount.
            sharesToMint = _amountToLock;
        } else {
            // Calculate shares based on the current ratio:
            // shares = (amount * totalShares) / totalTokenAmount
            sharesToMint = (_amountToLock * totalShares) / _currentManagerBalance;
        }

        /// @dev Reverts if not enough balance is approved
        _doLockTransfer(_amountToLock);

        totalShares += sharesToMint;
        shares[msg.sender] += sharesToMint;
        emit BalanceLocked(msg.sender, _amountToLock);
    }

    /// @inheritdoc ILockManager
    function unlock() public virtual override(ILockManager, LockManagerBase) {
        uint256 userShares = getLockedBalance(msg.sender);
        if (userShares == 0) {
            revert NoBalance();
        }

        // Attempt to remove any active votes before doing anything. The plugin may revert.
        _withdrawActiveVotingPower();

        // Calculate how many tokens the user's shares are worth now
        uint256 balanceToUnlock = sharesToTokenBalance(userShares);

        // Burn the user's shares
        totalShares -= userShares;
        shares[msg.sender] = 0;

        _doUnlockTransfer(msg.sender, balanceToUnlock);
        emit BalanceUnlocked(msg.sender, balanceToUnlock);
    }

    // Internal transfer overrides

    /// @inheritdoc LockManagerBase
    function _incomingTokenBalance() internal view virtual override returns (uint256) {
        return tokenAddr.allowance(msg.sender, address(this));
    }

    /// @inheritdoc LockManagerBase
    function _doLockTransfer(uint256 _amount) internal virtual override {
        tokenAddr.transferFrom(msg.sender, address(this), _amount);
    }

    /// @inheritdoc LockManagerBase
    function _doUnlockTransfer(address _recipient, uint256 _amount) internal virtual override {
        tokenAddr.transfer(_recipient, _amount);
    }
}
