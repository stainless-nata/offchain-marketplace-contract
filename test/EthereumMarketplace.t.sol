// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {EthereumMarketplace} from "../src/EthereumMarketplace.sol";
import {IComposable} from "../src/interfaces/IComposable.sol";

contract EthereumMarketplaceHarness is EthereumMarketplace {
    constructor(address _owner) EthereumMarketplace(_owner) {}

    function eip712Name() external view returns (string memory) {
        return _EIP712Name();
    }

    function eip712Version() external view returns (string memory) {
        return _EIP712Version();
    }

    function eip712TradeHash(Trade memory _trade) external view returns (bytes32) {
        return _hashTypedDataV4(_hashTrade(_trade));
    }
}

abstract contract EthereumMarketplaceTests is Test {
    VmSafe.Wallet signer;
    address other;
    EthereumMarketplaceHarness marketplace;

    function setUp() public virtual {
        uint256 forkId = vm.createFork("https://rpc.decentraland.org/mainnet", 19755898); // Apr-28-2024 07:27:59 PM +UTC
        vm.selectFork(forkId);

        signer = vm.createWallet("signer");
        other = 0x79c63172C7B01A8a5B074EF54428a452E0794E7A;
        marketplace = new EthereumMarketplaceHarness(0x9A6ebE7E2a7722F8200d0ffB63a1F6406A0d7dce); // DAO Agent;
    }

    function signTrade(EthereumMarketplace.Trade memory _trade) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.privateKey, marketplace.eip712TradeHash(_trade));
        return abi.encodePacked(r, s, v);
    }

    function _getBaseTrades() internal view virtual returns (EthereumMarketplace.Trade[] memory) {
        EthereumMarketplace.Trade[] memory trades = new EthereumMarketplace.Trade[](1);
        trades[0].expiration = block.timestamp;
        trades[0].signer = signer.addr;
        return trades;
    }
}

contract UnsupportedAssetTypeTests is EthereumMarketplaceTests {
    error UnsupportedAssetType(uint256 _assetType);

    function test_RevertsIfAssetTypeIsInvalid() public {
        uint256 invalidAssetType = 100;

        EthereumMarketplace.Trade[] memory trades = _getBaseTrades();
        trades[0].sent = new EthereumMarketplace.Asset[](1);
        trades[0].sent[0].assetType = invalidAssetType;
        trades[0].signature = signTrade(trades[0]);

        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(UnsupportedAssetType.selector, invalidAssetType));
        marketplace.accept(trades);
    }
}

