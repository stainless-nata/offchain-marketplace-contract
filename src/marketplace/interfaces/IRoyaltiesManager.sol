// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC721} from "@openzeppelin/contracts/interfaces/IERC721.sol";

/// @notice Interface for the Royalties Manager contract.
interface IRoyaltiesManager is IERC721 {
    function getRoyaltiesReceiver(address _contractAddress, uint256 _tokenId) external view returns(address);
}
