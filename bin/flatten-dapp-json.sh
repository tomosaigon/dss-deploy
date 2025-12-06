#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./bin/flatten-dapp-json.sh [path/to/dapp.sol.json]
#
# Defaults to out/dapp.sol.json

JSON="${1:-out/dapp.sol.json}"
TMP="${JSON}.tmp"

jq '
  # 1) First normalize/flatten .contracts so that instead of:
  #    "src/DssDeploy.sol": { "VatFab": {..}, "DssDeploy": {..}, ... }
  #    we get:
  #    "src/DssDeploy.sol:VatFab": {..}, "src/DssDeploy.sol:DssDeploy": {..}, ...
  .contracts as $c
  | .contracts =
      ( $c
        | to_entries
        | reduce .[] as $e ({};
            # Case A: value already looks like a contract object { abi, bin, ... }
            #         (this happens for most library packages)
            if ($e.value | type) == "object" and ($e.value | has("abi")) then
              . + { ($e.key): $e.value }
            # Case B: value is a nested map of contractName -> { abi, bin, ... }
            else
              reduce ($e.value | to_entries[]) as $ce (.;
                . + { ($e.key + ":" + $ce.key): $ce.value }
              )
            end
          )
      )
  # 2) Also add *bare* names for the DssDeploy compilation unit, so that
  #    dapp-create can find "VatFab", "DogFab", "CureFab", etc. directly.
  #    We scan for keys starting with "src/DssDeploy.sol:" and duplicate
  #    them under just the contract name.
  | .contracts as $flat
  | .contracts +=
      ( $flat
        | to_entries
        | map(select(.key | startswith("src/DssDeploy.sol:")))
        | if length == 0 then
            {}
          else
            map({
              # key is "src/DssDeploy.sol:ContractName" -> we keep just "ContractName"
              ((.key | split(":")[1])): .value
            })
            | add
          end
      )
' "$JSON" > "$TMP"

mv "$TMP" "$JSON"
echo "Flattened $JSON and added bare DssDeploy contract names (VatFab, DogFab, CalcFab, CureFab, etc.)."
