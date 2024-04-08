// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ICollection} from "../interfaces/ICollection.sol";

contract MockCollection is ICollection {
    function issueTokens(address[] calldata _beneficiaries, uint256[] calldata _itemIds) external {}
}
