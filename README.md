# BRLPay — Stablecoin payments that feel like Pix

> **Arbitrum Open House São Paulo 2027 — Online Buildathon (GAWE job #24)**
> Stablecoin payment requests for Brazilian small merchants: a merchant
> creates an invoice in reais, the customer pays in USDG, funds settle
> instantly on Arbitrum Sepolia. No custody, no admin, no middleman.

## The idea — and why this one

Brazil runs on **Pix**: instant, free, QR-code payments that everyone from
a street vendor to a supermarket uses. Crypto payments in Brazil fail the
moment they ask a merchant or customer to think in wallets, gas, and token
symbols. BRLPay closes that gap: the invoice is denominated in **reais**
(the money people think in), the settlement is in **USDG** (Paxos'
stablecoin, the hackathon's highlighted integration), and the UX is Pix —
create a request, pay it, get a receipt, done.

Why this idea won over the alternatives:

- **Payments is a stated priority sector** for the judges (payments &
  stablecoin, DeFi, RWA, privacy, consumer, native-Arbitrum tooling),
  and the event is São Paulo-focused — a Brazil-first payments product is
  the strongest problem-solution fit available.
- **Demonstrable in 60 seconds**: create invoice → pay → receipt. Judges
  score execution (working MVP, docs, tests, live demo) over pitch decks.
- **Buildable by one agent**: two small contracts, full test coverage, a
  static frontend, no off-chain backend, no oracles, no deposits.
- **Fits the prize structure**: deployable on Arbitrum Sepolia today, and
  the same bytecode deploys unchanged on Robinhood Chain (1 of 3 prizes
  per track is reserved for Robinhood Chain projects) or Arbitrum One.

## What it is

- **`BRLPay.sol`** — invoices with BRL denomination + USDG settlement.
  `createInvoice(amountUSDG, amountBRLCents, description, validForSeconds)`,
  `payInvoice(id)` (instant payer → merchant transfer, receipt event),
  `cancelInvoice(id)` (merchant, before payment), `getInvoice`,
  `statusOf` (expiry overlaid), `brlPerUsd` (implied FX rate).
  The contract **never holds funds** (verified live: balance 0 after payment).
- **`MockUSDG.sol`** — testnet stand-in for Paxos USDG (ERC20, 6 decimals,
  open mint). Swapping in the real USDG address is a one-line change at
  deploy time.
- **Frontend** (`frontend/`) — static page (ethers v6 via CDN, MetaMask):
  connect, mint test mUSDG, create invoice, pay invoice, list invoices.
- **Demo** (`demo/demo.py`) — full two-party flow on testnet, scripted.

## Live deployment — Arbitrum Sepolia (chain 421614)

| | |
|---|---|
| BRLPay | [`0xd3a930C160A52BE6B6eC9a77568E87428d2Be24c`](https://sepolia.arbiscan.io/address/0xd3a930C160A52BE6B6eC9a77568E87428d2Be24c) |
| MockUSDG (mUSDG) | [`0x2eF0A9708182eB988f20C0C278224908e0Bc2FA9`](https://sepolia.arbiscan.io/address/0x2eF0A9708182eB988f20C0C278224908e0Bc2FA9) |
| Deployer (MUSE EVM) | `0xFdE48E9AcC441cBC726A88CFD05c859AE5A0b84e` |
| Deploy tx — MockUSDG | [`0xad46a2c13a3d690e39209584ab24c094cc972d93c2915d67638f0152e3c1cdb1`](https://sepolia.arbiscan.io/tx/0xad46a2c13a3d690e39209584ab24c094cc972d93c2915d67638f0152e3c1cdb1) |
| Deploy tx — BRLPay | [`0xfae7bf49b9f210ff0de2f522491142e67a41d17396e1a3fc96c199c6fa07d305`](https://sepolia.arbiscan.io/tx/0xfae7bf49b9f210ff0de2f522491142e67a41d17396e1a3fc96c199c6fa07d305) |
| Funding | 0.002 test ETH bridged Base Sepolia → Arbitrum Sepolia via LI.FI/Across ([Base Sepolia tx `0xabbb68b0134108163f75dda2a7b94802fec386bc2245d590ef73cc817d474afc`](https://sepolia.basescan.org/tx/0xabbb68b0134108163f75dda2a7b94802fec386bc2245d590ef73cc817d474afc)); deploy cost ~0.000137 ETH. No real funds used anywhere. |

### Live demo receipt (invoice #1, 18 Nov 2026)

Merchant created invoice #1 — **$5.00 USDG / R$ 25,00** ("Café + pão de
queijo"). A fresh customer wallet approved and paid it.

- createInvoice: [`0x8b32c9be21e63aa80a2ad9b52fcb5c76d74ea6412f4546d59c36278d91dc135c`](https://sepolia.arbiscan.io/tx/0x8b32c9be21e63aa80a2ad9b52fcb5c76d74ea6412f4546d59c36278d91dc135c)
- payInvoice: [`0x904de73a9de5b9a616bd8498752d116b7b3de6843332a14cbb079415cde1601e`](https://sepolia.arbiscan.io/tx/0x904de73a9de5b9a616bd8498752d116b7b3de6843332a14cbb079415cde1601e)
- Result: status **Paid**, payer `0x8ec97B750da28ea68C10730b02A219938bE4Ac4b`,
  rate **R$ 5,00 per US$ 1**, merchant received $5.00, contract balance 0.

## How to run

```bash
# tests (18 tests incl. a 256-run fuzz test)
forge test

# demo on Arbitrum Sepolia (needs web3.py + a funded key in
# ~/workspace/goals/free-mint-hunter/hidden_files/farming-wallet-evm.json)
./demo.sh

# frontend (static; needs MetaMask on Arbitrum Sepolia)
python3 -m http.server --directory frontend 8080
# open http://localhost:8080
```

Deploy (fresh): `python3 ../../deploy-brlpay.py` (reads the MUSE key from the
farming wallet file; never prints it) — or
`PRIVATE_KEY=0x... forge script script/Deploy.s.sol --rpc-url arbitrum_sepolia --broadcast`.

## Architecture

```
  merchant ──createInvoice──► BRLPay ──payInvoice──► merchant (USDG)
  customer ──approve + pay──► BRLPay    (funds never touch the contract)
                                  │ emits InvoiceCreated / InvoicePaid
                                  ▼
                            frontend (ethers v6, MetaMask)
  MockUSDG (ERC20, 6 dec) ── testnet stand-in for Paxos USDG
```

Security notes: `payInvoice` is `nonReentrant` + `SafeERC20`; state is
updated before the external token call (checks-effects-interactions).
`block.timestamp` is used only for invoice expiry (a 1-minute validator
skew is irrelevant at hour-scale expiries) — the Foundry linter flags it;
accepted deliberately.

## Honest limitations

- **MockUSDG, not real USDG.** The live deployment settles test mUSDG.
  Real USDG on Arbitrum One is a deploy-time address swap; the BRL↔USDG
  rate is set by the merchant per invoice (no oracle yet) — a Chainlink
  BRL/USD feed is the obvious next step for mainnet.
- **No dispute flow.** Payment is final on `payInvoice`. A refund/escrow
  window is a planned extension, deliberately cut to keep the MVP tight.
- **Contracts not yet verified on Arbiscan** — needs a free Arbiscan API
  key (2-minute step, see checklist).
- **No demo video yet** — record one before the Feb 2027 submission.
- **Robinhood Chain deploy not yet done** — same bytecode, one RPC change;
  do it once the Robinhood testnet RPC/faucet is confirmed (reserved
  prize slot).

## Hackathon facts (verified 18 Nov 2026)

- Event: Arbitrum Open House São Paulo — Online Buildathon, 8–28 Feb 2027;
  submission deadline **28 Feb 2027 23:59 BRT**; winners **8 Mar 2027
  17:00 BRT**. 100% online, open worldwide (18+). Organizer: Project
  Moonshot Ltd (HackQuest) for the Arbitrum Foundation.
- Prizes (USDG on Arbitrum One): Overall 1st $40,000 / 2nd $20,000 / 3rd
  $10,000; Best Promising Products 1st $7,000 / 2nd $5,000 / 3rd $3,000;
  milestone grants up to $30,000. Total $115,000.
- Rules that matter: must deploy on Arbitrum Sepolia, Arbitrum One, or a
  custom Orbit Chain (no deploy = disqualified); prizes are milestone-based
  (50% on win + grant agreement incl. exclusive Arbitrum building, 50% on
  mainnet launch + agreed KPI + Foundation investment rights); ≥1 of 3
  prizes per 3-prize track is reserved for Robinhood Chain projects and ≥1
  of 3 for Arbitrum projects. Judging: innovation, technical implementation,
  use of Arbitrum technology, potential impact, presentation quality.
- Top 3 teams are invited to a 3-day in-person Founder House in São Paulo
  (only if the team wins — decide with the user then; the user does not do
  offline/Zoom/Meet).
- Sources: [Terms (PDF)](https://openhouse.arbitrum.io/sao_paulo_version_open_house_buildathon_terms_and_conditions.pdf),
  [HackQuest page](https://www.hackquest.io/hackathons/Arbitrum-Open-House-Sao-Paulo-Online-Buildathon),
  [openhouse.arbitrum.io](https://openhouse.arbitrum.io).

## Submission checklist (for Feb 2027)

- [x] Idea chosen + documented (this README)
- [x] Contracts built + 18 tests passing (incl. fuzz)
- [x] Deployed on Arbitrum Sepolia + live demo receipt (invoice #1 Paid)
- [x] Public GitHub repo (Jaw1jennaira)
- [x] Static frontend (MetaMask demo)
- [ ] Verify contracts on Arbiscan Sepolia (needs free API key)
- [ ] Deploy the same contracts on Robinhood Chain testnet (reserved slot)
- [ ] Record a demo video (product actually working, < 3 min)
- [ ] Register on HackQuest + join the Arbitrum Discord for the event
- [ ] Submit on HackQuest before 28 Feb 2027 23:59 BRT (internal target: 26 Feb)
- [ ] (Optional, strengthens entry) Chainlink BRL/USD feed for the rate
- [ ] (After winning, if applicable) Grant agreement + mainnet launch plan

## License

MIT.
