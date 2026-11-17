// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BRLPay} from "../src/BRLPay.sol";
import {MockUSDG} from "../src/MockUSDG.sol";

contract BRLPayTest is Test {
    BRLPay public pay;
    MockUSDG public usdg;

    address public merchant = makeAddr("merchant");
    address public customer = makeAddr("customer");
    address public stranger = makeAddr("stranger");

    // $5.00 USDG (6 decimals) <-> R$ 25,00 (2500 cents) => R$ 5,00 per US$ 1
    uint256 public constant AMOUNT_USDG = 5_000_000;
    uint256 public constant AMOUNT_BRL_CENTS = 2500;

    event InvoiceCreated(
        uint256 indexed id,
        address indexed merchant,
        uint256 amountUSDG,
        uint256 amountBRLCents,
        string description,
        uint256 expiresAt
    );
    event InvoicePaid(
        uint256 indexed id,
        address indexed payer,
        address indexed merchant,
        uint256 amountUSDG,
        uint256 amountBRLCents
    );
    event InvoiceCancelled(uint256 indexed id, address indexed merchant);

    function setUp() public {
        usdg = new MockUSDG();
        pay = new BRLPay(address(usdg));
        usdg.mint(customer, 1_000_000_000); // $1,000 mUSDG for the customer
        usdg.mint(merchant, 0);
    }

    function _createInvoice() internal returns (uint256 id) {
        vm.prank(merchant);
        id = pay.createInvoice(AMOUNT_USDG, AMOUNT_BRL_CENTS, "Cafe + pao de queijo", 1 hours);
    }

    function testCreateInvoice() public {
        vm.expectEmit(true, true, false, true);
        emit InvoiceCreated(1, merchant, AMOUNT_USDG, AMOUNT_BRL_CENTS, "Cafe + pao de queijo", block.timestamp + 1 hours);
        vm.prank(merchant);
        uint256 id = pay.createInvoice(AMOUNT_USDG, AMOUNT_BRL_CENTS, "Cafe + pao de queijo", 1 hours);
        assertEq(id, 1);
        assertEq(pay.invoiceCount(), 1);

        BRLPay.Invoice memory inv = pay.getInvoice(id);
        assertEq(inv.merchant, merchant);
        assertEq(inv.payer, address(0));
        assertEq(inv.amountUSDG, AMOUNT_USDG);
        assertEq(inv.amountBRLCents, AMOUNT_BRL_CENTS);
        assertEq(inv.description, "Cafe + pao de queijo");
        assertEq(inv.createdAt, block.timestamp);
        assertEq(inv.expiresAt, block.timestamp + 1 hours);
        assertEq(inv.paidAt, 0);
        assertEq(uint256(inv.status), uint256(BRLPay.Status.Open));
        assertEq(uint256(pay.statusOf(id)), uint256(BRLPay.Status.Open));
    }

    function testCreateInvoiceRevertsOnZeroAmount() public {
        vm.prank(merchant);
        vm.expectRevert(BRLPay.ZeroAmount.selector);
        pay.createInvoice(0, AMOUNT_BRL_CENTS, "x", 1 hours);

        vm.prank(merchant);
        vm.expectRevert(BRLPay.ZeroAmount.selector);
        pay.createInvoice(AMOUNT_USDG, 0, "x", 1 hours);
    }

    function testCreateInvoiceRevertsOnZeroExpiry() public {
        vm.prank(merchant);
        vm.expectRevert(BRLPay.InvalidExpiry.selector);
        pay.createInvoice(AMOUNT_USDG, AMOUNT_BRL_CENTS, "x", 0);
    }

    function testPayInvoiceSettlesInstantly() public {
        uint256 id = _createInvoice();
        uint256 merchantBefore = usdg.balanceOf(merchant);
        uint256 customerBefore = usdg.balanceOf(customer);

        vm.prank(customer);
        usdg.approve(address(pay), AMOUNT_USDG);

        vm.expectEmit(true, true, true, true);
        emit InvoicePaid(id, customer, merchant, AMOUNT_USDG, AMOUNT_BRL_CENTS);
        vm.prank(customer);
        pay.payInvoice(id);

        assertEq(usdg.balanceOf(merchant), merchantBefore + AMOUNT_USDG);
        assertEq(usdg.balanceOf(customer), customerBefore - AMOUNT_USDG);
        // contract itself never holds funds
        assertEq(usdg.balanceOf(address(pay)), 0);

        BRLPay.Invoice memory inv = pay.getInvoice(id);
        assertEq(inv.payer, customer);
        assertEq(inv.paidAt, block.timestamp);
        assertEq(uint256(inv.status), uint256(BRLPay.Status.Paid));
        assertEq(uint256(pay.statusOf(id)), uint256(BRLPay.Status.Paid));
    }

    function testPayInvoiceTwiceReverts() public {
        uint256 id = _createInvoice();
        vm.prank(customer);
        usdg.approve(address(pay), AMOUNT_USDG * 2);
        vm.prank(customer);
        pay.payInvoice(id);

        vm.prank(customer);
        vm.expectRevert(BRLPay.NotOpen.selector);
        pay.payInvoice(id);
    }

    function testPayExpiredInvoiceReverts() public {
        uint256 id = _createInvoice();
        vm.warp(block.timestamp + 1 hours + 1);
        assertEq(uint256(pay.statusOf(id)), uint256(BRLPay.Status.Expired));

        vm.prank(customer);
        usdg.approve(address(pay), AMOUNT_USDG);
        vm.prank(customer);
        vm.expectRevert(BRLPay.Expired.selector);
        pay.payInvoice(id);
    }

    function testPayOwnInvoiceReverts() public {
        uint256 id = _createInvoice();
        vm.prank(merchant);
        usdg.mint(merchant, AMOUNT_USDG);
        vm.prank(merchant);
        usdg.approve(address(pay), AMOUNT_USDG);
        vm.prank(merchant);
        vm.expectRevert(BRLPay.SelfPayment.selector);
        pay.payInvoice(id);
    }

    function testPayNonexistentReverts() public {
        vm.prank(customer);
        vm.expectRevert(BRLPay.NotFound.selector);
        pay.payInvoice(999);
    }

    function testPayWithoutAllowanceReverts() public {
        uint256 id = _createInvoice();
        vm.prank(customer);
        vm.expectRevert();
        pay.payInvoice(id);
    }

    function testPayWithInsufficientBalanceReverts() public {
        uint256 id = _createInvoice();
        address poor = makeAddr("poor");
        vm.prank(poor);
        usdg.approve(address(pay), AMOUNT_USDG);
        vm.prank(poor);
        vm.expectRevert();
        pay.payInvoice(id);
    }

    function testCancelInvoice() public {
        uint256 id = _createInvoice();
        vm.expectEmit(true, true, false, true);
        emit InvoiceCancelled(id, merchant);
        vm.prank(merchant);
        pay.cancelInvoice(id);
        assertEq(uint256(pay.statusOf(id)), uint256(BRLPay.Status.Cancelled));

        vm.prank(customer);
        usdg.approve(address(pay), AMOUNT_USDG);
        vm.prank(customer);
        vm.expectRevert(BRLPay.NotOpen.selector);
        pay.payInvoice(id);
    }

    function testCancelByNonMerchantReverts() public {
        uint256 id = _createInvoice();
        vm.prank(stranger);
        vm.expectRevert(BRLPay.NotMerchant.selector);
        pay.cancelInvoice(id);
    }

    function testCancelPaidInvoiceReverts() public {
        uint256 id = _createInvoice();
        vm.prank(customer);
        usdg.approve(address(pay), AMOUNT_USDG);
        vm.prank(customer);
        pay.payInvoice(id);

        vm.prank(merchant);
        vm.expectRevert(BRLPay.NotOpen.selector);
        pay.cancelInvoice(id);
    }

    function testBrlPerUsd() public {
        uint256 id = _createInvoice();
        // $5.00 -> R$ 25,00 => R$ 5,0000 per US$ 1 => 50000 scaled by 1e4
        assertEq(pay.brlPerUsd(id), 50_000);
    }

    function testBrlPerUsdOtherRate() public {
        vm.prank(merchant);
        uint256 id = pay.createInvoice(10_000_000, 5_430, "Acaraje", 1 hours);
        // $10.00 -> R$ 54,30 => R$ 5,43 per US$ 1 => 54300
        assertEq(pay.brlPerUsd(id), 54_300);
    }

    function testGetInvoiceNonexistentReverts() public {
        vm.expectRevert(BRLPay.NotFound.selector);
        pay.getInvoice(42);
    }

    function testInvoiceIdsIncrement() public {
        vm.prank(merchant);
        uint256 a = pay.createInvoice(AMOUNT_USDG, AMOUNT_BRL_CENTS, "a", 1 hours);
        vm.prank(merchant);
        uint256 b = pay.createInvoice(AMOUNT_USDG, AMOUNT_BRL_CENTS, "b", 1 hours);
        assertEq(a, 1);
        assertEq(b, 2);
        assertEq(pay.invoiceCount(), 2);
    }

    function testFuzzPayAndCancel(uint256 amountUsdg, uint256 amountBrl) public {
        amountUsdg = bound(amountUsdg, 1, 1_000_000_000);
        amountBrl = bound(amountBrl, 1, 100_000_000);
        vm.prank(merchant);
        uint256 id = pay.createInvoice(amountUsdg, amountBrl, "fuzz", 1 hours);
        vm.prank(customer);
        usdg.approve(address(pay), amountUsdg);
        vm.prank(customer);
        pay.payInvoice(id);
        assertEq(usdg.balanceOf(merchant), amountUsdg);
        assertEq(uint256(pay.statusOf(id)), uint256(BRLPay.Status.Paid));
    }
}
