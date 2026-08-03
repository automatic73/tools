#!/usr/bin/env bash
# Configure GA4 + Google Ads MCP (official servers) from Doppler.
# Usage (from automatic73-tools or with an absolute path):
#   bash mcp/ga4-ads/setup.sh
#
# Writes:
#   ~/.config/oden/gcp-oauth-desktop.json
#   merge into ~/.cursor/mcp.json (preserves existing servers)
# Optional overrides:
#   DOPPLER_PROJECT, DOPPLER_CONFIG, CLIENT_JSON_PATH, MCP_PATH
set -euo pipefail

CFG="${DOPPLER_CONFIG:-prd}"
PROJ="${DOPPLER_PROJECT:-automatic73-ops}"
KEYS_DIR="${KEYS_DIR:-${HOME}/.config/oden}"
CLIENT_JSON_PATH="${CLIENT_JSON_PATH:-${KEYS_DIR}/gcp-oauth-desktop.json}"
MCP_PATH="${MCP_PATH:-${HOME}/.cursor/mcp.json}"

mkdir -p "$(dirname "${CLIENT_JSON_PATH}")" "$(dirname "${MCP_PATH}")"

echo "-> Doppler -p ${PROJ} -c ${CFG}"
GOOGLE_PROJECT_ID="$(doppler secrets get GOOGLE_PROJECT_ID -p "${PROJ}" -c "${CFG}" --plain)"
GOOGLE_ADS_DEVELOPER_TOKEN="$(doppler secrets get GOOGLE_ADS_DEVELOPER_TOKEN -p "${PROJ}" -c "${CFG}" --plain)"
GOOGLE_ADS_LOGIN_CUSTOMER_ID="$(doppler secrets get GOOGLE_ADS_LOGIN_CUSTOMER_ID -p "${PROJ}" -c "${CFG}" --plain)"
doppler secrets get GCP_OAUTH_DESKTOP_CLIENT_JSON -p "${PROJ}" -c "${CFG}" --plain >"${CLIENT_JSON_PATH}"
chmod 600 "${CLIENT_JSON_PATH}"

export GOOGLE_PROJECT_ID GOOGLE_ADS_DEVELOPER_TOKEN GOOGLE_ADS_LOGIN_CUSTOMER_ID MCP_PATH
python3 <<'PY'
import json
import os
from pathlib import Path

mcp_path = Path(os.environ["MCP_PATH"])
if mcp_path.exists():
    data = json.loads(mcp_path.read_text())
else:
    data = {"mcpServers": {}}

servers = data.setdefault("mcpServers", {})
servers["analytics-mcp"] = {
    "command": "analytics-mcp",
    "env": {"GOOGLE_PROJECT_ID": os.environ["GOOGLE_PROJECT_ID"]},
}
servers["google-ads-mcp"] = {
    "command": "pipx",
    "args": [
        "run",
        "--spec",
        "git+https://github.com/googleads/google-ads-mcp.git",
        "google-ads-mcp",
    ],
    "env": {
        "GOOGLE_PROJECT_ID": os.environ["GOOGLE_PROJECT_ID"],
        "GOOGLE_ADS_DEVELOPER_TOKEN": os.environ["GOOGLE_ADS_DEVELOPER_TOKEN"],
        "GOOGLE_ADS_LOGIN_CUSTOMER_ID": os.environ["GOOGLE_ADS_LOGIN_CUSTOMER_ID"],
    },
}
mcp_path.write_text(json.dumps(data, indent=2) + "\n")
os.chmod(mcp_path, 0o600)
print(f"OK merged MCP servers -> {mcp_path}")
print("  servers:", ", ".join(sorted(servers)))
PY

echo "OK OAuth client -> ${CLIENT_JSON_PATH}"
echo
echo "Next (one time per machine):"
echo "  gcloud auth application-default login \\"
echo "    --scopes https://www.googleapis.com/auth/analytics.readonly,https://www.googleapis.com/auth/adwords,https://www.googleapis.com/auth/cloud-platform \\"
echo "    --client-id-file=\"${CLIENT_JSON_PATH}\""
echo
echo "Then: Cursor -> Developer: Reload Window (MCP should be green)."
echo "Note: Ads test token only sees test accounts. Explorer/Basic needed for prod."
