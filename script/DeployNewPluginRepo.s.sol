// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {DAO, IDAO} from "@aragon/osx/src/core/dao/DAO.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {LockToVotePlugin, MajorityVotingBase} from "../src/LockToVotePlugin.sol";
import {LockManagerERC20} from "../src/LockManagerERC20.sol";
import {LockToVotePluginSetup} from "../src/setup/LockToVotePluginSetup.sol";
import {ILockToGovernBase} from "../src/interfaces/ILockToGovernBase.sol";
import {PluginRepoFactory} from "@aragon/osx/src/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginRepo} from "@aragon/osx/src/framework/plugin/repo/PluginRepo.sol";
import {PluginSetupProcessor} from "@aragon/osx/src/framework/plugin/setup/PluginSetupProcessor.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {createProxyAndCall} from "../src/util/proxy.sol";
import {MinVotingPowerCondition} from "../src/conditions/MinVotingPowerCondition.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployNewPluginRepoScript is Script {
    using stdJson for string;

    address deployer;
    address maintainer;
    string ltvEnsSubdomain;
    PluginRepoFactory pluginRepoFactory;

    // Artifacts
    PluginRepo lockToVotePluginRepo;
    address lockToVotePluginSetup;

    modifier broadcast() {
        uint256 privKey = vm.envUint("DEPLOYMENT_PRIVATE_KEY");
        vm.startBroadcast(privKey);
        console.log("Chain ID:", block.chainid);
        console.log("Deploying from:", vm.addr(privKey));
        console.log("");

        _;

        vm.stopBroadcast();
    }

    function setUp() public {
        // Pick the contract addresses from
        // https://github.com/aragon/osx/blob/main/packages/artifacts/src/addresses.json

        maintainer = vm.envAddress("PLUGIN_REPO_MAINTAINER_ADDRESS");
        pluginRepoFactory = PluginRepoFactory(vm.envAddress("PLUGIN_REPO_FACTORY_ADDRESS"));
        ltvEnsSubdomain = vm.envString("PLUGIN_ENS_SUBDOMAIN");

        vm.label(maintainer, "Maintainer");
        vm.label(address(pluginRepoFactory), "PluginRepoFactory");
    }

    function run() public broadcast {
        // Deploy the plugin setup's
        prepareLockToVote();

        vm.label(address(lockToVotePluginRepo), "LockToVotePluginRepo");
        vm.label(lockToVotePluginSetup, "LockToVotePluginSetup");

        printDeployment();

        internalDummyDeploy();

        // Write the addresses to a JSON file
        if (!vm.envOr("SIMULATION", false)) {
            writeJsonArtifacts();
        }
    }

    function prepareLockToVote() internal {
        lockToVotePluginSetup = address(new LockToVotePluginSetup());

        // Use a random value if empty
        if (bytes(ltvEnsSubdomain).length == 0) {
            ltvEnsSubdomain = string.concat("lock-to-vote-plugin-", vm.toString(block.timestamp));
        }

        lockToVotePluginRepo = pluginRepoFactory.createPluginRepoWithFirstVersion(
            ltvEnsSubdomain, address(lockToVotePluginSetup), maintainer, " ", " "
        );
    }

    function internalDummyDeploy() private {
        // Deploying dummy contract instances to force verifying on all block explorers
        console.log("Deploying static (dummy) contracts to force verification");

        LockToVotePlugin pluginImplementation = new LockToVotePlugin();

        // Lock Manager
        LockManagerERC20 lockManager = new LockManagerERC20(IERC20(address(0)));

        // Condition
        IPlugin.TargetConfig memory targetConfig =
            IPlugin.TargetConfig({target: address(1234), operation: IPlugin.Operation.Call});

        MajorityVotingBase.VotingSettings memory votingSettings = MajorityVotingBase.VotingSettings({
            votingMode: MajorityVotingBase.VotingMode.Standard,
            supportThresholdRatio: 500_000,
            minParticipationRatio: 500_000,
            minApprovalRatio: 500_000,
            proposalDuration: 10 days,
            minProposerVotingPower: 0
        });

        LockToVotePlugin ltvPlugin = LockToVotePlugin(
            createProxyAndCall(
                address(pluginImplementation),
                abi.encodeCall(
                    LockToVotePlugin.initialize,
                    (IDAO(address(1234)), lockManager, votingSettings, targetConfig, bytes(""))
                )
            )
        );

        new MinVotingPowerCondition(ILockToGovernBase(ltvPlugin));

        // Proxy
        new ERC1967Proxy(address(ltvPlugin), bytes(""));
    }

    function printDeployment() internal view {
        console.log("Plugin setup's");
        console.log("- LockToVotePluginSetup:            ", lockToVotePluginSetup);
        console.log("");

        console.log("Plugin repositories");
        console.log("- LockToVote plugin repository:     ", address(lockToVotePluginRepo));
        console.log("- LockToVote repo ENS:              ", string.concat(ltvEnsSubdomain, ".plugin.dao.eth"));
        console.log("- Maintainer:                       ", address(maintainer));
        console.log("");

        console.log("Implementation");
        console.log(
            "- LockToVote plugin:                ", LockToVotePluginSetup(lockToVotePluginSetup).implementation()
        );
        console.log("");
    }

    function writeJsonArtifacts() internal {
        string memory artifacts = "output";
        artifacts.serialize("lockToVotePluginRepo", address(lockToVotePluginRepo));
        artifacts.serialize("pluginRepoMaintainer", maintainer);
        artifacts =
            artifacts = artifacts.serialize("lockToVoteEnsDomain", string.concat(ltvEnsSubdomain, ".plugin.dao.eth"));

        string memory networkName = vm.envString("NETWORK_NAME");
        string memory filePath = string.concat(
            vm.projectRoot(), "/artifacts/deployment-", networkName, "-", vm.toString(block.timestamp), ".json"
        );
        artifacts.write(filePath);

        console.log("Deployment artifacts written to", filePath);
    }
}
