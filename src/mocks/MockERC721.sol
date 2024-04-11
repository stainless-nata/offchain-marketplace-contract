// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ERC721} from "lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";

contract MockERC721 is ERC721 {
    constructor() ERC721("MockERC721", "MERC") {}

    function mint(address _to, uint256 _tokenId) external {
        _mint(_to, _tokenId);
    }
}
