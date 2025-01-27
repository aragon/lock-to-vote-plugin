// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {DAO} from "@aragon/osx/src/core/dao/DAO.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {LockToVotePluginSetup} from "../src/setup/LockToVotePluginSetup.sol";
import {LockToApprovePluginSetup} from "../src/setup/LockToApprovePluginSetup.sol";
import {PluginRepoFactory} from "@aragon/osx/src/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginRepo} from "@aragon/osx/src/framework/plugin/repo/PluginRepo.sol";
import {PluginSetupProcessor} from "@aragon/osx/src/framework/plugin/setup/PluginSetupProcessor.sol";
import {TestToken} from "../test/mocks/TestToken.sol";

contract Deploy is Script {
    modifier broadcast() {
        uint256 privKey = vm.envUint("DEPLOYMENT_PRIVATE_KEY");
        vm.startBroadcast(privKey);
        console.log("Deploying from:", vm.addr(privKey));

        _;

        vm.stopBroadcast();
    }

    function run() public broadcast {
        address maintainer = vm.envAddress("PLUGIN_MAINTAINER");
        address pluginRepoFactory = vm.envAddress("PLUGIN_REPO_FACTORY");
        string memory ltvEnsSubdomain = vm.envString("LOCK_TO_VOTE_REPO_ENS_SUBDOMAIN");
        string memory ltaEnsSubdomain = vm.envString("LOCK_TO_APPROVE_REPO_ENS_SUBDOMAIN");

        // Deploy the plugin setup's
        (address lockToVotePluginSetup, PluginRepo lockToVotePluginRepo) = prepareLockToVote(
            maintainer,
            PluginRepoFactory(pluginRepoFactory),
            ltvEnsSubdomain
        );
        (address lockToApprovePluginSetup, PluginRepo lockToApprovePluginRepo) = prepareLockToApprove(
            maintainer,
            PluginRepoFactory(pluginRepoFactory),
            ltaEnsSubdomain
        );

        console.log("Chain ID:", block.chainid);

        console.log("");

        console.log("Plugins");
        console.log("- LockToVotePluginSetup:", lockToVotePluginSetup);
        console.log("- LockToApprovePluginSetup:", lockToApprovePluginSetup);
        console.log("");

        console.log("Plugin repositories");
        console.log("- LockToVote plugin repository:", address(lockToVotePluginRepo));
        console.log("- LockToApprove plugin repository:", address(lockToApprovePluginRepo));
    }

    function prepareLockToVote(
        address maintainer,
        PluginRepoFactory pluginRepoFactory,
        string memory ensSubdomain
    ) internal returns (address pluginSetup, PluginRepo) {
        // Publish repo
        LockToVotePluginSetup lockToVotePluginSetup = new LockToVotePluginSetup();

        PluginRepo pluginRepo = pluginRepoFactory.createPluginRepoWithFirstVersion(
            ensSubdomain, // ENS repo subdomain left empty
            address(lockToVotePluginSetup),
            maintainer,
            " ",
            " "
        );
        return (address(lockToVotePluginSetup), pluginRepo);
    }

    function prepareLockToApprove(
        address maintainer,
        PluginRepoFactory pluginRepoFactory,
        string memory ensSubdomain
    ) internal returns (address pluginSetup, PluginRepo) {
        // Publish repo
        LockToApprovePluginSetup lockToApprovePluginSetup = new LockToApprovePluginSetup();

        PluginRepo pluginRepo = pluginRepoFactory.createPluginRepoWithFirstVersion(
            ensSubdomain,
            address(lockToApprovePluginSetup),
            maintainer,
            " ",
            " "
        );
        return (address(lockToApprovePluginSetup), pluginRepo);
    }
}
