# Semáforo Inteligente · DevOps Tools & Cloud Computing

Global Solution 2026/2 · CitizenTech · Turma 2TDSPR

| Integrante | RM |
|---|---|
| Ruan Lima da Silva | 566719 |
| Julia Valerio Guimarães da Silva | 568275 |
| Rhayssa Graziano Bernardes e Rocha Ferreira | 567549 |

**Solução:** semáforos que mudam de modo em enchentes (El Niño). O sensor de nível de água do cruzamento envia leituras; acima do limite, o cruzamento entra em `ATENCAO` (amarelo piscante). Alertas da Defesa Civil/CEMADEN levam a `EVACUACAO` (onda verde até o abrigo). O cidadão consulta o modo pelo app.

Esta entrega roda a **API Java (Spring Boot 3.5 / Java 21)** e o **Oracle Database 23ai Free** em dois containers Docker Compose numa VM Azure provisionada por Azure CLI.

## Arquitetura macro

```mermaid
flowchart LR
  subgraph Borda["Cruzamento (borda)"]
    UNO["Arduino UNO<br/>HC-SR04 + LEDs"] -- serial --> GW["Gateway Python<br/>contagem YOLO"]
  end
  APP["App Flutter<br/>(cidadão)"]
  DEV["Professor / Operador<br/>curl · Swagger"]
  CEM["CEMADEN<br/>alertas"]

  subgraph Azure["Microsoft Azure · rg-semaforo-566719"]
    NSG["NSG<br/>porta 80 e 22"]
    subgraph VM["VM Ubuntu 22.04 · Standard_B2als_v2"]
      subgraph Docker["Docker Compose · rede semaforo"]
        API["semaforo-api<br/>Spring Boot · usuário app<br/>8080 → 80"]
        DB[("semaforo-db<br/>Oracle 23ai Free<br/>1521 · FREEPDB1")]
        VOL[["volume<br/>semaforo-oradata"]]
      end
    end
  end

  GW -- "HTTP POST leituras / GET modo" --> NSG
  APP -- HTTP --> NSG
  DEV -- HTTP --> NSG
  NSG --> API
  API -- "JDBC (depends_on: healthy)" --> DB
  DB --- VOL
  API -- "@Scheduled 5 min" --> CEM
```

### Modelo de dados (tabelas relacionadas)

```mermaid
erDiagram
  CRUZAMENTO ||--o{ LEITURA_SENSOR : "recebe"
  CRUZAMENTO ||--o{ ALERTA : "afetado por"
  CRUZAMENTO { number id PK; varchar nome; varchar municipio; varchar uf; number limite_agua_cm; varchar modo; number verde_seg }
  LEITURA_SENSOR { number id PK; number cruzamento_id FK; number nivel_agua_cm; number carros; number pedestres; timestamp registrada_em }
  ALERTA { number id PK; number cruzamento_id FK; varchar titulo; varchar severidade; varchar fonte; number ativo }
  USUARIO { number id PK; varchar email; varchar senha; varchar papel }
```

## Estrutura do repositório

```
.
├── Dockerfile            # build multi-stage (Maven → JRE), WORKDIR /app, USER app, EXPOSE 8080
├── docker-compose.yml    # api + db, network, volume nomeado, portas, env, depends_on (healthcheck)
├── .env.example          # variáveis de ambiente (copiar para .env)
├── deploy.sh             # Azure CLI: RG, VM, NSG, instala Docker e sobe o Compose
├── destroy.sh            # Azure CLI: exclui o grupo de recursos
├── crud-demo.sh          # CRUD completo via curl
├── pom.xml
└── src/                  # código-fonte da API Java
```

## How To

### 1. Pré-requisitos (máquina local)

- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) e `az login` feito
- `git`, `curl`, `tar`, `ssh`

### 2. Provisionar e subir tudo na Azure

```bash
git clone https://github.com/theruansilva/semaforo-devops.git
cd semaforo-devops
cp .env.example .env        # opcional: troque senhas e JWT_SECRET
./deploy.sh
```

O `deploy.sh` executa, em ordem:

```bash
az group create -n rg-semaforo-566719 -l northcentralus
az vm create -g rg-semaforo-566719 -n vm-semaforo-566719 --image Ubuntu2204 \
  --size Standard_B2als_v2 --admin-username azureuser --generate-ssh-keys --public-ip-sku Standard
az vm open-port -g rg-semaforo-566719 -n vm-semaforo-566719 --port 80 --priority 1010
az vm run-command invoke -g rg-semaforo-566719 -n vm-semaforo-566719 --command-id RunShellScript \
  --scripts "curl -fsSL https://get.docker.com | sh; ...; docker compose up -d --build"
```

Ao final ele imprime o IP público. O Oracle leva ~1–2 min no primeiro start; a API só sobe depois que o banco fica `healthy`.

### 3. Acessar a VM

```bash
IP=$(az vm show -d -g rg-semaforo-566719 -n vm-semaforo-566719 --query publicIps -o tsv)
ssh azureuser@$IP
cd /opt/semaforo
```

### 4. Evidências (dentro da VM)

| Evidência | Comando |
|---|---|
| Containers executando (background) | `docker compose ps` |
| Logs | `docker compose logs api --tail 50` · `docker compose logs db --tail 20` |
| Acesso ao container | `docker compose exec api sh` |
| Usuário não-root | `docker compose exec api whoami` → `app` |
| Estrutura de diretórios | `docker compose exec api sh -c 'pwd; ls -la'` → `/app/app.jar` · `ls -la /opt/semaforo` |
| Volume nomeado | `docker volume ls` · `docker volume inspect semaforo_semaforo-oradata` |
| Rede | `docker network inspect semaforo_semaforo` |
| Variáveis de ambiente | `docker compose exec api env \| grep -E 'DB_\|PORT'` |

> O nome do volume e da rede recebe o prefixo da pasta (`semaforo_` em `/opt/semaforo`). Confira com `docker volume ls`.

### 5. CRUD funcionando

Da sua máquina (ou da VM com `http://localhost`):

```bash
./crud-demo.sh http://$IP
```

Faz login como ADMIN, cria um cruzamento (`POST 201`), registra uma leitura na tabela relacionada (`POST /cruzamentos/{id}/leituras`), lê (`GET`), atualiza (`PUT`), lista e exclui um registro temporário (`DELETE 204`, depois `GET 404`). A leitura acima do limite muda o modo do cruzamento para `ATENCAO`.

Swagger: `http://$IP/swagger-ui/index.html` · usuários de demonstração: `admin@semaforo.dev`, `operador@semaforo.dev`, `cidadao@semaforo.dev`, senha `Semaforo@2026`.

### 6. SELECT direto no banco

```bash
docker compose exec db sqlplus semaforo/Semaforo#2026@//localhost/FREEPDB1
```

```sql
SET LINESIZE 200
COLUMN nome FORMAT A40
SELECT c.id, c.nome, c.modo, l.nivel_agua_cm, l.registrada_em
  FROM cruzamento c JOIN leitura_sensor l ON l.cruzamento_id = c.id
 ORDER BY l.registrada_em DESC;
SELECT * FROM leitura_sensor;
```

### 7. Persistência

```bash
docker compose down          # remove os containers, mantém o volume
docker compose up -d
docker compose exec db sqlplus -s semaforo/Semaforo#2026@//localhost/FREEPDB1 <<< "SELECT COUNT(*) FROM cruzamento;"
```

Os registros criados antes continuam lá (dados em `/opt/oracle/oradata`, volume nomeado).

### 8. Rodar localmente (opcional)

```bash
cp .env.example .env && sed -i 's/^API_PORT=80/API_PORT=8088/' .env
docker compose up -d --build
./crud-demo.sh http://localhost:8088
```

### 9. Remover os recursos da Azure

```bash
./destroy.sh
```

## Variáveis de ambiente

| Variável | Container | Uso |
|---|---|---|
| `ORACLE_PASSWORD` | db | senha de SYS/SYSTEM |
| `DB_USER` / `DB_PASSWORD` | db e api | usuário da aplicação criado no `FREEPDB1` e usado no JDBC |
| `DB_URL` | api | `jdbc:oracle:thin:@db:1521/FREEPDB1` (o host `db` é o nome do serviço na rede do Compose) |
| `JWT_SECRET` | api | assinatura dos tokens (32+ caracteres) |
| `API_PORT` | host | porta publicada da API (padrão 80) |
| `CEMADEN_ENABLED` | api | liga a sincronização agendada de alertas |

## Links

- Vídeo (YouTube, não listado): _adicionar_
