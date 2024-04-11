// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Marketplace} from "./Marketplace.sol";
import {ERC20Transfer} from "./transferables/ERC20Transfer.sol";
import {ERC721Transfer} from "./transferables/ERC721Transfer.sol";
import {ComposableERC721Transfer} from "./transferables/ComposableERC721Transfer.sol";

contract EthereumMarketplace is Marketplace, ERC20Transfer, ERC721Transfer, ComposableERC721Transfer {
    uint256 public constant ERC20_ID = 0;
    uint256 public constant ERC721_ID = 1;
    uint256 public constant COMPOSABLE_ERC721_ID = 2;

    function _transferAsset(Asset memory _asset, address _from, address _to) internal override {
        if (_asset.assetType == ERC20_ID) {
            _transferERC20(_asset.contractAddress, _from, _to, _asset.value);
        } else if (_asset.assetType == ERC721_ID) {
            _transferERC721(_asset.contractAddress, _from, _to, _asset.value, _asset.extra);
        } else {
            _transferComposableERC721(_asset.contractAddress, _from, _to, _asset.value, _asset.extra);
        }
    }
}
