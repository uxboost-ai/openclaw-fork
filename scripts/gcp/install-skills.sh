#!/usr/bin/env bash
# Install skill dependencies into the running openclaw-gateway Docker container.
#
# This script installs binary tools and language runtimes needed by OpenClaw
# skills that aren't included in the base Docker image. Run it on the GCP VM
# host (not inside the container).
#
# Installs:
#   - gog        (Google Workspace CLI)       - GitHub release binary
#   - goplaces   (Google Places CLI)          - GitHub release binary
#   - camsnap    (Camera snapshot CLI)        - GitHub release binary
#   - wacli      (WhatsApp CLI)              - Built from Go source
#   - bird       (X/Twitter CLI)             - npm package
#   - python3    (for openai-image-gen)      - apt package
#   - codex      (OpenAI Codex CLI)          - npm package
#   - pi         (Pi Coding Agent)           - npm package
#
# Usage:
#   bash ~/install-skills.sh
#   OPENAI_API_KEY=sk-... bash ~/install-skills.sh
#
# Note: Installs inside the container are ephemeral. Re-run this script after
# rebuilding/recreating the container, or use install-skills-dockerfile.sh to
# bake them into the image.

set -euo pipefail

CONTAINER="${OPENCLAW_CONTAINER:-openclaw-gateway}"

# Use sudo for docker if the user is not in the docker group for this session
DOCKER_CMD="docker"
if ! docker info >/dev/null 2>&1; then
  DOCKER_CMD="sudo docker"
fi

# --- Preflight ---
if ! $DOCKER_CMD ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
  echo "Error: Container '$CONTAINER' is not running." >&2
  echo "Start it first: $DOCKER_CMD start $CONTAINER" >&2
  exit 1
fi

echo "============================================"
echo "  OpenClaw Skills - Dependency Installer"
echo "============================================"
echo ""
echo "  Container: $CONTAINER"
echo ""

# Helper: run command in container as root
droot() { $DOCKER_CMD exec -u root "$CONTAINER" "$@"; }
# Helper: run command in container as default user (node)
dnode() { $DOCKER_CMD exec "$CONTAINER" "$@"; }