contract TransferERC20Tests is EthereumMarketplaceTests {
    IERC20 erc20;
    uint256 erc20Sent;
    address erc20OriginalHolder;

    event Transfer(address indexed from, address indexed to, uint256 value);

    error FailedInnerCall();

    function setUp() public override {
        super.setUp();
        erc20 = IERC20(0x0F5D2fB29fb7d3CFeE444a200298f468908cC942);
        erc20Sent = 1 ether;
        erc20OriginalHolder = 0x67c231cF2B0E9518aBa46bDea6b10E0D0C5fEd1B;
    }

    function _getBaseTradesForSent() private view returns (EthereumMarketplace.Trade[] memory) {
        EthereumMarketplace.Trade[] memory trades = _getBaseTrades();
        trades[0].sent = new EthereumMarketplace.Asset[](1);
        trades[0].sent[0].assetType = marketplace.ERC20_ID();
        trades[0].sent[0].contractAddress = address(erc20);
        trades[0].sent[0].value = erc20Sent;
        trades[0].signature = signTrade(trades[0]);
        return trades;
    }

    function _getBaseTradesForReceived() private view returns (EthereumMarketplace.Trade[] memory) {
        EthereumMarketplace.Trade[] memory trades = _getBaseTrades();
        trades[0].received = new EthereumMarketplace.Asset[](1);
        trades[0].received[0].assetType = marketplace.ERC20_ID();
        trades[0].received[0].contractAddress = address(erc20);
        trades[0].received[0].value = erc20Sent;
        trades[0].signature = signTrade(trades[0]);
        return trades;
    }

    function test_RevertsIfSignerHasNotApprovedTheMarketplaceToSendERC20() public {
        vm.prank(erc20OriginalHolder);
        erc20.transfer(signer.addr, erc20Sent);

        EthereumMarketplace.Trade[] memory trades = _getBaseTradesForSent();

        vm.prank(other);
        vm.expectRevert(FailedInnerCall.selector);
        marketplace.accept(trades);
    }

    function test_RevertsIfCallerHasNotApprovedTheMarketplaceToSendERC20() public {
        vm.prank(erc20OriginalHolder);
        erc20.transfer(other, erc20Sent);

        EthereumMarketplace.Trade[] memory trades = _getBaseTradesForReceived();

        vm.prank(other);
        vm.expectRevert(FailedInnerCall.selector);
        marketplace.accept(trades);
    }

    function test_RevertsIfSignerDoesNotHaveEnoughERC20Balance() public {
        vm.prank(signer.addr);
        erc20.approve(address(marketplace), erc20Sent);

        EthereumMarketplace.Trade[] memory trades = _getBaseTradesForSent();

        vm.prank(other);
        vm.expectRevert(FailedInnerCall.selector);
        marketplace.accept(trades);
    }

    function test_RevertsIfCallerDoesNotHaveEnoughERC20Balance() public {
        vm.prank(other);
        erc20.approve(address(marketplace), erc20Sent);

        EthereumMarketplace.Trade[] memory trades = _getBaseTradesForReceived();

        vm.prank(other);
        vm.expectRevert(FailedInnerCall.selector);
        marketplace.accept(trades);
    }

    function test_TransfersERC20FromSignerToCaller() public {
        vm.prank(signer.addr);
        erc20.approve(address(marketplace), erc20Sent);

        vm.prank(erc20OriginalHolder);
        erc20.transfer(signer.addr, erc20Sent);

        EthereumMarketplace.Trade[] memory trades = _getBaseTradesForSent();

        vm.prank(other);
        vm.expectEmit(address(erc20));
        emit Transfer(signer.addr, other, erc20Sent);
        marketplace.accept(trades);

        assertEq(erc20.balanceOf(signer.addr), 0);
        assertEq(erc20.balanceOf(other), erc20Sent);
    }

    function test_TransfersERC20FromCallerToSigner() public {
        vm.prank(other);
        erc20.approve(address(marketplace), erc20Sent);

        vm.prank(erc20OriginalHolder);
        erc20.transfer(other, erc20Sent);

        EthereumMarketplace.Trade[] memory trades = _getBaseTradesForReceived();

        vm.prank(other);
        vm.expectEmit(address(erc20));
        emit Transfer(other, signer.addr, erc20Sent);
        marketplace.accept(trades);

        assertEq(erc20.balanceOf(other), 0);
        assertEq(erc20.balanceOf(signer.addr), erc20Sent);
    }
}

