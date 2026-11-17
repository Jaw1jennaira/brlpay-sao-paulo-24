#!/usr/bin/env python3
"""End-to-end BRLPay demo on Arbitrum Sepolia (chain 421614).

Flow: deployer (merchant) creates a R$ 25,00 / $5.00 invoice; a fresh
customer wallet is funded with a little ETH + mUSDG, approves BRLPay and
pays the invoice; the receipt is read back on-chain. Keys live only in
this process memory (deployer key from the farming wallet file; customer
key freshly generated each run and never saved).

Usage: /tmp/venvs/web3env/bin/python demo/demo.py
"""
import json

from eth_account import Account
from web3 import Web3

KEY_FILE = "/home/hatch/workspace/goals/free-mint-hunter/hidden_files/farming-wallet-evm.json"
REPO_DIR = "/home/hatch/workspace/goals/free-mint-hunter/hidden_files/gawe-repos/arbitrum-sao-paulo-24"
RPC = "https://arbitrum-sepolia.publicnode.com"
EXPLORER = "https://sepolia.arbiscan.io"

deps = json.load(open(REPO_DIR + "/deployments.json"))
USDG = deps["usdg"]
BRLPAY = deps["brlPay"]

ERC20_ABI = [
    {"name": "approve", "type": "function", "inputs": [{"name": "s", "type": "address"}, {"name": "a", "type": "uint256"}], "outputs": [{"name": "", "type": "bool"}], "stateMutability": "nonpayable"},
    {"name": "transfer", "type": "function", "inputs": [{"name": "t", "type": "address"}, {"name": "a", "type": "uint256"}], "outputs": [{"name": "", "type": "bool"}], "stateMutability": "nonpayable"},
    {"name": "balanceOf", "type": "function", "inputs": [{"name": "a", "type": "address"}], "outputs": [{"name": "", "type": "uint256"}], "stateMutability": "view"},
]
BRLPAY_ABI = [
    {"name": "createInvoice", "type": "function", "inputs": [{"name": "amountUSDG", "type": "uint256"}, {"name": "amountBRLCents", "type": "uint256"}, {"name": "description", "type": "string"}, {"name": "validForSeconds", "type": "uint256"}], "outputs": [{"name": "id", "type": "uint256"}], "stateMutability": "nonpayable"},
    {"name": "payInvoice", "type": "function", "inputs": [{"name": "id", "type": "uint256"}], "outputs": [], "stateMutability": "nonpayable"},
    {"name": "getInvoice", "type": "function", "inputs": [{"name": "id", "type": "uint256"}], "outputs": [{"name": "", "type": "tuple", "components": [{"name": "merchant", "type": "address"}, {"name": "payer", "type": "address"}, {"name": "amountUSDG", "type": "uint256"}, {"name": "amountBRLCents", "type": "uint256"}, {"name": "description", "type": "string"}, {"name": "createdAt", "type": "uint256"}, {"name": "expiresAt", "type": "uint256"}, {"name": "paidAt", "type": "uint256"}, {"name": "status", "type": "uint8"}]}], "stateMutability": "view"},
    {"name": "invoiceCount", "type": "function", "inputs": [], "outputs": [{"name": "", "type": "uint256"}], "stateMutability": "view"},
    {"name": "brlPerUsd", "type": "function", "inputs": [{"name": "id", "type": "uint256"}], "outputs": [{"name": "", "type": "uint256"}], "stateMutability": "view"},
]

w3 = Web3(Web3.HTTPProvider(RPC))
assert w3.is_connected()
key = json.load(open(KEY_FILE))["private_key"]
if not key.startswith("0x"):
    key = "0x" + key
deployer = w3.eth.account.from_key(key)
print("deployer:", deployer.address)
print("deployer ETH:", w3.from_wei(w3.eth.get_balance(deployer.address), "ether"))

usdg = w3.eth.contract(address=USDG, abi=ERC20_ABI)
pay = w3.eth.contract(address=BRLPAY, abi=BRLPAY_ABI)

customer = Account.create()
print("customer (fresh):", customer.address)


def send(acct, tx):
    # EIP-1559 fees with a buffer: the public RPC's gas_price can lag the
    # block base fee by a hair, which makes the tx underpriced.
    base_fee = w3.eth.get_block("latest")["baseFeePerGas"]
    tx["nonce"] = w3.eth.get_transaction_count(acct.address)
    tx["maxFeePerGas"] = base_fee * 2 + 1_000_000
    tx["maxPriorityFeePerGas"] = 1
    tx["chainId"] = 421614
    signed = acct.sign_transaction(tx)
    h = w3.eth.send_raw_transaction(signed.raw_transaction)
    r = w3.eth.wait_for_transaction_receipt(h, timeout=180)
    assert r["status"] == 1, f"tx failed: {h.hex()}"
    return h.hex()


# 1. fund the customer: 0.0002 ETH gas + $20 mUSDG
h1 = send(deployer, {"to": customer.address, "value": w3.to_wei(0.0002, "ether"), "gas": 21000})
print("fund ETH tx:", h1, f"{EXPLORER}/tx/{h1}")
h2 = send(deployer, usdg.functions.transfer(customer.address, 20_000_000).build_transaction({"from": deployer.address, "gas": 100000}))
print("fund mUSDG tx:", h2)

# 2. merchant creates invoice: $5.00 USDG for R$ 25,00, valid 1h
tx = pay.functions.createInvoice(5_000_000, 2500, "Cafe + pao de queijo", 3600).build_transaction({"from": deployer.address, "gas": 300000})
h3 = send(deployer, tx)
print("createInvoice tx:", h3, f"{EXPLORER}/tx/{h3}")
inv_id = pay.functions.invoiceCount().call()
print("invoice id:", inv_id)

# 3. customer approves + pays
h4 = send(customer, usdg.functions.approve(BRLPAY, 5_000_000).build_transaction({"from": customer.address, "gas": 100000}))
print("approve tx:", h4)
h5 = send(customer, pay.functions.payInvoice(inv_id).build_transaction({"from": customer.address, "gas": 300000}))
print("payInvoice tx:", h5, f"{EXPLORER}/tx/{h5}")

# 4. read the receipt back
inv = pay.functions.getInvoice(inv_id).call()
status = ["Open", "Paid", "Cancelled", "Expired"][inv[8]]
print("--- receipt ---")
print("invoice:", inv_id, "| status:", status)
print("merchant:", inv[0], "| payer:", inv[1])
print("amountUSDG:", inv[2], "($%.2f)" % (inv[2] / 1e6))
print("amountBRLCents:", inv[3], "(R$ %.2f)" % (inv[3] / 100))
print("description:", inv[4])
print("rate BRL/USD:", pay.functions.brlPerUsd(inv_id).call() / 1e4)
print("merchant mUSDG balance:", usdg.functions.balanceOf(inv[0]).call() / 1e6)
print("customer mUSDG balance:", usdg.functions.balanceOf(customer.address).call() / 1e6)
print("BRLPay contract mUSDG balance (must be 0, no custody):", usdg.functions.balanceOf(BRLPAY).call())
print("contracts:")
print("  BRLPay:", BRLPAY, f"{EXPLORER}/address/{BRLPAY}")
print("  MockUSDG:", USDG, f"{EXPLORER}/address/{USDG}")
