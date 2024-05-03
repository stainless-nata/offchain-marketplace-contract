// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ICollection} from "../interfaces/ICollection.sol";
import {Marketplace} from "../Marketplace.sol";

abstract contract CollectionDiscountModifier {
    /// @dev Schema for a collection discount.
    /// @param contractAddresses - The contract addresses of the collections that will receive the discount.
    /// An empty array means all collections will benefit from the discount.
    /// @param discountRate - The discount rate to apply to the collections. Should be provided over a million instead of a hundred.
    struct CollectionDiscount {
        address[] contractAddresses;
        uint256 discountRate;
    }

    error NotCreator();

    function _applyCollectionDiscountModifier(Marketplace.Trade memory _trade, Marketplace.Modifier memory _modifier) internal {
        address signer = _trade.signer;

        CollectionDiscount memory collectionDiscount = abi.decode(_modifier.data, (CollectionDiscount));

        

        for (uint256 i = 0; i < _trade.sent.length; i++) {
            Marketplace.Asset memory asset = _trade.sent[i];

            ICollection collection = ICollection(asset.contractAddress);

            if (collection.creator() != signer) {
                revert NotCreator();
            }
        }
    }
}
