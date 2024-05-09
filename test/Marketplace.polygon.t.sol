// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {Marketplace} from "../src/Marketplace.sol";
import {ICollection} from "../src/interfaces/ICollection.sol";

contract MarketplaceHarness is Marketplace {
    constructor(address _owner, address _couponManager, string memory _eip712Name, string memory _eip712Version)
        Marketplace(_owner, _couponManager, _eip712Name, _eip712Version)
    {}

    function eip712Name() external view returns (string memory) {
        return _EIP712Name();
    }

    function eip712Version() external view returns (string memory) {
        return _EIP712Version();
    }

    function eip712TradeHash(Trade memory _trade) external view returns (bytes32) {
        return _hashTypedDataV4(_hashTrade(_trade));
    }

    function eip712MetaTransactionHash(MetaTransaction memory _metaTx) external view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    keccak256(bytes("MetaTransaction(uint256 nonce,address from,bytes functionData)")),
                    _metaTx.nonce,
                    _metaTx.from,
                    keccak256(_metaTx.functionData)
                )
            )
        );
    }
}

abstract contract MarketplaceTests is Test {
    VmSafe.Wallet signer;
    address other;
    MarketplaceHarness marketplace;

    function setUp() public virtual {
        uint256 forkId = vm.createFork("https://rpc.decentraland.org/polygon", 56395304); // Apr-29-2024 07:23:50 PM +UTC
        vm.selectFork(forkId);

        signer = vm.createWallet("signer");
        other = 0x79c63172C7B01A8a5B074EF54428a452E0794E7A;
        marketplace = new MarketplaceHarness(0x0E659A116e161d8e502F9036bAbDA51334F2667E, address(0), "Marketplace", "1.0.0");
    }

    function signTrade(Marketplace.Trade memory _trade) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.privateKey, marketplace.eip712TradeHash(_trade));
        return abi.encodePacked(r, s, v);
    }

    function _getBaseTrades() internal view virtual returns (Marketplace.Trade[] memory) {
        Marketplace.Trade[] memory trades = new Marketplace.Trade[](1);
        trades[0].checks.expiration = block.timestamp;
        trades[0].signer = signer.addr;
        return trades;
    }
}

contract UnsupportedAssetTypeTests is MarketplaceTests {
    error UnsupportedAssetType(uint256 _assetType);

    function test_RevertsIfAssetTypeIsInvalid() public {
        uint256 invalidAssetType = 100;

        Marketplace.Trade[] memory trades = _getBaseTrades();
        trades[0].sent = new Marketplace.Asset[](1);
        trades[0].sent[0].assetType = invalidAssetType;
        trades[0].signature = signTrade(trades[0]);

        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(UnsupportedAssetType.selector, invalidAssetType));
        marketplace.accept(trades);
    }
}

