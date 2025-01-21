// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

/* solhint-disable max-line-length */

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILockManager} from "../interfaces/ILockManager.sol";
import {ILockToVoteBase} from "../interfaces/ILockToVoteBase.sol";
import {IMembership} from "@aragon/osx-commons-contracts/src/plugin/extensions/membership/IMembership.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";

/// @title LockToVoteBase
/// @author Aragon X 2024-2025
abstract contract LockToVoteBase is ILockToVoteBase, IMembership, ERC165Upgradeable {
    event LockManagerDefined(ILockManager lockManager);

    error NoVotingPower();
    error LockManagerAlreadyDefined();

    /// @inheritdoc ILockToVoteBase
    ILockManager public lockManager;

    /// @notice Initializes the component to be used by inheriting contracts.
    /// @param _lockManager The address of the contract with the ability to manager votes on behalf of users.
    function __LockToVoteBase_init(ILockManager _lockManager) internal onlyInitializing {
        _setLockManager(_lockManager);
    }

    /// @notice Checks if this or the parent contract supports an interface by its ID.
    /// @param _interfaceId The ID of the interface.
    /// @return Returns `true` if the interface is supported.
    function supportsInterface(bytes4 _interfaceId) public view virtual override(ERC165Upgradeable) returns (bool) {
        return
            _interfaceId == type(ILockToVoteBase).interfaceId ||
            _interfaceId == type(IMembership).interfaceId ||
            super.supportsInterface(_interfaceId);
    }

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

    function _setLockManager(ILockManager _lockManager) private {
        if (address(lockManager) != address(0)) {
            revert LockManagerAlreadyDefined();
        }

        lockManager = _lockManager;

        emit LockManagerDefined(_lockManager);
    }

    /// @notice This empty reserved space is put in place to allow future versions to add
    /// new variables without shifting down storage in the inheritance chain
    /// (see [OpenZeppelin's guide about storage gaps]
    /// (https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps)).
    uint256[49] private __gap;
}
