#!/usr/bin/env bash
# =============================================================================
# fetch-ng-tvl.sh: total liquidity (TVL) held by the Curve "NG" contracts.
#
# Sums on-chain TVL across the three NG factory registries (Stableswap-NG,
# Tricrypto-NG, Twocrypto-NG) over every Curve network, using the public
# Curve API. These are the Vyper 0.3.10-era pools whose core contracts the
# three changes in this repo's README discuss.
#
# Reports the value held by these contracts as a live, reproducible number
# rather than a static claim. Run it for a current snapshot.
#
# Requirements: bash, curl, jq.
# Usage:        ./fetch-ng-tvl.sh            # prints per-registry + grand total
#               OUTDIR=./snapshot ./fetch-ng-tvl.sh   # also keep raw JSON
#
# Notes on correctness (these matter and are easy to get wrong):
#   * TVL basis is `data.tvlAll`, which the API computes as the sum of each
#     pool's usdTotalExcludingBasePool. A naive sum of poolData[].usdTotal
#     DOUBLE-COUNTS metapools (their base-pool liquidity is already counted in
#     the base pool's own entry). On Ethereum stable-ng that overcount was ~$8M.
#   * The `/getPools/all/<registry>` endpoint is broken for these registries
#     (returns success:true with an empty/err payload), so the script iterates
#     per network and sums.
#   * Hosts: api.curve.finance is canonical; api.curve.fi 301-redirects to it.
# =============================================================================
set -euo pipefail

API="https://api.curve.finance/api"
OUTDIR="${OUTDIR:-$(mktemp -d)}"
mkdir -p "$OUTDIR"

# The three NG factory registries authored in stableswap-ng / tricrypto-ng.
REGISTRIES=(factory-stable-ng factory-tricrypto factory-twocrypto)

# Networks Curve serves. (getPlatforms is authoritative; this is its result at
# the time of writing. gnosis is served as "xdai"; OKX X Layer as "x-layer".)
NETWORKS=(ethereum arbitrum optimism polygon base fraxtal mantle avalanche \
          fantom xdai bsc celo kava aurora moonbeam sonic hyperliquid x-layer \
          zkevm zksync)

fetch() { # registry network -> writes JSON file, echoes its path
  local reg="$1" net="$2" f="$OUTDIR/${1}__${2}.json"
  curl -fsS --max-time 150 "$API/getPools/$net/$reg" -o "$f" 2>/dev/null || echo '{}' > "$f"
  echo "$f"
}

echo "Curve NG liquidity snapshot  (host: $API)"
echo "raw JSON: $OUTDIR"
echo

grand=0
printf "%-22s %18s %8s\n" "REGISTRY" "TVL (USD)" "POOLS"
printf "%-22s %18s %8s\n" "----------------------" "------------------" "--------"
for reg in "${REGISTRIES[@]}"; do
  files=()
  for net in "${NETWORKS[@]}"; do files+=("$(fetch "$reg" "$net")"); done

  # Per-registry TVL = sum of data.tvlAll across that registry's network files.
  tvl=$(jq -rs 'map(.data.tvlAll // 0) | add' "${files[@]}")
  # Active pools = pools with usdTotal > 0 across all networks.
  pools=$(jq -rs '[.[].data.poolData[]? | select(.usdTotal > 0)] | length' "${files[@]}")

  printf "%-22s %18s %8s\n" "$reg" "$(printf "%'.0f" "${tvl%.*}")" "$pools"
  grand=$(jq -n --argjson a "$grand" --argjson b "$tvl" '$a + $b')
done
printf "%-22s %18s\n" "----------------------" "------------------"
printf "%-22s %18s\n" "GRAND TOTAL" "$(printf "%'.0f" "${grand%.*}")"

echo
echo "Top 10 pools by TVL across the three NG registries:"
jq -rs '[.[].data.poolData[]? | select(.usdTotal > 0)]
        | sort_by(-.usdTotal)[:10][]
        | "  $\(.usdTotal | floor)  \(.name // .address)"' "$OUTDIR"/*.json 2>/dev/null || true

# --- Optional: corroborate the NG implementation addresses (0.3.10 / *-ng) ----
# jq -r '.data.poolData[]?.implementationAddress' "$OUTDIR"/factory-tricrypto__*.json \
#   | sort | uniq -c | sort -rn
