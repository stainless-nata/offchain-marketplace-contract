// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {ECDSA} from "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "./EIP712.sol";

/// @dev This is a similar contract ti the one found at https://github.com/decentraland/common-contracts/blob/1c85438e913fe5affbef8e480c467585738e694a/contracts/meta-transactions/NativeMetaTransaction.sol.
/// The differences being this this contract uses solidity 0.8.20 and does not use upgradeable OZ contracts.
abstract contract NativeMetaTransaction is EIP712 {
    /// @dev EIP712 type hash for recovering the signer from the signature.
    bytes32 private constant META_TRANSACTION_TYPEHASH = keccak256(bytes("MetaTransaction(uint256 nonce,address from,bytes functionData)"));

    /// @notice Track signer nonces so the same signature cannot be used more than once.
    mapping(address => uint256) private nonces;

    /// @notice Struct with the data required to verify that the signature signer is the same as `from`.
    struct MetaTransaction {
        uint256 nonce;
        address from;
        bytes functionData;
    }

    event MetaTransactionExecuted(address indexed _userAddress, address indexed _relayerAddress, bytes _functionData);

    /// @notice Get the current nonce of a given signer.
    /// @param _signer The address of the signer.
    /// @return The current nonce of the signer.
    function getNonce(address _signer) external view returns (uint256) {
        return nonces[_signer];
    }

    /// @notice Execute a transaction from the contract appending _userAddress to the call data.
    /// @dev The appended address can then be extracted from the called context with _getMsgSender instead of using msg.sender.
    /// The caller of `executeMetaTransaction` will pay for gas fees so _userAddress can experience "gasless" transactions.
    /// @param _userAddress The address appended to the call data.
    /// @param _functionData Data containing information about the contract function to be called.
    /// @param _signature Signature created by _userAddress to validate that they wanted
    /// @return The data as bytes of what the relayed function would have returned.
    function executeMetaTransaction(
        address _userAddress,
        bytes calldata _functionData,
        bytes calldata _signature
    ) external payable returns (bytes memory) {
        MetaTransaction memory metaTx = MetaTransaction({nonce: nonces[_userAddress], from: _userAddress, functionData: _functionData});

        require(_verify(_userAddress, metaTx, _signature), "NativeMetaTransaction#executeMetaTransaction: SIGNER_AND_SIGNATURE_DO_NOT_MATCH");

        nonces[_userAddress]++;

        emit MetaTransactionExecuted(_userAddress, msg.sender, _functionData);

        (bool success, bytes memory returnData) = address(this).call{value: msg.value}(abi.encodePacked(_functionData, _userAddress));

        // Bubble up error based on https://ethereum.stackexchange.com/a/83577
        if (!success) {
            assembly {
                // Slice the sighash.
                returnData := add(returnData, 0x04)
            }

            revert(abi.decode(returnData, (string)));
        }

        return returnData;
    }

    function _verify(
        address _signer,
        MetaTransaction memory _metaTx,
        bytes calldata _signature
    ) private view returns (bool) {
        bytes32 structHash = keccak256(abi.encode(META_TRANSACTION_TYPEHASH, _metaTx.nonce, _metaTx.from, keccak256(_metaTx.functionData)));
        bytes32 typedDataHash = _hashTypedDataV4(structHash);

        return _signer == ECDSA.recover(typedDataHash, _signature);
    }

    /// @dev Extract the address of the sender from the msg.data if available. If not, fallback to returning the msg.sender.
    /// @dev It is vital that the implementor uses this function for meta transaction support.
    function _getMsgSender() internal view returns (address sender) {
        if (msg.sender == address(this)) {
            assembly {
                sender := shr(96, calldataload(sub(calldatasize(), 20)))
            }
        } else {
            sender = msg.sender;
        }

        return sender;
    }
}