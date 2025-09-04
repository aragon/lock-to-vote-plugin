// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {DAO} from "@aragon/osx/src/core/dao/DAO.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {LockToVotePluginSetup} from "../src/setup/LockToVotePluginSetup.sol";
import {PluginRepoFactory} from "@aragon/osx/src/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginRepo} from "@aragon/osx/src/framework/plugin/repo/PluginRepo.sol";
import {PluginSetupProcessor} from "@aragon/osx/src/framework/plugin/setup/PluginSetupProcessor.sol";
import {TestToken} from "../test/mocks/TestToken.sol";

contract Nice {}

contract DeployNewPluginRepoScript is Script {
    using stdJson for string;

    modifier broadcast() {
        uint256 privKey = vm.envUint("DEPLOYMENT_PRIVATE_KEY");
        vm.startBroadcast(privKey);
        console.log("Chain ID:", block.chainid);
        console.log("Deploying from:", vm.addr(privKey));
        console.log("");

        _;

        vm.stopBroadcast();
    }

    function run() public broadcast {
        Nice n = new Nice();
        uint256 kk = 1;
    }
}
