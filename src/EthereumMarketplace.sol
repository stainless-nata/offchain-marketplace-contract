// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {Marketplace} from "./Marketplace.sol";
import {SimpleTokenTransfer} from "./transfers/SimpleTokenTransfer.sol";
import {ComposableTokenTransfer} from "./transfers/ComposableTokenTransfer.sol";
import {EIP712} from "./external/EIP712.sol";

contract EthereumMarketplace is Marketplace, SimpleTokenTransfer, ComposableTokenTransfer {
    uint256 public constant ERC20_ID = 0;
    uint256 public constant ERC721_ID = 1;
    uint256 public constant COMPOSABLE_ERC721_ID = 2;

    error UnsupportedAssetType(uint256 _assetType);

    constructor(address _owner) Marketplace(address(0)) EIP712("EthereumMarketplace", "1.0.0") Ownable(_owner) {}

    function _transferAsset(Asset memory _asset, address _from, address) internal override {
        if (_asset.assetType == ERC20_ID) {
            _transferERC20(_asset, _from);
        } else if (_asset.assetType == ERC721_ID) {
            _transferERC721(_asset, _from);
        } else if (_asset.assetType == COMPOSABLE_ERC721_ID) {
            _transferComposableERC721(_asset, _from);
        } else {
            revert UnsupportedAssetType(_asset.assetType);
        }
    }
}
