#!/bin/bash
# ============================================================
# AIOPS.SH — Local AI Operations Server
# Version:    5.3.0
# Author:     Quantocos AI Labs
# Compatible: WSL2 Ubuntu 22.04 / 24.04
# Usage:      bash aiops.sh
#
# ARCHITECTURE:
#   - No hardcoded IPs, domains, or ports anywhere in launchers
#   - All config lives in $AIOPS_CONF (~/aiops-server/aiops.conf)
#   - Every launcher sources the config at runtime
#   - Change config → restart PM2 → everything updates
#   - Works for any username, any machine, any network
# ============================================================

# ── Colors ───────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# ── Static paths only — nothing machine-specific ─────────────
AIOPS_HOME="$HOME/aiops-server"
AIOPS_CONF="$AIOPS_HOME/aiops.conf"
SCRIPTS_DIR="$HOME/scripts"
AGENTS_DIR="$HOME/agents"
VENVS_DIR="$HOME/.venvs"
QDRANT_DIR="$HOME/qdrant-data"
LOG_FILE="$AIOPS_HOME/install.log"
ADDONS_LOG="$AIOPS_HOME/addons.log"

# ── Pinned Versions ──────────────────────────────────────────
NODE_VERSION="22"
OPEN_WEBUI_VERSION="0.8.10"
QDRANT_VERSION="v1.17.0"
QDRANT_WEBUI_VERSION="v0.2.7"
CREWAI_VERSION="1.10.1"
CREWAI_TOOLS_VERSION="1.10.1"
OPEN_INTERPRETER_VERSION="0.4.3"
AIDER_VERSION="0.86.2"

# ── Runtime globals (populated during execution) ─────────────
UBUNTU_VERSION="0"
PIP_FLAGS=""

# ── Helpers ──────────────────────────────────────────────────
_log()     { echo -e "${GREEN}[✓]${NC} $1" | tee -a "$LOG_FILE"; }
_warn()    { echo -e "${YELLOW}[!]${NC} $1" | tee -a "$LOG_FILE"; }
_error()   { echo -e "${RED}[✗]${NC} $1" | tee -a "$LOG_FILE"; exit 1; }
_info()    { echo -e "${CYAN}[→]${NC} $1" | tee -a "$LOG_FILE"; }
_section() { echo -e "\n${BOLD}${BLUE}══ $1 ══${NC}\n" | tee -a "$LOG_FILE"; }

_log_add()     { echo -e "${GREEN}[✓]${NC} $1" | tee -a "$ADDONS_LOG"; }
_warn_add()    { echo -e "${YELLOW}[!]${NC} $1" | tee -a "$ADDONS_LOG"; }
_info_add()    { echo -e "${CYAN}[→]${NC} $1" | tee -a "$ADDONS_LOG"; }
_section_add() { echo -e "\n${BOLD}${MAGENTA}══ $1 ══${NC}\n" | tee -a "$ADDONS_LOG"; }

confirm() {
    read -rp "$(echo -e "${YELLOW}$1 [y/N]: ${NC}")" r
    [[ "$r" =~ ^[Yy]$ ]]
}

nvm_load() {
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
}

# ── Source the config file (used by all functions that need ports/domain) ──
conf_load() {
    [ -f "$AIOPS_CONF" ] && source "$AIOPS_CONF"
}

# ============================================================
# BANNERS
# ============================================================
banner_core() {
cat << 'BANNER'

   ____  _   _   _    _   _ _____ ___   ____  ___  ____
  / __ \| | | | / \  | \ | |_   _/ _ \ / ___|/ _ \/ ___|
 | |  | | | | |/ _ \ |  \| | | || | | | |   | | | \___ \
 | |__| | |_| / ___ \| |\  | | || |_| | |___| |_| |___) |
  \___\_\\___/_/   \_\_| \_| |_| \___/ \____|\___/|____/

  ─────────────────────────────────────────────────────────
  Local AI Operations Server  ·  Quantocos AI Labs  ·  v5.3.0
  WSL2 Ubuntu 22.04 / 24.04
  ─────────────────────────────────────────────────────────

BANNER
}

banner_addons() {
cat << 'BANNER'

   ____  _   _   _    _   _ _____ ___   ____  ___  ____
  / __ \| | | | / \  | \ | |_   _/ _ \ / ___|/ _ \/ ___|
 | |  | | | | |/ _ \ |  \| | | || | | | |   | | | \___ \
 | |__| | |_| / ___ \| |\  | | || |_| | |___| |_| |___) |
  \___\_\\___/_/   \_\_| \_| |_| \___/ \____|\___/|____/

  ─────────────────────────────────────────────────────────
  Optional Tools Installer  ·  Quantocos AI Labs  ·  v5.3.0
  ─────────────────────────────────────────────────────────

BANNER
}

# ============================================================
# PART 1 — CORE INSTALL
# ============================================================

preinit() {
    mkdir -p "$AIOPS_HOME"
    touch "$LOG_FILE" "$ADDONS_LOG"
    command -v lsb_release &>/dev/null || sudo apt-get install -y lsb-release -qq 2>/dev/null || true
}

# ── Preflight ────────────────────────────────────────────────
preflight() {
    _section "Preflight Checks"

    grep -qi "ubuntu" /etc/os-release 2>/dev/null \
        || _error "This script requires Ubuntu. Detected: $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '\"')"

    UBUNTU_VERSION=$(lsb_release -rs 2>/dev/null \
        || grep VERSION_ID /etc/os-release | cut -d= -f2 | tr -d '"')

    case "$UBUNTU_VERSION" in
        24.04) _log "OS: Ubuntu 24.04 LTS — fully supported"; PIP_FLAGS="--break-system-packages" ;;
        22.04) _log "OS: Ubuntu 22.04 LTS — supported"; PIP_FLAGS="" ;;
        20.04) _warn "OS: Ubuntu 20.04 — Python 3.8 default. Recommend upgrading."; PIP_FLAGS="" ;;
        *)
            _warn "OS: Ubuntu $UBUNTU_VERSION — untested. Proceeding."
            awk "BEGIN {exit !($UBUNTU_VERSION >= 24.04)}" && PIP_FLAGS="--break-system-packages" || PIP_FLAGS=""
            ;;
    esac

    grep -qi "microsoft" /proc/version 2>/dev/null \
        && _log "Environment: WSL2 detected" \
        || _warn "Not running in WSL2 — optimised for WSL2 but continuing"

    curl -s --max-time 5 https://google.com > /dev/null \
        || _error "No internet connection."
    _log "Internet: Connected"

    AVAILABLE=$(df ~ | awk 'NR==2 {print $4}')
    [ "$AVAILABLE" -lt 20971520 ] \
        && _warn "Low disk space: $(df -h ~ | awk 'NR==2 {print $4}') — recommend 20GB+" \
        || _log "Disk: $(df -h ~ | awk 'NR==2 {print $4}') free"

    TOTAL_RAM=$(free -g | awk 'NR==2 {print $2}')
    [ "$TOTAL_RAM" -lt 16 ] \
        && _warn "RAM: ${TOTAL_RAM}GB — 16GB+ recommended for 14B models" \
        || _log "RAM: ${TOTAL_RAM}GB"
}

