// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title BRLPay — stablecoin payment requests with a Pix-style UX for Brazil
/// @notice A merchant creates an invoice denominated in BRL (cents) with its
/// USDG amount. Anyone can pay it in USDG; funds settle instantly to the
/// merchant and a receipt event is emitted. No admin, no custody: the
/// contract never holds funds — payment goes straight from payer to
/// merchant. Invoices expire; expired invoices cannot be paid.
/// @dev Built for the Arbitrum Open House São Paulo 2027 buildathon.
/// Deployed on Arbitrum Sepolia (chain 421614). USDG here is MockUSDG, a
/// testnet stand-in for Paxos USDG; swapping in the real USDG address is a
/// one-line change at deploy time.
contract BRLPay is ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum Status {
        Open,
        Paid,
        Cancelled,
        Expired // only ever returned by statusOf(), never stored
    }

    struct Invoice {
        address merchant;
        address payer;
        uint256 amountUSDG; // 6 decimals (USDG), e.g. 25_000_000 = $25.00
        uint256 amountBRLCents; // BRL cents, e.g. 12500 = R$ 125,00
        string description;
        uint256 createdAt;
        uint256 expiresAt;
        uint256 paidAt;
        Status status;
    }

    IERC20 public immutable usdg;
    uint256 public invoiceCount;
    mapping(uint256 => Invoice) public invoices;

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

    error ZeroAmount();
    error InvalidExpiry();
    error NotFound();
    error NotMerchant();
    error NotOpen();
    error Expired();
    error SelfPayment();

    constructor(address _usdg) {
        usdg = IERC20(_usdg);
    }

    /// @notice Create a payment request. The caller is the merchant.
    /// @param amountUSDG Amount to receive, in USDG smallest units (6 decimals).
    /// @param amountBRLCents Amount shown to the payer, in BRL cents.
    /// @param description What the payment is for (e.g. "Café + pão de queijo").
    /// @param validForSeconds How long the invoice stays payable.
    /// @return id The new invoice id.
    function createInvoice(
        uint256 amountUSDG,
        uint256 amountBRLCents,
        string calldata description,
        uint256 validForSeconds
    ) external returns (uint256 id) {
        if (amountUSDG == 0 || amountBRLCents == 0) revert ZeroAmount();
        if (validForSeconds == 0) revert InvalidExpiry();
        id = ++invoiceCount;
        uint256 expiresAt = block.timestamp + validForSeconds;
        invoices[id] = Invoice({
            merchant: msg.sender,
            payer: address(0),
            amountUSDG: amountUSDG,
            amountBRLCents: amountBRLCents,
            description: description,
            createdAt: block.timestamp,
            expiresAt: expiresAt,
            paidAt: 0,
            status: Status.Open
        });
        emit InvoiceCreated(id, msg.sender, amountUSDG, amountBRLCents, description, expiresAt);
    }

    /// @notice Pay an open, unexpired invoice. USDG moves payer -> merchant.
    /// The payer must have approved this contract for at least amountUSDG.
    function payInvoice(uint256 id) external nonReentrant {
        Invoice storage inv = invoices[id];
        if (inv.merchant == address(0)) revert NotFound();
        if (inv.status != Status.Open) revert NotOpen();
        if (block.timestamp > inv.expiresAt) revert Expired();
        if (msg.sender == inv.merchant) revert SelfPayment();
        inv.status = Status.Paid;
        inv.payer = msg.sender;
        inv.paidAt = block.timestamp;
        usdg.safeTransferFrom(msg.sender, inv.merchant, inv.amountUSDG);
        emit InvoicePaid(id, msg.sender, inv.merchant, inv.amountUSDG, inv.amountBRLCents);
    }

    /// @notice Cancel an open invoice. Only the merchant, only before payment.
    function cancelInvoice(uint256 id) external {
        Invoice storage inv = invoices[id];
        if (inv.merchant == address(0)) revert NotFound();
        if (msg.sender != inv.merchant) revert NotMerchant();
        if (inv.status != Status.Open) revert NotOpen();
        inv.status = Status.Cancelled;
        emit InvoiceCancelled(id, msg.sender);
    }

    function getInvoice(uint256 id) external view returns (Invoice memory) {
        if (invoices[id].merchant == address(0)) revert NotFound();
        return invoices[id];
    }

    /// @notice Effective status: an open invoice past its expiry reads Expired.
    function statusOf(uint256 id) external view returns (Status) {
        Invoice storage inv = invoices[id];
        if (inv.merchant == address(0)) revert NotFound();
        if (inv.status == Status.Open && block.timestamp > inv.expiresAt) {
            return Status.Expired;
        }
        return inv.status;
    }

    /// @notice Implied BRL per USD, scaled by 1e4 (50000 = R$ 5,0000 per US$ 1).
    function brlPerUsd(uint256 id) external view returns (uint256) {
        Invoice storage inv = invoices[id];
        if (inv.merchant == address(0)) revert NotFound();
        return (inv.amountBRLCents * 1e4 * 1e6) / (inv.amountUSDG * 100);
    }
}
