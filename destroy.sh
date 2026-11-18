#!/bin/bash
# Remove todos os recursos (VM, disco, IP, NSG) excluindo o grupo de recursos.
set -euo pipefail
RG="rg-semaforo-566719"
az group delete -n "$RG" --yes --no-wait
az group show -n "$RG" --query "{Nome:name, Estado:properties.provisioningState}" -o table || true
