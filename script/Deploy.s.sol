// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {DAO} from "@aragon/osx/src/core/dao/DAO.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {LockToVotePluginSetup} from "../src/setup/LockToVotePluginSetup.sol";
import {PluginRepoFactory} from "@aragon/osx/src/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginSetupProcessor} from "@aragon/osx/src/framework/plugin/setup/PluginSetupProcessor.sol";
import {TestToken} from "../test/mocks/TestToken.sol";

contract Deploy is Script {
    LockToVotePluginSetup lockToVotePluginSetup;

    modifier broadcast() {
        uint256 privKey = vm.envUint("DEPLOYMENT_PRIVATE_KEY");
        vm.startBroadcast(privKey);
        console.log("Deploying from:", vm.addr(privKey));

        _;

        vm.stopBroadcast();
    }

    // function run() public broadcast {
    //     // Deploy the plugin setup's
    //     lockToVotePluginSetup = new LockToVotePluginSetup(
    //         GovernanceERC20(vm.envAddress("GOVERNANCE_ERC20_BASE")),
    //         GovernanceWrappedERC20(
    //             vm.envAddress("GOVERNANCE_WRAPPED_ERC20_BASE")
    //         )
    //     );

    //     console.log("Chain ID:", block.chainid);

    //     DeploymentSettings memory settings;
    //     if (vm.envOr("MINT_TEST_TOKENS", false)) {
    //         settings = getTestTokenSettings();
    //     } else {
    //         settings = getProductionSettings();
    //     }

    //     console.log("");

    //     // TODO: DEPLOY

    //     // Done
    //     printDeploymentSummary(factory, delegationWall);
    // }

    // function getProductionSettings()
    //     internal
    //     view
    //     returns (DeploymentSettings memory settings)
    // {
    //     console.log("Using production settings");

    //     settings = DeploymentSettings({
    //         tokenAddress: IVotesUpgradeable(vm.envAddress("TOKEN_ADDRESS")),
    //         timelockPeriod: uint32(vm.envUint("TIME_LOCK_PERIOD")),
    //         l2InactivityPeriod: uint32(vm.envUint("L2_INACTIVITY_PERIOD")),
    //         l2AggregationGracePeriod: uint32(
    //             vm.envUint("L2_AGGREGATION_GRACE_PERIOD")
    //         ),
    //         skipL2: bool(vm.envBool("SKIP_L2")),
    //         // Voting settings
    //         minVetoRatio: uint32(vm.envUint("MIN_VETO_RATIO")),
    //         minStdProposalDuration: uint32(
    //             vm.envUint("MIN_STD_PROPOSAL_DURATION")
    //         ),
    //         minStdApprovals: uint16(vm.envUint("MIN_STD_APPROVALS")),
    //         minEmergencyApprovals: uint16(
    //             vm.envUint("MIN_EMERGENCY_APPROVALS")
    //         ),
    //         // OSx contracts
    //         osxDaoFactory: vm.envAddress("DAO_FACTORY"),
    //         pluginSetupProcessor: PluginSetupProcessor(
    //             vm.envAddress("PLUGIN_SETUP_PROCESSOR")
    //         ),
    //         pluginRepoFactory: PluginRepoFactory(
    //             vm.envAddress("PLUGIN_REPO_FACTORY")
    //         ),
    //         // Plugin setup's
    //         multisigPluginSetup: MultisigPluginSetup(multisigPluginSetup),
    //         emergencyMultisigPluginSetup: EmergencyMultisigPluginSetup(
    //             emergencyMultisigPluginSetup
    //         ),
    //         lockToVotePluginSetup: LockToVotePluginSetup(lockToVotePluginSetup),
    //         // Multisig members
    //         multisigMembers: readMultisigMembers(),
    //         multisigExpirationPeriod: uint32(
    //             vm.envUint("MULTISIG_PROPOSAL_EXPIRATION_PERIOD")
    //         ),
    //         // ENS
    //         stdMultisigEnsDomain: vm.envString("STD_MULTISIG_ENS_DOMAIN"),
    //         emergencyMultisigEnsDomain: vm.envString(
    //             "EMERGENCY_MULTISIG_ENS_DOMAIN"
    //         ),
    //         optimisticTokenVotingEnsDomain: vm.envString(
    //             "OPTIMISTIC_TOKEN_VOTING_ENS_DOMAIN"
    //         )
    //     });
    // }

    // function getTestTokenSettings()
    //     internal
    //     returns (DeploymentSettings memory settings)
    // {
    //     console.log("Using test token settings");

    //     address[] memory multisigMembers = readMultisigMembers();
    //     address votingToken = createTestToken(
    //         multisigMembers
    //     );

    //     settings = DeploymentSettings({
    //         tokenAddress: IVotesUpgradeable(votingToken),
    //         timelockPeriod: uint32(vm.envUint("TIME_LOCK_PERIOD")),
    //         l2InactivityPeriod: uint32(vm.envUint("L2_INACTIVITY_PERIOD")),
    //         l2AggregationGracePeriod: uint32(
    //             vm.envUint("L2_AGGREGATION_GRACE_PERIOD")
    //         ),
    //         skipL2: bool(vm.envBool("SKIP_L2")),
    //         // Voting settings
    //         minVetoRatio: uint32(vm.envUint("MIN_VETO_RATIO")),
    //         minStdProposalDuration: uint32(
    //             vm.envUint("MIN_STD_PROPOSAL_DURATION")
    //         ),
    //         minStdApprovals: uint16(vm.envUint("MIN_STD_APPROVALS")),
    //         minEmergencyApprovals: uint16(
    //             vm.envUint("MIN_EMERGENCY_APPROVALS")
    //         ),
    //         // OSx contracts
    //         osxDaoFactory: vm.envAddress("DAO_FACTORY"),
    //         pluginSetupProcessor: PluginSetupProcessor(
    //             vm.envAddress("PLUGIN_SETUP_PROCESSOR")
    //         ),
    //         pluginRepoFactory: PluginRepoFactory(
    //             vm.envAddress("PLUGIN_REPO_FACTORY")
    //         ),
    //         // Plugin setup's
    //         multisigPluginSetup: MultisigPluginSetup(multisigPluginSetup),
    //         emergencyMultisigPluginSetup: EmergencyMultisigPluginSetup(
    //             emergencyMultisigPluginSetup
    //         ),
    //         lockToVotePluginSetup: LockToVotePluginSetup(lockToVotePluginSetup),
    //         // Multisig members
    //         multisigMembers: multisigMembers,
    //         multisigExpirationPeriod: uint32(
    //             vm.envUint("MULTISIG_PROPOSAL_EXPIRATION_PERIOD")
    //         ),
    //         // ENS
    //         stdMultisigEnsDomain: vm.envString("STD_MULTISIG_ENS_DOMAIN"),
    //         emergencyMultisigEnsDomain: vm.envString(
    //             "EMERGENCY_MULTISIG_ENS_DOMAIN"
    //         ),
    //         optimisticTokenVotingEnsDomain: vm.envString(
    //             "OPTIMISTIC_TOKEN_VOTING_ENS_DOMAIN"
    //         )
    //     });
    // }

    // function printDeploymentSummary(
    // ) internal view {
    //     DeploymentSettings memory settings = factory.getSettings();
    //     Deployment memory daoDeployment = factory.getDeployment();

    //     console.log("Factory:", address(factory));
    //     console.log("");
    //     console.log("DAO:", address(daoDeployment.dao));
    //     console.log("Voting token:", address(settings.tokenAddress));
    //     console.log("");

    //     console.log("Plugins");
    //     console.log(
    //         "- Lock to vote plugin:",
    //         address(daoDeployment.multisigPlugin)
    //     );
    //     console.log("");

    //     console.log("Helpers");
    //     console.log("- Lock Manager", address(daoDeployment.signerList));

    //     console.log("");

    //     console.log("Plugin repositories");
    //     console.log(
    //         "- Lock to vote plugin repository:",
    //         address(daoDeployment.optimisticTokenVotingPluginRepo)
    //     );
    // }

    // function createTestToken(
    //     address[] memory members,
    // ) internal returns (address) {
    //     GovernanceERC20Mock testToken = new GovernanceERC20Mock(address(0));
    //     console.log("Minting test tokens for the members");
    //     testToken.mintAndDelegate(members, 10 ether);

    //     return address(testToken);
    // }
}
