# API Contract Guard

Detects schema drift between Mockoon fixtures and live API responses. Prevents stale fixtures from masking real API changes that affect the UI.

## Problem

Mockoon fixtures stabilize test data (no false positives from API fluctuation), but stale fixtures hide real API contract changes (false negatives — real breakdowns go undetected).

## Drift Classification

| Category | Definition | Example | Action |
|----------|-----------|---------|--------|
| **Breaking** | Field removed, type changed, structure changed | `price: number` → `price: string`; field deleted | Block downstream task. Flag for dev work (type update, component fix) |
| **Additive** | New field added, existing fields unchanged | New `discount_info` object in response | Auto-update fixture. Evaluate if UI should use the new field |
| **Value-only** | Same schema, different values | `name: "A"` → `name: "B"` | Auto-update fixture if running in refresh mode. No dev work |

## When to Run

| Caller | Trigger point | Scope |
|--------|--------------|-------|
| `visual-regression` | Pre-screenshot (before Step 3) | All fixture routes for the VR domain set |
| `engineering` | Pre-verification (before implementation) | Fixture routes matching the bug's affected endpoints |
| `engineering` | Pre-implementation (Phase 2 start) | Fixture routes matching the ticket's affected pages |
| `engineering` (engineer-delivery-flow Step 3) | Pre-verification | Same as engineering |
| Manual | `contract-check.sh` CLI | User-specified scope |

## Prerequisites

The contract check requires live API access:

1. **Docker nginx running** — `polaris-env.sh start {company} --docker-only` or full `--vr`
2. **Network access to SIT/dev domains** — routes hit `proxyHost` (e.g., `https://api-lang.sit.example.com`)

If Docker is not running, the check should **warn and skip** (not block). The caller decides whether to proceed without the check.

## Script Interface

```bash
# Check all fixtures for an epic (path per references/epic-folder-structure.md)
contract-check.sh --env-dir {company_specs_dir}/PROJ-123/tests/mockoon

# Check specific environment file
contract-check.sh --file <environment.json>

# Output format
contract-check.sh --env-dir {company_specs_dir}/PROJ-123/tests/mockoon --format json|text
```

### Output Structure

```json
{
  "checked_at": "2026-04-10T14:30:00Z",
  "epic": "PROJ-123",
  "files": [
    {
      "file": "dev.yourapp.com.json",
      "proxy_host": "https://dev.yourapp.com",
      "routes": [
        {
          "method": "GET",
          "endpoint": "/api/v2/product/123",
          "status": "breaking",
          "diffs": [
            { "path": ".data.price", "fixture_type": "number", "live_type": "string" },
            { "path": ".data.discount_info", "fixture": "missing", "live": "object" }
          ]
        }
      ]
    }
  ],
  "summary": {
    "total_routes": 26,
    "checked": 24,
    "skipped": 2,
    "breaking": 1,
    "additive": 3,
    "value_only": 8,
    "unchanged": 12
  }
}
```

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | No breaking drift |
| 1 | Breaking drift detected |
| 2 | Environment not reachable (Docker not running, network error) |
| 3 | Invalid arguments |

## Schema Comparison Rules

### How to compare

For each route in the fixture file:

1. Parse `routes[i].responses[0].body` as JSON (the fixture response)
2. Build the live URL: `proxyHost + endpoint`
3. `curl` the live URL with the same HTTP method
4. Compare the two JSON structures recursively

### What counts as "schema"

| Check | Breaking? | Example |
|-------|-----------|---------|
| Key exists in fixture but not in live | Yes (removed) | `{a: 1}` vs `{}` |
| Key exists in live but not in fixture | No (additive) | `{}` vs `{a: 1}` |
| Value type changed | Yes | `string` → `number` |
| Null ↔ non-null | Yes | `null` → `"hello"` |
| Array element structure changed | Yes | `[{a:1}]` → `[{a:"x"}]` |
| Array length different | No (value-only) | `[1,2]` → `[1,2,3]` |
| Value different, same type | No (value-only) | `"A"` → `"B"` |

### Edge cases

- **Empty fixture body**: skip (no schema to compare)
- **Non-JSON response** (HTML error page): mark as `error`, don't classify
- **Auth-required endpoint returns 401/403**: mark as `auth_required`, skip
- **Timeout**: mark as `timeout`, skip
- **Multiple responses per route** (`responses[]` length > 1): compare `responses[0]` only (default response)

## Skill Integration Pattern

Skills that call contract-check should follow this pattern:

```markdown
### Pre-step: Contract Check (if fixtures involved)

1. Check if the current task uses Mockoon fixtures (read workspace-config `visual_regression.domains[].fixtures`)
2. If yes, check if Docker nginx is running (`curl -s -o /dev/null -w "%{http_code}" http://localhost:80`)
3. If Docker is up → run `contract-check.sh --env-dir <dir> --epic <epic>`
4. If exit code 1 (breaking drift):
   - Display the drift report
   - Ask user: "API contract 有 breaking change，要先處理再繼續，還是忽略？"
   - User chooses to proceed → continue with warning
   - User chooses to fix → stop current task, suggest opening a ticket
5. If exit code 2 (env not reachable) → warn, continue without check
6. If exit code 0 → proceed normally
```

## Fixture Update Flow

When drift is detected and the user decides to update fixtures:

1. Start Mockoon in **record mode**: `polaris-env.sh start {company} --vr --record`
2. Navigate to affected pages (Mockoon proxy captures fresh responses)
3. Stop recording: `polaris-env.sh stop`
4. New fixtures are saved in the environment files
5. Re-run contract-check to confirm drift is resolved
6. Resume the original task

## Relationship to Existing Mechanisms

- **`polaris-env.sh`**: provides the Docker + Mockoon infrastructure. Contract-check depends on Layer 1 (Docker) being up
- **`mockoon-runner.sh`**: starts/stops Mockoon. Contract-check does NOT start Mockoon — it reads fixture files directly and hits live APIs
- **`visual-regression` skill**: primary consumer. VR already requires `polaris-env.sh` — contract-check piggybacks on the same infra
- **`feedback_mockoon_fixture_value.md`** memory: the original design decision for using fixtures. Contract-guard is the missing complement
