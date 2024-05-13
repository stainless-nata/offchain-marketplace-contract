// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {EIP712} from "src/common/EIP712.sol";
import {NativeMetaTransaction} from "src/common/NativeMetaTransaction.sol";
import {ICollection} from "src/marketplace/interfaces/ICollection.sol";
import {MarketplaceWithCouponManager} from "src/marketplace/MarketplaceWithCouponManager.sol";
import {DecentralandMarketplacePolygonAssetTypes} from "src/marketplace/DecentralandMarketplacePolygonAssetTypes.sol";
import {IRoyaltiesManager} from "src/marketplace/interfaces/IRoyaltiesManager.sol";
import {FeeCollector} from "src/marketplace/FeeCollector.sol";

contract DecentralandMarketplacePolygon is
    DecentralandMarketplacePolygonAssetTypes,
    MarketplaceWithCouponManager,
    NativeMetaTransaction,
    FeeCollector
{
    IRoyaltiesManager public royaltiesManager;
    uint256 public royaltiesRate;

    event RoyaltiesManagerUpdated(address indexed _caller, address indexed _royaltiesManager);
    event RoyaltiesRateUpdated(address indexed _caller, uint256 _royaltiesRate);

    error NotCreator();
    error NoRoyaltiesReceiver();

    constructor(address _owner, address _couponManager, address _feeCollector, uint256 _feeRate, address _royaltiesManager, uint256 _royaltiesRate)
        FeeCollector(_feeCollector, _feeRate)
        Ownable(_owner)
        EIP712("DecentralandMarketplacePolygon", "1.0.0")
        MarketplaceWithCouponManager(_couponManager)
    {
        _updateRoyaltiesManager(_royaltiesManager);
        _updateRoyaltiesRate(_royaltiesRate);
    }

    function updateFeeCollector(address _feeCollector) external onlyOwner {
        _updateFeeCollector(_msgSender(), _feeCollector);
    }

    function updateFeeRate(uint256 _feeRate) external onlyOwner {
        _updateFeeRate(_msgSender(), _feeRate);
    }

    function updateRoyaltiesManager(address _royaltiesManager) external onlyOwner {
        _updateRoyaltiesManager(_royaltiesManager);
    }

    function updateRoyaltiesRate(uint256 _royaltiesRate) external onlyOwner {
        _updateRoyaltiesRate(_royaltiesRate);
    }

    function _transferAsset(Asset memory _asset, address _from, address _signer, address _caller) internal override {
        uint256 assetType = _asset.assetType;

        if (assetType == ASSET_TYPE_ERC20) {
            _transferERC20WithCollectorFee(_asset, _from, feeCollector, feeRate);
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

        _transferERC20WithCollectorFee(_asset, _from, royaltiesReceiver, royaltiesRate);
    }

    function _updateRoyaltiesManager(address _royaltiesManager) internal {
        royaltiesManager = IRoyaltiesManager(_royaltiesManager);

        emit RoyaltiesManagerUpdated(_msgSender(), _royaltiesManager);
    }

    function _updateRoyaltiesRate(uint256 _royaltiesRate) internal {
        royaltiesRate = _royaltiesRate;

        emit RoyaltiesRateUpdated(_msgSender(), _royaltiesRate);
    }

    function _msgSender() internal view override returns (address) {
        return _getMsgSender();
    }
}
