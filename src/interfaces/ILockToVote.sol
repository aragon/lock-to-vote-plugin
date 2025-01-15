// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import {ILockToVoteBase} from "./ILockToVoteBase.sol";
import {IMajorityVoting} from "./IMajorityVoting.sol";

/// @title ILockToVote
/// @author Aragon X
/// @notice Governance plugin allowing token holders to use tokens locked without a snapshot requirement and engage in proposals immediately
interface ILockToVote is ILockToVoteBase, IMajorityVoting {

}