contract TransferERC20Tests is MarketplaceTests {
    IERC20 erc20;
    uint256 erc20Sent;
    address erc20OriginalHolder;

    event Transfer(address indexed from, address indexed to, uint256 value);

    error FailedInnerCall();

    function setUp() public override {
        super.setUp();
        erc20 = IERC20(0xA1c57f48F0Deb89f569dFbE6E2B7f46D33606fD4);
        erc20Sent = 1 ether;
        erc20OriginalHolder = 0x673e6B75a58354919FF5db539AA426727B385D17;
    }

    function _getBaseTradesForSent() private view returns (Marketplace.Trade[] memory) {
        Marketplace.Trade[] memory trades = _getBaseTrades();
        trades[0].sent = new Marketplace.Asset[](1);
        trades[0].sent[0].assetType = marketplace.ASSET_TYPE_ERC20();
        trades[0].sent[0].contractAddress = address(erc20);
        trades[0].sent[0].value = erc20Sent;
        trades[0].signature = signTrade(trades[0]);
        return trades;
    }

    function _getBaseTradesForReceived() private view returns (Marketplace.Trade[] memory) {
        Marketplace.Trade[] memory trades = _getBaseTrades();
        trades[0].received = new Marketplace.Asset[](1);
        trades[0].received[0].assetType = marketplace.ASSET_TYPE_ERC20();
        trades[0].received[0].contractAddress = address(erc20);
        trades[0].received[0].value = erc20Sent;
        trades[0].signature = signTrade(trades[0]);
        return trades;
    }

    function test_RevertsIfSignerHasNotApprovedTheMarketplaceToSendERC20() public {
        vm.prank(erc20OriginalHolder);
        erc20.transfer(signer.addr, erc20Sent);

        Marketplace.Trade[] memory trades = _getBaseTradesForSent();

        vm.prank(other);
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        marketplace.accept(trades);
    }

    function test_RevertsIfCallerHasNotApprovedTheMarketplaceToSendERC20() public {
        vm.prank(erc20OriginalHolder);
        erc20.transfer(other, erc20Sent);

        Marketplace.Trade[] memory trades = _getBaseTradesForReceived();

        vm.prank(other);
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        marketplace.accept(trades);
    }

    function test_RevertsIfSignerDoesNotHaveEnoughERC20Balance() public {
        vm.prank(signer.addr);
        erc20.approve(address(marketplace), erc20Sent);

        Marketplace.Trade[] memory trades = _getBaseTradesForSent();

        vm.prank(other);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        marketplace.accept(trades);
    }

    function test_RevertsIfCallerDoesNotHaveEnoughERC20Balance() public {
        vm.prank(other);
        erc20.approve(address(marketplace), erc20Sent);

        Marketplace.Trade[] memory trades = _getBaseTradesForReceived();

        vm.prank(other);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        marketplace.accept(trades);
    }

    function test_TransfersERC20FromSignerToCaller() public {
        vm.prank(signer.addr);
        erc20.approve(address(marketplace), erc20Sent);

        vm.prank(erc20OriginalHolder);
        erc20.transfer(signer.addr, erc20Sent);

        Marketplace.Trade[] memory trades = _getBaseTradesForSent();

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

        Marketplace.Trade[] memory trades = _getBaseTradesForReceived();

        vm.prank(other);
        vm.expectEmit(address(erc20));
        emit Transfer(other, signer.addr, erc20Sent);
        marketplace.accept(trades);

        assertEq(erc20.balanceOf(other), 0);
        assertEq(erc20.balanceOf(signer.addr), erc20Sent);
    }
}

