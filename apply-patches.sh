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
#   4. Valida a sintaxe dos bundles
#   5. Atualiza o status da licença no banco de dados
#   6. Commita uma nova imagem Docker e atualiza os serviços
#   7. Valida que tudo está funcionando
# =============================================================================

set -e

# ============================================
# Configurações (altere se necessário)
# ============================================
# IMAGE_NAME será auto-detectado se não for definido
IMAGE_NAME="${IMAGE_NAME:-}"
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
  echo ""
  echo "Para ver os servicos disponiveis:"
  echo "  docker service ls --filter name=wootrico"
  exit 1
fi
echo "  App container:    $APP_CID"
echo "  Worker container: ${WORKER_CID:-nao encontrado}"
echo ""

# Auto-detectar IMAGE_NAME se não foi configurado
if [ -z "$IMAGE_NAME" ]; then
  IMAGE_NAME=$(docker service ls --filter name=wootrico_app --format '{{.Image}}' | head -1)
  echo -e "${YELLOW}  Imagem auto-detectada:${NC} $IMAGE_NAME"
  echo "  (Defina IMAGE_NAME antes de executar para sobrescrever)"
  echo ""
fi

# ============================================
# Passo 2: Copiar patches para os containers
# ============================================
echo -e "${YELLOW}[2/7]${NC} Copiando scripts de patch para os containers..."

docker cp "$PATCHES_DIR/patch-panelapi.js" "$APP_CID:/tmp/patch-panelapi.js" && \
  echo "  patch-panelapi.js -> app container"

if [ -n "$WORKER_CID" ]; then
  docker cp "$PATCHES_DIR/patch-worker.js" "$WORKER_CID:/tmp/patch-worker.js" && \
    echo "  patch-worker.js -> worker container"
fi

# Ambos os bundles existem nos dois containers, então aplicar em ambos
if [ -n "$WORKER_CID" ]; then
  docker cp "$PATCHES_DIR/patch-panelapi.js" "$WORKER_CID:/tmp/patch-panelapi.js" 2>/dev/null && \
    echo "  patch-panelapi.js -> worker container"
fi
docker cp "$PATCHES_DIR/patch-worker.js" "$APP_CID:/tmp/patch-worker.js" 2>/dev/null && \
  echo "  patch-worker.js -> app container"
echo ""

# ============================================
# Passo 3: Aplicar patches nos bundles
# ============================================
echo -e "${YELLOW}[3/7]${NC} Aplicando patches nos bundles compilados..."

# Patch no panel-api (todos os containers que tem o bundle)
echo "  Patchando panel-api..."
docker exec "$APP_CID" node /tmp/patch-panelapi.js 2>&1
if [ -n "$WORKER_CID" ]; then
  docker exec "$WORKER_CID" node /tmp/patch-panelapi.js 2>&1
fi

# Patch no worker (todos os containers que tem o bundle)
echo "  Patchando worker..."
docker exec "$APP_CID" node /tmp/patch-worker.js 2>&1
if [ -n "$WORKER_CID" ]; then
  docker exec "$WORKER_CID" node /tmp/patch-worker.js 2>&1
fi

echo ""

# ============================================
# Passo 4: Validar sintaxe dos bundles
# ============================================
echo -e "${YELLOW}[4/7]${NC} Validando sintaxe dos bundles..."

docker exec "$APP_CID" node --check /app/apps/panel-api/dist/server.cjs && \
  echo -e "  ${GREEN}App Panel-api: sintaxe OK${NC}" || \
  echo -e "  ${RED}App Panel-api: ERRO de sintaxe!${NC}"

docker exec "$APP_CID" node --check /app/apps/worker/dist/main.cjs && \
  echo -e "  ${GREEN}App Worker: sintaxe OK${NC}" || \
  echo -e "  ${RED}App Worker: ERRO de sintaxe!${NC}"

if [ -n "$WORKER_CID" ]; then
  docker exec "$WORKER_CID" node --check /app/apps/panel-api/dist/server.cjs && \
    echo -e "  ${GREEN}Worker Panel-api: sintaxe OK${NC}" || \
    echo -e "  ${RED}Worker Panel-api: ERRO de sintaxe!${NC}"

  docker exec "$WORKER_CID" node --check /app/apps/worker/dist/main.cjs && \
    echo -e "  ${GREEN}Worker Worker: sintaxe OK${NC}" || \
    echo -e "  ${RED}Worker Worker: ERRO de sintaxe!${NC}"