# ── Config file — single source of truth ─────────────────────
# All launchers source this file at runtime. Nothing is hardcoded
# into launcher scripts. Change this file, restart PM2, done.
setup_config() {
    _section "Configuration"

    echo -e "${CYAN}This name is used for LAN access via mDNS.${NC}"
    echo -e "${CYAN}Example: 'myserver' → http://myserver.local${NC}"
    echo ""
    read -rp "$(echo -e "${YELLOW}Enter .local domain name (Enter for 'aiops'): ${NC}")" domain_input

    local domain_base="${domain_input%.local}"
    [ -z "$domain_base" ] && domain_base="aiops"
    local local_domain="${domain_base}.local"

    # Write the config file — this is the ONLY place ports and domain live.
    # Launchers source this at runtime — never baked into script text.
    cat > "$AIOPS_CONF" << CONF
# ============================================================
# AIOPS Configuration — Quantocos AI Labs
# Generated: $(date)
# Edit this file and run: pm2 restart all
# ============================================================

# Domain
AIOPS_DOMAIN="${local_domain}"

# Ports — change here to avoid conflicts, restart PM2 to apply
AIOPS_PORT_OPENWEBUI=8080
AIOPS_PORT_N8N=5678
AIOPS_PORT_QDRANT=6333
AIOPS_PORT_CREWAI=8501
AIOPS_PORT_TWENTY=3000
AIOPS_PORT_LISTMONK=9000
AIOPS_PORT_MAUTIC=8100
AIOPS_PORT_CHATWOOT=3100
AIOPS_PORT_CALCOM=3002
AIOPS_PORT_NETDATA=19999
AIOPS_PORT_OLLAMA=11434

# Paths
AIOPS_SCRIPTS_DIR="${SCRIPTS_DIR}"
AIOPS_AGENTS_DIR="${AGENTS_DIR}"
AIOPS_VENVS_DIR="${VENVS_DIR}"
AIOPS_QDRANT_DIR="${QDRANT_DIR}"
CONF

    chmod 600 "$AIOPS_CONF"
    _log "Config written to $AIOPS_CONF"
    _info "Domain: $local_domain"
    _info "Edit $AIOPS_CONF to change ports or domain. Restart PM2 to apply."

    # Source it now so this install session has the values
    conf_load

    mkdir -p "$HOME/.streamlit"
    cat > "$HOME/.streamlit/credentials.toml" << 'EOF'
[general]
email = ""
EOF
    _log "Streamlit credentials configured"
}

# ── Directories ───────────────────────────────────────────────
setup_dirs() {
    _section "Creating Directory Structure"
    mkdir -p "$SCRIPTS_DIR" "$VENVS_DIR"
    mkdir -p "$AGENTS_DIR"/{crews,tasks,tools,outputs,configs}
    mkdir -p "$QDRANT_DIR"/{config,static,storage,snapshots}
    _log "Directories created"
}

# ── System deps ───────────────────────────────────────────────
install_system_deps() {
    _section "Installing System Dependencies"
    sudo apt-get update -qq
    sudo apt-get install -y \
        curl wget git unzip \
        python3 python3-pip python3-venv \
        build-essential ffmpeg lsof \
        ca-certificates gnupg lsb-release zstd \
        2>/dev/null
    _log "System dependencies installed"
}

# ── WSL system config ─────────────────────────────────────────
setup_wsl_system() {
    _section "WSL System Configuration"
    if ! grep -q "systemd=true" /etc/wsl.conf 2>/dev/null; then
        sudo tee -a /etc/wsl.conf > /dev/null << 'EOF'
[boot]
systemd=true
EOF
        _log "systemd=true added to /etc/wsl.conf"
        _warn "WSL restart required after install for systemd to take effect"
    else
        _log "systemd=true already set"
    fi
}

# ── mDNS (Avahi) ──────────────────────────────────────────────
setup_mdns() {
    _section "Setting Up mDNS (Avahi)"
    conf_load

    sudo apt-get install -y avahi-daemon avahi-utils libnss-mdns -qq

    # hostname extracted from domain at runtime — no hardcoding
    local hostname="${AIOPS_DOMAIN%.local}"

    sudo tee /etc/avahi/avahi-daemon.conf > /dev/null << AVAHI
[server]
host-name=${hostname}
domain-name=local
use-ipv4=yes
use-ipv6=no
allow-interfaces=eth0
deny-interfaces=lo
enable-dbus=yes
check-response-ttl=no
use-iff-running=no

[wide-area]
enable-wide-area=yes

[publish]
publish-addresses=yes
publish-hinfo=yes
publish-workstation=no
publish-domain=yes
AVAHI

    grep -q "mdns4_minimal" /etc/nsswitch.conf 2>/dev/null \
        || sudo sed -i 's/^hosts:.*/hosts:          files mdns4_minimal [NOTFOUND=return] dns/' /etc/nsswitch.conf

    sudo systemctl enable avahi-daemon 2>/dev/null || true
    sudo systemctl restart avahi-daemon 2>/dev/null || true
    _log "mDNS configured — hostname: ${hostname}"
}

# ── Caddy ─────────────────────────────────────────────────────
# Caddyfile uses variables sourced from AIOPS_CONF via the
# caddy-env wrapper. Ports are read from conf at caddy start.
# For simplicity, Caddyfile is regenerated from conf values
# since Caddy doesn't natively source shell env files.
install_caddy() {
    _section "Installing Caddy Reverse Proxy"
    conf_load

    if ! command -v caddy &>/dev/null; then
        sudo apt-get install -y debian-keyring debian-archive-keyring apt-transport-https -qq
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
            | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
            | sudo tee /etc/apt/sources.list.d/caddy-stable.list
        sudo apt-get update -qq
        sudo apt-get install -y caddy
        _log "Caddy installed: $(caddy version)"
    else
        _log "Caddy already installed: $(caddy version)"
    fi

    write_caddyfile
}

