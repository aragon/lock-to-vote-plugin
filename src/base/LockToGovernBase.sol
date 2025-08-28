// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

/* solhint-disable max-line-length */

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILockManager} from "../interfaces/ILockManager.sol";
import {ILockToGovernBase} from "../interfaces/ILockToGovernBase.sol";
import {IMembership} from "@aragon/osx-commons-contracts/src/plugin/extensions/membership/IMembership.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";

/// @title LockToGovernBase
/// @author Aragon X 2024-2025
abstract contract LockToGovernBase is ILockToGovernBase, IMembership, ERC165Upgradeable {
    /// @notice Emitted when the address of the LockManager is set.
    /// @param lockManager The address of the LockManager contract
    event LockManagerDefined(ILockManager indexed lockManager);

    /// @notice Thrown when creating a proposal without any locked tokens.
    error NoVotingPower();

    /// @notice Thrown when attempting to define the address of the LockManager after it was already set.
    error LockManagerAlreadyDefined();

    /// @inheritdoc ILockToGovernBase
    ILockManager public lockManager;

    /// @notice Initializes the component to be used by inheriting contracts.
    /// @param _lockManager The address of the contract with the ability to manager votes on behalf of users.
    function __LockToGovernBase_init(ILockManager _lockManager) internal onlyInitializing {
        _setLockManager(_lockManager);
    }

    /// @notice Checks if this or the parent contract supports an interface by its ID.
    /// @param _interfaceId The ID of the interface.
    /// @return Returns `true` if the interface is supported.
    function supportsInterface(bytes4 _interfaceId) public view virtual override(ERC165Upgradeable) returns (bool) {
        return _interfaceId == type(ILockToGovernBase).interfaceId || _interfaceId == type(IMembership).interfaceId
            || super.supportsInterface(_interfaceId);
    }

    /// @inheritdoc ILockToGovernBase
    function token() public view returns (IERC20) {
        return IERC20(lockManager.token());
    }

    /// @inheritdoc IMembership
    function isMember(address _account) external view returns (bool) {
        if (lockManager.getLockedBalance(_account) > 0) return true;

        IERC20 _token = token();
        if (address(_token) != address(0)) {
            if (_token.balanceOf(_account) > 0) return true;
        }

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
