# CI Local Environment Blocker

`BLOCKED_ENV` is a mandatory-gate blocking status for local CI failures caused by external execution environment or dependency infrastructure, not by the implementation under test.

It is not a pass and it is not a degraded success. Delivery remains blocked until the environment issue is remediated and the same gate can run honestly.

## Status Semantics

| Status | Meaning | Gate result |
|--------|---------|-------------|
| `PASS` | Local CI mirror ran and passed | allow |
| `FAIL` | Repo behavior / implementation / test failure | block; fix code or plan |
| `BLOCKED_ENV` | Mandatory gate could not run because dependency infrastructure or local network is unavailable | block; remediate environment |
| `SKIP` | Check is not applicable for current CI context | neutral |

## Evidence Schema

`ci-local.sh` evidence may use top-level `status: BLOCKED_ENV` with a `blocked_env` object:

```jsonc
{
  "status": "BLOCKED_ENV",
  "blocked_env": {
    "reason": "dns_resolution_failed",
    "stage": "install",
    "host": "nexus3.sit.exampleco.com",
    "package_manager": "pnpm",
    "registry_hosts": ["nexus3.sit.exampleco.com"],
    "output_tail": "sanitized stderr tail",
    "retry": {
      "action": "RETRY_WITH_ESCALATION",
      "context_hash": "abc123",
      "command": "bash .../ci-local-run.sh --repo ...",
      "manual_remediation": "Connect VPN or use an unsandboxed shell, then rerun the same command."
    }
  }
}
```

Initial producer work may omit `retry`; T3 of DP-046 adds retry payload and context hash handling.

Generated `ci-local.sh` producer contract:

- Top-level `status` is `BLOCKED_ENV` when any check is classified as an environment blocker.
- `summary.blocked_env_checks` counts blocked checks separately from implementation `failed_checks`.
- The first blocked check is copied to top-level `blocked_env` for gate wrappers.
- Dependency/bootstrap `BLOCKED_ENV` stops downstream checks because lint/test/typecheck results would be meaningless.
- `BLOCKED_ENV` exits non-zero and is never treated as a PASS cache hit.

## Reason Enum

| Reason | Typical signals |
|--------|-----------------|
| `dns_resolution_failed` | `getaddrinfo ENOTFOUND`, `Could not resolve host`, `Name or service not known` |
| `connection_timeout` | `ETIMEDOUT`, connection timeout, network timeout |
| `tls_or_proxy_failure` | self-signed certificate, unable to verify certificate, proxy tunnel failure, TLS / SSL / reset errors |
| `auth_required_or_forbidden` | `401`, `403`, unauthorized, forbidden, authentication required |
| `vpn_or_private_network_required` | VPN/private network hints or company-internal hosts such as `*.sit.*`, `*.internal`, `nexus*`, `artifactory*` |

## Adapter Contract

The classifier is stdlib-only and must run without repo dependencies installed.

Initial package-manager adapters:

| Package manager | Detection | Host discovery |
|-----------------|-----------|----------------|
| `pnpm` | failed command starts with `pnpm install` or category is `install` | `.npmrc` registry / scoped registry |
| `npm` | `npm install` / `npm ci` | `.npmrc` registry / scoped registry |
| `yarn` | `yarn install` | `.yarnrc.yml` `npmRegistryServer` / `npmPublishRegistry` |

Future adapters may add pip/poetry/bundler/composer/go/cargo. They must use the same evidence schema and reason enum.

## Secret Scrub Rules

Evidence may record host, stage, reason, package manager, and sanitized stderr tail. It must not write raw credentials.

Scrub at minimum:

- URL userinfo: `https://user:pass@host` → `https://***:***@host`
- bearer/basic auth headers
- npm `_authToken`
- query params named `token`, `access_token`, `secret`, `password`, `api_key`, or similar

## Gate Behavior

- `BLOCKED_ENV` exits non-zero from `ci-local.sh`.
- `BLOCKED_ENV` must not be cached as PASS.
- downstream checks should stop after dependency/bootstrap `BLOCKED_ENV`; their results would be meaningless.
- preflight host discovery is advisory only. It must not block when the actual install command succeeds.

## Retry / Escalation Boundary

`ci-local-run.sh` owns the portable retry ladder:

1. Run the canonical generated `ci-local.sh` once.
2. If evidence status is `BLOCKED_ENV`, rerun the same canonical command once with the same repo path, event, base branch, source branch, ref, and HEAD.
3. If the second evidence is still `BLOCKED_ENV`, verify branch/head/context hash match the first run.
4. Emit a runtime-neutral `RETRY_WITH_ESCALATION` payload and exit non-zero.

The framework core never performs elevated execution. Codex may translate the payload into `require_escalated`; Claude or a human shell may use the same command manually after VPN/proxy/registry remediation.

Context hash is derived from `event|base_branch|source_branch|ref`. A retry with different branch/head/context must hard stop instead of producing an escalation payload.
