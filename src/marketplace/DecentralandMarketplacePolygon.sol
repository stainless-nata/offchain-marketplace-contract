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

/// @notice Decentraland Marketplace contract for the Polygon network assets. MANA, Wearables, Emotes, etc.
contract DecentralandMarketplacePolygon is
    DecentralandMarketplacePolygonAssetTypes,
    MarketplaceWithCouponManager,
    NativeMetaTransaction,
    FeeCollector
{
    /// @notice The royalties manager contract. Used to get the royalties receiver for collection nft trades.
    IRoyaltiesManager public royaltiesManager;

    /// @notice The rate of the royalties to be sent to the royalties receiver.
    uint256 public royaltiesRate;

    event RoyaltiesManagerUpdated(address indexed _caller, address indexed _royaltiesManager);
    event RoyaltiesRateUpdated(address indexed _caller, uint256 _royaltiesRate);

    error NotCreator();

    /// @param _owner The owner of the contract.
    /// @param _couponManager The address of the coupon manager contract.
    /// @param _feeCollector The address that will receive erc20 fees.
    /// @param _feeRate The rate of the fee. 25_000 is 2.5%
    /// @param _royaltiesManager The address of the royalties manager contract.
    /// @param _royaltiesRate The rate of the royalties. 25_000 is 2.5%
    constructor(address _owner, address _couponManager, address _feeCollector, uint256 _feeRate, address _royaltiesManager, uint256 _royaltiesRate)
        Ownable(_owner)
        MarketplaceWithCouponManager(_couponManager)
        FeeCollector(_feeCollector, _feeRate)
        EIP712("DecentralandMarketplacePolygon", "1.0.0")
    {
        _updateRoyaltiesManager(_royaltiesManager);
        _updateRoyaltiesRate(_royaltiesRate);
    }

    /// @notice Updates the fee collector address.
    /// @param _feeCollector The new fee collector address.
    function updateFeeCollector(address _feeCollector) external onlyOwner {
        _updateFeeCollector(_msgSender(), _feeCollector);
    }

    /// @notice Updates the fee rate.
    /// @param _feeRate The new fee rate.
    function updateFeeRate(uint256 _feeRate) external onlyOwner {
        _updateFeeRate(_msgSender(), _feeRate);
    }

    /// @notice Updates the royalties manager address.
    /// @param _royaltiesManager The new royalties manager address.
    function updateRoyaltiesManager(address _royaltiesManager) external onlyOwner {
        _updateRoyaltiesManager(_royaltiesManager);
    }

    /// @notice Updates the royalties rate.
    /// @param _royaltiesRate The new royalties rate.
    function updateRoyaltiesRate(uint256 _royaltiesRate) external onlyOwner {
        _updateRoyaltiesRate(_royaltiesRate);
    }

    /// @dev Overriden Marketplace function which modifies the Trade before being accepted.
    /// In this case, the Trade is modified to handle fees and royalties.
    function _modifyTrade(Trade memory _trade) internal view override returns (Trade memory) {
        uint256 sentLength = _trade.sent.length;
        uint256 receivedLength = _trade.received.length;

        // Tracks if the fee collector should be paid.
        bool payFeeCollector = false;
        // Tracks the number of addresses that have to be paid royalties.
        uint256 royaltyBeneficiariesCount = 0;
        // Tracks the addresses that have to be paid royalties.
        address[] memory royaltyBeneficiaries = new address[](sentLength + receivedLength);

        (payFeeCollector, royaltyBeneficiariesCount, royaltyBeneficiaries) =
            _getFeesAndRoyalties(payFeeCollector, royaltyBeneficiariesCount, royaltyBeneficiaries, _trade.sent);

        (payFeeCollector, royaltyBeneficiariesCount, royaltyBeneficiaries) =
            _getFeesAndRoyalties(payFeeCollector, royaltyBeneficiariesCount, royaltyBeneficiaries, _trade.received);

        // Encodes the fees and royalties data to be stored in the assets.
        bytes memory endocodedFeeAndRoyaltyData = abi.encode(payFeeCollector, royaltyBeneficiariesCount, royaltyBeneficiaries);

        // Update erc20 assets to include fee and royalties data.
        _trade.sent = _updateERC20sWithFees(_trade.sent, endocodedFeeAndRoyaltyData);
        _trade.received = _updateERC20sWithFees(_trade.received, endocodedFeeAndRoyaltyData);

        return _trade;
    }

    /// @dev From the provided assets, returns if the fee collector should be paid and the respective royalties beneficiaries.
    function _getFeesAndRoyalties(
        bool _payFeeCollector,
        uint256 _royaltyBeneficiariesCount,
        address[] memory _royaltyBeneficiaries,
        Asset[] memory _assets
    ) private view returns (bool, uint256, address[] memory) {
        for (uint256 i = 0; i < _assets.length; i++) {
            // Users cannot use this asset type directly in the trade, it is only used internally.
            if (_assets[i].assetType == ASSET_TYPE_ERC20_WITH_FEES) {
                revert UnsupportedAssetType(ASSET_TYPE_ERC20_WITH_FEES);
            }

            if (_assets[i].assetType == ASSET_TYPE_ERC721) {
                // If the NFT is of a Decentraland Collection, the royalty beneficiary will be the item beneficiary or it's creator.
                // If not, the royalty beneficiary will return address(0)
                address royaltyBeneficiary = royaltiesManager.getRoyaltiesReceiver(_assets[i].contractAddress, _assets[i].value);

                if (royaltyBeneficiary != address(0)) {
                    _royaltyBeneficiaries[_royaltyBeneficiariesCount++] = royaltyBeneficiary;
                } else {
                    // If the NFT is not a Decentraland Collection, the fee collector should be paid.
                    _payFeeCollector = true;
                }
            } else if (_assets[i].assetType == ASSET_TYPE_COLLECTION_ITEM) {
                // Minting Collection Items pay fees to the collector.
                _payFeeCollector = true;
            }
        }

        return (_payFeeCollector, _royaltyBeneficiariesCount, _royaltyBeneficiaries);
    }

    /// @dev Iterate through the provided assets and update the ERC20 assets to include the fees and royalties data.
    function _updateERC20sWithFees(Asset[] memory _assets, bytes memory _endocodedFeeAndRoyaltyData) private pure returns (Asset[] memory) {
        for (uint256 i = 0; i < _assets.length; i++) {
            if (_assets[i].assetType == ASSET_TYPE_ERC20) {
                _assets[i].assetType = ASSET_TYPE_ERC20_WITH_FEES;
                _assets[i].extra = _endocodedFeeAndRoyaltyData;
            }
        }

        return _assets;
    }

    /// @dev Overriden Marketplace function to transfer assets.
    /// Handles the transfer of ERC721s and the minting of Collection Items. Also handles the transfer of ERC20s with fees.
    function _transferAsset(Asset memory _asset, address _from, address _signer, address _caller) internal override {
        uint256 assetType = _asset.assetType;

        if (assetType == ASSET_TYPE_ERC20_WITH_FEES) {
            _transferERC20WithFees(_asset, _from);
        } else if (assetType == ASSET_TYPE_ERC721) {
            _transferERC721(_asset, _from);
        } else if (assetType == ASSET_TYPE_COLLECTION_ITEM) {
            _transferERC721CollectionItem(_asset, _signer, _caller);
        } else {
            revert UnsupportedAssetType(assetType);
        }
    }

    /// @dev Transfers ERC20 assets with fees and royalties.
    /// The fees are included in the `extra` asset data and were set in the `_modifyTrade` function.
    function _transferERC20WithFees(Asset memory _asset, address _from) private {
        // Get the fee data from the `extra` field.
        (bool payFeeCollector, uint256 royaltyBeneficiariesCount, address[] memory royaltyBeneficiaries) =
            abi.decode(_asset.extra, (bool, uint256, address[]));

        uint256 originalValue = _asset.value;
        // Track the total amount of fees and royalties to be paid.
        uint256 fees = 0;

        IERC20 erc20 = IERC20(_asset.contractAddress);

        // If the fee collector has to be paid, calculate the fee and transfer it.
        if (payFeeCollector) {
            fees = originalValue * feeRate / 1_000_000;

            SafeERC20.safeTransferFrom(erc20, _from, feeCollector, fees);
        }

        // If there are royalties to be paid, calculate the royalties and transfer them.
        if (royaltyBeneficiariesCount > 0) {
            uint256 royaltyFees = originalValue * royaltiesRate / 1_000_000;
            uint256 individualRoyaltyFee = royaltyFees / royaltyBeneficiariesCount;

            for (uint256 i = 0; i < royaltyBeneficiariesCount; i++) {
                SafeERC20.safeTransferFrom(erc20, _from, royaltyBeneficiaries[i], individualRoyaltyFee);
            }

            fees += royaltyFees;
        }

        SafeERC20.safeTransferFrom(erc20, _from, _asset.beneficiary, originalValue - fees);
    }

    /// @dev Transfers ERC721 assets.
    function _transferERC721(Asset memory _asset, address _from) private {
        IERC721 erc721 = IERC721(_asset.contractAddress);

        erc721.safeTransferFrom(_from, _asset.beneficiary, _asset.value);
    }

    /// @dev Mints collection items.
    function _transferERC721CollectionItem(Asset memory _asset, address _signer, address _caller) private {
        ICollection collection = ICollection(_asset.contractAddress);

        address creator = collection.creator();

        // This check verifies that at least the caller or the signer have to be the creator.
        // This allows the following:
        // 1. The creator creates a Trade to sell a collection item. Any user can accept the Trade an will be valid.
        // 2. Any user creates a counter offer to buy a collection item. Only the creator should be able to accept the Trade.
        if (creator != _signer && creator != _caller) {
            revert NotCreator();
        }

        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = _asset.beneficiary;

        uint256[] memory itemIds = new uint256[](1);
        itemIds[0] = _asset.value;

        collection.issueTokens(beneficiaries, itemIds);
    }

    /// @dev Updates the royalties manager address.
    /// @param _royaltiesManager The new royalties manager address.
    function _updateRoyaltiesManager(address _royaltiesManager) internal {
        royaltiesManager = IRoyaltiesManager(_royaltiesManager);

        emit RoyaltiesManagerUpdated(_msgSender(), _royaltiesManager);
    }

    /// @dev Updates the royalties rate.
    /// @param _royaltiesRate The new royalties rate.
    function _updateRoyaltiesRate(uint256 _royaltiesRate) internal {
        royaltiesRate = _royaltiesRate;

        emit RoyaltiesRateUpdated(_msgSender(), _royaltiesRate);
    }

    /// @dev Overriden function to obtain the caller of the transaction.
    /// The contract accepts meta transactions, so the caller could be the signer of the meta transaction or the real caller depending the situation.
    function _msgSender() internal view override returns (address) {
        return _getMsgSender();
    }
}
