// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import {ICollection} from "src/marketplace/ICollection.sol";

contract MockCollection is ICollection, ERC721 {
    address public creator;

    constructor() ERC721("MockCollection", "MC") {}

    function issueTokens(address[] calldata _beneficiaries, uint256[] calldata _itemIds) external {}

    function items(uint256 _itemId) external view returns (string memory, uint256, uint256, uint256, address, string memory, string memory) {}

    function transferCreatorship(address _newCreator) external {
        creator = _newCreator;
    }

    function setMinters(address[] calldata _minters, bool[] calldata _values) external {}
}
