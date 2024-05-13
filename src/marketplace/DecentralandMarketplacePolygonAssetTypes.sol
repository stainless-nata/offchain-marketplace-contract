// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {DecentralandMarketplaceEthereumAssetTypes} from "src/marketplace/DecentralandMarketplaceEthereumAssetTypes.sol";

abstract contract DecentralandMarketplacePolygonAssetTypes is DecentralandMarketplaceEthereumAssetTypes {
    uint256 public constant ASSET_TYPE_COLLECTION_ITEM = 3;
}
