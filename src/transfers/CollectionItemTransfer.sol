// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Context} from "lib/openzeppelin-contracts/contracts/utils/Context.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {ICollection} from "../interfaces/ICollection.sol";
import {ICollectionStore} from "../interfaces/ICollectionStore.sol";
import {Marketplace} from "../Marketplace.sol";

abstract contract CollectionItemTransfer is Context {
    /// @dev The item id that represents an empty item.
    /// This is because the item id 0 represents the firt item of a collection.
    uint256 private constant EMPTY_ITEM_ID = 1337;

    /// @dev The type of discounts that can be applied.
    /// Flat will subtract the discount from the price.
    /// Rate will discount a % from the price.
    uint256 private constant DISCOUNT_TYPE_FLAT = 0;
    uint256 private constant DISCOUNT_TYPE_RATE = 1;

    IERC20 private immutable collectionStoreErc20;
    uint256 private immutable collectionStoreFeeRate;
    uint256 private immutable collectionStoreFeeRateBase;
    address private immutable collectionStoreFeeCollector;

    error NotSentAsset();
    error NotCreator();
    error DifferentCollectionContractAddress();
    error DifferentCollectionItemId();
    error InvalidPrice();
    error InvalidDiscountType();

    constructor(ICollectionStore _collectionStore) {
        // See the _transferCollectionItemWithDiscount for more info about these values.
        collectionStoreErc20 = _collectionStore.acceptedToken();
        collectionStoreFeeRate = _collectionStore.fee();
        collectionStoreFeeRateBase = _collectionStore.BASE_FEE();
        collectionStoreFeeCollector = _collectionStore.feeOwner();
    }

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

    /// @dev Allows creators to apply discounts to their collections.
    /// The discount can be applied to all their collections, a specific collection, or a certain item.
    /// The discount will be applied over the price defined on the collection item.
    /// This function contains behavior similar to the one found on the `buy` function of the CollectionStore contract.
    ///
    /// https://polygonscan.com/address/0x214ffC0f0103735728dc66b61A22e4F163e275ae#code <- CollectionStore
    ///
    /// It will obtain the item price from the collection and apply the discount to it.
    /// The same ERC20 token, and Fee parameters from the CollectionsStore contract are used.
    function _transferCollectionItemWithDiscount(Marketplace.Asset memory _asset, address _from, address _signer) internal {
        // If the from is different from the signer, this is because the Asset has been set as an asset that will be received by the signer,
        // which in this case is not supported given that it could cause the caller to pay for the items but the signer receiving them.
        if (_from != _signer) {
            revert NotSentAsset();
        }

        // Extract the item that the user wants to buy.
        (address contractAddress, uint256 itemId, uint256 price) = abi.decode(_asset.unverifiedExtra, (address, uint256, uint256));

        // Extract the extra Trade data defined by the signer.
        // The discountedItemId defined by the signer is only useful if the contract address for the collection is provided.
        // If an item id is provided and the collection address is address(0), it will be ignored.
        (uint256 discountType, uint256 discountedItemId) = abi.decode(_asset.extra, (uint256, uint256));

        // The signer can define on what level the discount is applied.
        // - If the contract address is address(0) the discount is for all the _signer's collections.
        // - If the contract address is defined the discount is for a specific collection.
        // - If the item id is defined the discount is for a specific item only.
        if (_asset.contractAddress != address(0)) {
            if (_asset.contractAddress != contractAddress) {
                revert DifferentCollectionContractAddress();
            }

            if (discountedItemId != EMPTY_ITEM_ID && discountedItemId != itemId) {
                revert DifferentCollectionItemId();
            }
        }

        ICollection collection = ICollection(contractAddress);

        // Only the creator of the collection can apply discounts.
        if (collection.creator() != _signer) {
            revert NotCreator();
        }

        // Get the price of the collection.
        (,,, uint256 itemPrice, address itemBeneficiary,,) = collection.items(itemId);

        // If the price the original price the caller wants to pay is different from the price of the item, revert.
        // This is to prevent the signer from updating the price beforehand without the caller noticing.
        if (price != itemPrice) {
            revert InvalidPrice();
        }

        uint256 priceWithDiscount;

        // Apply the discount to the price of the item.
        if (discountType == DISCOUNT_TYPE_FLAT) {
            priceWithDiscount = price - _asset.value;
        } else if (discountType == DISCOUNT_TYPE_RATE) {
            priceWithDiscount = price - (price * _asset.value / collectionStoreFeeRateBase);
        } else {
            revert InvalidDiscountType();
        }

        address caller = _msgSender();

        // Get how much from the discounted price has to go to the fee owner.
        uint256 fee = priceWithDiscount * collectionStoreFeeRate / collectionStoreFeeRateBase;

        // Make the caller pay for the item with the discounted price.
        // Also sends the fee to the feeOwner.
        SafeERC20.safeTransferFrom(collectionStoreErc20, caller, itemBeneficiary, priceWithDiscount - fee);
        SafeERC20.safeTransferFrom(collectionStoreErc20, caller, collectionStoreFeeCollector, fee);

        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = _asset.beneficiary;

        uint256[] memory itemIds = new uint256[](1);
        itemIds[0] = _asset.value;

        // Issue the item to the beneficiary defined by the caller.
        collection.issueTokens(beneficiaries, itemIds);
    }
}
