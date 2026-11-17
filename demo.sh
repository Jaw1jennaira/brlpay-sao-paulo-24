#!/usr/bin/env bash
# BRLPay demo: forge tests + live end-to-end demo on Arbitrum Sepolia.
# Usage: ./demo.sh
# demo.py needs web3.py + eth-account (pip install web3 eth-account in a venv)
# and the MUSE farming wallet key at
# ~/workspace/goals/free-mint-hunter/hidden_files/farming-wallet-evm.json
# (the script only ever reads it; it never prints it).
set -e
cd "$(dirname "$0")"
export PATH="$HOME/.foundry/bin:$PATH"

echo "== forge test =="
forge test

echo
echo "== live demo on Arbitrum Sepolia =="
PY=""
for cand in /tmp/venvs/web3env/bin/python python3; do
  if "$cand" -c "import web3" 2>/dev/null; then PY="$cand"; break; fi
done
if [ -z "$PY" ]; then
  echo "web3.py not found. Create a venv and run: pip install web3 eth-account"
  exit 1
fi
"$PY" demo/demo.py
