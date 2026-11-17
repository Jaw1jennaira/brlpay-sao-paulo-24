// BRLPay demo frontend — Arbitrum Sepolia (chain 421614).
// Static page, no build step. Serve the repo root (or frontend/) with any
// static server, e.g. `python3 -m http.server`, and open index.html.
const CHAIN_ID = 421614;
const BRLPAY = "0xd3a930C160A52BE6B6eC9a77568E87428d2Be24c";
const USDG = "0x2eF0A9708182eB988f20C0C278224908e0Bc2FA9";
const EXPLORER = "https://sepolia.arbiscan.io";

const USDG_ABI = [
  "function approve(address spender, uint256 amount) returns (bool)",
  "function balanceOf(address a) view returns (uint256)",
  "function mint(address to, uint256 amount)",
  "function decimals() view returns (uint8)",
];
const BRLPAY_ABI = [
  "function createInvoice(uint256 amountUSDG, uint256 amountBRLCents, string description, uint256 validForSeconds) returns (uint256)",
  "function payInvoice(uint256 id)",
  "function getInvoice(uint256 id) view returns (tuple(address merchant, address payer, uint256 amountUSDG, uint256 amountBRLCents, string description, uint256 createdAt, uint256 expiresAt, uint256 paidAt, uint8 status))",
  "function invoiceCount() view returns (uint256)",
  "function statusOf(uint256 id) view returns (uint8)",
  "event InvoiceCreated(uint256 indexed id, address indexed merchant, uint256 amountUSDG, uint256 amountBRLCents, string description, uint256 expiresAt)",
];

const STATUS = ["Open", "Paid", "Cancelled", "Expired"];
let provider, signer, usdg, brlpay, account;

document.getElementById("brlpayAddr").textContent = BRLPAY;
document.getElementById("usdgAddr").textContent = USDG;

const $ = (id) => document.getElementById(id);

async function connect() {
  if (!window.ethereum) { $("walletInfo").textContent = "MetaMask not found."; return; }
  provider = new ethers.BrowserProvider(window.ethereum);
  await provider.send("eth_requestAccounts", []);
  const net = await provider.getNetwork();
  if (Number(net.chainId) !== CHAIN_ID) {
    try {
      await window.ethereum.request({ method: "wallet_switchEthereumChain", params: [{ chainId: "0x66eee" }] });
    } catch (e) {
      $("walletInfo").textContent = "Please switch MetaMask to Arbitrum Sepolia (chain 421614).";
      return;
    }
  }
  signer = await provider.getSigner();
  account = await signer.getAddress();
  usdg = new ethers.Contract(USDG, USDG_ABI, signer);
  brlpay = new ethers.Contract(BRLPAY, BRLPAY_ABI, signer);
  const bal = await usdg.balanceOf(account);
  const eth = await provider.getBalance(account);
  $("walletInfo").innerHTML = `Connected: <code>${account}</code><br>mUSDG: $${(Number(bal) / 1e6).toFixed(2)} · ETH: ${ethers.formatEther(eth)}`;
  $("mintBtn").disabled = false;
  $("createBtn").disabled = false;
  $("payBtn").disabled = false;
  refreshList();
}

async function mint() {
  $("mintBtn").disabled = true;
  try {
    const tx = await usdg.mint(account, 100_000_000); // $100 mUSDG
    await tx.wait();
    $("walletInfo").textContent += " · minted $100 mUSDG ✓";
  } catch (e) { alert("Mint failed: " + (e.reason || e.message)); }
  $("mintBtn").disabled = false;
}

async function createInvoice() {
  const usd = Math.round(parseFloat($("invUsd").value) * 1e6);
  const brl = Math.round(parseFloat($("invBrl").value) * 100);
  const desc = $("invDesc").value.trim() || "Payment";
  const valid = parseInt($("invValid").value, 10) * 60;
  $("createMsg").textContent = "Sending…";
  try {
    const tx = await brlpay.createInvoice(usd, brl, desc, valid);
    const r = await tx.wait();
    const id = await brlpay.invoiceCount();
    $("createMsg").innerHTML = `Invoice #${id} created ✓ <a href="${EXPLORER}/tx/${r.hash}" target="_blank">tx</a>`;
    $("payId").value = id;
    refreshList();
  } catch (e) { $("createMsg").textContent = "Failed: " + (e.reason || e.message); }
}

async function payInvoice() {
  const id = parseInt($("payId").value, 10);
  $("payMsg").textContent = "Approving + paying…";
  try {
    const inv = await brlpay.getInvoice(id);
    const approveTx = await usdg.approve(BRLPAY, inv.amountUSDG);
    await approveTx.wait();
    const tx = await brlpay.payInvoice(id);
    const r = await tx.wait();
    $("payMsg").innerHTML = `Invoice #${id} paid ✓ <a href="${EXPLORER}/tx/${r.hash}" target="_blank">tx</a>`;
    refreshList();
  } catch (e) { $("payMsg").textContent = "Failed: " + (e.reason || e.message); }
}

async function refreshList() {
  if (!brlpay) return;
  const count = Number(await brlpay.invoiceCount());
  const rows = [];
  for (let id = Math.max(1, count - 9); id <= count; id++) {
    const inv = await brlpay.getInvoice(id);
    const st = Number(await brlpay.statusOf(id));
    rows.push(`<tr><td>${id}</td><td>${inv.description}</td><td>R$ ${(Number(inv.amountBRLCents) / 100).toFixed(2)}</td><td>$${(Number(inv.amountUSDG) / 1e6).toFixed(2)}</td><td>${STATUS[st]}</td></tr>`);
  }
  $("invTable").innerHTML = rows.reverse().join("") || `<tr><td colspan="5" class="muted">No invoices yet.</td></tr>`;
}

$("connectBtn").onclick = connect;
$("mintBtn").onclick = mint;
$("createBtn").onclick = createInvoice;
$("payBtn").onclick = payInvoice;
$("refreshBtn").onclick = refreshList;
