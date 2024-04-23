// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Context} from "lib/openzeppelin-contracts/contracts/utils/Context.sol";
import {ICollection} from "../interfaces/ICollection.sol";
import {Marketplace} from "../Marketplace.sol";

abstract contract CollectionItemTransfer is Context {
    error NotCreator();

    function _transferCollectionItem(Marketplace.Asset memory _asset, address _signer) internal {
        ICollection collection = ICollection(_asset.contractAddress);

        address creator = collection.creator();

        if (creator != _signer || creator != _msgSender()) {
            revert NotCreator();
        }

        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = _asset.beneficiary;

        uint256[] memory itemIds = new uint256[](1);
        itemIds[0] = _asset.value;

        collection.issueTokens(beneficiaries, itemIds);
    }
}
