// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Marketplace} from "./Marketplace.sol";
import {SimpleTokenTransfer} from "./transfers/SimpleTokenTransfer.sol";
import {CollectionItemTransfer} from "./transfers/CollectionItemTransfer.sol";
import {NativeMetaTransaction} from "./external/NativeMetaTransaction.sol";
import {ICollectionStore} from "./interfaces/ICollectionStore.sol";

error UnsupportedAssetType(uint256 _assetType);

contract PolygonMarketplace is Marketplace, NativeMetaTransaction, SimpleTokenTransfer, CollectionItemTransfer {
    uint256 public constant ERC20_ID = 0;
    uint256 public constant ERC721_ID = 1;
    uint256 public constant COLLECTION_ITEM_ID = 2;
    uint256 public constant COLLECTION_ITEM_WITH_DISCOUNT_ID = 3;

    constructor(address _owner, ICollectionStore _collectionStore) Marketplace(_owner) CollectionItemTransfer(_collectionStore) {}

    function _transferAsset(Asset memory _asset, address _from, address _signer) internal override {
        if (_asset.assetType == ERC20_ID) {
            _transferERC20(_asset, _from);
        } else if (_asset.assetType == ERC721_ID) {
            _transferERC721(_asset, _from);
        } else if (_asset.assetType == COLLECTION_ITEM_ID) {
            _transferCollectionItem(_asset, _signer);
        } else if (_asset.assetType == COLLECTION_ITEM_WITH_DISCOUNT_ID) {
            _transferCollectionItemWithDiscount(_asset, _from, _signer);
        } else {
            revert UnsupportedAssetType(_asset.assetType);
        }
    }

    function _msgSender() internal view override returns (address sender) {
        return _getMsgSender();
    }
}
