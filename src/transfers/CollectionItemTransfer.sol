// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";

import {ICollection} from "../interfaces/ICollection.sol";
import {Marketplace} from "../Marketplace.sol";

abstract contract CollectionItemTransfer is Context {
    error NotCreator();

    /// @dev Issues a token from a collection to the beneficiary defined in the asset.
    /// @param _asset - The asset that will be transferred.
    /// @param _signer - The user that signed the Trade request that contains this asset.
    function _transferCollectionItem(Marketplace.Asset memory _asset, address _signer) internal {
        ICollection collection = ICollection(_asset.contractAddress);

        address creator = collection.creator();

        // The creator of the collections has to be the signer or the caller in order for the Trade to succeed.
        // This is because it is logical that the creator is the one that wants to sign a Trade request for one of their collection items.
        // Also another user might offer a Trade request for a collection item, which the creator should be able to accept.
        if (creator != _signer && creator != _msgSender()) {
            revert NotCreator();
        }

        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = _asset.beneficiary;

        uint256[] memory itemIds = new uint256[](1);
        itemIds[0] = _asset.value;

        collection.issueTokens(beneficiaries, itemIds);
    }
}
