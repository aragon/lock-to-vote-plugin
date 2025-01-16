// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

/* solhint-disable max-line-length */

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILockManager} from "../interfaces/ILockManager.sol";
import {ILockToVoteBase} from "../interfaces/ILockToVoteBase.sol";
import {IMembership} from "@aragon/osx-commons-contracts/src/plugin/extensions/membership/IMembership.sol";

/// @title LockToVoteBase
/// @author Aragon X 2024-2025
abstract contract LockToVoteBase is ILockToVoteBase, IMembership {
    /// @inheritdoc ILockToVoteBase
    ILockManager public lockManager;

    /// @inheritdoc ILockToVoteBase
    function token() external view returns (IERC20) {
        return lockManager.token();
    }

    /// @inheritdoc ILockToVoteBase
    function underlyingToken() external view returns (IERC20) {
        return lockManager.underlyingToken();
    }

    /// @inheritdoc IMembership
    function isMember(address _account) external view returns (bool) {
        if (lockManager.lockedBalances(_account) > 0) return true;
        else if (lockManager.token().balanceOf(_account) > 0) return true;
        return false;
    }

}
