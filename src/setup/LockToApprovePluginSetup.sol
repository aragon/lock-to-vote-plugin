// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {DAO} from "@aragon/osx/src/core/dao/DAO.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {PluginSetup, IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/PluginSetup.sol";
import {LockToApprovePlugin} from "../LockToApprovePlugin.sol";
import {LockManager} from "../LockManager.sol";
import {LockManagerSettings, PluginMode} from "../../src/interfaces/ILockManager.sol";
import {ILockToGovernBase} from "../../src/interfaces/ILockToGovernBase.sol";
import {MinVotingPowerCondition} from "../../src/conditions/MinVotingPowerCondition.sol";
import {createProxyAndCall} from "../util/proxy.sol";

/// @title LockToApprovePluginSetup
/// @author Aragon X - 2022-2025
/// @notice The setup contract of the `LockToApprovePlugin` contract.
/// @custom:security-contact sirt@aragon.org
contract LockToApprovePluginSetup is PluginSetup {
    using Address for address;
    using Clones for address;
    using ERC165Checker for address;

    /// @notice The address of the `LockManager` implementation.
    LockManager private immutable lockManagerImpl;

    /// @notice Struct containing all the parameters to set up the plugin, helpers and permissions
    /// @param token The address of the token that users can lock for voting (staking token in most cases)
    /// @param underlyingToken If users obtain `token` by staking another token, the address of that token. Zero otherwise.
    /// @param approvalSettings The plugin settings
    /// @param pluginMetadata An IPFS URI pointing to a pinned JSON file with the plugin's details
    /// @param createProposalCaller The address that can call createProposal (can be ANY_ADDR)
    /// @param executeCaller The address that can call execute (can be ANY_ADDR)
    /// @param targetConfig Where and how the plugin will execute actions
    struct InstallationParameters {
        IERC20 token;
        IERC20 underlyingToken;
        LockToApprovePlugin.ApprovalSettings approvalSettings;
        bytes pluginMetadata;
        address createProposalCaller;
        address executeCaller;
        IPlugin.TargetConfig targetConfig;
    }

    /// @notice Thrown if token address is passed which is not a token.
    /// @param token The token address
    error TokenNotContract(address token);

    /// @notice Thrown if token address is not ERC20.
    /// @param token The token address
    error TokenNotERC20(address token);

    /// @notice Thrown if passed helpers array is of wrong length.
    /// @param length The array length of passed helpers.
    error WrongHelpersArrayLength(uint256 length);

    /// @notice The contract constructor deploying the implementation contracts to use.
    constructor() PluginSetup(address(new LockToApprovePlugin())) {
        lockManagerImpl = new LockManager(LockManagerSettings(PluginMode(0)), IERC20(address(0)), IERC20(address(0)));
    }

    /// @inheritdoc IPluginSetup
    function prepareInstallation(address _dao, bytes calldata _installParameters)
        external
        returns (address plugin, PreparedSetupData memory preparedSetupData)
    {
        // Decode `_installParameters` to extract the params needed for deploying and initializing `LockToApprovePlugin` contract,
        // and the required helpers
        InstallationParameters memory installationParams = decodeInstallationParams(_installParameters);

        // Prepare helpers.
        address[] memory helpers = new address[](3);

        // Lock Manager
        helpers[0] = address(
            new LockManager(
                LockManagerSettings(PluginMode.Approval), installationParams.token, installationParams.underlyingToken
            )
        );

        if (!address(installationParams.token).isContract()) {
            revert TokenNotContract(address(installationParams.token));
        } else if (!_supportsErc20(address(installationParams.token))) {
            revert TokenNotERC20(address(installationParams.token));
        }

        if (address(installationParams.underlyingToken) != address(0)) {
            if (!address(installationParams.underlyingToken).isContract()) {
                revert TokenNotContract(address(installationParams.underlyingToken));
            } else if (!_supportsErc20(address(installationParams.underlyingToken))) {
                revert TokenNotERC20(address(installationParams.underlyingToken));
            }
        }

        // Prepare and deploy plugin proxy.
        plugin = createProxyAndCall(
            implementation(),
            abi.encodeCall(
                LockToApprovePlugin.initialize,
                (
                    IDAO(_dao),
                    LockManager(helpers[0]),
                    installationParams.approvalSettings,
                    installationParams.targetConfig,
                    installationParams.pluginMetadata
                )
            )
        );
        LockManager(helpers[0]).setPluginAddress(ILockToGovernBase(plugin));

        // Condition
        address minVotingPowerCondition = address(new MinVotingPowerCondition(ILockToGovernBase(plugin)));
        helpers[1] = installationParams.createProposalCaller;
        helpers[2] = installationParams.executeCaller;

        LockToApprovePlugin impl = LockToApprovePlugin(implementation());

        // Request the permissions to be granted
        PermissionLib.MultiTargetPermission[] memory permissions = new PermissionLib.MultiTargetPermission[](8);

        // The plugin can execute on the DAO
        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: _dao,
            who: plugin,
            condition: PermissionLib.NO_CONDITION,
            permissionId: DAO(payable(_dao)).EXECUTE_PERMISSION_ID()
        });

        // The DAO can update the plugin settings
        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: impl.UPDATE_SETTINGS_PERMISSION_ID()
        });

        // The DAO can upgrade the plugin implementation
        permissions[2] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: impl.UPGRADE_PLUGIN_PERMISSION_ID()
        });

        // The DAO can update the target config
        permissions[3] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: impl.SET_TARGET_CONFIG_PERMISSION_ID()
        });

        // The DAO can set update the plugin metadata
        permissions[4] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: impl.SET_METADATA_PERMISSION_ID()
        });

        // createProposalCaller (possibly ANY_ADDR) can create proposals on the plugin
        permissions[5] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: installationParams.createProposalCaller,
            condition: minVotingPowerCondition,
            permissionId: impl.CREATE_PROPOSAL_PERMISSION_ID()
        });

        // The LockManager can call approve and clearApproval on the plugin
        permissions[6] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: helpers[0], // Lock Manager
            condition: PermissionLib.NO_CONDITION,
            permissionId: impl.LOCK_MANAGER_PERMISSION_ID()
        });

        // executeCaller (possibly ANY_ADDR) can call execute() on the plugin
        permissions[7] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: installationParams.executeCaller,
            condition: PermissionLib.NO_CONDITION,
            permissionId: impl.EXECUTE_PROPOSAL_PERMISSION_ID()
        });

        preparedSetupData.helpers = helpers;
        preparedSetupData.permissions = permissions;
    }

    /// @inheritdoc IPluginSetup
    function prepareUninstallation(address _dao, SetupPayload calldata _payload)
        external
        view
        returns (PermissionLib.MultiTargetPermission[] memory permissions)
    {
        // Prepare permissions.
        uint256 helperLength = _payload.currentHelpers.length;
        if (helperLength != 3) {
            revert WrongHelpersArrayLength({length: helperLength});
        }
        permissions = new PermissionLib.MultiTargetPermission[](8);

        // Set permissions to be Revoked.

        LockToApprovePlugin impl = LockToApprovePlugin(implementation());

        // The plugin cannot execute on the DAO
        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _dao,
            who: _payload.plugin,
            condition: PermissionLib.NO_CONDITION,
            permissionId: DAO(payable(_dao)).EXECUTE_PERMISSION_ID()
        });

        // The DAO cannot update the plugin settings
        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: impl.UPDATE_SETTINGS_PERMISSION_ID()
        });

        // The DAO cannot upgrade the plugin implementation
        permissions[2] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: impl.UPGRADE_PLUGIN_PERMISSION_ID()
        });

        // The DAO cannot update the target config
        permissions[3] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: impl.SET_TARGET_CONFIG_PERMISSION_ID()
        });

        // The DAO cannot set update the plugin metadata
        permissions[4] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: impl.SET_METADATA_PERMISSION_ID()
        });

        // createProposalCaller (possibly ANY_ADDR) cannot create proposals on the plugin
        permissions[5] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: _payload.currentHelpers[1], // createProposalCaller,
            condition: PermissionLib.NO_CONDITION,
            permissionId: impl.CREATE_PROPOSAL_PERMISSION_ID()
        });

        // The LockManager cannot call approve or clearApproval on the plugin
        permissions[6] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: _payload.currentHelpers[0], // Lock Manager
            condition: PermissionLib.NO_CONDITION,
            permissionId: impl.LOCK_MANAGER_PERMISSION_ID()
        });

        // executeCaller (possibly ANY_ADDR) cannot call execute() on the plugin
        permissions[7] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: _payload.currentHelpers[2], // executeCaller,
            condition: PermissionLib.NO_CONDITION,
            permissionId: impl.EXECUTE_PROPOSAL_PERMISSION_ID()
        });
    }

    /// @notice Encodes the given installation parameters into a byte array
    function encodeInstallationParams(InstallationParameters memory installationParams)
        external
        pure
        returns (bytes memory)
    {
        return abi.encode(installationParams);
    }

    /// @notice Decodes the given byte array into the original installation parameters
    function decodeInstallationParams(bytes memory _data)
        public
        pure
        returns (InstallationParameters memory installationParams)
    {
        installationParams = abi.decode(_data, (InstallationParameters));
    }

    /// @notice Unsatisfiably determines if the contract is an ERC20 token.
    /// @dev It's important to first check whether token is a contract prior to this call.
    /// @param token The token address
    function _supportsErc20(address token) private view returns (bool) {
        (bool success, bytes memory data) = token.staticcall(abi.encodeCall(IERC20.balanceOf, (address(this))));
        if (!success || data.length != 0x20) return false;

        (success, data) = token.staticcall(abi.encodeCall(IERC20.totalSupply, ()));
        if (!success || data.length != 0x20) return false;

        (success, data) = token.staticcall(abi.encodeCall(IERC20.allowance, (address(this), address(this))));
        if (!success || data.length != 0x20) return false;

        return true;
    }
}