contract TransferERC721Tests is MarketplaceTests {
    IERC721 erc721;
    uint256 erc721TokenId;
    address erc721OriginalHolder;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    function setUp() public override {
        super.setUp();
        erc721 = IERC721(0xDed1e53D7A43aC1844b66c0Ca0F02627EB42e16d);
        erc721TokenId = 1053122916685571866979180276836704323188950954005491112543109775497;
        erc721OriginalHolder = 0xc1325a7Cb84b41626eDCC97f5a124B592976cd5d;
    }

    function _getBaseTradesForSent() private view returns (Marketplace.Trade[] memory) {
        Marketplace.Trade[] memory trades = _getBaseTrades();
        trades[0].sent = new Marketplace.Asset[](1);
        trades[0].sent[0].assetType = marketplace.ASSET_TYPE_ERC721();
        trades[0].sent[0].contractAddress = address(erc721);
        trades[0].sent[0].value = erc721TokenId;
        trades[0].signature = signTrade(trades[0]);
        return trades;
    }

    function _getBaseTradesForReceived() private view returns (Marketplace.Trade[] memory) {
        Marketplace.Trade[] memory trades = _getBaseTrades();
        trades[0].received = new Marketplace.Asset[](1);
        trades[0].received[0].assetType = marketplace.ASSET_TYPE_ERC721();
        trades[0].received[0].contractAddress = address(erc721);
        trades[0].received[0].value = erc721TokenId;
        trades[0].signature = signTrade(trades[0]);
        return trades;
    }

    function test_RevertsIfSignerHasNotApprovedTheMarketplaceToSendERC721() public {
        vm.prank(erc721OriginalHolder);
        erc721.transferFrom(erc721OriginalHolder, signer.addr, erc721TokenId);

        Marketplace.Trade[] memory trades = _getBaseTradesForSent();

        vm.prank(other);
        vm.expectRevert();
        marketplace.accept(trades);
    }

    function test_RevertsIfCallerHasNotApprovedTheMarketplaceToSendERC721() public {
        vm.prank(erc721OriginalHolder);
        erc721.transferFrom(erc721OriginalHolder, other, erc721TokenId);

        Marketplace.Trade[] memory trades = _getBaseTradesForReceived();

        vm.prank(other);
        vm.expectRevert();
        marketplace.accept(trades);
    }

    function test_RevertsIfSignerDoesNotHaveTheERC721Token() public {
        vm.prank(signer.addr);
        erc721.setApprovalForAll(address(marketplace), true);

        Marketplace.Trade[] memory trades = _getBaseTradesForSent();

        vm.prank(other);
        vm.expectRevert();
        marketplace.accept(trades);
    }

    function test_RevertsIfCallerDoesNotHaveTheERC721Token() public {
        vm.prank(other);
        erc721.setApprovalForAll(address(marketplace), true);

        Marketplace.Trade[] memory trades = _getBaseTradesForReceived();

        vm.prank(other);
        vm.expectRevert();
        marketplace.accept(trades);
    }

    function test_TransfersERC721FromSignerToCaller() public {
        vm.prank(signer.addr);
        erc721.setApprovalForAll(address(marketplace), true);

        vm.prank(erc721OriginalHolder);
        erc721.transferFrom(erc721OriginalHolder, signer.addr, erc721TokenId);

        Marketplace.Trade[] memory trades = _getBaseTradesForSent();

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

        Marketplace.Trade[] memory trades = _getBaseTradesForReceived();

        vm.prank(other);
        vm.expectEmit(address(erc721));
        emit Transfer(other, signer.addr, erc721TokenId);
        marketplace.accept(trades);

        assertEq(erc721.ownerOf(erc721TokenId), signer.addr);
    }
}

