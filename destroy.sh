#!/bin/bash
# ==============================================================================
# FIAP 2026 • GLOBAL SOLUTION 2026/2 • CITIZENTECH
# Disciplina: DevOps Tools & Cloud Computing
# Script para exclusão limpa e comprovação de exclusão dos recursos no Azure
# ==============================================================================

set -euo pipefail

RG="rg-semaforo-566719"

echo "=============================================================================="
echo " EXCLUSÃO DE RECURSOS NO MICROSOFT AZURE • SEMÁFORO INTELIGENTE"
echo " Grupo de Recursos a excluir: $RG"
echo "=============================================================================="

if [ "$(az group exists -n "$RG")" != "true" ]; then
  echo "O grupo de recursos '$RG' já não existe ou já foi excluído anteriormente."
  exit 0
fi

echo -e "\n>>> DISPARANDO EXCLUSÃO DO RESOURCE GROUP ($RG)..."
az group delete -n "$RG" --yes --no-wait

echo -e "\n[+] Comando de exclusão enviado com sucesso ao Azure Resource Manager (ARM)!"
echo "    VM, disco, IP público, NSG e rede virtual estão sendo removidos."
echo -e "\nVerificando status atual do grupo:"
az group show -n "$RG" --query "{Nome:name, Estado:properties.provisioningState}" -o table || true

echo -e "\n=============================================================================="
echo " Solicitação de exclusão registrada. Confira o fim com: az group exists -n $RG"
echo "=============================================================================="
