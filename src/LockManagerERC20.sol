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
    IERC20 private immutable erc20Token;

    /// @param _settings The operation mode of the contract (plugin mode)
    /// @param _token The address of the token contract that users can lock
    constructor(LockManagerSettings memory _settings, IERC20 _token) LockManagerBase(_settings) {
        erc20Token = _token;
    }

    /// @inheritdoc ILockManager
    /// @dev Not having `token` as a public variable because the return types would differ (address vs IERC20)
    function token() public view virtual returns (address _token) {
        return address(erc20Token);
    }

    // Overrides

    /// @inheritdoc LockManagerBase
    function _incomingTokenBalance() internal view virtual override returns (uint256) {
        return erc20Token.allowance(msg.sender, address(this));
    }

    /// @inheritdoc LockManagerBase
    function _doLockTransfer(uint256 _amount) internal virtual override {
        erc20Token.transferFrom(msg.sender, address(this), _amount);
    }

    /// @inheritdoc LockManagerBase
    function _doUnlockTransfer(address _recipient, uint256 _amount) internal virtual override {
        erc20Token.transfer(_recipient, _amount);
    }
}
