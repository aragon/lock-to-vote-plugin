// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

import {ILockToGovernBase} from "../interfaces/ILockToGovernBase.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPermissionCondition} from "@aragon/osx-commons-contracts/src/permission/condition/IPermissionCondition.sol";
import {PermissionCondition} from "@aragon/osx-commons-contracts/src/permission/condition/PermissionCondition.sol";

/// @title MinVotingPowerCondition
/// @author Aragon X - 2024
/// @notice Checks if an account's voting power or token balance meets the threshold defined on the given plugin.
/// @custom:security-contact sirt@aragon.org
contract MinVotingPowerCondition is PermissionCondition {
    /// @notice The address of the `ILockToGovernBase` plugin used to fetch the settings from.
    ILockToGovernBase public immutable plugin;

    /// @notice The `IERC20` token interface used to check token balance.
    IERC20 public immutable token;

    /// @notice Initializes the contract with the `ILockToGovernBase` plugin address and caches the associated token.
    /// @param _plugin The address of the `ILockToGovernBase` plugin.
    constructor(ILockToGovernBase _plugin) {
        plugin = _plugin;
        token = plugin.token();
    }

    /// @inheritdoc IPermissionCondition
    /// @dev The function checks both the voting power and token balance to ensure `_who` meets the minimum voting
    ///      threshold defined in the `TokenVoting` plugin. Returns `false` if the minimum requirement is unmet.
    function isGranted(address _where, address _who, bytes32 _permissionId, bytes calldata _data)
        public
        view
        override
        returns (bool)
    {
        (_where, _data, _permissionId);

        uint256 minProposerVotingPower_ = plugin.minProposerVotingPower();

        if (token.balanceOf(_who) < minProposerVotingPower_) {
            return false;
        }

        return true;
    }
}
