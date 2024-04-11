// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {EIP712} from "lib/openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {IERC721} from "lib/openzeppelin-contracts/contracts/interfaces/IERC721.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

error InvalidSigner();
error Expired();
error NotAllowed();
error InvalidContractSignatureIndex();
error InvalidSignerSignatureIndex();
error TooEarly();
error SignatureReuse();

abstract contract Marketplace is EIP712, Ownable {
    // keccak256("Asset(uint8 assetType,address contractAddress,uint256 value)")
    bytes32 private constant ASSET_TYPE_HASH = 0xb99bebde0a31108e2aed751915f8c3174d744fbda4708f4f545daf7c07fc8937;
    // keccak256("Trade(uint256 expiration,uint256 effective,bytes32 salt,uint256 contractSignatureIndex,uint256 signerSignatureIndex,address[] allowed,Asset[] sent,Asset[] received)Asset(uint8 assetType,address contractAddress,uint256 value)")
    bytes32 private constant TRADE_TYPE_HASH = 0x1bdec0e51d4e120fdb787292dc72c87dc263335a7a6691d368f4f3bd8bd5df1f;

    uint256 private contractSignatureIndex;
    mapping(address => uint256) private signerSignatureIndex;
    mapping(bytes32 => uint256) private signatureUses;

    struct Asset {
        uint256 assetType;
        address contractAddress;
        uint256 value;
        bytes extra;
    }

    struct Trade {
        address signer;
        bytes signature;
        uint256 uses;
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

            bytes32 hashedSignature = keccak256(trade.signature);

            if (signatureUses[hashedSignature] >= trade.uses) {
                revert SignatureReuse();
            }

            if (trade.effective != 0 && trade.effective < block.timestamp) {
                revert TooEarly();
            }

            if (contractSignatureIndex != trade.contractSignatureIndex) {
                revert InvalidContractSignatureIndex();
            }

            if (signerSignatureIndex[trade.signer] != trade.signerSignatureIndex) {
                revert InvalidSignerSignatureIndex();
            }

            if (trade.expiration < block.timestamp) {
                revert Expired();
            }

            if (trade.allowed.length > 0) {
                for (uint256 j = 0; j < trade.allowed.length; j++) {
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
                            abi.encodePacked(_hashAssets(trade.sent)),
                            abi.encodePacked(_hashAssets(trade.received))
                        )
                    )
                ),
                trade.signature
            );

            if (recovered != trade.signer) {
                revert InvalidSigner();
            }

            signatureUses[hashedSignature]++;

            _transferAssets(trade.sent, trade.signer, _msgSender());
            _transferAssets(trade.received, _msgSender(), trade.signer);
        }
    }

    function _hashAssets(Asset[] memory _assets) private pure returns (bytes32[] memory) {
        bytes32[] memory hashes = new bytes32[](_assets.length);

        for (uint256 i = 0; i < hashes.length; i++) {
            Asset memory asset = _assets[i];

            hashes[i] = keccak256(abi.encode(ASSET_TYPE_HASH, asset.contractAddress, asset.value));
        }

        return hashes;
    }

    function _transferAssets(Asset[] memory _assets, address _from, address _to) private {
        for (uint256 i = 0; i < _assets.length; i++) {
            _transferAsset(_assets[i], _from, _to);
        }
    }

    function _transferAsset(Asset memory _asset, address _from, address _to) internal virtual;
}
