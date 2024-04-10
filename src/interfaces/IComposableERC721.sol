// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IComposableERC721 is IERC721 {
    function verifyFingerprint(uint256 _estateId, bytes memory _fingerprint) external returns (bool);
}