# Separate function so it can be called standalone to regenerate
# the Caddyfile when ports/domain change in aiops.conf
write_caddyfile() {
    conf_load

    sudo tee /etc/caddy/Caddyfile > /dev/null << CADDY
# ============================================================
# /etc/caddy/Caddyfile — Quantocos AI Labs — AIOPS v5.3.0
# Auto-generated from ${AIOPS_CONF}
# Regenerate: aiops-caddy-regen (alias added to ~/.bashrc)
# Architecture: per-port — no subpath proxying for WS apps
# WebSocket: Connection "Upgrade" literal (not placeholder)
# ============================================================

:80 {

    header {
        Access-Control-Allow-Origin  "*"
        Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS"
        Access-Control-Allow-Headers "*"
        -X-Frame-Options
        X-Content-Type-Options "nosniff"
        -Server
    }

    # n8n — strip prefix, n8n owns root on its port
    handle /n8n* {
        uri strip_prefix /n8n
        reverse_proxy localhost:${AIOPS_PORT_N8N} {
            header_up Host              {host}
            header_up X-Real-IP         {remote_host}
            header_up X-Forwarded-Proto http
            header_up Upgrade           {http.upgrade}
            header_up Connection        "Upgrade"
        }
    }

    # CrewAI Studio — strip prefix, baseUrlPath set in launcher
    handle /agents* {
        uri strip_prefix /agents
        reverse_proxy localhost:${AIOPS_PORT_CREWAI} {
            header_up Host       {host}
            header_up Upgrade    {http.upgrade}
            header_up Connection "Upgrade"
        }
    }

    # Qdrant REST API — UI accessed directly at :PORT_QDRANT
    handle /qdrant* {
        uri strip_prefix /qdrant
        reverse_proxy localhost:${AIOPS_PORT_QDRANT}
    }

    # Netdata
    handle /monitor* {
        uri strip_prefix /monitor
        reverse_proxy localhost:${AIOPS_PORT_NETDATA}
    }

    # Ollama API
    handle /ollama* {
        uri strip_prefix /ollama
        reverse_proxy localhost:${AIOPS_PORT_OLLAMA}
    }

    # OpenWebUI — catch-all
    handle /* {
        reverse_proxy localhost:${AIOPS_PORT_OPENWEBUI} {
            header_up Host      {host}
            header_up X-Real-IP {remote_host}
        }
    }
}
CADDY

    sudo caddy validate --config /etc/caddy/Caddyfile \
        && sudo systemctl reload caddy 2>/dev/null || sudo systemctl restart caddy
    _log "Caddyfile written and reloaded"
}

# ── Node via NVM ──────────────────────────────────────────────
install_node() {
    _section "Installing Node.js ${NODE_VERSION} via NVM"
    nvm_load

    if command -v node &>/dev/null; then
        local current
        current=$(node -v | cut -d. -f1 | tr -d 'v')
        [ "$current" -ge "$NODE_VERSION" ] 2>/dev/null \
            && { _log "Node.js $(node -v) already installed — skipping"; return; }
    fi

    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.2/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    \. "$NVM_DIR/nvm.sh"
    nvm install "$NODE_VERSION"
    nvm alias default "$NODE_VERSION"
    nvm use "$NODE_VERSION"
    _log "Node.js $(node -v) installed"
    _log "npm $(npm -v) ready"
}

# ── pnpm ─────────────────────────────────────────────────────
install_pnpm() {
    _section "Installing pnpm"
    nvm_load
    command -v pnpm &>/dev/null \
        && { _log "pnpm $(pnpm -v) already installed — skipping"; return; }
    npm install -g pnpm
    _log "pnpm $(pnpm -v) installed"
}

# ── PM2 ───────────────────────────────────────────────────────
install_pm2() {
    _section "Installing PM2"
    nvm_load
    command -v pm2 &>/dev/null \
        && { _log "PM2 $(pm2 -v) already installed — skipping"; return; }
    npm install -g pm2
    _log "PM2 $(pm2 -v) installed"
}

# ── Ollama ────────────────────────────────────────────────────
install_ollama() {
    _section "Installing Ollama"
    conf_load

    command -v ollama &>/dev/null \
        && { _log "Ollama already installed — skipping"; return; }

    curl -fsSL https://ollama.com/install.sh | sh
    command -v ollama &>/dev/null || _error "Ollama install failed."

    sudo mkdir -p /etc/systemd/system/ollama.service.d
    sudo tee /etc/systemd/system/ollama.service.d/override.conf > /dev/null << 'EOF'
[Service]
Environment="OLLAMA_HOST=0.0.0.0"
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable ollama 2>/dev/null || true
    sudo systemctl start ollama 2>/dev/null || (ollama serve &>/dev/null & sleep 3)
    _log "Ollama installed — listening on 0.0.0.0:${AIOPS_PORT_OLLAMA}"
    echo ""
    echo -e "  ${YELLOW}Pull models after install:${NC}"
    echo "  ollama pull nomic-embed-text      # embeddings/RAG"
    echo "  ollama pull qwen3:4b              # fast chat   — 2.5GB"
    echo "  ollama pull qwen2.5:7b            # general     — 4.7GB"
    echo "  ollama pull qwen2.5-coder:7b      # coding      — 4.7GB"
    echo "  ollama pull deepseek-r1:8b        # reasoning   — 5.2GB"
    echo "  ollama pull llama3.1:8b           # agent tools — 4.9GB"
    echo ""
}

# ── n8n ───────────────────────────────────────────────────────
install_n8n() {
    _section "Installing n8n"
    nvm_load
    command -v n8n &>/dev/null \
        && { _log "n8n already installed — skipping"; return; }
    npm install -g n8n
    _log "n8n installed"
}

# ── OpenWebUI ─────────────────────────────────────────────────
install_openwebui() {
    _section "Installing OpenWebUI ${OPEN_WEBUI_VERSION}"
    pip show open-webui &>/dev/null 2>&1 \
        && { _log "OpenWebUI already installed — skipping"; return; }
    # shellcheck disable=SC2086
    pip install "open-webui==${OPEN_WEBUI_VERSION}" $PIP_FLAGS
    # shellcheck disable=SC2086
    pip install qdrant-client $PIP_FLAGS
    export PATH="$HOME/.local/bin:$PATH"
    _log "OpenWebUI ${OPEN_WEBUI_VERSION} installed"
}

# ── Qdrant ────────────────────────────────────────────────────
install_qdrant() {
    _section "Installing Qdrant ${QDRANT_VERSION}"
    local qdrant_bin="$HOME/qdrant"

    if [ ! -f "$qdrant_bin" ]; then
        curl -L "https://github.com/qdrant/qdrant/releases/download/${QDRANT_VERSION}/qdrant-x86_64-unknown-linux-gnu.tar.gz" \
            -o /tmp/qdrant.tar.gz
        tar -xzf /tmp/qdrant.tar.gz -C "$HOME"
        rm /tmp/qdrant.tar.gz
        chmod +x "$qdrant_bin"
        _log "Qdrant binary downloaded"
    else
        _log "Qdrant binary already exists"
    fi

    if [ ! -f "$QDRANT_DIR/static/index.html" ]; then
        curl -L "https://github.com/qdrant/qdrant-web-ui/releases/download/${QDRANT_WEBUI_VERSION}/dist-qdrant.zip" \
            -o /tmp/qdrant-webui.zip
        sudo apt-get install -y unzip -qq
        unzip -q /tmp/qdrant-webui.zip -d /tmp/qdrant-webui-temp
        cp -r /tmp/qdrant-webui-temp/dist/. "$QDRANT_DIR/static/"
        rm -rf /tmp/qdrant-webui.zip /tmp/qdrant-webui-temp
        _log "Qdrant Web UI installed"
    else
        _log "Qdrant Web UI already exists"
    fi
}

# ── Python Venvs ──────────────────────────────────────────────
setup_venvs() {
    _section "Setting Up Python Virtual Environments"

    _make_venv() {
        local name="$1"; shift
        local dir="$VENVS_DIR/$name"
        if [ ! -d "$dir" ]; then
            python3 -m venv "$dir"
            "$dir/bin/pip" install --upgrade pip -q
            "$dir/bin/pip" install "$@" -q
            _log "$name venv ready"
        else
            _log "$name venv already exists"
        fi
    }

    _make_venv crewai      "crewai==${CREWAI_VERSION}" "crewai-tools==${CREWAI_TOOLS_VERSION}"
    _make_venv aider       "aider-chat==${AIDER_VERSION}"
    _make_venv interpreter "open-interpreter==${OPEN_INTERPRETER_VERSION}"
    _make_venv scrapy      scrapy pandas dedupe email-validator phonenumbers tqdm python-dotenv
    _make_venv playwright  playwright requests dnspython

    if [ ! -d "$VENVS_DIR/playwright/lib" ] || \
       ! "$VENVS_DIR/playwright/bin/playwright" show-trace --help &>/dev/null 2>&1; then
        "$VENVS_DIR/playwright/bin/playwright" install chromium
        "$VENVS_DIR/playwright/bin/playwright" install-deps chromium
        _log "Playwright chromium installed"
    fi
}

# ── CrewAI Studio ─────────────────────────────────────────────
install_crewai_studio() {
    _section "Installing CrewAI Studio"
    local studio_dir="$HOME/CrewAI-Studio"

    if [ ! -d "$studio_dir" ]; then
        git clone https://github.com/strnad/CrewAI-Studio.git "$studio_dir"
        _log "CrewAI Studio cloned"
    else
        _log "CrewAI Studio already cloned"
    fi

    if [ ! -d "$studio_dir/venv" ]; then
        cd "$studio_dir"
        python3 -m venv venv
        source venv/bin/activate
        pip install --upgrade pip -q
        pip install -r requirements.txt -q
        deactivate
        cd "$HOME"
        _log "CrewAI Studio dependencies installed"
    else
        _log "CrewAI Studio venv already exists"
    fi
}

# ── Launcher Scripts ──────────────────────────────────────────
# ALL launchers source $AIOPS_CONF at runtime.
# No ports, domains, IPs, or usernames are hardcoded in launcher text.
# Runtime IP discovery for anything that needs the LAN address.
create_launchers() {
    _section "Creating Launcher Scripts"
    conf_load

    local studio_dir="$HOME/CrewAI-Studio"
    local conf_path="$AIOPS_CONF"

    # ── OpenWebUI ─────────────────────────────────────────────
    # Binary discovery at runtime — handles any username, any
    # Python version, any pip install location. Never hardcoded.
    cat > "$SCRIPTS_DIR/run-openwebui.sh" << OWSCRIPT
#!/bin/bash
source "${conf_path}"

export PATH="\$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
export VECTOR_DB=qdrant
export QDRANT_URI="http://localhost:\${AIOPS_PORT_QDRANT}"
export DATA_DIR="\$HOME/.local/share/open-webui"

# Runtime binary discovery — no hardcoded paths
_find_owu() {
    [ -x "\$HOME/.local/bin/open-webui" ] && echo "\$HOME/.local/bin/open-webui" && return
    for pyver in 3.13 3.12 3.11 3.10; do
        local p="\$HOME/.local/lib/python\${pyver}/site-packages/../../../bin/open-webui"
        [ -x "\$p" ] && echo "\$p" && return
    done
    [ -x "/usr/local/bin/open-webui" ] && echo "/usr/local/bin/open-webui" && return
    command -v open-webui 2>/dev/null
}

OWU_BIN=\$(_find_owu)
if [ -z "\$OWU_BIN" ]; then
    echo "[✗] open-webui binary not found"
    echo "    Reinstall: pip install open-webui --break-system-packages"
    exit 1
fi

echo "[→] open-webui: \$OWU_BIN  port: \${AIOPS_PORT_OPENWEBUI}"
exec "\$OWU_BIN" serve --port "\${AIOPS_PORT_OPENWEBUI}"
OWSCRIPT

    # ── n8n ───────────────────────────────────────────────────
    # Domain and port sourced from conf at runtime.
    # N8N_EDITOR_BASE_URL uses AIOPS_DOMAIN from conf — not hardcoded.
    cat > "$SCRIPTS_DIR/run-n8n.sh" << 'N8NHEAD'
#!/bin/bash
N8NHEAD
    cat >> "$SCRIPTS_DIR/run-n8n.sh" << N8NBODY
source "${conf_path}"
export NVM_DIR="\$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && \\. "\$NVM_DIR/nvm.sh"
export N8N_PORT="\${AIOPS_PORT_N8N}"
export N8N_HOST=0.0.0.0
export N8N_PROTOCOL=http
export N8N_SECURE_COOKIE=false
export N8N_EDITOR_BASE_URL="http://\${AIOPS_DOMAIN}/n8n"
export WEBHOOK_URL="http://\${AIOPS_DOMAIN}/n8n/"
export N8N_USER_FOLDER="\$HOME/.n8n"
exec n8n start
N8NBODY

    # ── Qdrant ────────────────────────────────────────────────
    cat > "$SCRIPTS_DIR/run-qdrant.sh" << QDRANTSCRIPT
#!/bin/bash
source "${conf_path}"
export QDRANT__SERVICE__STATIC_CONTENT_DIR="\${AIOPS_QDRANT_DIR}/static"
export QDRANT__SERVICE__HTTP_PORT="\${AIOPS_PORT_QDRANT}"
cd "\${AIOPS_QDRANT_DIR}"
exec "\$HOME/qdrant"
QDRANTSCRIPT

    # ── CrewAI Studio ─────────────────────────────────────────
    # --server.baseUrlPath sourced from port config — always /agents
    # which matches the Caddyfile handle block
    cat > "$SCRIPTS_DIR/run-crewai-studio.sh" << CREWSCRIPT
#!/bin/bash
source "${conf_path}"
cd "${studio_dir}"
exec "${studio_dir}/venv/bin/streamlit" run app/app.py \\
    --server.port "\${AIOPS_PORT_CREWAI}" \\
    --server.address 0.0.0.0 \\
    --server.headless true \\
    --server.baseUrlPath /agents
CREWSCRIPT

    # ── AI tool launchers (source conf for venv path) ─────────
    cat > "$SCRIPTS_DIR/run-aider.sh" << AIDSCRIPT
#!/bin/bash
source "${conf_path}"
source "\${AIOPS_VENVS_DIR}/aider/bin/activate"
MODEL="\${1:-ollama/qwen2.5-coder:7b}"
exec aider --model "\$MODEL" "\${@:2}"
AIDSCRIPT

    cat > "$SCRIPTS_DIR/run-crew.sh" << CREWRSCRIPT
#!/bin/bash
source "${conf_path}"
source "\${AIOPS_VENVS_DIR}/crewai/bin/activate"
exec python3 "\$@"
CREWRSCRIPT

    cat > "$SCRIPTS_DIR/run-interpreter.sh" << INTRSCRIPT
#!/bin/bash
source "${conf_path}"
source "\${AIOPS_VENVS_DIR}/interpreter/bin/activate"
MODEL="\${1:-ollama/llama3.1:8b}"
exec interpreter --model "\$MODEL"
INTRSCRIPT

    cat > "$SCRIPTS_DIR/run-scrapy.sh" << SCRAPYSCRIPT
#!/bin/bash
source "${conf_path}"
source "\${AIOPS_VENVS_DIR}/scrapy/bin/activate"
exec python3 "\$@"
SCRAPYSCRIPT

    cat > "$SCRIPTS_DIR/run-playwright.sh" << PWSCRIPT
#!/bin/bash
source "${conf_path}"
source "\${AIOPS_VENVS_DIR}/playwright/bin/activate"
exec python3 "\$@"
PWSCRIPT

    chmod +x "$SCRIPTS_DIR"/*.sh
    _log "Launcher scripts created — all source $AIOPS_CONF at runtime"
}

# ── Shell Aliases ─────────────────────────────────────────────
setup_aliases() {
    _section "Setting Up Shell Aliases"
    conf_load

    sed -i '/# AIOPS START/,/# AIOPS END/d' ~/.bashrc

    cat >> ~/.bashrc << BASHRC

# AIOPS START — Quantocos AI Labs v5.3.0
export PATH="\$HOME/.local/bin:\$HOME/.openfang/bin:\$PATH"
export NVM_DIR="\$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && \\. "\$NVM_DIR/nvm.sh"

# Load AIOPS config
[ -f "${AIOPS_CONF}" ] && source "${AIOPS_CONF}"

# Service management
alias ai-status='pm2 status'
alias ai-start='pm2 resurrect'
alias ai-stop='pm2 stop all'
alias ai-restart='pm2 restart all'
alias ai-logs='pm2 logs'
alias ai-config='nano ${AIOPS_CONF}'
alias aiops-caddy-regen='source ${AIOPS_CONF} && bash -c "$(declare -f write_caddyfile conf_load _log _warn _info _section)" && write_caddyfile'

# AI tools
alias aider='${SCRIPTS_DIR}/run-aider.sh'
alias crew='${SCRIPTS_DIR}/run-crew.sh'
alias interpreter='${SCRIPTS_DIR}/run-interpreter.sh'
alias scrape='${SCRIPTS_DIR}/run-scrapy.sh'
alias automate='${SCRIPTS_DIR}/run-playwright.sh'

# Chat (model names not hardcoded — use ollama list to see what you've pulled)
alias chat='ollama run qwen3:4b'
alias chat-coder='ollama run qwen2.5-coder:7b'
alias chat-reason='ollama run deepseek-r1:8b'
alias models='ollama list'

# Service URLs — read from config at shell open, always accurate
alias ai-urls='source ${AIOPS_CONF} && LOCAL_IP=\$(ip route get 1 2>/dev/null | awk "{print \$7; exit}") && echo "OpenWebUI  http://\${LOCAL_IP}:\${AIOPS_PORT_OPENWEBUI}" && echo "n8n        http://\${AIOPS_DOMAIN}/n8n" && echo "Qdrant     http://\${LOCAL_IP}:\${AIOPS_PORT_QDRANT}" && echo "Agents     http://\${AIOPS_DOMAIN}/agents" && echo "Ollama     http://\${LOCAL_IP}:\${AIOPS_PORT_OLLAMA}"'

# PM2 auto-resurrect
[[ -z \$(pm2 list 2>/dev/null | grep online) ]] && pm2 resurrect 2>/dev/null

# AIOPS END
BASHRC

    _log "Shell aliases written to ~/.bashrc"
}

# ── PM2 Services ──────────────────────────────────────────────
setup_pm2_services() {
    _section "Configuring PM2 Services"
    nvm_load
    conf_load

    pm2 kill 2>/dev/null || true
    rm -f ~/.pm2/dump.pm2 2>/dev/null || true
    sleep 2

    # Clear ports using values from config — not hardcoded numbers
    for port in "$AIOPS_PORT_N8N" "$AIOPS_PORT_OPENWEBUI" "$AIOPS_PORT_QDRANT" "$AIOPS_PORT_CREWAI"; do
        sudo fuser -k "${port}/tcp" 2>/dev/null || true
    done
    sleep 2

    pm2 start "$SCRIPTS_DIR/run-n8n.sh"          --name n8n
    pm2 start "$SCRIPTS_DIR/run-openwebui.sh"     --name openwebui
    pm2 start "$SCRIPTS_DIR/run-qdrant.sh"        --name qdrant --cwd "$QDRANT_DIR"
    pm2 start "$SCRIPTS_DIR/run-crewai-studio.sh" --name crewai-studio

    sleep 5
    pm2 save
    _log "PM2 services started and saved"
}

# ── Sample crew ───────────────────────────────────────────────
create_sample_crew() {
    _section "Creating Sample Files"
    conf_load

    cat > "$AGENTS_DIR/crews/sample_crew.py" << 'PYEOF'
"""
Sample CrewAI crew — Quantocos AI Labs
Reads Ollama port from AIOPS config at runtime.
Run: crew ~/agents/crews/sample_crew.py
"""
import os
import subprocess

def get_ollama_url():
    """Read port from aiops.conf rather than hardcoding it."""
    conf = os.path.expanduser("~/aiops-server/aiops.conf")
    port = "11434"  # fallback default
    if os.path.exists(conf):
        with open(conf) as f:
            for line in f:
                if line.startswith("AIOPS_PORT_OLLAMA="):
                    port = line.strip().split("=", 1)[1].strip('"')
    return f"http://localhost:{port}"

from crewai import Agent, Task, Crew, LLM

llm = LLM(model="ollama/llama3.1:8b", base_url=get_ollama_url())

researcher = Agent(
    role="Research Analyst",
    goal="Research and summarize information accurately",
    backstory="Expert researcher with attention to detail",
    llm=llm, verbose=True
)
writer = Agent(
    role="Content Writer",
    goal="Write clear, engaging content",
    backstory="Professional business content writer",
    llm=llm, verbose=True
)

research_task = Task(
    description="List 3 benefits of local AI for small businesses",
    expected_output="3 bullet points, one sentence each",
    agent=researcher
)
write_task = Task(
    description="Write a 100 word LinkedIn post from the research",
    expected_output="A ready-to-post LinkedIn update",
    agent=writer
)

crew = Crew(agents=[researcher, writer], tasks=[research_task, write_task], verbose=True)

if __name__ == "__main__":
    result = crew.kickoff()
    print("\n=== OUTPUT ===")
    print(result)
PYEOF

    _log "Sample crew: $AGENTS_DIR/crews/sample_crew.py"
}

# ── Core install summary ──────────────────────────────────────
print_core_summary() {
    _section "Core Install Complete"
    conf_load

    # IP discovered at print time — not stored
    local local_ip
    local_ip=$(ip route get 1 2>/dev/null | awk '{print $7; exit}' || echo "YOUR_IP")

    echo -e "${BOLD}${GREEN}"
    echo "  ╔══════════════════════════════════════════════════════════╗"
    echo "  ║   AIOPS v5.3.0 — CORE STACK READY                       ║"
    echo "  ╠══════════════════════════════════════════════════════════╣"
    echo "  ║   Service         Port                                   ║"
    echo "  ║   ─────────────── ──────────────────────────────────     ║"
    printf "  ║   OpenWebUI       http://%-33s║\n" "${local_ip}:${AIOPS_PORT_OPENWEBUI}"
    printf "  ║   n8n             http://%-33s║\n" "${AIOPS_DOMAIN}/n8n"
    printf "  ║   Qdrant UI       http://%-33s║\n" "${local_ip}:${AIOPS_PORT_QDRANT}"
    printf "  ║   CrewAI Studio   http://%-33s║\n" "${AIOPS_DOMAIN}/agents"
    printf "  ║   Ollama          http://%-33s║\n" "${local_ip}:${AIOPS_PORT_OLLAMA}"
    echo "  ╠══════════════════════════════════════════════════════════╣"
    printf "  ║   Config:  %-46s║\n" "${AIOPS_CONF}"
    echo "  ╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    echo -e "${BOLD}Next Steps:${NC}"
    echo "  1. Pull a model:   ollama pull qwen3:4b"
    echo "  2. Reload shell:   source ~/.bashrc"
    echo "  3. Check status:   ai-status"
    echo "  4. Show URLs:      ai-urls"
    echo "  5. Edit config:    ai-config"
    echo ""
    echo -e "${CYAN}Config: $AIOPS_CONF${NC}"
    echo -e "${CYAN}Log:    $LOG_FILE${NC}"
    echo ""
}

# ============================================================
# PART 2 — ADDONS LOOP
# ============================================================

addon_dependencies() {
    _section_add "Installing Shared Dependencies"
    conf_load

    if ! command -v psql &>/dev/null; then
        sudo apt-get update -qq
        sudo apt-get install -y postgresql postgresql-contrib
        sudo systemctl enable postgresql && sudo systemctl start postgresql
        _log_add "PostgreSQL installed"
    else
        _log_add "PostgreSQL already installed"
    fi

    if ! command -v redis-server &>/dev/null; then
        sudo apt-get install -y redis-server
        sudo systemctl enable redis-server && sudo systemctl start redis-server
        _log_add "Redis installed"
    else
        _log_add "Redis already installed"
    fi

    if [ ! -d "$VENVS_DIR/firecrawl" ]; then
        python3 -m venv "$VENVS_DIR/firecrawl"
        "$VENVS_DIR/firecrawl/bin/pip" install --upgrade pip -q
        "$VENVS_DIR/firecrawl/bin/pip" install firecrawl-py -q
        cat > "$SCRIPTS_DIR/run-firecrawl.sh" << FSCRIPT
#!/bin/bash
source "${AIOPS_CONF}"
source "\${AIOPS_VENVS_DIR}/firecrawl/bin/activate"
exec python3 "\$@"
FSCRIPT
        chmod +x "$SCRIPTS_DIR/run-firecrawl.sh"
        _log_add "Firecrawl venv ready"
    else
        _log_add "Firecrawl venv already exists"
    fi
}

addon_twenty_crm() {
    _section_add "Installing Twenty CRM"
    conf_load
    nvm_load

    local twenty_dir="$HOME/twenty"

    [ ! -d "$twenty_dir" ] \
        && git clone https://github.com/twentyhq/twenty.git "$twenty_dir" \
        && _log_add "Twenty CRM cloned" \
        || _log_add "Twenty CRM already cloned"

    sudo -u postgres psql -lqt 2>/dev/null | grep -q twenty || {
        sudo -u postgres psql -c "CREATE USER twenty WITH PASSWORD 'twenty_password';" 2>/dev/null || true
        sudo -u postgres psql -c "CREATE DATABASE twenty OWNER twenty;" 2>/dev/null || true
        _log_add "Twenty CRM database created"
    }

    cd "$twenty_dir"
    [ ! -f ".env" ] && {
        local secret; secret=$(openssl rand -base64 24 | tr -d '=+/' | head -c 32)
        cat > .env << ENVEOF
APP_SECRET=${secret}
DATABASE_URL=postgresql://twenty:twenty_password@localhost:5432/twenty
FRONT_BASE_URL=http://localhost:${AIOPS_PORT_TWENTY}
REDIS_URL=redis://localhost:6379
ENVEOF
        _log_add ".env configured"
    }

    _info_add "Installing via pnpm (monorepo — npm will not work)..."
    pnpm install

    cat > "$SCRIPTS_DIR/run-twenty.sh" << TSCRIPT
#!/bin/bash
source "${AIOPS_CONF}"
export NVM_DIR="\$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && \\. "\$NVM_DIR/nvm.sh"
cd "${twenty_dir}"
exec pnpm nx start
TSCRIPT
    chmod +x "$SCRIPTS_DIR/run-twenty.sh"
    pm2 start "$SCRIPTS_DIR/run-twenty.sh" --name twenty 2>/dev/null || true
    pm2 save
    cd "$HOME"

    _log_add "Twenty CRM installed"
    local local_ip; local_ip=$(ip route get 1 2>/dev/null | awk '{print $7; exit}')
    echo "  → http://${local_ip}:${AIOPS_PORT_TWENTY}"
}

addon_listmonk() {
    _section_add "Installing Listmonk"
    conf_load

    local lm_bin="$HOME/listmonk"
    local lm_dir="$HOME/listmonk-data"
    mkdir -p "$lm_dir"

    if [ ! -f "$lm_bin" ]; then
        local lm_url
        lm_url=$(curl -s https://api.github.com/repos/knadh/listmonk/releases/latest \
            | grep "browser_download_url.*linux_amd64.tar.gz" | cut -d'"' -f4 | head -1)
        [ -z "$lm_url" ] && lm_url="https://github.com/knadh/listmonk/releases/download/v4.1.0/listmonk_4.1.0_linux_amd64.tar.gz"
        curl -L "$lm_url" -o /tmp/listmonk.tar.gz
        tar -xzf /tmp/listmonk.tar.gz -C /tmp/
        mv /tmp/listmonk "$lm_bin" 2>/dev/null \
            || find /tmp -name "listmonk" -type f | head -1 | xargs -I{} mv {} "$lm_bin"
        chmod +x "$lm_bin"
        rm -f /tmp/listmonk.tar.gz
        _log_add "Listmonk binary downloaded"
    else
        _log_add "Listmonk binary already exists"
    fi

    sudo -u postgres psql -lqt 2>/dev/null | grep -q listmonk || {
        sudo -u postgres psql -c "CREATE USER listmonk WITH PASSWORD 'listmonk_password';" 2>/dev/null || true
        sudo -u postgres psql -c "CREATE DATABASE listmonk OWNER listmonk;" 2>/dev/null || true
    }

    if [ ! -f "$lm_dir/config.toml" ]; then
        cat > "$lm_dir/config.toml" << TOML
[app]
address = "0.0.0.0:${AIOPS_PORT_LISTMONK}"
admin_username = "admin"
admin_password = "change_me_now"

[db]
host = "localhost"
port = 5432
user = "listmonk"
password = "listmonk_password"
database = "listmonk"
ssl_mode = "disable"
TOML
        "$lm_bin" --config "$lm_dir/config.toml" --install --yes 2>/dev/null || true
        _log_add "Listmonk database installed"
    fi

    cat > "$SCRIPTS_DIR/run-listmonk.sh" << LSCRIPT
#!/bin/bash
source "${AIOPS_CONF}"
exec "${lm_bin}" --config "${lm_dir}/config.toml"
LSCRIPT
    chmod +x "$SCRIPTS_DIR/run-listmonk.sh"
    pm2 start "$SCRIPTS_DIR/run-listmonk.sh" --name listmonk 2>/dev/null || true
    pm2 save

    _log_add "Listmonk installed"
    local local_ip; local_ip=$(ip route get 1 2>/dev/null | awk '{print $7; exit}')
    echo "  → http://${local_ip}:${AIOPS_PORT_LISTMONK}  (admin / change_me_now)"
    echo -e "  ${RED}⚠  Change password on first login${NC}"
}

addon_openfang() {
    _section_add "Installing OpenFang"
    _warn_add "Checking OpenFang availability..."

    if curl -fsSL --max-time 10 https://openfang.sh/install -o /tmp/openfang-install.sh 2>/dev/null; then
        bash /tmp/openfang-install.sh
        rm -f /tmp/openfang-install.sh
        # Export in-session immediately — installer writes to ~/.bashrc
        # but the running script won't source it
        export PATH="$HOME/.openfang/bin:$PATH"
        if command -v openfang &>/dev/null; then
            _log_add "OpenFang $(openfang --version 2>/dev/null) installed"
            for hand in lead browser researcher twitter; do
                openfang hand activate "$hand" 2>/dev/null \
                    && _log_add "Hand activated: $hand" \
                    || _warn_add "Hand activation failed: $hand"
            done
            echo "  Config: ~/.openfang/config.yaml"
            echo "  Init:   openfang init"
        else
            _warn_add "OpenFang binary not found after install — check ~/.openfang/bin"
        fi
    else
        if [ ! -d "$VENVS_DIR/openfang" ]; then
            python3 -m venv "$VENVS_DIR/openfang"
            "$VENVS_DIR/openfang/bin/pip" install --upgrade pip -q
            "$VENVS_DIR/openfang/bin/pip" install openfang -q 2>/dev/null \
                && { cat > "$SCRIPTS_DIR/run-openfang.sh" << OFSCRIPT
#!/bin/bash
source "${AIOPS_CONF}"
exec "\${AIOPS_VENVS_DIR}/openfang/bin/openfang" "\$@"
OFSCRIPT
                chmod +x "$SCRIPTS_DIR/run-openfang.sh"
                _log_add "OpenFang installed via pip"; } \
                || _warn_add "OpenFang not yet available — check https://github.com/openfang"
        fi
    fi
}

addon_mautic() {
    _section_add "Installing Mautic"
    conf_load

    command -v php &>/dev/null || {
        _info_add "Installing PHP 8.1..."
        sudo apt-get install -y \
            php8.1 php8.1-cli php8.1-fpm \
            php8.1-mysql php8.1-xml php8.1-mbstring \
            php8.1-curl php8.1-zip php8.1-gd \
            php8.1-intl php8.1-bcmath composer -q
        _log_add "PHP 8.1 installed"
    }

    command -v mysql &>/dev/null || {
        sudo apt-get install -y mariadb-server -q
        sudo systemctl enable mariadb && sudo systemctl start mariadb
        sudo mysql -e "CREATE DATABASE IF NOT EXISTS mautic CHARACTER SET utf8mb4;" 2>/dev/null || true
        sudo mysql -e "CREATE USER IF NOT EXISTS 'mautic'@'localhost' IDENTIFIED BY 'mautic_password';" 2>/dev/null || true
        sudo mysql -e "GRANT ALL PRIVILEGES ON mautic.* TO 'mautic'@'localhost';" 2>/dev/null || true
        sudo mysql -e "FLUSH PRIVILEGES;" 2>/dev/null || true
        _log_add "MariaDB configured"
    }

    local mautic_dir="$HOME/mautic"
    if [ ! -d "$mautic_dir" ]; then
        _info_add "Installing Mautic via Composer..."
        composer create-project mautic/recommended-project:^5 "$mautic_dir" \
            --no-interaction -q 2>/dev/null \
            || composer create-project mautic/recommended-project "$mautic_dir" --no-interaction
        cat > "$mautic_dir/.env.local" << MENV
APP_URL=http://localhost:${AIOPS_PORT_MAUTIC}
APP_ENV=prod
DB_HOST=localhost
DB_PORT=3306
DB_NAME=mautic
DB_USER=mautic
DB_PASSWD=mautic_password
MENV
        _log_add "Mautic installed"
    else
        _log_add "Mautic already installed"
    fi

    cat > "$SCRIPTS_DIR/run-mautic.sh" << MSCRIPT
#!/bin/bash
source "${AIOPS_CONF}"
cd "${mautic_dir}"
export APP_ENV=prod
exec php -S 0.0.0.0:\${AIOPS_PORT_MAUTIC} public/index.php
MSCRIPT
    chmod +x "$SCRIPTS_DIR/run-mautic.sh"
    pm2 start "$SCRIPTS_DIR/run-mautic.sh" --name mautic 2>/dev/null || true
    pm2 save

    _log_add "Mautic running"
    local local_ip; local_ip=$(ip route get 1 2>/dev/null | awk '{print $7; exit}')
    echo "  → http://${local_ip}:${AIOPS_PORT_MAUTIC}"
}

addon_chatwoot() {
    _section_add "Installing Chatwoot"
    conf_load

    command -v ruby &>/dev/null \
        && _log_add "Ruby: $(ruby -v)" \
        || { sudo apt-get install -y ruby ruby-dev -q && _log_add "Ruby: $(ruby -v)"; }

    # User gem install — system Ruby dir is root-owned on Ubuntu 22/24
    local ruby_minor; ruby_minor=$(ruby -e 'puts RUBY_VERSION.split(".")[0..1].join(".")' 2>/dev/null || echo "3.2")
    local gem_bin="$HOME/.gem/ruby/${ruby_minor}.0/bin"
    command -v bundle &>/dev/null || [ -f "$gem_bin/bundle" ] \
        || gem install bundler --user-install
    export PATH="$gem_bin:$PATH"

    local cw_dir="$HOME/chatwoot"
    [ ! -d "$cw_dir" ] \
        && git clone https://github.com/chatwoot/chatwoot.git "$cw_dir" \
        && _log_add "Chatwoot cloned" \
        || _log_add "Chatwoot already cloned"

    sudo -u postgres psql -lqt 2>/dev/null | grep -q chatwoot || {
        sudo -u postgres psql -c "CREATE USER chatwoot WITH PASSWORD 'chatwoot_password';" 2>/dev/null || true
        sudo -u postgres psql -c "CREATE DATABASE chatwoot OWNER chatwoot;" 2>/dev/null || true
    }

    cd "$cw_dir"
    if [ ! -f ".env" ]; then
        cp .env.example .env
        local secret; secret=$(openssl rand -hex 64)
        sed -i "s|SECRET_KEY_BASE=.*|SECRET_KEY_BASE=${secret}|" .env
        sed -i "s|DATABASE_URL=.*|DATABASE_URL=postgresql://chatwoot:chatwoot_password@localhost:5432/chatwoot|" .env
        sed -i "s|REDIS_URL=.*|REDIS_URL=redis://localhost:6379|" .env
        sed -i "s|PORT=3000|PORT=${AIOPS_PORT_CHATWOOT}|" .env
        _log_add ".env configured"
    fi

    _info_add "Installing Chatwoot gems..."
    bundle install -q 2>/dev/null || (gem install bundler --user-install && bundle install -q)
    RAILS_ENV=production bundle exec rails db:chatwoot_prepare 2>/dev/null \
        || RAILS_ENV=production bundle exec rails db:migrate 2>/dev/null || true

    local bundle_bin; bundle_bin=$(command -v bundle 2>/dev/null || echo "$gem_bin/bundle")

    cat > "$SCRIPTS_DIR/run-chatwoot.sh" << CWSCRIPT
#!/bin/bash
source "${AIOPS_CONF}"
export PATH="${gem_bin}:\$PATH"
cd "${cw_dir}"
export RAILS_ENV=production
exec ${bundle_bin} exec rails server -b 0.0.0.0 -p \${AIOPS_PORT_CHATWOOT}
CWSCRIPT

    cat > "$SCRIPTS_DIR/run-chatwoot-worker.sh" << CWWSCRIPT
#!/bin/bash
source "${AIOPS_CONF}"
export PATH="${gem_bin}:\$PATH"
cd "${cw_dir}"
export RAILS_ENV=production
exec ${bundle_bin} exec sidekiq
CWWSCRIPT

    chmod +x "$SCRIPTS_DIR/run-chatwoot.sh" "$SCRIPTS_DIR/run-chatwoot-worker.sh"
    pm2 start "$SCRIPTS_DIR/run-chatwoot.sh"        --name chatwoot
    pm2 start "$SCRIPTS_DIR/run-chatwoot-worker.sh" --name chatwoot-worker
    pm2 save
    cd "$HOME"

    _log_add "Chatwoot installed"
    local local_ip; local_ip=$(ip route get 1 2>/dev/null | awk '{print $7; exit}')
    echo "  → http://${local_ip}:${AIOPS_PORT_CHATWOOT}"
}

addon_calcom() {
    _section_add "Installing Cal.com"
    conf_load
    nvm_load

    local cal_dir="$HOME/calcom"
    [ ! -d "$cal_dir" ] \
        && git clone https://github.com/calcom/cal.com.git "$cal_dir" \
        && _log_add "Cal.com cloned" \
        || _log_add "Cal.com already cloned"

    sudo -u postgres psql -lqt 2>/dev/null | grep -q calcom || {
        sudo -u postgres psql -c "CREATE USER calcom WITH PASSWORD 'calcom_password';" 2>/dev/null || true
        sudo -u postgres psql -c "CREATE DATABASE calcom OWNER calcom;" 2>/dev/null || true
    }

    cd "$cal_dir"
    if [ ! -f ".env" ]; then
        cp .env.example .env 2>/dev/null || touch .env
        local secret; secret=$(openssl rand -base64 32)
        cat >> .env << CAENV
DATABASE_URL=postgresql://calcom:calcom_password@localhost:5432/calcom
NEXTAUTH_SECRET=${secret}
NEXTAUTH_URL=http://localhost:${AIOPS_PORT_CALCOM}
NEXT_PUBLIC_APP_URL=http://localhost:${AIOPS_PORT_CALCOM}
PORT=${AIOPS_PORT_CALCOM}
CAENV
        _log_add ".env configured"
    fi

    _info_add "Installing Cal.com via pnpm (monorepo — npm will not work)..."
    pnpm install
    pnpm prisma generate 2>/dev/null || true
    pnpm prisma db push 2>/dev/null || true

    cat > "$SCRIPTS_DIR/run-calcom.sh" << CASCRIPT
#!/bin/bash
source "${AIOPS_CONF}"
export NVM_DIR="\$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && \\. "\$NVM_DIR/nvm.sh"
cd "${cal_dir}"
exec pnpm next start -p \${AIOPS_PORT_CALCOM}
CASCRIPT
    chmod +x "$SCRIPTS_DIR/run-calcom.sh"
    pm2 start "$SCRIPTS_DIR/run-calcom.sh" --name calcom 2>/dev/null || true
    pm2 save
    cd "$HOME"

    _log_add "Cal.com installed"
    local local_ip; local_ip=$(ip route get 1 2>/dev/null | awk '{print $7; exit}')
    echo "  → http://${local_ip}:${AIOPS_PORT_CALCOM}"
}

addon_monitors() {
    _section_add "Installing System Monitors"
    sudo apt-get update -qq
    command -v htop  &>/dev/null && _log_add "htop already installed"  || { sudo apt-get install -y htop  -q; _log_add "htop installed"; }
    command -v nvtop &>/dev/null && _log_add "nvtop already installed" || { sudo apt-get install -y nvtop -q; _log_add "nvtop installed"; }
    echo "  htop   → CPU, RAM, processes"
    echo "  nvtop  → GPU VRAM, temperature"
}

addon_netdata() {
    _section_add "Installing Netdata"
    conf_load

    command -v netdata &>/dev/null \
        || { curl -fsSL https://my-netdata.io/kickstart.sh | sh -s -- --non-interactive 2>/dev/null || true; _log_add "Netdata installed"; } \
        && _log_add "Netdata already installed"

    local nd_conf; nd_conf=$(find /etc/netdata -name "netdata.conf" 2>/dev/null | head -1)
    if [ -n "$nd_conf" ]; then
        sudo sed -i 's/# *bind to.*/bind to = 0.0.0.0/' "$nd_conf" 2>/dev/null || true
        sudo sed -i 's/bind to = localhost/bind to = 0.0.0.0/' "$nd_conf" 2>/dev/null || true
        sudo systemctl restart netdata 2>/dev/null || true
    fi

    _log_add "Netdata configured"
    local local_ip; local_ip=$(ip route get 1 2>/dev/null | awk '{print $7; exit}')
    echo "  → http://${local_ip}:${AIOPS_PORT_NETDATA}"
    echo "  → http://${AIOPS_DOMAIN}/monitor"
}

# ── Addons menu ───────────────────────────────────────────────
show_addons_menu() {
    conf_load
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║         AIOPS ADDONS — INSTALL MENU  v5.3.0             ║${NC}"
    echo -e "${BOLD}╠══════════════════════════════════════════════════════════╣${NC}"
    echo "║  [d]  Shared deps     PostgreSQL · Redis · Firecrawl     ║"
    echo "║  [1]  Twenty CRM      Lead + deal management             ║"
    echo "║  [2]  Listmonk        Email campaigns (binary)           ║"
    echo "║  [3]  OpenFang        AI agent Hands                     ║"
    echo "║  [4]  Mautic          Full marketing automation (PHP)    ║"
    echo "║  [5]  Chatwoot        Unified inbox                      ║"
    echo "║  [6]  Cal.com         Booking and scheduling             ║"
    echo "║  [7]  Monitors        htop + nvtop                       ║"
    echo "║  [8]  Netdata         Full system dashboard              ║"
    echo -e "${BOLD}╠══════════════════════════════════════════════════════════╣${NC}"
    echo "║  [a]  Core GTM        d + 1 + 2 + 3                     ║"
    echo "║  [b]  Full GTM        d + 1 + 2 + 3 + 4 + 5 + 6         ║"
    echo "║  [m]  All monitors    7 + 8                              ║"
    echo -e "${BOLD}╠══════════════════════════════════════════════════════════╣${NC}"
    echo "║  [s]  PM2 status                                         ║"
    echo -e "${BOLD}║  [exit]  Done                                            ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

run_addon() {
    case "$1" in
        d|D) addon_dependencies ;;
        1)   addon_twenty_crm ;;
        2)   addon_listmonk ;;
        3)   addon_openfang ;;
        4)   addon_mautic ;;
        5)   addon_chatwoot ;;
        6)   addon_calcom ;;
        7)   addon_monitors ;;
        8)   addon_netdata ;;
        a|A) addon_dependencies; addon_twenty_crm; addon_listmonk; addon_openfang ;;
        b|B) addon_dependencies; addon_twenty_crm; addon_listmonk; addon_openfang; addon_mautic; addon_chatwoot; addon_calcom ;;
        m|M) addon_monitors; addon_netdata ;;
        s|S) nvm_load; pm2 status ;;
        "exit"|"EXIT"|"q"|"Q") return 1 ;;
        *) echo -e "${YELLOW}[!] Unknown: $1${NC}" ;;
    esac
    return 0
}