contract TransferERC721Tests is EthereumMarketplaceTests {
    IERC721 erc721;
    uint256 erc721TokenId;
    address erc721OriginalHolder;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    function setUp() public override {
        super.setUp();
        erc721 = IERC721(0xF87E31492Faf9A91B02Ee0dEAAd50d51d56D5d4d);
        erc721TokenId = 1;
        erc721OriginalHolder = 0x959e104E1a4dB6317fA58F8295F586e1A978c297;
    }

    function _getBaseTradesForSent() private view returns (EthereumMarketplace.Trade[] memory) {
        EthereumMarketplace.Trade[] memory trades = _getBaseTrades();
        trades[0].sent = new EthereumMarketplace.Asset[](1);
        trades[0].sent[0].assetType = marketplace.ERC721_ID();
        trades[0].sent[0].contractAddress = address(erc721);
        trades[0].sent[0].value = erc721TokenId;
        trades[0].signature = signTrade(trades[0]);
        return trades;
    }

    function _getBaseTradesForReceived() private view returns (EthereumMarketplace.Trade[] memory) {
        EthereumMarketplace.Trade[] memory trades = _getBaseTrades();
        trades[0].received = new EthereumMarketplace.Asset[](1);
        trades[0].received[0].assetType = marketplace.ERC721_ID();
        trades[0].received[0].contractAddress = address(erc721);
        trades[0].received[0].value = erc721TokenId;
        trades[0].signature = signTrade(trades[0]);
        return trades;
    }

    function test_RevertsIfSignerHasNotApprovedTheMarketplaceToSendERC721() public {
        vm.prank(erc721OriginalHolder);
        erc721.transferFrom(erc721OriginalHolder, signer.addr, erc721TokenId);

        EthereumMarketplace.Trade[] memory trades = _getBaseTradesForSent();

        vm.prank(other);
        vm.expectRevert();
        marketplace.accept(trades);
    }

    function test_RevertsIfCallerHasNotApprovedTheMarketplaceToSendERC721() public {
        vm.prank(erc721OriginalHolder);
        erc721.transferFrom(erc721OriginalHolder, other, erc721TokenId);

        EthereumMarketplace.Trade[] memory trades = _getBaseTradesForReceived();

        vm.prank(other);
        vm.expectRevert();
        marketplace.accept(trades);
    }

    function test_RevertsIfSignerDoesNotHaveTheERC721Token() public {
        vm.prank(signer.addr);
        erc721.setApprovalForAll(address(marketplace), true);

        EthereumMarketplace.Trade[] memory trades = _getBaseTradesForSent();

        vm.prank(other);
        vm.expectRevert();
        marketplace.accept(trades);
    }

    function test_RevertsIfCallerDoesNotHaveTheERC721Token() public {
        vm.prank(other);
        erc721.setApprovalForAll(address(marketplace), true);

        EthereumMarketplace.Trade[] memory trades = _getBaseTradesForReceived();

        vm.prank(other);
        vm.expectRevert();
        marketplace.accept(trades);
    }

    function test_TransfersERC721FromSignerToCaller() public {
        vm.prank(signer.addr);
        erc721.setApprovalForAll(address(marketplace), true);

        vm.prank(erc721OriginalHolder);
        erc721.transferFrom(erc721OriginalHolder, signer.addr, erc721TokenId);

        EthereumMarketplace.Trade[] memory trades = _getBaseTradesForSent();

        vm.prank(other);
        vm.expectEmit(address(erc721));
        emit Transfer(signer.addr, other, erc721TokenId);
        marketplace.accept(trades);

        assertEq(erc721.ownerOf(erc721TokenId), other);
    }

    function test_TransfersERC721FromCallerToSigner() public {
        vm.prank(other);
        erc721.setApprovalForAll(address(marketplace), true);

        vm.prank(erc721OriginalHolder);
        erc721.transferFrom(erc721OriginalHolder, other, erc721TokenId);

        EthereumMarketplace.Trade[] memory trades = _getBaseTradesForReceived();

        vm.prank(other);
        vm.expectEmit(address(erc721));
        emit Transfer(other, signer.addr, erc721TokenId);
        marketplace.accept(trades);

        assertEq(erc721.ownerOf(erc721TokenId), signer.addr);
    }
}

