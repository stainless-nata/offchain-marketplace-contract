// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {CommonTypes} from "src/common/CommonTypes.sol";

/// @notice Types used by the Marketplace.
abstract contract MarketplaceTypes is CommonTypes {
    /// @notice Schema for the Asset type.
    /// This represents any kind of asset that will be traded.
    /// @param assetType Type of the asset. Used to know how to handle it.
    /// @param contractAddress Address of the contract of the asset.
    /// @param value Value of the asset. The amount for ERC20s, the ID for ERC721s, etc.
    /// @param beneficiary Address that will receive the asset. If empty, depending if the asset is sent or received, the beneficiary will be the signer or the caller.
    /// In the case of sent assets, the beneficiary is not validated in the signature. This is to allow the caller to determine which address will receive the asset.
    /// @param extra Extra data that can be used to store additional information. 
    struct Asset {
        uint256 assetType;
        address contractAddress;
        uint256 value;
        address beneficiary;
        bytes extra;
    }

    /// @notice Schema for the Trade type.
    /// This represents a signed Trade that indicates the terms of the Trade, as well as the assets involved.
    /// @param signer Address of the signer of the Trade.
    /// @param signature Signature of the Trade.
    /// @param checks Checks to be performed before executing the Trade.
    /// @param sent Assets that will be sent to the caller in the Trade.
    /// @param received Assets that will be received by the signer in the Trade.
    struct Trade {
        address signer;
        bytes signature;
        Checks checks;
        Asset[] sent;
        Asset[] received;
    }
}
