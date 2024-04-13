// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {EIP712} from "lib/openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {IERC721} from "lib/openzeppelin-contracts/contracts/interfaces/IERC721.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {Pausable} from "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

error InvalidSigner();
error Expired();
error NotAllowed();
error InvalidContractSignatureIndex();
error InvalidSignerSignatureIndex();
error SignatureReuse();

abstract contract Marketplace is EIP712, Ownable, Pausable, ReentrancyGuard {
    /// EIP712 Type hash for the Asset struct without the beneficiary.
    /// keccak256("AssetWithoutBeneficiary(uint256 assetType,address contractAddress,uint256 value,bytes extra)")
    bytes32 private constant ASSET_WO_BENEFICIARY_TYPE_HASH =
        0x7be57332caf51c5f0f0fa0e7c362534d22d81c0bee1ffac9b573acd336e032bd;

    /// EIP712 Type hash for the Asset struct.
    /// keccak256("Asset(uint256 assetType,address contractAddress,uint256 value,bytes extra,address beneficiary)")
    bytes32 private constant ASSET_TYPE_HASH = 0xe5f9e1ebc316d1bde562c77f47da7dc2cccb903eb04f9b82e29212b96f9e57e1;

    /// EIP712 Type hash for the Trade struct.
    /// keccak256("Trade(uint256 uses,uint256 expiration,bytes32 salt,uint256 contractSignatureIndex,uint256 signerSignatureIndex,address[] allowed,Asset[] sent,AssetWithBeneficiary[] received)Asset(uint256 assetType,address contractAddress,uint256 value,bytes extra,address beneficiary)AssetWithoutBeneficiary(uint256 assetType,address contractAddress,uint256 value,bytes extra)")
    bytes32 private constant TRADE_TYPE_HASH = 0x2cb5b71f5756633db8ac23d6cea72af6b7e0d03bae2b258f89288bb7f045d851;

    /// Number used as part of the trade signature.
    /// Can be updated by the owner to invalidate all trades signed with it.
    uint256 private contractSignatureIndex;

    /// Number used as part of the trade signature,
    /// Can be updated by the signer to invalidate all trades signed with it.
    mapping(address => uint256) private signerSignatureIndex;

    /// Number of times a signature has been used.
    /// Depends on the trade how many times a signature can be used.
    mapping(bytes32 => uint256) private signatureUses;

    /// Asset struct representing an asset to be traded.
    struct Asset {
        /// The type of asset to be traded, e.g. ERC20, ERC721, etc.
        /// Should be handled accordingly on the overriden _transferAsset function.
        uint256 assetType;
        /// The address of the contract of the asset to be traded.
        address contractAddress;
        /// Depending on the asset to be traded, it could be the amount for ERC20s or the tokenId for ERC721s.
        uint256 value;
        /// Any extra data that might be useful for the asset to be traded.
        /// For example, the data for ERC721 safe transfers or the fingerprint for Composable ERC721s.
        bytes extra;
        /// Used by the signer or the caller to determine who will receive the asset.
        /// If empty, the asset will be sent to the signer or the caller respectively.
        address beneficiary;
    }

    /// Trade struct representing a trade between two parties.
    struct Trade {
        /// The address of the signer of the trade.
        address signer;
        /// The signature of the trade. Created by aforementioned signer.
        bytes signature;
        /// How many times the trade can be executed.
        /// 0 means infinite uses. 1 or more means that the trade can only be executed that many times.
        uint256 uses;
        /// The timestamp the trade cannot be accepted anymore.
        uint256 expiration;
        /// A random value to make the trade signature unique even for Trades with the same values.
        bytes32 salt;
        /// Should be the current contractSignatureIndex to be a valid trade.
        uint256 contractSignatureIndex;
        /// Should be the current signerSignatureIndex of the signer to be a valid trade.
        uint256 signerSignatureIndex;
        /// The addresses allowed to accept the trade.
        /// If empty, any address can accept the trade.
        address[] allowed;
        /// The assets to be sent by the signer.
        Asset[] sent;
        /// The assets to be received by the signer.
        Asset[] received;
    }

    /// @param _owner - The owner of the contract.
    constructor(address _owner) EIP712("Marketplace", "0.0.1") Ownable(_owner) {}

    /// Pauses the contract.
    /// The contract will not accept any trades while paused.
    function pause() external onlyOwner {
        _pause();
    }

    /// Unpauses the contract.
    function unpause() external onlyOwner {
        _unpause();
    }

    /// Increases the contractSignatureIndex by 1.
    /// Can only be called by the owner of the contract.
    /// Increasing it is a way to invalidate all trades signed with the previous value.
    function increaseContractSignatureIndex() external onlyOwner {
        contractSignatureIndex++;
    }

    /// Increases the signerSignatureIndex of the caller by 1.
    /// Increasing it is a way to invalidate all trades signed by the caller with the previous value.
    function increaseSignerSignatureIndex() external {
        signerSignatureIndex[_msgSender()]++;
    }

    /// Main function of the contract.
    /// Accepts an array of trades and executes them.
    /// @param _trades - The trades to be executed.
    function accept(Trade[] calldata _trades) external whenNotPaused nonReentrant {
        for (uint256 i = 0; i < _trades.length; i++) {
            Trade memory trade = _trades[i];

            /// Given that the signature needs to be stored in order to verify how many times it has been used,
            /// it is more efficient to hash it and store the hash than store the whole signature.
            bytes32 hashedSignature = keccak256(trade.signature);

            /// If the trade comes with a defined amount of uses higher than 0.
            /// Will fail if the signature has been used more times than allowed.
            if (trade.uses > 0 && signatureUses[hashedSignature] >= trade.uses) {
                revert SignatureReuse();
            }

            /// Fails if the contractSignatureIndex of the trade is different from the current contractSignatureIndex.
            if (contractSignatureIndex != trade.contractSignatureIndex) {
                revert InvalidContractSignatureIndex();
            }

            /// Fails if the signerSignatureIndex of the trade is different from the current signerSignatureIndex of the signer.
            if (signerSignatureIndex[trade.signer] != trade.signerSignatureIndex) {
                revert InvalidSignerSignatureIndex();
            }

            /// Fails if the trade has expired.
            if (trade.expiration < block.timestamp) {
                revert Expired();
            }

            /// If a list of allowed addresses is provided with at least 1 address.
            /// Fails if the caller is not in the list of allowed addresses.
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

            /// Recovers the address of the signer of the trade.
            /// Used to verify that the trade values are what the signer has agreed upon.
            address recovered = ECDSA.recover(
                _hashTypedDataV4(
                    keccak256(
                        abi.encode(
                            TRADE_TYPE_HASH,
                            trade.uses,
                            trade.expiration,
                            trade.salt,
                            trade.contractSignatureIndex,
                            trade.signerSignatureIndex,
                            abi.encodePacked(trade.allowed),
                            /// The beneficiary of the sent assets are not hashed.
                            /// This makes it possible to the caller to decide at the time of the trade execution, to define who is going to receive the assets sent by the signer.
                            abi.encodePacked(_hashAssetsWithoutBeneficiary(trade.sent)),
                            abi.encodePacked(_hashAssets(trade.received))
                        )
                    )
                ),
                trade.signature
            );

            /// Fails if the recovered address is different from the signer of the trade.
            if (recovered != trade.signer) {
                revert InvalidSigner();
            }

            /// Increases the amount of times the signature has been used.
            signatureUses[hashedSignature]++;

            /// Transfers the assets from the signer to the caller.
            _transferAssets(trade.sent, trade.signer, _msgSender());

            /// Transfers the assets from the caller to the signer.
            _transferAssets(trade.received, _msgSender(), trade.signer);
        }
    }

    /// @param _assets - The assets to be hashed.
    /// @return hashes - The hashes of the provided assets.
    function _hashAssetsWithoutBeneficiary(Asset[] memory _assets) private pure returns (bytes32[] memory) {
        bytes32[] memory hashes = new bytes32[](_assets.length);

        for (uint256 i = 0; i < hashes.length; i++) {
            Asset memory asset = _assets[i];

            hashes[i] = keccak256(
                abi.encode(
                    ASSET_WO_BENEFICIARY_TYPE_HASH, asset.assetType, asset.contractAddress, asset.value, asset.extra
                )
            );
        }

        return hashes;
    }

    /// @param _assets - The assets to be hashed.
    /// @return hashes - The hashes of the provided assets.
    function _hashAssets(Asset[] memory _assets) private pure returns (bytes32[] memory) {
        bytes32[] memory hashes = new bytes32[](_assets.length);

        for (uint256 i = 0; i < hashes.length; i++) {
            Asset memory asset = _assets[i];

            hashes[i] = keccak256(
                abi.encode(
                    ASSET_TYPE_HASH, asset.assetType, asset.contractAddress, asset.value, asset.extra, asset.beneficiary
                )
            );
        }

        return hashes;
    }

    /// @param _assets - The assets to be transferred.
    /// @param _from - The address of the sender.
    /// @param _to - The address of the receiver.
    function _transferAssets(Asset[] memory _assets, address _from, address _to) private {
        for (uint256 i = 0; i < _assets.length; i++) {
            Asset memory asset = _assets[i];

            if (asset.beneficiary != address(0)) {
                asset.beneficiary = _to;
            }

            _transferAsset(asset, _from);
        }
    }

    /// This function should be overriden to handle the transfer of the provided asset.
    /// @param _asset - The asset to be transferred.
    /// @param _from - The address of the sender.
    function _transferAsset(Asset memory _asset, address _from) internal virtual;
}
