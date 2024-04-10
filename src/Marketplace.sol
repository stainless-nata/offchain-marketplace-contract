// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/interfaces/IERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ICollection} from "./interfaces/ICollection.sol";

error InvalidSignature();
error Expired();
error NotAllowed();
error UsedSalt();
error InvalidContractSignatureIndex();
error InvalidSignerSignatureIndex();
error TooEarly();

contract Marketplace is EIP712, Ownable {
    // keccak256("Asset(uint8 assetType,address contractAddress,uint256 value)")
    bytes32 internal constant ASSET_TYPE_HASH = 0xb99bebde0a31108e2aed751915f8c3174d744fbda4708f4f545daf7c07fc8937;
    // keccak256("Trade(uint256 expiration,uint256 effective,bytes32 salt,uint256 contractSignatureIndex,uint256 signerSignatureIndex,address[] allowed,Asset[] sent,Asset[] received)Asset(uint8 assetType,address contractAddress,uint256 value)")
    bytes32 internal constant TRADE_TYPE_HASH = 0x1bdec0e51d4e120fdb787292dc72c87dc263335a7a6691d368f4f3bd8bd5df1f;

    uint256 private contractSignatureIndex;
    mapping(address => uint256) private signerSignatureIndex;
    mapping(address => mapping(bytes32 => bool)) private usedSalts;

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
        bytes signature;
        uint256 expiration;
        uint256 effective;
        bytes32 salt;
        uint256 contractSignatureIndex;
        uint256 signerSignatureIndex;
        address[] allowed;
        Asset[] sent;
        Asset[] received;
    }

    constructor() EIP712("Marketplace", "0.0.1") Ownable(_msgSender()) {}

    function increaseContractSignatureIndex() external onlyOwner {
        contractSignatureIndex++;
    }

    function increaseSignerSignatureIndex() external {
        signerSignatureIndex[_msgSender()]++;
    }

    function accept(Trade[] calldata _trades) external {
        for (uint256 i = 0; i < _trades.length; i++) {
            Trade memory trade = _trades[i];

            if (trade.effective != 0 && trade.effective < block.timestamp) {
                revert TooEarly();
            }

            if (contractSignatureIndex != trade.contractSignatureIndex) {
                revert InvalidContractSignatureIndex();
            }

            if (signerSignatureIndex[trade.signer] != trade.signerSignatureIndex) {
                revert InvalidSignerSignatureIndex();
            }

            if (usedSalts[_msgSender()][trade.salt]) {
                revert UsedSalt();
            }

            if (trade.expiration < block.timestamp) {
                revert Expired();
            }

            if (trade.allowed.length > 0) {
                for (uint256 j = 0; i < trade.allowed.length; j++) {
                    if (trade.allowed[j] == _msgSender()) {
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
                            trade.effective,
                            trade.salt,
                            trade.contractSignatureIndex,
                            trade.signerSignatureIndex,
                            abi.encodePacked(trade.allowed),
                            _hashAssets(trade.sent),
                            _hashAssets(trade.received)
                        )
                    )
                ),
                trade.signature
            );

            if (recovered != trade.signer) {
                revert InvalidSignature();
            }

            usedSalts[_msgSender()][trade.salt] = true;

            _transferAssets(trade.sent, trade.signer, _msgSender());
            _transferAssets(trade.received, _msgSender(), trade.signer);
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
