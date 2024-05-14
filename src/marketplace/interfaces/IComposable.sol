// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC721} from "@openzeppelin/contracts/interfaces/IERC721.sol";

/// @notice Interface for ERC721 Composable contracts.
interface IComposable is IERC721 {
    function verifyFingerprint(uint256 _estateId, bytes memory _fingerprint) external returns (bool);

    function getFingerprint(uint256 _estateId) external view returns (bytes32);
}