contract TransferComposableTokenTests is EthereumMarketplaceTests {
    IComposable composable;
    uint256 composableTokenId;
    address composableOriginalHolder;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    error InvalidFingerprint();

    function setUp() public override {
        super.setUp();
        composable = IComposable(0x959e104E1a4dB6317fA58F8295F586e1A978c297);
        composableTokenId = 1;
        composableOriginalHolder = 0x9aBdCb8825696CC2Ef3A0a955f99850418847F5D;
    }

    function _getBaseTradesForSent() private view returns (EthereumMarketplace.Trade[] memory) {
        EthereumMarketplace.Trade[] memory trades = _getBaseTrades();
        trades[0].sent = new EthereumMarketplace.Asset[](1);
        trades[0].sent[0].assetType = marketplace.COMPOSABLE_ERC721_ID();
        trades[0].sent[0].contractAddress = address(composable);
        trades[0].sent[0].value = composableTokenId;
        trades[0].sent[0].extra = abi.encode(composable.getFingerprint(composableTokenId));
        trades[0].signature = signTrade(trades[0]);
        return trades;
    }

    function _getBaseTradesForReceived() private view returns (EthereumMarketplace.Trade[] memory) {
        EthereumMarketplace.Trade[] memory trades = _getBaseTrades();
        trades[0].received = new EthereumMarketplace.Asset[](1);
        trades[0].received[0].assetType = marketplace.COMPOSABLE_ERC721_ID();
        trades[0].received[0].contractAddress = address(composable);
        trades[0].received[0].value = composableTokenId;
        trades[0].received[0].extra = abi.encode(composable.getFingerprint(composableTokenId));
        trades[0].signature = signTrade(trades[0]);
        return trades;
    }

    function test_RevertsIfSentAssetFingerprintIsInvalid() public {
        EthereumMarketplace.Trade[] memory trades = _getBaseTradesForSent();
        trades[0].sent[0].extra = abi.encode(uint256(123));
        trades[0].signature = signTrade(trades[0]);

        vm.prank(other);
        vm.expectRevert(InvalidFingerprint.selector);
        marketplace.accept(trades);
    }

    function test_RevertsIfReceivedAssetFingerprintIsInvalid() public {
        EthereumMarketplace.Trade[] memory trades = _getBaseTradesForReceived();
        trades[0].received[0].extra = abi.encode(uint256(123));
        trades[0].signature = signTrade(trades[0]);

        vm.prank(other);
        vm.expectRevert(InvalidFingerprint.selector);
        marketplace.accept(trades);
    }

    function test_RevertsIfSignerIsNotTheOwnerOfTheComposableToken() public {
        vm.prank(signer.addr);
        composable.setApprovalForAll(address(marketplace), true);

        EthereumMarketplace.Trade[] memory trades = _getBaseTradesForSent();

        vm.prank(other);
        vm.expectRevert("Only owner or operator can transfer");
        marketplace.accept(trades);
    }

    function test_RevertsIfCallerIsNotTheOwnerOfTheComposableToken() public {
        vm.prank(other);
        composable.setApprovalForAll(address(marketplace), true);

        EthereumMarketplace.Trade[] memory trades = _getBaseTradesForReceived();

        vm.prank(other);
        vm.expectRevert("Only owner or operator can transfer");
        marketplace.accept(trades);
    }

    function test_RevertsIfSignerHasNotApprovedTheMarketplaceContractToTransferTheComposableToken() public {
        vm.prank(composableOriginalHolder);
        composable.transferFrom(composableOriginalHolder, signer.addr, composableTokenId);

        EthereumMarketplace.Trade[] memory trades = _getBaseTradesForSent();

        vm.prank(other);
        vm.expectRevert("Only owner or operator can transfer");
        marketplace.accept(trades);
    }

    function test_RevertsIfCallerHasNotApprovedTheMarketplaceContractToTransferTheComposableToken() public {
        vm.prank(composableOriginalHolder);
        composable.transferFrom(composableOriginalHolder, other, composableTokenId);

        EthereumMarketplace.Trade[] memory trades = _getBaseTradesForReceived();

        vm.prank(other);
        vm.expectRevert("Only owner or operator can transfer");
        marketplace.accept(trades);
    }

    function test_TransfersComposableTokenFromSignerToCaller() public {
        vm.prank(composableOriginalHolder);
        composable.transferFrom(composableOriginalHolder, signer.addr, composableTokenId);

        vm.prank(signer.addr);
        composable.setApprovalForAll(address(marketplace), true);

        EthereumMarketplace.Trade[] memory trades = _getBaseTradesForSent();

        vm.prank(other);
        vm.expectEmit(address(composable));
        emit Transfer(signer.addr, other, composableTokenId);
        marketplace.accept(trades);

        assertEq(composable.ownerOf(composableTokenId), other);
    }

    function test_TransfersComposableTokenFromCallerToSigner() public {
        vm.prank(composableOriginalHolder);
        composable.transferFrom(composableOriginalHolder, other, composableTokenId);

        vm.prank(other);
        composable.setApprovalForAll(address(marketplace), true);

        EthereumMarketplace.Trade[] memory trades = _getBaseTradesForReceived();

        vm.prank(other);
        vm.expectEmit(address(composable));
        emit Transfer(other, signer.addr, composableTokenId);
        marketplace.accept(trades);

        assertEq(composable.ownerOf(composableTokenId), signer.addr);
    }
}
