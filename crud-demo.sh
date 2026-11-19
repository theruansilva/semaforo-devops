#!/bin/bash
# ==============================================================================
# FIAP 2026 • GLOBAL SOLUTION 2026/2 • CITIZENTECH
# Disciplina: DevOps Tools & Cloud Computing
# Demonstração do CRUD completo nas tabelas relacionadas do Oracle:
# CRUZAMENTO 1:N LEITURA_SENSOR e CRUZAMENTO 1:N ALERTA
# Uso: ./crud-demo.sh [URL]   (padrão http://localhost)
# ==============================================================================

set -euo pipefail
API="${1:-http://localhost}"
SENHA="${SENHA_DEMO:-Semaforo@2026}"
j() { curl -s -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" "$@"; echo; }

echo "=============================================================================="
echo " DEMONSTRAÇÃO DO CRUD • SINALIZE.AI"
echo " API: $API"
echo "=============================================================================="

echo -e "\n>>> [0/7] AUTENTICANDO COMO ADMIN (JWT)..."
TOKEN=$(curl -s -H "Content-Type: application/json" -d "{\"email\":\"admin@semaforo.dev\",\"senha\":\"$SENHA\"}" \
  "$API/auth/login" | sed -E 's/.*"token":"([^"]+)".*/\1/')
echo "[+] Token obtido: ${TOKEN:0:20}..."

echo -e "\n>>> [1/7] CREATE: CADASTRANDO NOVO CRUZAMENTO (POST /cruzamentos)..."
NOVO=$(j -X POST "$API/cruzamentos" -d '{"nome":"Av. Ipiranga x Av. São João","municipio":"São Paulo","uf":"SP","latitude":-23.5432,"longitude":-46.6417,"limiteAguaCm":30}')
echo "$NOVO"
ID=$(echo "$NOVO" | sed -E 's/^\{"id":([0-9]+).*/\1/')

echo -e "\n>>> [2/7] CREATE: REGISTRANDO LEITURA DO SENSOR ACIMA DO LIMITE (tabela LEITURA_SENSOR)..."
j -X POST "$API/cruzamentos/$ID/leituras" -d '{"nivelAguaCm":42,"carros":7,"pedestres":3}'

echo -e "\n>>> [3/7] READ: CONSULTANDO CRUZAMENTO, LEITURAS E MODO DO SEMÁFORO..."
j "$API/cruzamentos/$ID"
j "$API/cruzamentos/$ID/leituras"
echo "    Modo do semáforo (esperado ATENCAO, nível 42 cm > limite 30 cm):"
j "$API/cruzamentos/$ID/modo"

echo -e "\n>>> [4/7] UPDATE: ATUALIZANDO O CRUZAMENTO (PUT /cruzamentos/$ID)..."
j -X PUT "$API/cruzamentos/$ID" -d '{"nome":"Av. Ipiranga x Av. São João (CCO)","municipio":"São Paulo","uf":"SP","latitude":-23.5432,"longitude":-46.6417,"limiteAguaCm":35}' -o /dev/null -w "HTTP %{http_code}"
j "$API/cruzamentos/$ID"

echo -e "\n>>> [5/7] LIST: LISTANDO CRUZAMENTOS CADASTRADOS (GET /cruzamentos)..."
j "$API/cruzamentos"

echo -e "\n>>> [6/7] DELETE: EXCLUINDO UM CRUZAMENTO TEMPORÁRIO (o id=$ID fica para o SELECT)..."
TMP=$(j -X POST "$API/cruzamentos" -d '{"nome":"Temporário","municipio":"Porto Alegre","uf":"RS","limiteAguaCm":20}' | sed -E 's/^\{"id":([0-9]+).*/\1/')
j -X DELETE "$API/cruzamentos/$TMP" -o /dev/null -w "HTTP %{http_code}"
j "$API/cruzamentos/$TMP" -o /dev/null -w "GET após DELETE: HTTP %{http_code}"

echo -e "\n>>> [7/7] CRUD DE ALERTA (tabela ALERTA, FK cruzamento_id -> CRUZAMENTO.id)..."
echo "    CREATE (POST /alertas):"
ALERTA=$(j -X POST "$API/alertas" -d "{\"titulo\":\"Alagamento na via\",\"descricao\":\"Defesa Civil: nível crítico\",\"severidade\":\"ALTA\",\"municipio\":\"São Paulo\",\"uf\":\"SP\",\"cruzamentoId\":$ID}")
echo "$ALERTA"
AID=$(echo "$ALERTA" | sed -E 's/^\{"id":([0-9]+).*/\1/')
echo "    READ (GET /alertas/$AID):"
j "$API/alertas/$AID"
echo "    UPDATE (PUT /alertas/$AID):"
j -X PUT "$API/alertas/$AID" -d "{\"titulo\":\"Alagamento na via (atualizado)\",\"descricao\":\"Nível em queda\",\"severidade\":\"MODERADA\",\"municipio\":\"São Paulo\",\"uf\":\"SP\",\"cruzamentoId\":$ID}"
j "$API/cruzamentos/$ID/modo"
echo "    DELETE de um alerta temporário (o id=$AID fica para o SELECT):"
TMPA=$(j -X POST "$API/alertas" -d "{\"titulo\":\"Temporário\",\"severidade\":\"BAIXA\",\"municipio\":\"São Paulo\",\"uf\":\"SP\",\"cruzamentoId\":$ID}" | sed -E 's/^\{"id":([0-9]+).*/\1/')
j -X DELETE "$API/alertas/$TMPA" -o /dev/null -w "HTTP %{http_code}"
j "$API/alertas/$TMPA" -o /dev/null -w "GET após DELETE: HTTP %{http_code}"

echo -e "\n=============================================================================="
echo " CRUD COMPLETO EXECUTADO! Confira os dados direto no banco (SELECT no README)."
echo "=============================================================================="
