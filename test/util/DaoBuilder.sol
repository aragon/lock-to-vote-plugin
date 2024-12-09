// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {createProxyAndCall} from "./proxy.sol";
import {ALICE_ADDRESS} from "../constants.sol";
import {LockToVotePlugin} from "../../src/LockToVotePlugin.sol";
import {LockManager} from "../../src/LockManager.sol";
import {GovernanceERC20Mock} from "../mocks/GovernanceERC20Mock.sol";

contract DaoBuilder is Test {
    // address immutable DAO_BASE = address(new DAO());

    // struct MintEntry {
    //     address tokenHolder;
    //     uint256 amount;
    // }

    // address public owner = ALICE_ADDRESS;

    // address[] public proposers;
    // MintEntry[] public tokenHolders;

    // bool public onlyListed = true;
    // uint16 public minApprovals = 1;
    // uint32 public proposalDuration = 10 days;

    // function withDaoOwner(address newOwner) public returns (DaoBuilder) {
    //     owner = newOwner;
    //     return this;
    // }

    // function withTokenHolder(
    //     address newTokenHolder,
    //     uint256 amount
    // ) public returns (DaoBuilder) {
    //     tokenHolders.push(
    //         MintEntry({tokenHolder: newTokenHolder, amount: amount})
    //     );
    //     return this;
    // }

    // function withMinVetoRatio(
    //     uint32 newMinVetoRatio
    // ) public returns (DaoBuilder) {
    //     if (newMinVetoRatio > RATIO_BASE) revert("Veto rate above 100%");
    //     minVetoRatio = newMinVetoRatio;
    //     return this;
    // }

    // function withMinDuration(
    //     uint32 newMinDuration
    // ) public returns (DaoBuilder) {
    //     minDuration = newMinDuration;
    //     return this;
    // }

    // function withDuration(uint32 newDuration) public returns (DaoBuilder) {
    //     proposalDuration = newDuration;
    //     return this;
    // }

    // function withTimelock(uint32 newTimeLock) public returns (DaoBuilder) {
    //     timelockPeriod = newTimeLock;
    //     return this;
    // }

    // function withExpiration(
    //     uint32 newExpirationPeriod
    // ) public returns (DaoBuilder) {
    //     multisigProposalExpirationPeriod = newExpirationPeriod;
    //     return this;
    // }

    // function withOnlyListed() public returns (DaoBuilder) {
    //     onlyListed = true;
    //     return this;
    // }

    // function withoutOnlyListed() public returns (DaoBuilder) {
    //     onlyListed = false;
    //     return this;
    // }

    // function withMultisigMember(address newMember) public returns (DaoBuilder) {
    //     multisigMembers.push(newMember);
    //     return this;
    // }

    // function withProposer(address newProposer) public returns (DaoBuilder) {
    //     proposers.push(newProposer);
    //     return this;
    // }

    // function withMinApprovals(
    //     uint16 newMinApprovals
    // ) public returns (DaoBuilder) {
    //     if (newMinApprovals > multisigMembers.length) {
    //         revert("You should add enough multisig members first");
    //     }
    //     minApprovals = newMinApprovals;
    //     return this;
    // }

    // /// @dev Creates a DAO with the given orchestration settings.
    // /// @dev The setup is done on block/timestamp 0 and tests should be made on block/timestamp 1 or later.
    // function build()
    //     public
    //     returns (DAO dao, LockToVotePlugin plugin, LockManager helper)
    // {
    //     // Deploy the DAO with `this` as root
    //     dao = DAO(
    //         payable(
    //             createProxyAndCall(
    //                 address(DAO_BASE),
    //                 abi.encodeCall(
    //                     DAO.initialize,
    //                     ("", address(this), address(0x0), "")
    //                 )
    //             )
    //         )
    //     );

    //     // Deploy ERC20 token
    //     votingToken = new GovernanceERC20Mock(address(dao));

    //     if (tokenHolders.length > 0) {
    //         for (uint256 i = 0; i < tokenHolders.length; i++) {
    //             votingToken.mintAndDelegate(
    //                 tokenHolders[i].tokenHolder,
    //                 tokenHolders[i].amount
    //             );
    //         }
    //     } else {
    //         votingToken.mintAndDelegate(owner, 10 ether);
    //     }

    //     {
    //         LockToVote.PluginSettings memory targetContractSettings = LockToVote
    //             .PluginSettings({
    //                 minVetoRatio: minVetoRatio,
    //                 minDuration: minDuration,
    //                 timelockPeriod: timelockPeriod,
    //                 l2InactivityPeriod: l2InactivityPeriod,
    //                 l2AggregationGracePeriod: l2AggregationGracePeriod,
    //                 skipL2: skipL2
    //             });

    //         plugin = LockToVote(
    //             createProxyAndCall(
    //                 address(OPTIMISTIC_BASE),
    //                 abi.encodeCall(
    //                     LockToVote.initialize,
    //                     (
    //                         dao,
    //                         targetContractSettings,
    //                         votingToken,
    //                     )
    //                 )
    //             )
    //         );
    //     }

    //     // The plugin can execute on the DAO
    //     dao.grant(address(dao), address(plugin), dao.EXECUTE_PERMISSION_ID());

    //     if (proposers.length > 0) {
    //         for (uint256 i = 0; i < proposers.length; i++) {
    //             dao.grant(
    //                 address(plugin),
    //                 proposers[i],
    //                 plugin.PROPOSER_PERMISSION_ID()
    //             );
    //         }
    //     } else {
    //         // Ensure that at least the owner can propose
    //         dao.grant(address(plugin), owner, plugin.PROPOSER_PERMISSION_ID());
    //     }

    //     // Revoke transfer ownership to the owner
    //     dao.grant(address(dao), owner, dao.ROOT_PERMISSION_ID());
    //     dao.revoke(address(dao), address(this), dao.ROOT_PERMISSION_ID());

    //     // Labels
    //     vm.label(address(dao), "DAO");
    //     vm.label(address(plugin), "LockToVote plugin");
    //     vm.label(address(votingToken), "VotingToken");

    //     // Moving forward to avoid proposal creations failing or getVotes() giving inconsistent values
    //     vm.roll(block.number + 1);
    //     vm.warp(block.timestamp + 1);
    // }
}
