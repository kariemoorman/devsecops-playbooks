#!/usr/bin/env bash
# setup-client.sh
#
# Automated setup script for developer machines. Configures pip, uv, npm,
# and Docker to use internal registries (devpi, Verdaccio, GitLab).
#
# Usage:
#   chmod +x scripts/setup-client.sh
#   ./scripts/setup-client.sh
#
# Prerequisites:
#   - GitLab personal access token with 'read_api' scope
#   - Network access to devpi.internal:3141 and verdaccio.internal:4873
#   - Docker installed (for container registry setup)
#
# What this script configures:
#   1. pip  -> devpi (PyPI cache) + GitLab (private packages)
#   2. uv   -> devpi (PyPI cache) + GitLab (private packages)
#   3. npm  -> Verdaccio (npm cache) + GitLab (private packages)
#   4. Docker -> GitLab Container Registry + Dependency Proxy
#   5. ~/.netrc for GitLab authentication

set -euo pipefail

# ──────────────────────────────────────────────────
# Configuration - EDIT THESE VALUES
# ──────────────────────────────────────────────────

GITLAB_HOST="${GITLAB_HOST:-gitlab.example.com}"
GITLAB_REGISTRY="${GITLAB_REGISTRY:-registry.${GITLAB_HOST}}"
GITLAB_GROUP_ID="${GITLAB_GROUP_ID:-}"  # Your GitLab group ID (numeric)
DEVPI_HOST="${DEVPI_HOST:-devpi.internal}"
DEVPI_PORT="${DEVPI_PORT:-3141}"
VERDACCIO_HOST="${VERDACCIO_HOST:-verdaccio.internal}"
VERDACCIO_PORT="${VERDACCIO_PORT:-4873}"
NPM_SCOPE="${NPM_SCOPE:-@myorg}"       # Your npm scope

# ──────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

confirm() {
    read -r -p "$1 [y/N]: " response
    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

backup_file() {
    local file="$1"
    if [ -f "$file" ]; then
        cp "$file" "${file}.bak.$(date +%Y%m%d%H%M%S)"
        info "Backed up existing $file"
    fi
}

# ──────────────────────────────────────────────────
# Preflight Checks
# ──────────────────────────────────────────────────

echo "============================================"
echo "  Internal Registry Client Setup"
echo "============================================"
echo ""

if [ -z "$GITLAB_GROUP_ID" ]; then
    read -r -p "Enter your GitLab group ID (numeric): " GITLAB_GROUP_ID
fi

# Prompt for GitLab Token
echo ""
info "You need a GitLab personal access token with 'read_api' scope."
info "Create one at: https://${GITLAB_HOST}/-/user_settings/personal_access_tokens"
echo ""
read -r -s -p "Enter your GitLab personal access token: " GITLAB_TOKEN
echo ""

if [ -z "$GITLAB_TOKEN" ]; then
    error "Token cannot be empty."
    exit 1
fi

read -r -p "Enter your GitLab username (for token auth): " GITLAB_USERNAME

# Check Connectivity
echo ""
info "Checking connectivity..."

check_host() {
    local host="$1" port="$2" name="$3"
    if command -v nc &>/dev/null; then
        if nc -z -w 3 "$host" "$port" 2>/dev/null; then
            info "  $name ($host:$port) - reachable"
            return 0
        else
            warn "  $name ($host:$port) - NOT reachable"
            return 1
        fi
    else
        warn "  Cannot check $name (nc not installed). Continuing anyway."
        return 0
    fi
}

DEVPI_OK=true
VERDACCIO_OK=true
check_host "$DEVPI_HOST" "$DEVPI_PORT" "devpi" || DEVPI_OK=false
check_host "$VERDACCIO_HOST" "$VERDACCIO_PORT" "Verdaccio" || VERDACCIO_OK=false

# ──────────────────────────────────────────────────
# 1. Configure pip
# ──────────────────────────────────────────────────

echo ""
info "=== Configuring pip ==="

PIP_CONF_DIR="${HOME}/.config/pip"
PIP_CONF="${PIP_CONF_DIR}/pip.conf"

if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]]; then
    PIP_CONF_DIR="${APPDATA}/pip"
    PIP_CONF="${PIP_CONF_DIR}/pip.ini"
fi

mkdir -p "$PIP_CONF_DIR"
backup_file "$PIP_CONF"

if [ "$DEVPI_OK" = true ]; then
    cat > "$PIP_CONF" << EOF
[global]
index-url = http://${DEVPI_HOST}:${DEVPI_PORT}/root/pypi/+simple/
extra-index-url = https://${GITLAB_HOST}/api/v4/groups/${GITLAB_GROUP_ID}/-/packages/pypi/simple
trusted-host = ${DEVPI_HOST}
timeout = 60
EOF
    info "Wrote $PIP_CONF (devpi + GitLab)"
else
    cat > "$PIP_CONF" << EOF
[global]
index-url = https://pypi.org/simple
extra-index-url = https://${GITLAB_HOST}/api/v4/groups/${GITLAB_GROUP_ID}/-/packages/pypi/simple
timeout = 60
EOF
    warn "Wrote $PIP_CONF (PyPI direct + GitLab -- devpi unreachable)"
fi

# ──────────────────────────────────────────────────
# 2. Configure uv (environment variables)
# ──────────────────────────────────────────────────

info "=== Configuring uv ==="

UV_EXPORTS=""
if [ "$DEVPI_OK" = true ]; then
    UV_EXPORTS="
