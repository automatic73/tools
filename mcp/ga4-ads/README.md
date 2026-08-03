# MCP Google Analytics + Google Ads (Cursor and Claude)

Shared setup bundle for Automatic73. Official Google MCP servers, read-only.

| Server | Repo | Useful tools |
|--------|------|--------------|
| `analytics-mcp` | [googleanalytics/google-analytics-mcp](https://github.com/googleanalytics/google-analytics-mcp) | accounts, reports, funnel, realtime, custom dims |
| `google-ads-mcp` | [googleads/google-ads-mcp](https://github.com/googleads/google-ads-mcp) | customers, GAQL `search`, metadata |

**GCP:** project ID `oden-pos-500518` - number `707494054188`  
**Default Doppler project:** `automatic73-ops` (`prd` / `stg` / `dev`)

| Secret | Usage |
|--------|-------|
| `GOOGLE_PROJECT_ID` | `oden-pos-500518` |
| `GOOGLE_CLOUD_PROJECT_NUMBER` | `707494054188` |
| `GOOGLE_ADS_DEVELOPER_TOKEN` | API Center (MCC) |
| `GOOGLE_ADS_LOGIN_CUSTOMER_ID` | Manager without dashes (`3198821992`) |
| `GCP_OAUTH_DESKTOP_CLIENT_JSON` | OAuth Desktop client JSON |

Design doc for Basic Access: [`google-ads-api-access-design.md`](google-ads-api-access-design.md).

Product funnel reference: repo `oden-pos` -> `apps/webapp/docs/ANALYTICS-FUNNEL.md`.

---

## Setup

Prereqs: `doppler login`, access to the chosen Doppler project/config, `pipx`,
`gcloud`, and `pipx install analytics-mcp`.

```bash
# From this repo (automatic73-tools)
bash mcp/ga4-ads/setup.sh

# optional overrides
DOPPLER_PROJECT=automatic73-ops DOPPLER_CONFIG=dev bash mcp/ga4-ads/setup.sh

# optional non-destructive test (writes in /tmp instead of your home config)
CLIENT_JSON_PATH=/tmp/gcp-oauth-desktop.json MCP_PATH=/tmp/cursor-mcp.json bash mcp/ga4-ads/setup.sh

# one time per machine
gcloud auth application-default login \
  --scopes https://www.googleapis.com/auth/analytics.readonly,https://www.googleapis.com/auth/adwords,https://www.googleapis.com/auth/cloud-platform \
  --client-id-file="$HOME/.config/oden/gcp-oauth-desktop.json"
```

The script:

1. Downloads OAuth client JSON to `~/.config/oden/gcp-oauth-desktop.json`
2. Merges `analytics-mcp` + `google-ads-mcp` into `~/.cursor/mcp.json` without wiping existing servers

Then reload Cursor. Servers should appear green in any workspace.

### Claude Code

```bash
GOOGLE_PROJECT_ID=$(doppler secrets get GOOGLE_PROJECT_ID -p automatic73-ops -c prd --plain)
GOOGLE_ADS_DEVELOPER_TOKEN=$(doppler secrets get GOOGLE_ADS_DEVELOPER_TOKEN -p automatic73-ops -c prd --plain)
GOOGLE_ADS_LOGIN_CUSTOMER_ID=$(doppler secrets get GOOGLE_ADS_LOGIN_CUSTOMER_ID -p automatic73-ops -c prd --plain)

claude mcp add analytics-mcp --scope user \
  -e "GOOGLE_PROJECT_ID=${GOOGLE_PROJECT_ID}" \
  -- analytics-mcp

claude mcp add google-ads-mcp --scope user \
  -e "GOOGLE_PROJECT_ID=${GOOGLE_PROJECT_ID}" \
  -e "GOOGLE_ADS_DEVELOPER_TOKEN=${GOOGLE_ADS_DEVELOPER_TOKEN}" \
  -e "GOOGLE_ADS_LOGIN_CUSTOMER_ID=${GOOGLE_ADS_LOGIN_CUSTOMER_ID}" \
  -- pipx run --spec git+https://github.com/googleads/google-ads-mcp.git google-ads-mcp
```

Each person still needs to be a test user in GCP OAuth consent and have viewer
access in GA4 / Ads.

---

## Notes

- Test developer token is not enough for production Ads accounts (Explorer/Basic needed).
- Never commit secrets. Keep them in Doppler.
- Do not configure these MCP servers at a parent directory scope that leaks into every repo session.
