// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ICollectionStore {
    function BASE_FEE() external view returns (uint256);

    function fee() external view returns (uint256);

    function feeOwner() external view returns (address);

    function acceptedToken() external view returns (IERC20);
}
