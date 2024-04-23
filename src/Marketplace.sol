// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ECDSA} from "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {IERC721} from "lib/openzeppelin-contracts/contracts/interfaces/IERC721.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {Pausable} from "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {SignatureChecker} from "lib/openzeppelin-contracts/contracts/utils/cryptography/SignatureChecker.sol";
import {EIP712} from "./external/EIP712.sol";

/**
 * @notice Marketplace contract that allows the execution of signed Trades.
 * Users can sign a Trade indicating which assets are to be traded. Another user can the accept the Trade using the signature, executing the exchange.
 */
abstract contract Marketplace is EIP712, Ownable, Pausable, ReentrancyGuard {
    // keccak256("AssetWithoutBeneficiary(uint256 assetType,address contractAddress,uint256 value,bytes extra)")
    bytes32 private constant ASSET_WO_BENEFICIARY_TYPE_HASH = 0x7be57332caf51c5f0f0fa0e7c362534d22d81c0bee1ffac9b573acd336e032bd;
    // keccak256("Asset(uint256 assetType,address contractAddress,uint256 value,bytes extra,address beneficiary)")
    bytes32 private constant ASSET_TYPE_HASH = 0xe5f9e1ebc316d1bde562c77f47da7dc2cccb903eb04f9b82e29212b96f9e57e1;
    // keccak256("Trade(uint256 uses,uint256 expiration,uint256 effective,bytes32 salt,uint256 contractSignatureIndex,uint256 signerSignatureIndex,address[] allowed,AssetWithoutBeneficiary[] sent,Asset[] received)Asset(uint256 assetType,address contractAddress,uint256 value,bytes extra,address beneficiary)AssetWithoutBeneficiary(uint256 assetType,address contractAddress,uint256 value,bytes extra)")
    bytes32 private constant TRADE_TYPE_HASH = 0xb967bcaa9c7a374d193cf0f8af42cb15a1f51f6e94e22610b82c42c7cb93dd86;

    uint256 public contractSignatureIndex;

    mapping(address => uint256) public signerSignatureIndex;
    mapping(bytes32 => uint256) private signatureUses;
    mapping(bytes32 => bool) private cancelledSignatures;

    struct Asset {
        uint256 assetType;
        address contractAddress;
        uint256 value;
        bytes extra;
        address beneficiary;
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

    event ContractSignatureIndexIncreased(uint256 _to, address _by);
    event SignerSignatureIndexIncreased(uint256 _to, address _by);
    event Traded();
    event SignatureCancelled();

    error InvalidSignature();
    error Expired();
    error NotAllowed();
    error InvalidContractSignatureIndex();
    error InvalidSignerSignatureIndex();
    error SignatureReuse();
    error CancelledSignature();
    error NotEffective();

    constructor(address _owner) EIP712("Marketplace", "0.0.1") Ownable(_owner) {}

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function increaseContractSignatureIndex() external onlyOwner {
        contractSignatureIndex++;

        emit ContractSignatureIndexIncreased(contractSignatureIndex, _msgSender());
    }

    function increaseSignerSignatureIndex() external {
        signerSignatureIndex[_msgSender()]++;

        emit SignerSignatureIndexIncreased(signerSignatureIndex[_msgSender()], _msgSender());
    }

    function cancelSignature(Trade[] calldata _trades) external {
        for (uint256 i = 0; i < _trades.length; i++) {
            Trade memory trade = _trades[i];

            _verifyTradeSignature(trade, _msgSender());

            cancelledSignatures[keccak256(trade.signature)] = true;

            emit SignatureCancelled();
        }
    }

    function accept(Trade[] calldata _trades) external whenNotPaused nonReentrant {
        for (uint256 i = 0; i < _trades.length; i++) {
            Trade memory trade = _trades[i];

            bytes32 hashedSignature = keccak256(trade.signature);

            if (cancelledSignatures[hashedSignature]) {
                revert CancelledSignature();
            }

            if (trade.uses > 0 && signatureUses[hashedSignature] >= trade.uses) {
                revert SignatureReuse();
            }

            if (trade.effective > block.timestamp) {
                revert NotEffective();
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

            _verifyTradeSignature(trade, trade.signer);

            signatureUses[hashedSignature]++;

            emit Traded();

            _transferAssets(trade.sent, trade.signer, _msgSender());

            _transferAssets(trade.received, _msgSender(), trade.signer);
        }
    }

    function _hashTrade(Trade memory _trade) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                TRADE_TYPE_HASH,
                _trade.uses,
                _trade.expiration,
                _trade.effective,
                _trade.salt,
                _trade.contractSignatureIndex,
                _trade.signerSignatureIndex,
                keccak256(abi.encodePacked(_trade.allowed)),
                _hashAssetsWithoutBeneficiary(_trade.sent),
                _hashAssets(_trade.received)
            )
        );
    }

    function _hashAssetsWithoutBeneficiary(Asset[] memory _assets) private pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](_assets.length);

        for (uint256 i = 0; i < hashes.length; i++) {
            Asset memory asset = _assets[i];

            hashes[i] = keccak256(abi.encode(ASSET_WO_BENEFICIARY_TYPE_HASH, asset.assetType, asset.contractAddress, asset.value, asset.extra));
        }

        return keccak256(abi.encodePacked(hashes));
    }

    function _hashAssets(Asset[] memory _assets) private pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](_assets.length);

        for (uint256 i = 0; i < hashes.length; i++) {
            Asset memory asset = _assets[i];

            hashes[i] = keccak256(abi.encode(ASSET_TYPE_HASH, asset.assetType, asset.contractAddress, asset.value, asset.extra, asset.beneficiary));
        }

        return keccak256(abi.encodePacked(hashes));
    }

    function _verifyTradeSignature(Trade memory _trade, address _signer) private view {
        if (!SignatureChecker.isValidSignatureNow(_signer, _hashTypedDataV4(_hashTrade(_trade)), _trade.signature)) {
            revert InvalidSignature();
        }
    }

    function _transferAssets(Asset[] memory _assets, address _from, address _to) private {
        for (uint256 i = 0; i < _assets.length; i++) {
            Asset memory asset = _assets[i];

            if (asset.beneficiary == address(0)) {
                asset.beneficiary = _to;
            }

            _transferAsset(asset, _from);
        }
    }

    function _transferAsset(Asset memory _asset, address _from) internal virtual;
}
