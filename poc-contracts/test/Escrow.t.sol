// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/BullEscrow.sol";
import "../src/Mocks.sol";

// Escrow behaviour tests on the VERIFIED BullEscrow source (bytecode-matched
// to mainnet 0xd685d39E7a3deF19E52B9AB09679b7452C23e20b, see report).
// Deployed here with feeSigner = vm.addr(1) so quotes can be signed locally.
contract RejectEthBuyer {
    BullEscrow public esc;
    constructor(BullEscrow _esc) { esc = _esc; }
    function createDeal(BullEscrow.DealParams calldata p, BullEscrow.Quote calldata q) external returns (uint256) {
        return esc.createDeal(p, q);
    }
    function fundPayment(uint256 id) external payable { esc.fundPayment{value: msg.value}(id); }
    function cancel(uint256 id) external { esc.cancel(id); }
    // NOTE: no receive()/fallback -> this contract cannot receive ETH.
}

contract EscrowTest is Test {
    BullEscrow esc;
    MockERC20 sellToken;
    MockERC20 payToken;
    address treasury = address(0x9999);
    address buyer = address(0x1111);
    address seller = address(0x2222);

    function setUp() public {
        esc = new BullEscrow(treasury, vm.addr(1));
        sellToken = new MockERC20();
        payToken = new MockERC20();
        sellToken.mint(seller, 1000 ether);
        payToken.mint(buyer, 1000 ether);
        vm.deal(buyer, 100 ether);
        vm.deal(seller, 100 ether);
    }

    function _quote(BullEscrow.DealParams memory p, uint16 feeBps, uint64 expiry, address _buyer) internal view returns (BullEscrow.Quote memory) {
        bytes32 ph = keccak256(abi.encode(p));
        bytes32 h = keccak256(abi.encode(block.chainid, address(esc), _buyer, ph, feeBps, expiry));
        bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", h));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, ethHash);
        return BullEscrow.Quote({feeBps: feeBps, expiry: expiry, sig: abi.encodePacked(r, s, v)});
    }

    function _params(address _seller, address _sellToken, uint256 _sellAmount, address _payToken, uint256 _payAmount) internal view returns (BullEscrow.DealParams memory) {
        return BullEscrow.DealParams({
            seller: _seller, sellerPayout: address(0), buyerReceive: address(0),
            sellToken: _sellToken, sellAmount: _sellAmount, payToken: _payToken,
            payAmount: _payAmount, deadline: uint64(block.timestamp + 1 days)
        });
    }

    // Happy path: ETH payment, 250 bps fee, exact settlement amounts.
    function test_settle_eth() public {
        BullEscrow.DealParams memory p = _params(seller, address(sellToken), 100 ether, address(0), 1 ether);
        vm.prank(buyer);
        uint256 id = esc.createDeal(p, _quote(p, 250, uint64(block.timestamp + 3600), buyer));
        vm.prank(seller);
        sellToken.approve(address(esc), 100 ether);
        vm.prank(seller);
        esc.fundTokens(id);
        vm.prank(buyer);
        esc.fundPayment{value: 1 ether}(id);
        assertEq(sellToken.balanceOf(buyer), 100 ether, "buyer gets sell tokens");
        assertEq(buyer.balance, 100 ether - 1 ether, "buyer paid 1 ETH");
        assertEq(seller.balance, 100 ether + 0.975 ether, "seller gets pay-fee");
        assertEq(treasury.balance, 0.025 ether, "treasury gets 250bps fee");
        assertEq(uint8(esc.deals(id).status), 2, "Settled");
    }

    // Fee rounds DOWN (favours the seller); 1 wei payment -> fee 0.
    function test_fee_rounds_down() public {
        BullEscrow.DealParams memory p = _params(seller, address(sellToken), 1 ether, address(0), 1 wei);
        vm.prank(buyer);
        uint256 id = esc.createDeal(p, _quote(p, 250, uint64(block.timestamp + 3600), buyer));
        vm.prank(seller);
        sellToken.approve(address(esc), 1 ether);
        vm.prank(seller);
        esc.fundTokens(id);
        vm.prank(buyer);
        esc.fundPayment{value: 1 wei}(id);
        assertEq(treasury.balance, 0, "fee 0 on 1 wei");
        assertEq(seller.balance, 100 ether + 1 wei, "seller gets full wei");
    }

    // Cancel-brick self-grief: a buyer that cannot receive ETH cannot cancel
    // (refund reverts), but settlement still rescues the funds when the seller funds.
    function test_cancel_brick_self_grief_recoverable_via_settle() public {
        RejectEthBuyer rb = new RejectEthBuyer(esc);
        vm.deal(address(rb), 10 ether);
        BullEscrow.DealParams memory p = _params(seller, address(sellToken), 10 ether, address(0), 1 ether);
        uint256 id = rb.createDeal(p, _quote(p, 100, uint64(block.timestamp + 3600), address(rb)));
        rb.fundPayment{value: 1 ether}(id);
        // cancel reverts: ETH refund to rb fails (no receive())
        vm.expectRevert(BullEscrow.TransferFailed.selector);
        rb.cancel(id);
        // but settlement rescues it: seller funds, buyer receives ERC20 (no ETH involved)
        vm.prank(seller);
        sellToken.approve(address(esc), 10 ether);
        vm.prank(seller);
        esc.fundTokens(id);
        assertEq(sellToken.balanceOf(address(rb)), 10 ether, "buyer got tokens via settle");
        assertEq(uint8(esc.deals(id).status), 2, "Settled");
    }

    // Reverting sellerPayout bricks settlement, but cancel refunds both sides.
    function test_reverting_seller_payout_recoverable_via_cancel() public {
        RejectEthBuyer sp = new RejectEthBuyer(esc); // stands in for a sellerPayout that rejects ETH
        BullEscrow.DealParams memory p = _params(seller, address(sellToken), 10 ether, address(0), 1 ether);
        p.sellerPayout = address(sp);
        vm.prank(buyer);
        uint256 id = esc.createDeal(p, _quote(p, 100, uint64(block.timestamp + 3600), buyer));
        vm.prank(seller);
        sellToken.approve(address(esc), 10 ether);
        vm.prank(seller);
        esc.fundTokens(id);
        // buyer funds -> _maybeSettle tries to pay sellerPayout (rejects ETH) -> reverts
        vm.prank(buyer);
        vm.expectRevert(BullEscrow.TransferFailed.selector);
        esc.fundPayment{value: 1 ether}(id);
        // cancel refunds both sides (buyer EOA receives ETH, seller receives tokens)
        vm.prank(buyer);
        esc.cancel(id);
        assertEq(buyer.balance, 100 ether, "buyer refunded");
        assertEq(sellToken.balanceOf(seller), 1000 ether, "seller refunded");
        assertEq(uint8(esc.deals(id).status), 3, "Cancelled");
    }
}