# uv package manager - internal registries
export UV_INDEX_URL=\"http://${DEVPI_HOST}:${DEVPI_PORT}/root/pypi/+simple/\"
export UV_EXTRA_INDEX_URL=\"https://${GITLAB_HOST}/api/v4/groups/${GITLAB_GROUP_ID}/-/packages/pypi/simple\"
"
fi

# ──────────────────────────────────────────────────
# 3. Configure npm
# ──────────────────────────────────────────────────

info "=== Configuring npm ==="

NPMRC="${HOME}/.npmrc"
backup_file "$NPMRC"

if [ "$VERDACCIO_OK" = true ]; then
    cat > "$NPMRC" << EOF
# Public packages: Verdaccio caching proxy
registry=http://${VERDACCIO_HOST}:${VERDACCIO_PORT}/

# Private packages: GitLab npm Registry
${NPM_SCOPE}:registry=https://${GITLAB_HOST}/api/v4/groups/${GITLAB_GROUP_ID}/-/packages/npm/
//${GITLAB_HOST}/api/v4/groups/${GITLAB_GROUP_ID}/-/packages/npm/:_authToken=${GITLAB_TOKEN}

# Security
audit=true
save-exact=true
fund=false
EOF
    info "Wrote $NPMRC (Verdaccio + GitLab)"
else
    cat > "$NPMRC" << EOF
# Public packages: npm registry (direct)
registry=https://registry.npmjs.org/

# Private packages: GitLab npm Registry
${NPM_SCOPE}:registry=https://${GITLAB_HOST}/api/v4/groups/${GITLAB_GROUP_ID}/-/packages/npm/
//${GITLAB_HOST}/api/v4/groups/${GITLAB_GROUP_ID}/-/packages/npm/:_authToken=${GITLAB_TOKEN}

# Security
audit=true
save-exact=true
fund=false
EOF
    warn "Wrote $NPMRC (npm direct + GitLab -- Verdaccio unreachable)"
fi

chmod 600 "$NPMRC"

# ──────────────────────────────────────────────────
# 4. Configure ~/.netrc (GitLab auth for pip)
# ──────────────────────────────────────────────────

info "=== Configuring ~/.netrc ==="

NETRC="${HOME}/.netrc"
backup_file "$NETRC"

# Append GitLab credentials (don't overwrite other entries)
if grep -q "machine ${GITLAB_HOST}" "$NETRC" 2>/dev/null; then
    warn "GitLab entry already exists in ~/.netrc. Skipping."
else
    cat >> "$NETRC" << EOF

machine ${GITLAB_HOST}
  login ${GITLAB_USERNAME}
  password ${GITLAB_TOKEN}
EOF
    info "Added GitLab credentials to $NETRC"
fi

chmod 600 "$NETRC"

# ──────────────────────────────────────────────────
# 5. Configure Docker
# ──────────────────────────────────────────────────

info "=== Configuring Docker ==="

if command -v docker &>/dev/null; then
    info "Logging into GitLab Container Registry..."
    echo "$GITLAB_TOKEN" | docker login "$GITLAB_REGISTRY" -u "$GITLAB_USERNAME" --password-stdin \
        && info "Docker: logged into $GITLAB_REGISTRY" \
        || warn "Docker: failed to log into $GITLAB_REGISTRY"

    info "Logging into GitLab Dependency Proxy..."
    echo "$GITLAB_TOKEN" | docker login "$GITLAB_HOST" -u "$GITLAB_USERNAME" --password-stdin \
        && info "Docker: logged into $GITLAB_HOST (Dependency Proxy)" \
        || warn "Docker: failed to log into $GITLAB_HOST"
else
    warn "Docker not found. Skipping Docker configuration."
fi

# ──────────────────────────────────────────────────
# 6. Shell Environment Variables
# ──────────────────────────────────────────────────

info "=== Configuring shell environment ==="

SHELL_RC=""
if [ -f "${HOME}/.zshrc" ]; then
    SHELL_RC="${HOME}/.zshrc"
elif [ -f "${HOME}/.bashrc" ]; then
    SHELL_RC="${HOME}/.bashrc"
fi

if [ -n "$SHELL_RC" ] && [ -n "$UV_EXPORTS" ]; then
    if ! grep -q "UV_INDEX_URL" "$SHELL_RC" 2>/dev/null; then
        echo "$UV_EXPORTS" >> "$SHELL_RC"
        info "Added uv environment variables to $SHELL_RC"
    else
        warn "uv environment variables already in $SHELL_RC. Skipping."
    fi
fi

# ──────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────

echo ""
echo "============================================"
echo "  Setup Complete"
echo "============================================"
echo ""
info "Configured:"
info "  pip   -> $PIP_CONF"
info "  npm   -> $NPMRC"
info "  netrc -> $NETRC"
[ -n "$UV_EXPORTS" ] && info "  uv    -> $SHELL_RC (env vars)"
command -v docker &>/dev/null && info "  Docker -> ~/.docker/config.json"
echo ""
info "Test your setup:"
info "  pip install flask              # Should resolve via devpi"
info "  pip install myorg-auth         # Should resolve via GitLab"
info "  npm install express            # Should resolve via Verdaccio"
info "  npm install ${NPM_SCOPE}/auth  # Should resolve via GitLab"
info "  docker pull ${GITLAB_REGISTRY}/my-org/my-app:latest"
echo ""
warn "Restart your terminal or run 'source $SHELL_RC' to apply environment changes."
