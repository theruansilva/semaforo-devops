#!/bin/bash
# ==============================================================================
# FIAP 2026 • GLOBAL SOLUTION 2026/2 • CITIZENTECH
# Disciplina: DevOps Tools & Cloud Computing
# Sinalize.Ai: provisionamento da VM Azure via CLI + API Java e
# Oracle Database em contêineres orquestrados pelo Docker Compose
#
# INTEGRANTES:
# - Ruan Lima da Silva (RM 566719)
# - Julia Valerio Guimarães da Silva (RM 568275)
# - Rhayssa Graziano Bernardes e Rocha Ferreira (RM 567549)
# Turma: 2TDSPR
# ==============================================================================

set -euo pipefail

# Configurações de recursos na nuvem Microsoft Azure (LOC e SIZE podem ser sobrescritos)
RG="rg-semaforo-566719"
LOC="${LOC:-northcentralus}"
VM="vm-semaforo-566719"
USER="azureuser"
SIZE="${SIZE:-Standard_B2als_v2}"   # 2 vCPU / 4 GB: Oracle Free (~2 GB) + API (512 MB)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

clear 2>/dev/null || true
echo "=============================================================================="
echo " GLOBAL SOLUTION DEVOPS • SINALIZE.AI (CITIZENTECH / EL NIÑO)"
echo " VM Azure via CLI + Docker Compose: API Spring Boot + Oracle Database 23ai"
echo " Integrantes: Ruan (566719), Julia Valerio (568275), Rhayssa Graziano (567549)"
echo "=============================================================================="

# 0. Verificação de autenticação e do arquivo de variáveis de ambiente
echo -e "\n>>> [0/5] VERIFICANDO AUTENTICAÇÃO NO AZURE CLI..."
if ! az account show >/dev/null 2>&1; then
  echo "[-] Erro: você não está autenticado na Azure CLI."
  echo "    Execute 'az login' antes de iniciar o script."
  exit 1
fi
echo "[+] Conectado à conta: $(az account show --query name -o tsv) ($(az account show --query user.name -o tsv))"
if [ ! -f "$DIR/.env" ]; then
  cp "$DIR/.env.example" "$DIR/.env"
  echo "[+] Arquivo .env criado a partir do .env.example (senhas e JWT_SECRET padrão)."
fi

# 1. Criação do grupo de recursos
echo -e "\n>>> [1/5] CRIANDO GRUPO DE RECURSOS ($RG em $LOC)..."
if [ "$(az group show -n "$RG" --query properties.provisioningState -o tsv 2>/dev/null || true)" = "Deleting" ]; then
  echo "    [!] O grupo '$RG' ainda está finalizando a exclusão anterior na Azure."
  echo "    Aguardando a exclusão completa antes de recriar..."
  az group wait -n "$RG" --deleted
  echo "    [+] Exclusão anterior concluída! Criando grupo de recursos limpo."
fi
az group create -n "$RG" -l "$LOC" -o table

# 2. Provisionamento da máquina virtual
echo -e "\n>>> [2/5] PROVISIONANDO MÁQUINA VIRTUAL NA AZURE..."
echo "    Nome: $VM | Tamanho: $SIZE | Imagem: Ubuntu 22.04 | Usuário: $USER"
az vm create -g "$RG" -n "$VM" --image Ubuntu2204 --size "$SIZE" \
  --admin-username "$USER" --generate-ssh-keys --public-ip-sku Standard -o table

# 3. Liberação da porta 80 (HTTP) no Network Security Group
echo -e "\n>>> [3/5] CONFIGURANDO REGRAS DE REDE (NSG) - LIBERANDO PORTA 80 (HTTP)..."
az vm open-port -g "$RG" -n "$VM" --port 80 --priority 1010 -o table

# 4. Instalação do Docker + Compose e subida dos contêineres na VM
echo -e "\n>>> [4/5] INSTALANDO DOCKER E SUBINDO OS CONTÊINERES (API + BANCO) NA VM AZURE..."
echo "    Gerando pacote com Dockerfile, docker-compose.yml, .env e código-fonte..."
TAR_B64=$(tar -cz -C "$DIR" Dockerfile docker-compose.yml .env pom.xml src | base64 -w 0)
echo "    Enviando comandos para a VM via Azure RunCommand (RunShellScript)..."
echo "    (build Maven + primeiro start do Oracle levam alguns minutos)"
az vm run-command invoke -g "$RG" -n "$VM" --command-id RunShellScript --scripts "
set -e
echo '=== [A] AGUARDANDO BOOTSTRAP DO UBUNTU E INSTALANDO DOCKER + COMPOSE ==='
cloud-init status --wait || true
curl -fsSL https://get.docker.com | sh >/dev/null
usermod -aG docker $USER
docker --version && docker compose version
echo '=== [B] COPIANDO O PROJETO PARA /opt/semaforo ==='
mkdir -p /opt/semaforo && cd /opt/semaforo
echo '$TAR_B64' | base64 -d | tar -xz
chown -R $USER:$USER /opt/semaforo
ls -la /opt/semaforo
echo '=== [C] BUILD DA IMAGEM E SUBIDA DOS CONTÊINERES EM BACKGROUND (docker compose up -d) ==='
docker compose up -d --build
echo '=== [D] STATUS DOS CONTÊINERES ==='
docker compose ps
" --query "value[0].message" -o tsv

# 5. Validação externa pelo IP público
echo -e "\n>>> [5/5] CONSULTANDO IP PÚBLICO E AGUARDANDO A API RESPONDER PELA INTERNET..."
IP=$(az vm show -d -g "$RG" -n "$VM" --query publicIps -o tsv)
echo "    A API só sobe depois que o Oracle fica 'healthy' (até ~10 min)."
HTTP_CODE="000"
for _ in $(seq 60); do
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://$IP/swagger-ui/index.html" || true)
  [ "$HTTP_CODE" = "200" ] && break
  sleep 10
done

echo -e "\n=============================================================================="
echo " SINALIZE.AI EM EXECUÇÃO NA NUVEM MICROSOFT AZURE!"
echo "=============================================================================="
echo " IP Público da VM:        http://$IP"
echo " Documentação Swagger UI: http://$IP/swagger-ui/index.html"
echo " Acesso SSH:              ssh $USER@$IP   (depois: cd /opt/semaforo)"
echo "=============================================================================="
if [ "$HTTP_CODE" = "200" ]; then
  echo "[+] Acesso público comprovado com sucesso (HTTP 200 OK)!"
else
  echo "[!] A API ainda não respondeu (HTTP $HTTP_CODE). Aguarde e teste:"
  echo "    curl -I http://$IP/swagger-ui/index.html"
fi

echo -e "\n------------------------------------------------------------------------------"
echo " Próximos passos:"
echo "   ./crud-demo.sh http://$IP     # CRUD completo nas tabelas relacionadas"
echo "   ./destroy.sh                  # exclui o grupo de recursos ao final"
echo "------------------------------------------------------------------------------"
