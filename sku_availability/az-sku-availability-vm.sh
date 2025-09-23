#!/bin/bash

LOCATION="$1"

ALL_SKUS=$(az vm list-skus --location "$LOCATION" --resource-type virtualMachines --output json)

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "$ALL_SKUS" | python3 "$SOURCE_DIR/filter_skus.py" "$LOCATION"
