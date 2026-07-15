# 🔧 Wootrico License Disable Patches

Desabilita permanentemente a verificação de licença no **Wootrico** (fork AstraOnline).

> ⚠️ **Aviso**: Este repositório contém patches para uso próprio. Use por sua conta e risco.

## 📂 Estrutura

```
wootrico-patches/
├── patch-panelapi.js       # Patch para o bundle do panel-api (server.cjs)
├── patch-worker.js         # Patch para o bundle do worker (main.cjs)
├── apply-patches.sh        # Script automático para aplicar patches
└── README.md               # Este arquivo
```

## 🔍 O que os patches fazem

| Função | Comportamento Original | Comportamento Patchado |
|---|---|---|
| `computeStatus()` | Verifica DB, expiração, heartbeat | ✅ Sempre retorna `"active"` |
| `evaluateLicense()` | Consulta status no DB | ✅ Sempre retorna `"active"` |
| `isProcessingAllowed()` | Bloqueia se não for active/warning | ✅ Sempre `true` |
| `assertLicenseActive()` | Bloqueia processamento | ✅ Sempre `{ allowed: true }` |
| `runHeartbeat()` | Faz fetch para servidor de licença | ✅ Retorna `{ status: "active" }` (sem rede) |
| `ensureLicenseSecret()` | Busca secret do servidor | ✅ Retorna `null` (ignorado) |

**Resultado:** ❌ Sem chamadas de rede · ❌ Sem verificação de expiração · ✅ Sempre ativo

## 🚀 Como usar

### Opção 1: Script automático (recomendado)

```bash
# Clone o repositório no servidor
git clone https://github.com/pvbarbosa/wootrico-patches.git
cd wootrico-patches

# Execute o script (com os serviços do wootrico rodando)
bash apply-patches.sh
```

O script faz tudo automaticamente:
1. Localiza os containers do wootrico
2. Copia e aplica os patches nos bundles compilados
3. Atualiza a licença no banco de dados
4. Commita uma nova imagem Docker
5. Atualiza os serviços
6. Valida o resultado

### Opção 2: Manual (passo a passo)

```bash
# 1. Clone o repositório
git clone https://github.com/pvbarbosa/wootrico-patches.git
cd wootrico-patches

# 2. Descobrir os containers
CID_APP=$(docker ps --filter name=wootrico_app --format '{{.ID}}' | head -1)
CID_WORKER=$(docker ps --filter name=wootrico_worker --format '{{.ID}}' | head -1)

# 3. Aplicar patches no panel-api
docker cp patch-panelapi.js $CID_APP:/tmp/
docker exec $CID_APP node /tmp/patch-panelapi.js

# 4. Aplicar patches no worker
docker cp patch-worker.js $CID_WORKER:/tmp/
docker exec $CID_WORKER node /tmp/patch-worker.js

# 5. Validar sintaxe
docker exec $CID_APP node --check /app/apps/panel-api/dist/server.cjs
docker exec $CID_WORKER node --check /app/apps/worker/dist/main.cjs

# 6. Ativar licença no banco de dados
DB_CID=$(docker ps --filter name=postgres --format '{{.ID}}' | head -1)
docker exec $DB_CID psql -U postgres -d wootrico -c "
  UPDATE license_state
  SET status = 'active', plan = 'paid',
      expires_at = '2030-12-31 23:59:59',
      last_error = NULL, last_validated_at = NOW(),
      next_heartbeat_at = NOW(), heartbeat_failures = 0
  WHERE id = 'singleton';
"

# 7. Commit da imagem
docker commit $CID_WORKER ericoautomacao/wootrico-v2:premium

# 8. Atualizar serviços (use --force!)
docker service update --force --image ericoautomacao/wootrico-v2:premium wootrico_app
docker service update --force --image ericoautomacao/wootrico-v2:premium wootrico_worker
```

### 🔄 Por que --force é essencial?

Os patches são aplicados nos **arquivos JS compilados** dentro do container. Porém, o **Node.js cacheia os módulos em memória** quando o processo inicia. Se você apenas atualizar o serviço sem `--force`:

1. ✅ Arquivo no disco é patcheado corretamente
2. ❌ Processo Node.js CONTINUA usando as funções antigas em memória
3. ❌ A verificação de licença ainda acontece com o código original

Com `--force`:
1. ✅ Container é destruído e recriado
2. ✅ Node.js carrega o arquivo patcheado do disco
3. ✅ Patches entram em vigor

> ⚠️ **IMPORTANTE**: Sempre use `--force` no `docker service update` após aplicar patches! Caso contrário, o Swarm pode não reiniciar os containers se a tag da imagem for a mesma.

## ✅ Verificação

Para confirmar que os patches estão funcionando:

```bash
# Verificar se o computeStatus foi patcheado
docker exec $(docker ps --filter name=wootrico_app --format '{{.ID}}' | head -1) \
  sh -c 'grep -A2 "function computeStatus" /app/apps/panel-api/dist/server.cjs'

# Deve retornar: function computeStatus() { return "active"; }

# Verificar status da licença no DB
docker exec $(docker ps --filter name=postgres --format '{{.ID}}' | head -1) \
  psql -U postgres -d wootrico -c "SELECT status, plan, expires_at FROM license_state WHERE id='singleton';"

# Deve retornar: active | paid | 2030-12-31
```

## 🔄 Reverter para a imagem original

```bash
docker service update --image ericoautomacao/wootrico-v2:latest wootrico_app
docker service update --image ericoautomacao/wootrico-v2:latest wootrico_worker
```

## ⚠️ Importante

- Os patches atuam nos **bundles JS compilados** (TypeScript → JS)
- Após atualizar a versão base do wootrico, **re-execute o script**
- Os patches originais em TypeScript (`/app/packages/license-client/src/`) também foram modificados no servidor, mas como o app roda do bundle compilado, apenas os patches nos `.cjs` têm efeito