contract TransferCollectionItemTests is MarketplaceTests {
    ICollection collection;
    uint256 collectionItemId;
    address collectionItemOriginalCreator;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    error NotCreator();

    function setUp() public override {
        super.setUp();
        collection = ICollection(0xDed1e53D7A43aC1844b66c0Ca0F02627EB42e16d);
        collectionItemId = 10;
        collectionItemOriginalCreator = 0x3cf368FaeCdb4a4E542c0efD17850ae133688C2a;
    }

    function _getBaseTradesForSent() private view returns (Marketplace.Trade[] memory) {
        Marketplace.Trade[] memory trades = _getBaseTrades();
        trades[0].sent = new Marketplace.Asset[](1);
        trades[0].sent[0].assetType = marketplace.ASSET_TYPE_ERC721_COLLECTION_ITEM();
        trades[0].sent[0].contractAddress = address(collection);
        trades[0].sent[0].value = collectionItemId;
        trades[0].signature = signTrade(trades[0]);
        return trades;
    }

    function _getBaseTradesForReceived() private view returns (Marketplace.Trade[] memory) {
        Marketplace.Trade[] memory trades = _getBaseTrades();
        trades[0].received = new Marketplace.Asset[](1);
        trades[0].received[0].assetType = marketplace.ASSET_TYPE_ERC721_COLLECTION_ITEM();
        trades[0].received[0].contractAddress = address(collection);
        trades[0].received[0].value = collectionItemId;
        trades[0].signature = signTrade(trades[0]);
        return trades;
    }

    function test_RevertsIfSignerIsNotTheCreator() public {
        Marketplace.Trade[] memory trades = _getBaseTradesForSent();

        vm.prank(other);
        vm.expectRevert(NotCreator.selector);
        marketplace.accept(trades);
    }

    function test_RevertsIfCallerIsNotTheCreator() public {
        Marketplace.Trade[] memory trades = _getBaseTradesForReceived();

        vm.prank(other);
        vm.expectRevert(NotCreator.selector);
        marketplace.accept(trades);
    }

    function test_RevertsIfTheMarketplaceIsNotCollectionMinterOfTheSentAsset() public {
        vm.prank(collectionItemOriginalCreator);
        collection.transferCreatorship(signer.addr);

        Marketplace.Trade[] memory trades = _getBaseTradesForSent();

        vm.prank(other);
        vm.expectRevert("_issueToken: CALLER_CAN_NOT_MINT");
        marketplace.accept(trades);
    }

    function test_RevertsIfTheMarketplaceIsNotCollectionMinterOfTheReceivedAsset() public {
        vm.prank(collectionItemOriginalCreator);
        collection.transferCreatorship(other);

        Marketplace.Trade[] memory trades = _getBaseTradesForReceived();

        vm.prank(other);
        vm.expectRevert("_issueToken: CALLER_CAN_NOT_MINT");
        marketplace.accept(trades);
    }

    function test_MintsAndTranfersTheItemToTheCaller() public {
        vm.prank(collectionItemOriginalCreator);
        collection.transferCreatorship(signer.addr);

        vm.prank(signer.addr);
        address[] memory setMintersMinters = new address[](1);
        setMintersMinters[0] = address(marketplace);
        bool[] memory setMintersValues = new bool[](1);
        setMintersValues[0] = true;
        collection.setMinters(setMintersMinters, setMintersValues);

        Marketplace.Trade[] memory trades = _getBaseTradesForSent();

        vm.prank(other);
        vm.expectEmit(address(collection));
        uint256 expectedTokenId = 1053122916685571866979180276836704323188950954005491112543109775772;
        emit Transfer(address(0), other, expectedTokenId);
        marketplace.accept(trades);

        assertEq(collection.ownerOf(expectedTokenId), other);
    }

    function test_MintsAndTranfersTheItemToTheSigner() public {
        vm.prank(collectionItemOriginalCreator);
        collection.transferCreatorship(other);

        vm.prank(other);
        address[] memory setMintersMinters = new address[](1);
        setMintersMinters[0] = address(marketplace);
        bool[] memory setMintersValues = new bool[](1);
        setMintersValues[0] = true;
        collection.setMinters(setMintersMinters, setMintersValues);

        Marketplace.Trade[] memory trades = _getBaseTradesForReceived();

        vm.prank(other);
        vm.expectEmit(address(collection));
        uint256 expectedTokenId = 1053122916685571866979180276836704323188950954005491112543109775772;
        emit Transfer(address(0), signer.addr, expectedTokenId);
        marketplace.accept(trades);

        assertEq(collection.ownerOf(expectedTokenId), signer.addr);
    }
}