# --- Step 1: System packages (as root) ---
echo "==> [1/6] Installing system packages (python3, Go toolchain)..."
droot apt-get update -qq
droot apt-get install -y -qq --no-install-recommends python3 golang-go ca-certificates
droot apt-get clean
droot rm -rf /var/lib/apt/lists/*
echo "  python3: $(dnode python3 --version 2>&1)"
echo "  go:      $(dnode go version 2>&1)"

# --- Step 2: Download Go binaries from GitHub releases ---
echo "==> [2/6] Downloading Go CLI binaries (gog, goplaces, camsnap)..."

install_github_binary() {
  local name="$1"
  local url="$2"
  local bin_name="$3"
  local extract_name="${4:-$bin_name}"

  echo "  Installing $name..."

  # Download and extract in container
  droot bash -c "
    cd /tmp && \
    curl -fsSL '$url' -o '${name}.tar.gz' && \
    tar xzf '${name}.tar.gz' && \
    mv '${extract_name}' '/usr/local/bin/${bin_name}' && \
    chmod +x '/usr/local/bin/${bin_name}' && \
    rm -f '${name}.tar.gz'
  "

  if dnode which "$bin_name" >/dev/null 2>&1; then
    echo "  [OK] $bin_name installed: $(dnode "$bin_name" --version 2>&1 | head -1)"
  else
    echo "  [!!] $bin_name installation failed"
  fi
}

# gog (gogcli) - Google Workspace CLI
# Fetch latest version from GitHub API
GOG_VERSION=$(curl -fsSL https://api.github.com/repos/steipete/gogcli/releases/latest | grep -o '"tag_name":"[^"]*"' | head -1 | cut -d'"' -f4 | sed 's/^v//')
if [[ -z "$GOG_VERSION" ]]; then GOG_VERSION="0.9.0"; fi
install_github_binary "gogcli" \
  "https://github.com/steipete/gogcli/releases/download/v${GOG_VERSION}/gogcli_${GOG_VERSION}_linux_amd64.tar.gz" \
  "gog" "gog"

# goplaces - Google Places CLI
GOPLACES_VERSION=$(curl -fsSL https://api.github.com/repos/steipete/goplaces/releases/latest | grep -o '"tag_name":"[^"]*"' | head -1 | cut -d'"' -f4 | sed 's/^v//')
if [[ -z "$GOPLACES_VERSION" ]]; then GOPLACES_VERSION="0.2.1"; fi
install_github_binary "goplaces" \
  "https://github.com/steipete/goplaces/releases/download/v${GOPLACES_VERSION}/goplaces_${GOPLACES_VERSION}_linux_amd64.tar.gz" \
  "goplaces" "goplaces"

# camsnap - Camera snapshot CLI
CAMSNAP_VERSION=$(curl -fsSL https://api.github.com/repos/steipete/camsnap/releases/latest | grep -o '"tag_name":"[^"]*"' | head -1 | cut -d'"' -f4 | sed 's/^v//')
if [[ -z "$CAMSNAP_VERSION" ]]; then CAMSNAP_VERSION="0.2.0"; fi
install_github_binary "camsnap" \
  "https://github.com/steipete/camsnap/releases/download/v${CAMSNAP_VERSION}/camsnap_${CAMSNAP_VERSION}_linux_amd64.tar.gz" \
  "camsnap" "camsnap"

# --- Step 3: Build wacli from Go source ---
echo "==> [3/6] Building wacli from source (Go)..."
# wacli has no Linux release binary; build from source
droot bash -c "
  export GOPATH=/tmp/gopath
  export GOBIN=/usr/local/bin
  go install github.com/steipete/wacli/cmd/wacli@latest
  rm -rf /tmp/gopath
"

if dnode which wacli >/dev/null 2>&1; then
  echo "  [OK] wacli installed: $(dnode wacli --version 2>&1 | head -1)"
else
  echo "  [!!] wacli build failed (may need newer Go version)"
fi

# --- Step 4: Install npm-based tools ---
echo "==> [4/6] Installing npm-based tools (bird, codex, pi)..."

# bird - X/Twitter CLI
echo "  Installing bird (npm)..."
dnode npm install -g @steipete/bird 2>&1 | tail -1
if dnode which bird >/dev/null 2>&1; then
  echo "  [OK] bird installed: $(dnode bird --version 2>&1 | head -1)"
else
  echo "  [!!] bird installation failed"
fi

# codex - OpenAI Codex CLI (for coding-agent skill)
echo "  Installing codex (npm)..."
dnode npm install -g @openai/codex 2>&1 | tail -1
if dnode which codex >/dev/null 2>&1; then
  echo "  [OK] codex installed"
else
  echo "  [!!] codex installation failed (optional - coding-agent has alternatives)"
fi

# pi - Pi Coding Agent (alternative for coding-agent skill)
echo "  Installing pi coding agent (npm)..."
dnode npm install -g @mariozechner/pi-coding-agent 2>&1 | tail -1
if dnode which pi >/dev/null 2>&1; then
  echo "  [OK] pi installed"
else
  echo "  [!!] pi installation failed (optional)"
fi

# --- Step 5: Configure OpenAI API key ---
echo "==> [5/6] Configuring API keys..."

OPENCLAW_CONFIG="$HOME/.openclaw/openclaw.json"

if [[ -n "${OPENAI_API_KEY:-}" ]]; then
  # Write OpenAI auth profile alongside existing profiles
  AUTH_PROFILES="$HOME/.openclaw/agent/auth-profiles.json"

  if [[ -f "$AUTH_PROFILES" ]]; then
    # Merge OpenAI profile into existing auth profiles using python3 on host
    # (or node if python3 not available on host)
    if command -v python3 >/dev/null 2>&1; then
      python3 -c "
import json, sys
with open('$AUTH_PROFILES') as f:
    data = json.load(f)
data.setdefault('profiles', {})
data['profiles']['openai:default'] = {
    'type': 'api_key',
    'provider': 'openai',
    'key': '$OPENAI_API_KEY'
}
data['version'] = 1
with open('$AUTH_PROFILES', 'w') as f:
    json.dump(data, f, indent=2)
"
    else
      node -e "
const fs = require('fs');
const data = JSON.parse(fs.readFileSync('$AUTH_PROFILES', 'utf8'));
data.profiles = data.profiles || {};
data.profiles['openai:default'] = { type: 'api_key', provider: 'openai', key: '$OPENAI_API_KEY' };
data.version = 1;
fs.writeFileSync('$AUTH_PROFILES', JSON.stringify(data, null, 2));
"
    fi
    echo "  [OK] OpenAI API key added to auth profiles"
  else
    # Create new auth profiles file
    cat > "$AUTH_PROFILES" <<AUTHEOF
{
  "version": 1,
  "profiles": {
    "openai:default": {
      "type": "api_key",
      "provider": "openai",
      "key": "$OPENAI_API_KEY"
    }
  }
}
AUTHEOF
    sudo chown 1000:1000 "$AUTH_PROFILES"
    echo "  [OK] OpenAI auth profile created"
  fi

  echo "  OpenAI key configured for whisper-api, image-gen, and coding-agent skills"
else
  echo "  No OPENAI_API_KEY provided. Set it and re-run, or configure later:"
  echo "    OPENAI_API_KEY=sk-... bash ~/install-skills.sh"
fi

# --- Step 6: Verify ---
echo "==> [6/6] Verifying skill dependencies..."
echo ""

check_bin() {
  local name="$1"
  local skill="$2"
  if dnode which "$name" >/dev/null 2>&1; then
    echo "  [OK] $name  ($skill)"
  else
    echo "  [!!] $name  ($skill) - NOT FOUND"
  fi
}

check_bin "gog"       "gog (Google Workspace)"
check_bin "goplaces"  "goplaces (Google Places)"
check_bin "camsnap"   "camsnap (Camera Snapshots)"
check_bin "wacli"     "wacli (WhatsApp CLI)"
check_bin "bird"      "bird (X/Twitter)"
check_bin "python3"   "openai-image-gen"
check_bin "curl"      "openai-whisper-api"
check_bin "codex"     "coding-agent (Codex)"
check_bin "pi"        "coding-agent (Pi)"

echo ""
echo "============================================"
echo "  Skills installation complete!"
echo "============================================"
echo ""
echo "  Restart the gateway to pick up new skills:"
echo "    $DOCKER_CMD restart $CONTAINER"
echo ""
echo "  Note: These installs are inside the container."
echo "  Re-run this script after rebuilding the image."
echo ""
