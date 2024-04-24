// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC721} from "lib/openzeppelin-contracts/contracts/interfaces/IERC721.sol";

interface ICollection is IERC721 {
    function issueTokens(address[] calldata _beneficiaries, uint256[] calldata _itemIds) external;

    function creator() external view returns (address);

    function transferCreatorship(address _newCreator) external;

    function setMinters(address[] calldata _minters, bool[] calldata _values) external;
}