contract ExecuteMetaTransactionTests is MarketplaceTests {
    VmSafe.Wallet metaTxSigner;

    event MetaTransactionExecuted(address indexed _userAddress, address indexed _relayerAddress, bytes _functionData);

    error Expired();
    error MetaTransactionFailedWithoutReason();

    function setUp() public override {
        super.setUp();
        metaTxSigner = vm.createWallet("metaTxSigner");
    }

    function signMetaTx(MarketplaceHarness.MetaTransaction memory _metaTx) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(metaTxSigner.privateKey, marketplace.eip712MetaTransactionHash(_metaTx));

        return abi.encodePacked(r, s, v);
    }

    function test_RevertsIfNonceIsInvalid() public {
        Marketplace.Trade[] memory trades = _getBaseTrades();
        trades[0].signature = signTrade(trades[0]);

        MarketplaceHarness.MetaTransaction memory metaTx;
        metaTx.nonce = 1;
        metaTx.from = metaTxSigner.addr;
        metaTx.functionData = abi.encodeWithSelector(marketplace.accept.selector, trades);

        bytes memory metaTxSignature = signMetaTx(metaTx);

        vm.prank(other);
        vm.expectRevert("NativeMetaTransaction#executeMetaTransaction: SIGNER_AND_SIGNATURE_DO_NOT_MATCH");
        marketplace.executeMetaTransaction(metaTx.from, metaTx.functionData, metaTxSignature);
    }

    function test_RevertsIfFromIsInvalid() public {
        Marketplace.Trade[] memory trades = _getBaseTrades();
        trades[0].signature = signTrade(trades[0]);

        MarketplaceHarness.MetaTransaction memory metaTx;
        metaTx.nonce = 0;
        metaTx.from = other;
        metaTx.functionData = abi.encodeWithSelector(marketplace.accept.selector, trades);

        bytes memory metaTxSignature = signMetaTx(metaTx);

        vm.prank(other);
        vm.expectRevert("NativeMetaTransaction#executeMetaTransaction: SIGNER_AND_SIGNATURE_DO_NOT_MATCH");
        marketplace.executeMetaTransaction(metaTx.from, metaTx.functionData, metaTxSignature);
    }

    function test_EmitMetaTransactionExecutedEvent() public {
        Marketplace.Trade[] memory trades = _getBaseTrades();
        trades[0].signature = signTrade(trades[0]);

        MarketplaceHarness.MetaTransaction memory metaTx;
        metaTx.nonce = 0;
        metaTx.from = metaTxSigner.addr;
        metaTx.functionData = abi.encodeWithSelector(marketplace.accept.selector, trades);

        bytes memory metaTxSignature = signMetaTx(metaTx);

        vm.prank(other);
        vm.expectEmit(address(marketplace));
        emit MetaTransactionExecuted(metaTx.from, other, metaTx.functionData);
        marketplace.executeMetaTransaction(metaTx.from, metaTx.functionData, metaTxSignature);
    }

    function test_RevertsIfTradeIsExpiredWithBubbledUpError() public {
        Marketplace.Trade[] memory trades = _getBaseTrades();
        trades[0].checks.expiration = block.timestamp - 1;
        trades[0].signature = signTrade(trades[0]);

        MarketplaceHarness.MetaTransaction memory metaTx;
        metaTx.nonce = 0;
        metaTx.from = metaTxSigner.addr;
        metaTx.functionData = abi.encodeWithSelector(marketplace.accept.selector, trades);

        bytes memory metaTxSignature = signMetaTx(metaTx);

        vm.prank(other);
        vm.expectRevert(Expired.selector);
        marketplace.executeMetaTransaction(metaTx.from, metaTx.functionData, metaTxSignature);
    }

    function test_RevertsIfERC721AssetHasContractAddressZeroWithWithoutReasonError() public {
        Marketplace.Trade[] memory trades = _getBaseTrades();
        trades[0].sent = new Marketplace.Asset[](1);
        trades[0].sent[0].assetType = marketplace.ASSET_TYPE_ERC721();
        trades[0].sent[0].contractAddress = address(0);
        trades[0].sent[0].value = 1;
        trades[0].signature = signTrade(trades[0]);

        MarketplaceHarness.MetaTransaction memory metaTx;
        metaTx.nonce = 0;
        metaTx.from = metaTxSigner.addr;
        metaTx.functionData = abi.encodeWithSelector(marketplace.accept.selector, trades);

        bytes memory metaTxSignature = signMetaTx(metaTx);

        vm.prank(other);
        vm.expectRevert(MetaTransactionFailedWithoutReason.selector);
        marketplace.executeMetaTransaction(metaTx.from, metaTx.functionData, metaTxSignature);
    }
}
