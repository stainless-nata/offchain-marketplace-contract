// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {Marketplace} from "./Marketplace.sol";
import {SimpleTokenTransfer} from "./transfers/SimpleTokenTransfer.sol";
import {CollectionItemTransfer} from "./transfers/CollectionItemTransfer.sol";
import {NativeMetaTransaction} from "./external/NativeMetaTransaction.sol";
import {EIP712} from "./external/EIP712.sol";

contract PolygonMarketplace is Marketplace, NativeMetaTransaction, SimpleTokenTransfer, CollectionItemTransfer {
    uint256 public constant ERC20_ID = 0;
    uint256 public constant ERC721_ID = 1;
    uint256 public constant COLLECTION_ITEM_ID = 2;

    error UnsupportedAssetType(uint256 _assetType);

    constructor(address _owner) Marketplace(address(0)) EIP712("PolygonMarketplace", "1.0.0") Ownable(_owner) {}

    function _transferAsset(Asset memory _asset, address _from, address _signer) internal override {
        if (_asset.assetType == ERC20_ID) {
            _transferERC20(_asset, _from);
        } else if (_asset.assetType == ERC721_ID) {
            _transferERC721(_asset, _from);
        } else if (_asset.assetType == COLLECTION_ITEM_ID) {
            _transferCollectionItem(_asset, _signer);
        } else {
            revert UnsupportedAssetType(_asset.assetType);
        }
    }

    function _msgSender() internal view override returns (address sender) {
        return _getMsgSender();
    }
}
