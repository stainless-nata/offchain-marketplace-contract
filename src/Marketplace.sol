// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/interfaces/IERC721.sol";
import {ICollection} from "./interfaces/ICollection.sol";

error InvalidSigner();
error Expired();
error NotAllowed();

contract Marketplace is EIP712 {
    // keccak256("Asset(uint8 assetType,address contractAddress,uint256 value)")
    bytes32 internal constant ASSET_TYPE_HASH = 0xb99bebde0a31108e2aed751915f8c3174d744fbda4708f4f545daf7c07fc8937;
    // keccak256("Trade(uint256 expiration,address[] allowed,Asset[] sent, Asset[] received)Asset(uint8 assetType,address contractAddress,uint256 value)")
    bytes32 internal constant TRADE_TYPE_HASH = 0x3ef7c41fc4fc09bac98f8a1de3e526cef4c2cace932ad41edf7e40e5201c0915;

    enum AssetType {
        ERC20,
        ERC721,
        ITEM
    }

    struct Asset {
        AssetType assetType;
        address contractAddress;
        uint256 value;
    }

    struct Trade {
        address signer;
        uint256 expiration;
        address[] allowed;
        bytes signature;
        Asset[] sent;
        Asset[] received;
    }

    constructor() EIP712("Marketplace", "0.0.1") {}

    function accept(Trade[] calldata _trades) external {
        for (uint256 i = 0; i < _trades.length; i++) {
            Trade memory trade = _trades[i];

            if (trade.expiration < block.timestamp) {
                revert Expired();
            }

            if (trade.allowed.length > 0) {
                for (uint256 j = 0; i < trade.allowed.length; j++) {
                    if (trade.allowed[j] == msg.sender) {
                        break;
                    }

                    if (j == trade.allowed.length - 1) {
                        revert NotAllowed();
                    }
                }
            }

            address recovered = ECDSA.recover(
                _hashTypedDataV4(
                    keccak256(
                        abi.encode(
                            TRADE_TYPE_HASH,
                            trade.expiration,
                            abi.encodePacked(trade.allowed),
                            _hashAssets(trade.sent),
                            _hashAssets(trade.received)
                        )
                    )
                ),
                trade.signature
            );

            if (recovered != trade.signer) {
                revert InvalidSigner();
            }

            _transferAssets(trade.sent, trade.signer, msg.sender);
            _transferAssets(trade.received, msg.sender, trade.signer);
        }
    }

    function _hashAssets(Asset[] memory _assets) internal pure returns (bytes memory) {
        bytes32[] memory hashes = new bytes32[](_assets.length);

        for (uint256 i = 0; i < hashes.length; i++) {
            hashes[i] = keccak256(abi.encode(ASSET_TYPE_HASH, _assets[i].contractAddress, _assets[i].value));
        }

        return abi.encodePacked(hashes);
    }

    function _transferAssets(Asset[] memory _assets, address _from, address _to) internal {
        for (uint256 i = 0; i < _assets.length; i++) {
            if (_assets[i].assetType == AssetType.ERC20) {
                IERC20(_assets[i].contractAddress).transferFrom(_from, _to, _assets[i].value);
            } else if (_assets[i].assetType == AssetType.ERC721) {
                IERC721(_assets[i].contractAddress).safeTransferFrom(_from, _to, _assets[i].value);
            } else {
                address[] memory beneficiaries = new address[](1);
                beneficiaries[0] = _to;

                uint256[] memory itemIds = new uint256[](1);
                itemIds[0] = _assets[i].value;

                ICollection(_assets[i].contractAddress).issueTokens(beneficiaries, itemIds);
            }
        }
    }
}
