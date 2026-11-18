#!/bin/bash
# CRUD completo nas duas tabelas relacionadas (CRUZAMENTO 1:N LEITURA_SENSOR).
# Uso: ./crud-demo.sh [URL]   (padrão http://localhost)
set -euo pipefail
API="${1:-http://localhost}"
SENHA="${SENHA_DEMO:-Semaforo@2026}"
j() { curl -s -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" "$@"; echo; }

TOKEN=$(curl -s -H "Content-Type: application/json" -d "{\"email\":\"admin@semaforo.dev\",\"senha\":\"$SENHA\"}" \
  "$API/auth/login" | sed -E 's/.*"token":"([^"]+)".*/\1/')

echo "== CREATE cruzamento"
NOVO=$(j -X POST "$API/cruzamentos" -d '{"nome":"Av. Ipiranga x Av. São João","municipio":"São Paulo","uf":"SP","latitude":-23.5432,"longitude":-46.6417,"limiteAguaCm":30}')
echo "$NOVO"
ID=$(echo "$NOVO" | sed -E 's/^\{"id":([0-9]+).*/\1/')

echo "== CREATE leitura (tabela relacionada, nível acima do limite)"
j -X POST "$API/cruzamentos/$ID/leituras" -d '{"nivelAguaCm":42,"carros":7,"pedestres":3}'

echo "== READ"
j "$API/cruzamentos/$ID"
j "$API/cruzamentos/$ID/leituras"
j "$API/cruzamentos/$ID/modo"

echo "== UPDATE"
j -X PUT "$API/cruzamentos/$ID" -d '{"nome":"Av. Ipiranga x Av. São João (CCO)","municipio":"São Paulo","uf":"SP","latitude":-23.5432,"longitude":-46.6417,"limiteAguaCm":35}' -o /dev/null -w "HTTP %{http_code}"
j "$API/cruzamentos/$ID"

echo "== LIST"
j "$API/cruzamentos"

echo "== DELETE (cria um cruzamento temporário e exclui; o id=$ID fica para o SELECT)"
TMP=$(j -X POST "$API/cruzamentos" -d '{"nome":"Temporário","municipio":"Porto Alegre","uf":"RS","limiteAguaCm":20}' | sed -E 's/^\{"id":([0-9]+).*/\1/')
j -X DELETE "$API/cruzamentos/$TMP" -o /dev/null -w "HTTP %{http_code}"
j "$API/cruzamentos/$TMP" -o /dev/null -w "GET após DELETE: HTTP %{http_code}"
