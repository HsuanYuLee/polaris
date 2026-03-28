# 環境變數新增流程

## 最高原則：禁止 commit 任何可用的 key / token / secret 到 repo

**任何環境（包含 SIT）的真實 token、API key、secret 都不可出現在 commit 中。** `.env` 是 tracked file，裡面的 secret 類變數必須留空或填 placeholder，真實值放 `.env.local`（gitignored）。

## 核心原則：先查 ansible，再決定要不要開新變數

新增環境變數時，必須同步更新 `.env`（開發用）和 `.env.template`（部署用）。部署環境的值由 ansible 注入，不是 `.env` 裡的值。

## 標準流程

### Step 1：查 ansible 是否有既有變數

```bash
# 搜尋目標 service 的 kk_service 設定
# ansible repo 路徑從公司 config 的 infra.ansible_repo 讀取（參考 references/workspace-config-reader.md）
gh api repos/{ansible_repo}/contents/inventories/production/group_vars/all/kk_service \
  --jq '.content' | base64 -d | grep -i -A10 '<SERVICE_NAME>'

# 也搜尋 SIT 環境（infra.ansible_sit_repo，fallback: your-org/your-ansible-sit）
gh api repos/{ansible_sit_repo}/contents/inventories/sit/group_vars/all/kk_service \
  --jq '.content' | base64 -d | grep -i -A10 '<SERVICE_NAME>'
```

常見已存在的 service（`KK_SERVICE.*`）：
- `LANG_API` — api-lang
- `RECOMMEND_API` — recommend
- `REVIEW_API` — review
- `CHATBOT_API` — chatbot
- `PC_WWW` — your-backend (PHP)
- `KTM_API`, `KHSR_API`, `B2C_SVC`, `MEMBER_SVC` 等

### Step 2：更新 `.env`（開發用，commit 進 repo）

**只宣告變數名稱，值留空。** 真實值（URL、token 等）放 `.env.local`（gitignored），由開發者自行設定。

```bash
# .env（committed）— 只宣告變數存在
API_LANG_BASE_URL=
API_LANG_TOKEN_KEY=

# .env.local（gitignored，開發者自行設定）
API_LANG_BASE_URL=https://api-lang.sit.example.com/api/
API_LANG_TOKEN_KEY=V3NlZ0Nx...（SIT token）
```

### Step 3：更新 `.env.template`（部署用）

依照 ansible 的 kk_service 定義，使用 Jinja2 template 語法：

```bash
# Base URL — 用 KK_SERVICE 的 PRIVATE_PROTOCOL + DOMAIN（走內網）
API_LANG_BASE_URL={{ KK_SERVICE.LANG_API.PRIVATE_PROTOCOL }}://{{ KK_SERVICE.LANG_API.DOMAIN }}/api/

# Secret — 用 ## PLACEHOLDER ## 格式，由 Config Manager 注入
API_LANG_TOKEN_KEY=## API_LANG_TOKEN_KEY ##
```

**三種注入模式**（優先順序由上而下）：
| 模式 | `.env.template` 語法 | 來源 | 適用 |
|------|----------------------|------|------|
| Ansible 變數 | `{{ KK_SERVICE.XXX.YYY }}` | kk_service YAML | URL、非機敏設定 |
| Ansible vault | `{{ KK_SERVICE.XXX.CUSTOM_VARS.YOUR_ORG.TOKEN }}` | vault 加密值 | token、key（優先用此方式） |
| Config Manager | `## VARIABLE_NAME ##` | Config Manager UI | vault 中不存在的 secret |

### Step 4：確認部署環境的 secret 來源

Secret 類型的變數優先用 ansible vault 引用（如 `{{ KK_SERVICE.LANG_API.CUSTOM_VARS.YOUR_ORG.READ_ACCESS_TOKEN }}`），不需額外到 Config Manager 加值。若 vault 中沒有，才用 `## PLACEHOLDER ##` 搭配 Config Manager。

### Step 5：更新 `turbo.json`（如適用）

Nuxt 專案（your-app）使用 Turborepo，新 env var 要加到 `turbo.json` 的 `globalEnv` 確保 cache invalidation。

## 常見模式參考

以 your-app 的 `.env.template` 為例：

```bash
# API base URL — 走內網
PHP_API_BASE_URL={{ KK_SERVICE.PC_WWW.PRIVATE_PROTOCOL }}://{{ KK_SERVICE.PC_WWW.INTERNAL_DOMAIN }}
CHATBOT_API_BASE_URL={{ KK_SERVICE.CHATBOT_API.PRIVATE_PROTOCOL }}://{{ KK_SERVICE.CHATBOT_API.DOMAIN }}/api/

# Secrets — 優先用 ansible vault 引用
API_LANG_TOKEN_KEY={{ KK_SERVICE.LANG_API.CUSTOM_VARS.YOUR_ORG.READ_ACCESS_TOKEN }}

# Secrets — vault 沒有時才用 Config Manager
API_KEY_SVC_B2C=## API_KEY_SVC_B2C ##
CHATBOT_API_AUTH_KEY=## CHATBOT_API_AUTH_KEY ##

# 非 Secret 的常數 — 直接寫值或 ansible 變數
VITE_ROOT_ENV={{ ROOT_ENV }}
```

## Do / Don't

- **Do**：先查 ansible，用既有 service 的 `PRIVATE_PROTOCOL` + `DOMAIN`（走內網更快）
- **Do**：`.env` 和 `.env.template` 同步更新
- **Do**：secret 類變數在 `.env` 留空，真實值放 `.env.local`（gitignored）
- **Do**：`.env.template` 的 secret 優先用 ansible vault 引用（`{{ KK_SERVICE.XXX.CUSTOM_VARS.YOUR_ORG.TOKEN }}`）
- **Don't**：**在 `.env` 放任何環境的真實 token / key / secret**（包含 SIT），這是 commit 進 repo 的檔案
- **Don't**：只改 `.env` 不改 `.env.template`（部署時變數會是空的）
- **Don't**：在 `.env.template` 放 hardcoded 的 URL 或 token（應該用 ansible 變數或 vault）
