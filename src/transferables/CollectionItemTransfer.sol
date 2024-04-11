// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ICollection} from "../interfaces/ICollection.sol";

abstract contract CollectionItemTransfer {
    function _transferCollectionItem(address _contractAddress, address _to, uint256 _itemId) internal {
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = _to;

        uint256[] memory itemIds = new uint256[](1);
        itemIds[0] = _itemId;

        ICollection(_contractAddress).issueTokens(beneficiaries, itemIds);
    }
}
