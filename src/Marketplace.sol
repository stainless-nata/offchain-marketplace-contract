// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/interfaces/IERC721.sol";
import {ICollection} from "./interfaces/ICollection.sol";

error InvalidSigner();
error Expired();

contract Marketplace is EIP712 {
    // keccak256("Asset(uint8 assetType,address contractAddress,uint256 amountOrTokenId)")
    bytes32 internal constant ASSET_TYPE_HASH = 0xca6dc34521a1a16a3c61f9d8d9dbb453951798636529b1dbc7cf94741d77dee3;
    // keccak256("Trade(uint256 expiration,Asset[] sent, Asset[] received)Asset(uint8 assetType,address contractAddress,uint256 amountOrTokenId)")
    bytes32 internal constant TRADE_TYPE_HASH = 0x9d49c7e9085f54e2e1b874043489c1fb55b91ee90f4a15f6b9cc7dfb0aa276d7;

    enum AssetType {
        ERC20,
        ERC721,
        ITEM
    }

    struct Asset {
        AssetType assetType;
        address contractAddress;
        uint256 amountOrTokenId;
    }

    struct Trade {
        address signer;
        uint256 expiration;
        bytes signature;
        Asset[] sent;
        Asset[] received;
    }

    constructor() EIP712("Marketplace", "0.0.1") {}

    function accept(Trade calldata _trade) external {
        if (_trade.expiration < block.timestamp) {
            revert Expired();
        }

        address recovered = ECDSA.recover(
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        TRADE_TYPE_HASH, _trade.expiration, _hashAssets(_trade.sent), _hashAssets(_trade.received)
                    )
                )
            ),
            _trade.signature
        );

        if (recovered != _trade.signer) {
            revert InvalidSigner();
        }

        _transferAssets(_trade.sent, _trade.signer, msg.sender);
        _transferAssets(_trade.received, msg.sender, _trade.signer);
    }

    function _hashAssets(Asset[] memory _assets) internal pure returns (bytes memory) {
        bytes32[] memory hashes = new bytes32[](_assets.length);

        for (uint256 i = 0; i < hashes.length; i++) {
            hashes[i] = keccak256(abi.encode(ASSET_TYPE_HASH, _assets[i].contractAddress, _assets[i].amountOrTokenId));
        }

        return abi.encodePacked(hashes);
    }

    function _transferAssets(Asset[] memory _assets, address _from, address _to) internal {
        for (uint256 i = 0; i < _assets.length; i++) {
            if (_assets[i].assetType == AssetType.ERC20) {
                IERC20(_assets[i].contractAddress).transferFrom(_from, _to, _assets[i].amountOrTokenId);
            } else if (_assets[i].assetType == AssetType.ERC721) {
                IERC721(_assets[i].contractAddress).safeTransferFrom(_from, _to, _assets[i].amountOrTokenId);
            } else {
                address[] memory beneficiaries = new address[](1);
                beneficiaries[0] = _to;

                uint256[] memory itemIds = new uint256[](1);
                itemIds[0] = _assets[i].amountOrTokenId;

                ICollection(_assets[i].contractAddress).issueTokens(beneficiaries, itemIds);
            }
        }
    }
}
