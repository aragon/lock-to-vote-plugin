// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {ForkTestBase} from "../lib/ForkTestBase.sol";

import {DAO, IDAO} from "@aragon/osx/src/core/dao/DAO.sol";
import {DAOFactory} from "@aragon/osx/src/framework/dao/DAOFactory.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {PermissionManager} from "@aragon/osx/src/core/permission/PermissionManager.sol";
import {PluginRepo} from "@aragon/osx/src/framework/plugin/repo/PluginRepo.sol";
import {PluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/PluginSetup.sol";
import {LockToVotePluginSetup} from "../../src/setup/LockToVotePluginSetup.sol";

contract ForkBuilder is ForkTestBase {
    // Add your own parameters here
    address pluginRepoMaintainerAddress;

    // Override methods
    function withMaintainer(address newMaintainer) public {
        pluginRepoMaintainerAddress = newMaintainer;
    }

    constructor() {
        pluginRepoMaintainerAddress = msg.sender;
    }

    /// @dev Creates a DAO with the given orchestration settings.
    /// @dev The setup is done on block/timestamp 0 and tests should be made on block/timestamp 1 or later.
    function build() public returns (DAO dao, PluginRepo repo, PluginSetup pluginSetup) {
        // DAO settings
        DAOFactory.DAOSettings memory daoSettings =
            DAOFactory.DAOSettings({trustedForwarder: address(0), daoURI: "http://host/", subdomain: "", metadata: ""});

        /// No plugins, this contract can execute anything
        DAOFactory.PluginSettings[] memory installSettings = new DAOFactory.PluginSettings[](0);

        // Create DAO
        DAOFactory.InstalledPlugin[] memory installedPlugins;
        (dao, installedPlugins) = daoFactory.createDao(daoSettings, installSettings);

        // Set msg.sender as the owner
        Action[] memory actions = new Action[](1);
        actions[0] = Action({
            to: address(dao),
            value: 0,
            data: abi.encodeCall(PermissionManager.grant, (address(dao), msg.sender, dao.ROOT_PERMISSION_ID()))
        });
        dao.execute(bytes32(0), actions, 0);

        // Plugin setup (the installer)
        pluginSetup = new LockToVotePluginSetup();

        // The new plugin repository
        string memory pluginEnsSubdomain = string.concat("my-lock-to-vote-plugin-", vm.toString(block.timestamp));
        repo = pluginRepoFactory.createPluginRepoWithFirstVersion(
            pluginEnsSubdomain, address(pluginSetup), pluginRepoMaintainerAddress, " ", " "
        );

        // Labels
        vm.label(address(dao), "DAO");
        vm.label(address(pluginSetup), "PluginSetup");
        vm.label(address(repo), "PluginRepo");
        vm.label(pluginRepoMaintainerAddress, "Maintainer");

        // Moving forward to avoid collisions
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
    }
}
