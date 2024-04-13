// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ICollection} from "../interfaces/ICollection.sol";
import {Marketplace} from "../Marketplace.sol";

abstract contract CollectionItemTransfer {
    function _transferCollectionItem(Marketplace.Asset memory _asset) internal {
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = _asset.beneficiary;

        uint256[] memory itemIds = new uint256[](1);
        itemIds[0] = _asset.value;

        ICollection(_asset.contractAddress).issueTokens(beneficiaries, itemIds);
    }
}
