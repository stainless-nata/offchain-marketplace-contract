// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "lib/forge-std/src/Test.sol";
import {VmSafe} from "lib/forge-std/src/Vm.sol";
import {EthereumMarketplace} from "../src/EthereumMarketplace.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {MessageHashUtils} from "lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";

contract MarketplaceHarness is EthereumMarketplace {
    constructor(address _owner) EthereumMarketplace(_owner) {}

    function getDomainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function hashTrade(Trade memory _trade) external pure returns (bytes32) {
        return _hashTrade(_trade);
    }
}

contract Accept is Test {
    VmSafe.Wallet owner;
    VmSafe.Wallet signer;

    MarketplaceHarness mkt;

    function setUp() public {
        uint256 fork = vm.createFork("https://rpc.decentraland.org/mainnet", 19662099);
        vm.selectFork(fork);

        owner = vm.createWallet("owner");
        signer = vm.createWallet("signer");

        mkt = new MarketplaceHarness(owner.addr);
    }

    function test_SetUpState() public view {
        assertEq(mkt.owner(), owner.addr);
    }

    function test_SendUSDCReceiveMANA() public {
        IERC20 usdt = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        IERC20 mana = IERC20(0x0F5D2fB29fb7d3CFeE444a200298f468908cC942);

        // Address of account that will call the accept function.
        address caller = 0x67c231cF2B0E9518aBa46bDea6b10E0D0C5fEd1B;

        // Preprare tokens.
        {
            // Send USDC to the signer.
            vm.prank(0xD6153F5af5679a75cC85D8974463545181f48772);
            usdt.transfer(signer.addr, 1000000);

            // Approve the market contract to spend the USDC for the signer.
            vm.prank(signer.addr);
            usdt.approve(address(mkt), 1000000);

            // Approve the market contract to spend the USDC for the caller.
            vm.prank(caller);
            mana.approve(address(mkt), 1 ether);
        }

        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        // Prepare trade.
        {
            trades[0].expiration = block.timestamp;

            trades[0].sent = new MarketplaceHarness.Asset[](1);

            trades[0].sent[0].assetType = mkt.ERC20_ID();
            trades[0].sent[0].contractAddress = address(usdt);
            trades[0].sent[0].value = 1000000;

            trades[0].received = new MarketplaceHarness.Asset[](1);

            trades[0].received[0].assetType = mkt.ERC20_ID();
            trades[0].received[0].contractAddress = address(mana);
            trades[0].received[0].value = 1 ether;

            (uint8 v, bytes32 r, bytes32 s) = vm.sign(
                signer.privateKey, MessageHashUtils.toTypedDataHash(mkt.getDomainSeparator(), mkt.hashTrade(trades[0]))
            );

            trades[0].signer = signer.addr;
            trades[0].signature = abi.encodePacked(r, s, v);
        }

        vm.prank(caller);
        mkt.accept(trades);
    }
}
