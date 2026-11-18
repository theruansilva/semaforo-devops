#!/bin/bash
# Global Solution 2026/2 · CitizenTech · DevOps Tools & Cloud Computing
# Semáforo Inteligente: provisiona VM Azure via CLI e sobe API Java + Oracle com Docker Compose.
# Integrantes: Ruan Lima da Silva (RM 566719), Julia Valerio Guimarães da Silva (RM 568275),
#              Rhayssa Graziano Bernardes e Rocha Ferreira (RM 567549) · Turma 2TDSPR
set -euo pipefail

RG="rg-semaforo-566719"
LOC="${LOC:-northcentralus}"
VM="vm-semaforo-566719"
USER="azureuser"
SIZE="${SIZE:-Standard_B2als_v2}"   # 2 vCPU / 4 GB: Oracle Free (~2 GB) + API (512 MB)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

az account show -o none 2>/dev/null || { echo "Execute 'az login' primeiro."; exit 1; }
[ -f "$DIR/.env" ] || cp "$DIR/.env.example" "$DIR/.env"

echo ">>> [1/5] Grupo de recursos $RG ($LOC)"
az group create -n "$RG" -l "$LOC" -o table

echo ">>> [2/5] VM $VM ($SIZE, Ubuntu 22.04)"
az vm create -g "$RG" -n "$VM" --image Ubuntu2204 --size "$SIZE" \
  --admin-username "$USER" --generate-ssh-keys --public-ip-sku Standard -o table

echo ">>> [3/5] Liberando porta 80 (API) no NSG"
az vm open-port -g "$RG" -n "$VM" --port 80 --priority 1010 -o table

echo ">>> [4/5] Instalando Docker + Compose e subindo os containers na VM"
TAR_B64=$(tar -cz -C "$DIR" Dockerfile docker-compose.yml .env pom.xml src | base64 -w 0)
az vm run-command invoke -g "$RG" -n "$VM" --command-id RunShellScript --scripts "
set -e
cloud-init status --wait || true
curl -fsSL https://get.docker.com | sh
usermod -aG docker $USER
mkdir -p /opt/semaforo && cd /opt/semaforo
echo '$TAR_B64' | base64 -d | tar -xz
chown -R $USER:$USER /opt/semaforo
docker compose up -d --build
docker compose ps
" --query "value[0].message" -o tsv

echo ">>> [5/5] Aguardando a API responder"
IP=$(az vm show -d -g "$RG" -n "$VM" --query publicIps -o tsv)
for _ in $(seq 60); do
  curl -sf "http://$IP/cruzamentos/1/modo" >/dev/null 2>&1 && break
  sleep 10
done
echo "API:     http://$IP"
echo "Swagger: http://$IP/swagger-ui/index.html"
echo "SSH:     ssh $USER@$IP   (depois: cd /opt/semaforo)"