addons_loop() {
    banner_addons
    echo -e "${CYAN}Core install complete. Install optional tools below.${NC}"
    echo -e "${YELLOW}Type 'exit' to finish. Space-separate multiple choices: d 1 2${NC}"
    echo ""

    while true; do
        show_addons_menu
        read -rp "$(echo -e "${YELLOW}Choice: ${NC}")" raw_input
        local choice; choice=$(echo "$raw_input" | xargs 2>/dev/null || echo "$raw_input")

        [[ "$choice" =~ ^(exit|EXIT|q|Q)$ ]] && { echo -e "${BOLD}${GREEN}Done.${NC}"; break; }

        if [[ "$choice" == *" "* ]]; then
            for item in $choice; do
                [[ "$item" =~ ^(exit|EXIT|q|Q)$ ]] && return
                run_addon "$item" || return
            done
        else
            run_addon "$choice" || break
        fi

        echo -e "\n${CYAN}Done. Back to menu...${NC}"
        sleep 1
    done
}

# ── Final summary ─────────────────────────────────────────────
print_final_summary() {
    conf_load
    local local_ip; local_ip=$(ip route get 1 2>/dev/null | awk '{print $7; exit}' || echo "YOUR_IP")

    echo ""
    echo -e "${BOLD}${GREEN}"
    echo "  ╔══════════════════════════════════════════════════════════╗"
    echo "  ║   AIOPS v5.3.0 — SETUP COMPLETE                         ║"
    echo "  ╠══════════════════════════════════════════════════════════╣"
    printf "  ║   OpenWebUI     http://%-34s║\n" "${local_ip}:${AIOPS_PORT_OPENWEBUI}"
    printf "  ║   n8n           http://%-34s║\n" "${AIOPS_DOMAIN}/n8n"
    printf "  ║   Qdrant        http://%-34s║\n" "${local_ip}:${AIOPS_PORT_QDRANT}"
    printf "  ║   CrewAI Studio http://%-34s║\n" "${AIOPS_DOMAIN}/agents"
    printf "  ║   Ollama        http://%-34s║\n" "${local_ip}:${AIOPS_PORT_OLLAMA}"
    echo "  ╠══════════════════════════════════════════════════════════╣"
    echo "  ║   ai-status   ai-logs   ai-restart   ai-urls   ai-config ║"
    echo "  ╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "  ${BOLD}Config:${NC} ${AIOPS_CONF}"
    echo -e "  ${BOLD}Reload:${NC} source ~/.bashrc"
    echo ""
    echo -e "${BOLD}${CYAN}Quantocos AI Labs${NC}"
    echo -e "${CYAN}\"Build with intelligence. Operate with precision.\"${NC}"
    echo ""
}

# ============================================================
# MAIN
# ============================================================
main() {
    clear
    banner_core

    echo -e "${BOLD}AIOPS v5.3.0 — Full Stack Installer${NC}"
    echo ""
    echo "  PART 1 — Core (automatic after first confirm)"
    echo "  PART 2 — Addons (interactive menu)"
    echo ""

    confirm "Proceed with installation?" || { echo "Cancelled."; exit 0; }

    preinit
    preflight
    setup_config       # writes ~/aiops-server/aiops.conf — single source of truth
    setup_dirs
    install_system_deps
    setup_wsl_system
    setup_mdns
    install_caddy
    install_node
    install_pnpm
    install_pm2
    install_ollama
    install_n8n
    install_openwebui
    install_qdrant
    setup_venvs
    install_crewai_studio
    create_launchers   # all launchers source aiops.conf at runtime
    setup_aliases
    setup_pm2_services
    create_sample_crew
    print_core_summary

    addons_loop

    print_final_summary
}

main "$@"
