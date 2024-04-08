// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface ICollection {
    function issueTokens(address[] calldata _beneficiaries, uint256[] calldata _itemIds) external;
}