fi
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

# Commitar a imagem a partir do worker (preferencial) ou app
if [ -n "$WORKER_CID" ]; then
  echo "  Commitando imagem a partir do worker container..."
  docker commit "$WORKER_CID" "$IMAGE_NAME" || {
    echo -e "${RED}ERRO: Falha ao commitar imagem do worker${NC}"
    exit 1
  }
else
  echo "  Commitando imagem a partir do app container..."
  docker commit "$APP_CID" "$IMAGE_NAME" || {
    echo -e "${RED}ERRO: Falha ao commitar imagem do app${NC}"
    exit 1
  }
fi
echo -e "  ${GREEN}Imagem criada: $IMAGE_NAME${NC}"

# Atualizar servicos com verificacao de erro
#
# IMPORTANTE: Usamos --force para garantir que o Swarm recrie os containers.
# Sem o --force, se a tag da imagem for a mesma (ex: "premium"), o Swarm
# pode nao reiniciar os containers porque o node do servico ja esta rodando
# com aquela tag. Isso faz com que os patches fiquem apenas no arquivo em
# disco, mas o processo Node.js continua usando as funcoes antigas em memoria
# (modulos cacheados). O --force força a recriacao do container.
echo "  Atualizando servico wootrico_app (--force)..."
docker service update --force --image "$IMAGE_NAME" wootrico_app 2>&1 | tail -5 || {
  echo -e "${RED}ERRO: Falha ao atualizar servico wootrico_app${NC}"
  exit 1
}

echo "  Atualizando servico wootrico_worker (--force)..."
docker service update --force --image "$IMAGE_NAME" wootrico_worker 2>&1 | tail -5 || {
  echo -e "${RED}ERRO: Falha ao atualizar servico wootrico_worker${NC}"
  exit 1
}
echo ""

# ============================================
# Passo 7: Validacao final
# ============================================
echo -e "${YELLOW}[7/7]${NC} Aguardando servicos estabilizarem e validando..."

# Loop de espera em vez de sleep fixo
for i in $(seq 1 30); do
  REPLICAS=$(docker service ls --filter name=wootrico_app --format '{{.Replicas}}')
  if echo "$REPLICAS" | grep -q "1/1"; then
    echo "  Servicos estaveis apos ${i}s"
    break
  fi
  sleep 2
done

echo ""
echo "  Verificando servicos..."
docker service ls --filter name=wootrico --format 'table {{.Name}}\t{{.Replicas}}\t{{.Image}}'

echo ""
# Verificar patches nos novos containers
NEW_APP=$(docker ps --filter name=wootrico_app --format '{{.ID}}' | head -1)
NEW_WORKER=$(docker ps --filter name=wootrico_worker --format '{{.ID}}' | head -1)

if [ -n "$NEW_APP" ]; then
  echo "  --- App container ---"
  docker exec "$NEW_APP" node -e "
    const fs=require('fs');
    const c=fs.readFileSync('/app/apps/panel-api/dist/server.cjs','utf8');
    console.log('  PanelAPI computeStatus():', c.includes('function computeStatus()') ? 'OK' : 'NAO ENCONTRADO');
    console.log('  PanelAPI evaluateLicense():', c.includes('async function evaluateLicense() { return') ? 'OK' : 'NAO ENCONTRADO');
    console.log('  PanelAPI runHeartbeat():', c.includes('async function runHeartbeat() { return') ? 'OK' : 'NAO ENCONTRADO');
  " 2>&1
fi

if [ -n "$NEW_WORKER" ]; then
  echo "  --- Worker container ---"
  docker exec "$NEW_WORKER" node -e "
    const fs=require('fs');
    const w=fs.readFileSync('/app/apps/worker/dist/main.cjs','utf8');
    console.log('  Worker computeStatus():', w.includes('function computeStatus() { return') ? 'OK' : 'NAO ENCONTRADO');
    console.log('  Worker assertLicenseActive():', w.includes('async function assertLicenseActive()') && w.includes('allowed: true') ? 'OK' : 'NAO ENCONTRADO');
    console.log('  Worker runHeartbeat():', w.includes('async function runHeartbeat() { return') ? 'OK' : 'NAO ENCONTRADO');
  " 2>&1
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
