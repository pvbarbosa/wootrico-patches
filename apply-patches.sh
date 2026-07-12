#!/bin/bash
# =============================================================================
# apply-patches.sh - Wootrico License Disable Patches
# =============================================================================
# Aplica patches para desabilitar permanentemente a verificação de licença
# no Wootrico (fork AstraOnline).
#
# Como usar:
#   1. Certifique-se que os serviços do wootrico estão rodando
#   2. Execute: bash apply-patches.sh
#
# O script:
#   1. Localiza os containers do wootrico
#   2. Copia os scripts de patch para dentro dos containers
#   3. Aplica os patches nos bundles compilados (panel-api e worker)
#   4. Atualiza o status da licença no banco de dados
#   5. Commita uma nova imagem Docker
#   6. Atualiza os serviços para usar a nova imagem
#   7. Valida que tudo está funcionando
# =============================================================================

set -e

# ============================================
# Configurações (altere se necessário)
# ============================================
IMAGE_NAME="ericoautomacao/wootrico-v2:premium"
PATCHES_DIR="$(cd "$(dirname "$0")" && pwd)"
DB_CONTAINER_FILTER="name=postgres"
DB_NAME="wootrico"
DB_USER="postgres"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN} Wootrico License Disable Patch${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# ============================================
# Passo 1: Localizar containers
# ============================================
echo -e "${YELLOW}[1/7]${NC} Localizando containers do wootrico..."

APP_CID=$(docker ps --filter name=wootrico_app --format '{{.ID}}' | head -1)
WORKER_CID=$(docker ps --filter name=wootrico_worker --format '{{.ID}}' | head -1)

if [ -z "$APP_CID" ]; then
  echo -e "${RED}ERRO: Container wootrico_app nao encontrado!${NC}"
  echo "Certifique-se que os servicos estao rodando."
  exit 1
fi
echo "  App container:    $APP_CID"
echo "  Worker container: $WORKER_CID"
echo ""

# ============================================
# Passo 2: Copiar patches para os containers
# ============================================
echo -e "${YELLOW}[2/7]${NC} Copiando scripts de patch para os containers..."

docker cp "$PATCHES_DIR/patch-panelapi.js" "$APP_CID:/tmp/patch-panelapi.js"
echo "  patch-panelapi.js -> app container"

if [ -n "$WORKER_CID" ]; then
  docker cp "$PATCHES_DIR/patch-worker.js" "$WORKER_CID:/tmp/patch-worker.js"
  echo "  patch-worker.js -> worker container"
fi
echo ""

# ============================================
# Passo 3: Aplicar patches nos bundles
# ============================================
echo -e "${YELLOW}[3/7]${NC} Aplicando patches nos bundles compilados..."

# Patch no panel-api (app container)
echo "  Patchando panel-api (server.cjs)..."
docker exec "$APP_CID" node /tmp/patch-panelapi.js

# Patch no worker (worker container) - se existir
if [ -n "$WORKER_CID" ]; then
  echo "  Patchando worker (main.cjs)..."
  docker exec "$WORKER_CID" node /tmp/patch-worker.js
fi

# Verificar se o worker tem o bundle do panel-api e aplicar tambem
docker exec "$WORKER_CID" ls /app/apps/panel-api/dist/server.cjs 2>/dev/null && \
  docker cp "$PATCHES_DIR/patch-panelapi.js" "$WORKER_CID:/tmp/patch-panelapi.js" && \
  docker exec "$WORKER_CID" node /tmp/patch-panelapi.js && \
  echo "  Panel-api tambem patchado no worker container"

# Verificar se o app tem o bundle do worker e aplicar tambem
docker exec "$APP_CID" ls /app/apps/worker/dist/main.cjs 2>/dev/null && \
  docker cp "$PATCHES_DIR/patch-worker.js" "$APP_CID:/tmp/patch-worker.js" && \
  docker exec "$APP_CID" node /tmp/patch-worker.js && \
  echo "  Worker tambem patchado no app container"

echo ""

# ============================================
# Passo 4: Validar sintaxe dos bundles
# ============================================
echo -e "${YELLOW}[4/7]${NC} Validando sintaxe dos bundles..."

docker exec "$APP_CID" node --check /app/apps/panel-api/dist/server.cjs && \
  echo -e "  ${GREEN}Panel-api: sintaxe OK${NC}" || \
  echo -e "  ${RED}Panel-api: ERRO de sintaxe!${NC}"

docker exec "$WORKER_CID" node --check /app/apps/worker/dist/main.cjs && \
  echo -e "  ${GREEN}Worker: sintaxe OK${NC}" || \
  echo -e "  ${RED}Worker: ERRO de sintaxe!${NC}"
echo ""

# ============================================
# Passo 5: Atualizar licenca no banco de dados
# ============================================
echo -e "${YELLOW}[5/7]${NC} Atualizando status da licenca no banco de dados..."

DB_CID=$(docker ps --filter "$DB_CONTAINER_FILTER" --format '{{.ID}}' | head -1)

if [ -n "$DB_CID" ]; then
  docker exec "$DB_CID" psql -U "$DB_USER" -d "$DB_NAME" -c "
    UPDATE license_state
    SET status = 'active',
        plan = 'paid',
        expires_at = '2030-12-31 23:59:59',
        last_error = NULL,
        last_validated_at = NOW(),
        next_heartbeat_at = NOW(),
        heartbeat_failures = 0
    WHERE id = 'singleton';
  " 2>/dev/null && echo -e "  ${GREEN}Licenca ativada no banco de dados!${NC}" \
    || echo -e "  ${YELLOW}Aviso: Nao foi possivel atualizar o banco (pode ser necessario fazer manualmente)${NC}"
else
  echo -e "  ${YELLOW}Aviso: Container do banco nao encontrado. Execute manualmente o UPDATE.${NC}"
fi
echo ""

# ============================================
# Passo 6: Commitar imagem e atualizar servicos
# ============================================
echo -e "${YELLOW}[6/7]${NC} Criando nova imagem Docker e atualizando servicos..."

# Commitar a imagem a partir do worker (que tem ambos os bundles)
if [ -n "$WORKER_CID" ]; then
  echo "  Commitando imagem a partir do worker container..."
  docker commit "$WORKER_CID" "$IMAGE_NAME"
else
  echo "  Commitando imagem a partir do app container..."
  docker commit "$APP_CID" "$IMAGE_NAME"
fi
echo -e "  ${GREEN}Imagem criada: $IMAGE_NAME${NC}"

# Atualizar servicos
echo "  Atualizando servico wootrico_app..."
docker service update --image "$IMAGE_NAME" wootrico_app 2>&1 | tail -1

echo "  Atualizando servico wootrico_worker..."
docker service update --image "$IMAGE_NAME" wootrico_worker 2>&1 | tail -1
echo ""

# ============================================
# Passo 7: Validacao final
# ============================================
echo -e "${YELLOW}[7/7]${NC} Aguardando servicos estabilizarem e validando..."
sleep 15

echo ""
echo "  Verificando servicos..."
docker service ls --filter name=wootrico --format 'table {{.Name}}\t{{.Replicas}}\t{{.Image}}'

echo ""
# Verificar patches no novo container
NEW_APP=$(docker ps --filter name=wootrico_app --format '{{.ID}}' | head -1)
if [ -n "$NEW_APP" ]; then
  STATUS=$(docker exec "$NEW_APP" node -e "
    const fs=require('fs');
    const c=fs.readFileSync('/app/apps/panel-api/dist/server.cjs','utf8');
    console.log(c.includes('function computeStatus()') ? 'computeStatus: OK' : 'computeStatus: NAO ENCONTRADO');
    console.log(c.includes('return \"active\"') ? 'retorno active: OK' : 'retorno active: NAO ENCONTRADO');
  " 2>&1)
  echo "  $STATUS"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN} ✅ Patches aplicados com sucesso!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Para verificar manualmente:"
echo "  docker exec -it \$(docker ps --filter name=wootrico_app --format '{{.ID}}' | head -1) sh"
echo "  grep -A2 'function computeStatus' /app/apps/panel-api/dist/server.cjs"
echo ""
echo "Se precisar reverter para a imagem original:"
echo "  docker service update --image ericoautomacao/wootrico-v2:latest wootrico_app"
echo "  docker service update --image ericoautomacao/wootrico-v2:latest wootrico_worker"
