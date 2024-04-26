// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {Marketplace} from "./Marketplace.sol";
import {ERC20Transfer} from "./transfers/ERC20Transfer.sol";
import {ERC721Transfer} from "./transfers/ERC721Transfer.sol";
import {CollectionItemTransfer} from "./transfers/CollectionItemTransfer.sol";
import {NativeMetaTransaction} from "./external/NativeMetaTransaction.sol";
import {ICollectionStore} from "./interfaces/ICollectionStore.sol";

error UnsupportedAssetType(uint256 _assetType);

contract PolygonMarketplace is Marketplace, ERC20Transfer, ERC721Transfer, CollectionItemTransfer, NativeMetaTransaction {
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
            _transferCollectionItemWithDiscount(_asset, _signer);
        } else {
            revert UnsupportedAssetType(_asset.assetType);
        }
    }

    function _msgSender() internal view override returns (address sender) {
        return _getMsgSender();
    }
}
