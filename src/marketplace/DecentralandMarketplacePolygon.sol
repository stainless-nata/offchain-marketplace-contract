// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {EIP712} from "src/common/EIP712.sol";
import {NativeMetaTransaction} from "src/common/NativeMetaTransaction.sol";
import {ICollection} from "src/marketplace/ICollection.sol";
import {MarketplaceWithCouponManager} from "src/marketplace/MarketplaceWithCouponManager.sol";
import {DecentralandMarketplacePolygonAssetTypes} from "src/marketplace/DecentralandMarketplacePolygonAssetTypes.sol";
import {IRoyaltiesManager} from "src/marketplace/IRoyaltiesManager.sol";

contract DecentralandMarketplacePolygon is DecentralandMarketplacePolygonAssetTypes, MarketplaceWithCouponManager, NativeMetaTransaction {
    address public feeCollector;
    uint256 public feeRate;
    IRoyaltiesManager public royaltiesManager;
    uint256 public royaltiesRate;

    error NotCreator();
    error NoRoyaltiesReceiver();

    constructor(address _owner, address _couponManager, address _feeCollector, uint256 _feeRate, address _royaltiesManager, uint256 _royaltiesRate)
        Ownable(_owner)
        EIP712("DecentralandMarketplacePolygon", "1.0.0")
        MarketplaceWithCouponManager(_couponManager)
    {
        feeCollector = _feeCollector;
        feeRate = _feeRate;
        royaltiesManager = IRoyaltiesManager(_royaltiesManager);
        royaltiesRate = _royaltiesRate;
    }

    function _transferAsset(Asset memory _asset, address _from, address _signer, address _caller) internal override {
        uint256 assetType = _asset.assetType;

        if (assetType == ASSET_TYPE_ERC20) {
            _transferERC20(_asset, _from, feeRate, feeCollector);
        } else if (assetType == ASSET_TYPE_ERC721) {
            _transferERC721(_asset, _from);
        } else if (assetType == ASSET_TYPE_COLLECTION_ITEM) {
            _transferERC721CollectionItem(_asset, _signer, _caller);
        } else if (assetType == ASSET_TYPE_ERC20_WITH_ROYALTIES) {
            _transferERC20WithRoyalties(_asset, _signer);
        } else {
            revert UnsupportedAssetType(assetType);
        }
    }

    function _transferERC20(Asset memory _asset, address _from, uint256 _feeRate, address _feeCollector) private {
        uint256 originalValue = _asset.value;
        uint256 fee = originalValue * _feeRate / 1_000_000;

        SafeERC20.safeTransferFrom(IERC20(_asset.contractAddress), _from, _asset.beneficiary, originalValue - fee);
        SafeERC20.safeTransferFrom(IERC20(_asset.contractAddress), _from, _feeCollector, fee);
    }

    function _transferERC721(Asset memory _asset, address _from) private {
        IERC721 erc721 = IERC721(_asset.contractAddress);

        erc721.safeTransferFrom(_from, _asset.beneficiary, _asset.value);
    }

    function _transferERC721CollectionItem(Asset memory _asset, address _signer, address _caller) private {
        ICollection collection = ICollection(_asset.contractAddress);

        address creator = collection.creator();

        if (creator != _signer && creator != _caller) {
            revert NotCreator();
        }

        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = _asset.beneficiary;

        uint256[] memory itemIds = new uint256[](1);
        itemIds[0] = _asset.value;

        collection.issueTokens(beneficiaries, itemIds);
    }

    function _transferERC20WithRoyalties(Asset memory _asset, address _from) private {
        (address contractAddress, uint256 tokenId) = abi.decode(_asset.extra, (address, uint256));
        address royaltiesReceiver = royaltiesManager.getRoyaltiesReceiver(contractAddress, tokenId);

        if (royaltiesReceiver == address(0)) {
            revert NoRoyaltiesReceiver();
        }

        _transferERC20(_asset, _from, royaltiesRate, royaltiesReceiver);
    }

    function _msgSender() internal view override returns (address) {
        return _getMsgSender();
    }
}
