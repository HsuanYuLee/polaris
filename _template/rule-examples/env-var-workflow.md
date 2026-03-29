# Environment Variable Workflow

## Top Rule: Never commit any usable key / token / secret to the repo

**Real tokens, API keys, and secrets for ANY environment (including SIT/staging) must never appear in a commit.** `.env` is a tracked file — secret variables must be left empty or use a placeholder. Real values go in `.env.local` (gitignored).

## Core Principle: Check ansible first, then decide whether to create a new variable

When adding environment variables, always update both `.env` (dev) and `.env.template` (deployment). Deployment values are injected by ansible, not from `.env`.

## Standard Workflow

### Step 1: Check ansible for existing variables

```bash
# Search target service's app_service config
# ansible repo path: read from workspace config `infra.ansible_repo` (see references/workspace-config-reader.md)
gh api repos/{ansible_repo}/contents/inventories/production/group_vars/all/app_service \
  --jq '.content' | base64 -d | grep -i -A10 '<SERVICE_NAME>'

# Also search SIT environment (workspace config `infra.ansible_sit_repo`)
gh api repos/{ansible_sit_repo}/contents/inventories/sit/group_vars/all/app_service \
  --jq '.content' | base64 -d | grep -i -A10 '<SERVICE_NAME>'
```

> Check your own ansible `app_service` inventory for available service keys. Each company will have different service definitions.

### Step 2: Update `.env` (dev, committed to repo)

**Only declare variable names, leave values empty.** Real values (URLs, tokens) go in `.env.local` (gitignored), set by each developer.

```bash
# .env (committed) — only declare variable existence
YOUR_API_BASE_URL=
YOUR_API_TOKEN_KEY=

# .env.local (gitignored, developer sets locally)
YOUR_API_BASE_URL=https://your-service.sit.example.com/api/
YOUR_API_TOKEN_KEY=<your-sit-token-here>
```

### Step 3: Update `.env.template` (deployment)

Use Jinja2 template syntax based on ansible's app_service definitions:

```bash
# Base URL — use APP_SERVICE PRIVATE_PROTOCOL + DOMAIN (internal network)
YOUR_API_BASE_URL={{ APP_SERVICE.YOUR_SERVICE.PRIVATE_PROTOCOL }}://{{ APP_SERVICE.YOUR_SERVICE.DOMAIN }}/api/

# Secret — use ## PLACEHOLDER ## format, injected by Config Manager
YOUR_API_TOKEN_KEY=## YOUR_API_TOKEN_KEY ##
```

**Three injection modes** (priority top-down):
| Mode | `.env.template` Syntax | Source | Use For |
|------|----------------------|--------|---------|
| Ansible variable | `{{ APP_SERVICE.XXX.YYY }}` | app_service YAML | URLs, non-sensitive config |
| Ansible vault | `{{ APP_SERVICE.XXX.CUSTOM_VARS.{COMPANY}.TOKEN }}` | vault encrypted value | tokens, keys (prefer this) |
| Config Manager | `## VARIABLE_NAME ##` | Config Manager UI | secrets not in vault |

### Step 4: Confirm deployment secret source

Secret variables should preferably use ansible vault references (e.g., `{{ APP_SERVICE.YOUR_SERVICE.CUSTOM_VARS.{COMPANY}.READ_ACCESS_TOKEN }}`). Only use `## PLACEHOLDER ##` with Config Manager when the vault doesn't have the value.

### Step 5: Update `turbo.json` (if applicable)

Nuxt projects using Turborepo need new env vars added to `turbo.json`'s `globalEnv` for cache invalidation.

## Example Patterns

```bash
# API base URL — internal network
YOUR_PHP_API_BASE_URL={{ APP_SERVICE.YOUR_PHP_SERVICE.PRIVATE_PROTOCOL }}://{{ APP_SERVICE.YOUR_PHP_SERVICE.INTERNAL_DOMAIN }}
YOUR_CHATBOT_BASE_URL={{ APP_SERVICE.YOUR_CHATBOT.PRIVATE_PROTOCOL }}://{{ APP_SERVICE.YOUR_CHATBOT.DOMAIN }}/api/

# Secrets — prefer ansible vault
YOUR_API_TOKEN={{ APP_SERVICE.YOUR_SERVICE.CUSTOM_VARS.{COMPANY}.READ_ACCESS_TOKEN }}

# Secrets — Config Manager fallback
YOUR_API_KEY=## YOUR_API_KEY ##
YOUR_AUTH_KEY=## YOUR_AUTH_KEY ##

# Non-secret constants — direct values or ansible variables
VITE_ROOT_ENV={{ ROOT_ENV }}
```

## Do / Don't

- **Do**: Check ansible first, use existing service's `PRIVATE_PROTOCOL` + `DOMAIN` (internal network is faster)
- **Do**: Update `.env` and `.env.template` together
- **Do**: Leave secret variables empty in `.env`, real values in `.env.local` (gitignored)
- **Do**: Prefer ansible vault references for secrets in `.env.template`
- **Don't**: **Put any real token / key / secret in `.env`** (including SIT) — this file is committed to the repo
- **Don't**: Only update `.env` without `.env.template` (deployment will have empty values)
- **Don't**: Put hardcoded URLs or tokens in `.env.template` (use ansible variables or vault)
