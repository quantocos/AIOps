#!/bin/bash
# ============================================================
# AIOPS.SH — Local AI Operations Server
# Version:    5.0.0
# Author:     Quantocos AI Labs
# Compatible: WSL2 Ubuntu 22.04 / 24.04
# Usage:      bash aiops.sh
#
# STRUCTURE:
#   PART 1 — Core stack install (runs once)
#   PART 2 — Addons loop (runs until user types 'exit')
# ============================================================

set -e

# ── Colors ───────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# ── Config ───────────────────────────────────────────────────
AIOPS_HOME="$HOME/aiops-server"
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

# ── Runtime globals (set during execution) ───────────────────
UBUNTU_VERSION="0"
PIP_FLAGS=""
LOCAL_DOMAIN="aiops.local"
LOCAL_IP=""

# ── Helpers ──────────────────────────────────────────────────
_log_core()    { echo -e "${GREEN}[✓]${NC} $1" | tee -a "$LOG_FILE"; }
_warn_core()   { echo -e "${YELLOW}[!]${NC} $1" | tee -a "$LOG_FILE"; }
_error_core()  { echo -e "${RED}[✗]${NC} $1" | tee -a "$LOG_FILE"; exit 1; }
_info_core()   { echo -e "${CYAN}[→]${NC} $1" | tee -a "$LOG_FILE"; }
_section_core(){ echo -e "\n${BOLD}${BLUE}══ $1 ══${NC}\n" | tee -a "$LOG_FILE"; }

_log_add()    { echo -e "${GREEN}[✓]${NC} $1" | tee -a "$ADDONS_LOG"; }
_warn_add()   { echo -e "${YELLOW}[!]${NC} $1" | tee -a "$ADDONS_LOG"; }
_error_add()  { echo -e "${RED}[✗]${NC} $1" | tee -a "$ADDONS_LOG"; }
_info_add()   { echo -e "${CYAN}[→]${NC} $1" | tee -a "$ADDONS_LOG"; }
_section_add(){ echo -e "\n${BOLD}${MAGENTA}══ $1 ══${NC}\n" | tee -a "$ADDONS_LOG"; }

confirm() {
    read -rp "$(echo -e "${YELLOW}$1 [y/N]: ${NC}")" r
    [[ "$r" =~ ^[Yy]$ ]]
}

nvm_load() {
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
}

# ============================================================
# BANNER
# ============================================================
banner_core() {
cat << 'BANNER'

   _   ___ ___  ___  ___
  /_\ |_ _/ _ \| _ \/ __|
 / _ \ | | (_) |  _/\__ \
/_/ \_\___\___/|_|  |___/

  Local AI Operations Server
  Quantocos AI Labs — v5.0.0
  WSL2 Ubuntu 22.04 / 24.04

BANNER
}

banner_addons() {
cat << 'BANNER'

   _   ___ ___  ___  ___      _   ___  ___   ___  _  _ ___
  /_\ |_ _/ _ \| _ \/ __|    /_\ |   \|   \ / _ \| \| / __|
 / _ \ | | (_) |  _/\__ \   / _ \| |) | |) | (_) | .` \__ \
/_/ \_\___\___/|_|  |___/  /_/ \_\___/|___/ \___/|_|\_|___/

  Optional Tools Installer
  Quantocos AI Labs — v5.0.0

BANNER
}

# ============================================================
# PART 1 — CORE INSTALL
# ============================================================

# ── Pre-boot: create log dir before any logging ──────────────
preinit() {
    mkdir -p "$AIOPS_HOME"
    touch "$LOG_FILE"
    mkdir -p "$AIOPS_HOME"
    touch "$ADDONS_LOG"
}

# ── Preflight ────────────────────────────────────────────────
preflight() {
    _section_core "Preflight Checks"

    # OS check
    if ! grep -qi "ubuntu" /etc/os-release 2>/dev/null; then
        _error_core "This script requires Ubuntu. Detected: $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '\"')"
    fi

    # Ubuntu version → sets PIP_FLAGS globally
    UBUNTU_VERSION=$(lsb_release -rs 2>/dev/null \
        || grep VERSION_ID /etc/os-release | cut -d= -f2 | tr -d '"')

    case "$UBUNTU_VERSION" in
        24.04)
            _log_core "OS: Ubuntu 24.04 LTS — fully supported"
            PIP_FLAGS="--break-system-packages"
            ;;
        22.04)
            _log_core "OS: Ubuntu 22.04 LTS — supported"
            PIP_FLAGS=""
            ;;
        20.04)
            _warn_core "OS: Ubuntu 20.04 — Python 3.8 default. Some packages may fail."
            _warn_core "Recommend upgrading to 22.04 or 24.04."
            PIP_FLAGS=""
            ;;
        *)
            _warn_core "OS: Ubuntu $UBUNTU_VERSION — untested. Proceeding with caution."
            if awk "BEGIN {exit !($UBUNTU_VERSION >= 24.04)}"; then
                PIP_FLAGS="--break-system-packages"
            else
                PIP_FLAGS=""
            fi
            ;;
    esac

    # WSL check
    if grep -qi "microsoft" /proc/version 2>/dev/null; then
        _log_core "Environment: WSL2 detected"
    else
        _warn_core "Not running in WSL2 — optimised for WSL2 but continuing"
    fi

    # Internet
    if ! curl -s --max-time 5 https://google.com > /dev/null; then
        _error_core "No internet connection. Check your network."
    fi
    _log_core "Internet: Connected"

    # Disk
    AVAILABLE=$(df ~ | awk 'NR==2 {print $4}')
    if [ "$AVAILABLE" -lt 20971520 ]; then
        _warn_core "Low disk space: $(df -h ~ | awk 'NR==2 {print $4}') available. Recommend 20GB+"
    else
        _log_core "Disk: $(df -h ~ | awk 'NR==2 {print $4}') free"
    fi

    # RAM
    TOTAL_RAM=$(free -g | awk 'NR==2 {print $2}')
    if [ "$TOTAL_RAM" -lt 16 ]; then
        _warn_core "RAM: ${TOTAL_RAM}GB — 16GB+ recommended for 14B models"
    else
        _log_core "RAM: ${TOTAL_RAM}GB"
    fi

    # Local IP
    LOCAL_IP=$(ip route get 1 2>/dev/null | awk '{print $7; exit}' || echo "YOUR_IP")
    _log_core "Local IP: $LOCAL_IP"
}

# ── Domain setup ─────────────────────────────────────────────
setup_config() {
    _section_core "Configuration"

    echo -e "${CYAN}This name will be used for LAN access via mDNS.${NC}"
    echo -e "${CYAN}Example: 'quantocos' → http://quantocos.local${NC}"
    echo ""
    read -rp "$(echo -e "${YELLOW}Enter your .local domain name (Enter for 'aiops'): ${NC}")" domain_input

    if [ -z "$domain_input" ]; then
        LOCAL_DOMAIN="aiops.local"
    else
        LOCAL_DOMAIN="${domain_input%.local}.local"
    fi

    _log_core "Domain: $LOCAL_DOMAIN"

    # Streamlit email (prevents interactive prompt blocking startup)
    mkdir -p "$HOME/.streamlit"
    cat > "$HOME/.streamlit/credentials.toml" << 'EOF'
[general]
email = ""
EOF
    _log_core "Streamlit credentials configured"
}

# ── Directories ───────────────────────────────────────────────
setup_dirs() {
    _section_core "Creating Directory Structure"

    mkdir -p "$SCRIPTS_DIR"
    mkdir -p "$AGENTS_DIR"/{crews,tasks,tools,outputs,configs}
    mkdir -p "$VENVS_DIR"
    mkdir -p "$QDRANT_DIR"/{config,static,storage,snapshots}

    _log_core "Directories created"
    _info_core "Scripts:  $SCRIPTS_DIR"
    _info_core "Agents:   $AGENTS_DIR"
    _info_core "Venvs:    $VENVS_DIR"
    _info_core "Qdrant:   $QDRANT_DIR"
}

# ── System deps ───────────────────────────────────────────────
install_system_deps() {
    _section_core "Installing System Dependencies"

    sudo apt-get update -qq
    sudo apt-get install -y \
        curl wget git unzip \
        python3 python3-pip python3-venv \
        build-essential ffmpeg lsof \
        ca-certificates gnupg \
        lsb-release \
        2>/dev/null

    _log_core "System dependencies installed"
}

# ── WSL system config ─────────────────────────────────────────
setup_wsl_system() {
    _section_core "WSL System Configuration"

    # Enable systemd if not already
    if ! grep -q "systemd=true" /etc/wsl.conf 2>/dev/null; then
        sudo tee -a /etc/wsl.conf > /dev/null << 'EOF'
[boot]
systemd=true
EOF
        _log_core "systemd=true added to /etc/wsl.conf"
        _warn_core "WSL restart required after install for systemd to take effect"
    else
        _log_core "systemd=true already set in /etc/wsl.conf"
    fi
}

# ── mDNS (Avahi) ──────────────────────────────────────────────
setup_mdns() {
    _section_core "Setting Up mDNS (Avahi)"

    sudo apt-get install -y avahi-daemon avahi-utils libnss-mdns -qq

    # Configure Avahi
    sudo tee /etc/avahi/avahi-daemon.conf > /dev/null << AVAHI
[server]
host-name=${LOCAL_DOMAIN%.local}
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

    # Enable mdns in nsswitch
    if ! grep -q "mdns4_minimal" /etc/nsswitch.conf 2>/dev/null; then
        sudo sed -i 's/^hosts:.*/hosts:          files mdns4_minimal [NOTFOUND=return] dns/' \
            /etc/nsswitch.conf
        _log_core "nsswitch.conf updated for mDNS"
    fi

    sudo systemctl enable avahi-daemon 2>/dev/null || true
    sudo systemctl restart avahi-daemon 2>/dev/null || true

    _log_core "mDNS configured — LAN access: http://$LOCAL_DOMAIN"
}

# ── Caddy ─────────────────────────────────────────────────────
install_caddy() {
    _section_core "Installing Caddy Reverse Proxy"

    if ! command -v caddy &>/dev/null; then
        sudo apt-get install -y debian-keyring debian-archive-keyring apt-transport-https -qq
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
            | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
            | sudo tee /etc/apt/sources.list.d/caddy-stable.list
        sudo apt-get update -qq
        sudo apt-get install -y caddy
        _log_core "Caddy installed: $(caddy version)"
    else
        _log_core "Caddy already installed: $(caddy version)"
    fi

    # Write full Caddyfile
    sudo tee /etc/caddy/Caddyfile > /dev/null << CADDY
# ============================================================
# /etc/caddy/Caddyfile — Quantocos AI Labs
# Generated by aiops.sh v5.0.0
# ============================================================

:80 {

    # Global CORS — required for LAN devices
    header {
        Access-Control-Allow-Origin "*"
        Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS"
        Access-Control-Allow-Headers "*"
        -X-Frame-Options
        X-Content-Type-Options "nosniff"
        -Server
    }

    # n8n — websocket required for editor
    handle /n8n* {
        reverse_proxy localhost:5678 {
            header_up Upgrade {http.upgrade}
            header_up Connection {http.headers.Connection}
            header_up Host {host}
            header_up X-Real-IP {remote_host}
            header_up X-Forwarded-For {remote_host}
            header_up X-Forwarded-Proto {scheme}
        }
    }

    # CrewAI Studio — Streamlit needs websocket
    handle /agents* {
        reverse_proxy localhost:8501 {
            header_up Upgrade {http.upgrade}
            header_up Connection {http.headers.Connection}
            header_up Host {host}
        }
    }

    # Qdrant dashboard
    handle /qdrant* {
        uri strip_prefix /qdrant
        reverse_proxy localhost:6333
    }

    # Netdata monitoring
    handle /monitor* {
        uri strip_prefix /monitor
        reverse_proxy localhost:19999
    }

    # Ollama API
    handle /ollama* {
        uri strip_prefix /ollama
        reverse_proxy localhost:11434
    }

    # Twenty CRM
    handle /crm* {
        reverse_proxy localhost:3000 {
            header_up Host {host}
        }
    }

    # Listmonk email
    handle /mail* {
        reverse_proxy localhost:9000 {
            header_up Host {host}
        }
    }

    # Chatwoot inbox
    handle /inbox* {
        reverse_proxy localhost:3100 {
            header_up Upgrade {http.upgrade}
            header_up Connection {http.headers.Connection}
            header_up Host {host}
        }
    }

    # Cal.com
    handle /cal* {
        reverse_proxy localhost:3002 {
            header_up Host {host}
        }
    }

    # Mautic
    handle /mautic* {
        reverse_proxy localhost:8100 {
            header_up Host {host}
        }
    }

    # OpenWebUI — default catch-all
    handle /* {
        reverse_proxy localhost:8080 {
            header_up Host {host}
            header_up X-Real-IP {remote_host}
            header_up X-Forwarded-For {remote_host}
            header_up X-Forwarded-Proto {scheme}
        }
    }
}
CADDY

    sudo caddy validate --config /etc/caddy/Caddyfile
    sudo systemctl enable caddy
    sudo systemctl restart caddy

    _log_core "Caddy configured and running"
    _log_core "All routes pre-configured in /etc/caddy/Caddyfile"
}

# ── Node via NVM ──────────────────────────────────────────────
install_node() {
    _section_core "Installing Node.js $NODE_VERSION via NVM"

    nvm_load

    if command -v node &>/dev/null; then
        CURRENT_NODE=$(node -v | cut -d. -f1 | tr -d 'v')
        if [ "$CURRENT_NODE" -ge "$NODE_VERSION" ] 2>/dev/null; then
            _log_core "Node.js $(node -v) already installed — skipping"
            return
        fi
    fi

    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.2/install.sh | bash
    nvm_load
    nvm install "$NODE_VERSION"
    nvm alias default "$NODE_VERSION"

    _log_core "Node.js $(node -v) installed"
    _log_core "npm $(npm -v) ready"
}

# ── PM2 ───────────────────────────────────────────────────────
install_pm2() {
    _section_core "Installing PM2"

    nvm_load

    if command -v pm2 &>/dev/null; then
        _log_core "PM2 $(pm2 -v) already installed — skipping"
        return
    fi

    npm install -g pm2
    _log_core "PM2 $(pm2 -v) installed"
}

# ── Ollama ────────────────────────────────────────────────────
install_ollama() {
    _section_core "Installing Ollama"

    if command -v ollama &>/dev/null; then
        _log_core "Ollama already installed — skipping"
        return
    fi

    curl -fsSL https://ollama.com/install.sh | sh

    # Configure to listen on all interfaces for LAN access
    sudo mkdir -p /etc/systemd/system/ollama.service.d
    sudo tee /etc/systemd/system/ollama.service.d/override.conf > /dev/null << 'EOF'
[Service]
Environment="OLLAMA_HOST=0.0.0.0"
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable ollama 2>/dev/null || true
    sudo systemctl start ollama 2>/dev/null || (ollama serve &>/dev/null & sleep 3)

    _log_core "Ollama installed — listening on 0.0.0.0:11434"
    echo ""
    echo -e "  ${YELLOW}Pull models after install based on your VRAM:${NC}"
    echo "  ollama pull nomic-embed-text    # RAG — always pull this"
    echo "  ollama pull qwen3:4b            # fast chat (2.5GB)"
    echo "  ollama pull qwen2.5:14b         # content/email (9GB)"
    echo "  ollama pull qwen2.5-coder:14b   # coding (9GB)"
    echo "  ollama pull deepseek-r1:8b      # reasoning (5.2GB)"
    echo "  ollama pull llama3.1:8b         # agents/tools (4.9GB)"
    echo ""
}

# ── n8n ───────────────────────────────────────────────────────
install_n8n() {
    _section_core "Installing n8n"

    nvm_load

    if command -v n8n &>/dev/null; then
        _log_core "n8n $(n8n --version 2>/dev/null) already installed — skipping"
        return
    fi

    npm install -g n8n
    _log_core "n8n installed"
}

# ── OpenWebUI ─────────────────────────────────────────────────
install_openwebui() {
    _section_core "Installing OpenWebUI $OPEN_WEBUI_VERSION"

    if pip show open-webui &>/dev/null 2>&1; then
        _log_core "OpenWebUI already installed — skipping"
        return
    fi

    pip install "open-webui==$OPEN_WEBUI_VERSION" $PIP_FLAGS
    pip install qdrant-client $PIP_FLAGS
    export PATH="$HOME/.local/bin:$PATH"

    _log_core "OpenWebUI $OPEN_WEBUI_VERSION installed"
}

# ── Qdrant ────────────────────────────────────────────────────
install_qdrant() {
    _section_core "Installing Qdrant $QDRANT_VERSION"

    QDRANT_BIN="$HOME/qdrant"

    if [ ! -f "$QDRANT_BIN" ]; then
        curl -L \
            "https://github.com/qdrant/qdrant/releases/download/$QDRANT_VERSION/qdrant-x86_64-unknown-linux-gnu.tar.gz" \
            -o /tmp/qdrant.tar.gz
        tar -xzf /tmp/qdrant.tar.gz -C "$HOME"
        rm /tmp/qdrant.tar.gz
        chmod +x "$QDRANT_BIN"
        _log_core "Qdrant binary downloaded"
    else
        _log_core "Qdrant binary already exists"
    fi

    if [ ! -f "$QDRANT_DIR/static/index.html" ]; then
        curl -L \
            "https://github.com/qdrant/qdrant-web-ui/releases/download/$QDRANT_WEBUI_VERSION/dist-qdrant.zip" \
            -o /tmp/qdrant-webui.zip
        sudo apt-get install -y unzip -qq
        unzip -q /tmp/qdrant-webui.zip -d /tmp/qdrant-webui-temp
        cp -r /tmp/qdrant-webui-temp/dist/. "$QDRANT_DIR/static/"
        rm -rf /tmp/qdrant-webui.zip /tmp/qdrant-webui-temp
        _log_core "Qdrant Web UI installed"
    else
        _log_core "Qdrant Web UI already exists"
    fi
}

# ── Python Venvs ──────────────────────────────────────────────
setup_venvs() {
    _section_core "Setting Up Python Virtual Environments"

    # CrewAI
    if [ ! -d "$VENVS_DIR/crewai" ]; then
        python3 -m venv "$VENVS_DIR/crewai"
        "$VENVS_DIR/crewai/bin/pip" install --upgrade pip -q
        "$VENVS_DIR/crewai/bin/pip" install \
            "crewai==$CREWAI_VERSION" \
            "crewai-tools==$CREWAI_TOOLS_VERSION" -q
        _log_core "CrewAI $CREWAI_VERSION venv ready"
    else
        _log_core "CrewAI venv already exists"
    fi

    # Aider
    if [ ! -d "$VENVS_DIR/aider" ]; then
        python3 -m venv "$VENVS_DIR/aider"
        "$VENVS_DIR/aider/bin/pip" install --upgrade pip -q
        "$VENVS_DIR/aider/bin/pip" install "aider-chat==$AIDER_VERSION" -q
        _log_core "Aider $AIDER_VERSION venv ready"
    else
        _log_core "Aider venv already exists"
    fi

    # Open Interpreter
    if [ ! -d "$VENVS_DIR/interpreter" ]; then
        python3 -m venv "$VENVS_DIR/interpreter"
        "$VENVS_DIR/interpreter/bin/pip" install --upgrade pip -q
        "$VENVS_DIR/interpreter/bin/pip" install \
            "open-interpreter==$OPEN_INTERPRETER_VERSION" -q
        _log_core "Open Interpreter $OPEN_INTERPRETER_VERSION venv ready"
    else
        _log_core "Open Interpreter venv already exists"
    fi

    # Scrapy (data pipeline)
    if [ ! -d "$VENVS_DIR/scrapy" ]; then
        python3 -m venv "$VENVS_DIR/scrapy"
        "$VENVS_DIR/scrapy/bin/pip" install --upgrade pip -q
        "$VENVS_DIR/scrapy/bin/pip" install \
            scrapy pandas dedupe \
            email-validator phonenumbers tqdm python-dotenv -q
        _log_core "Scrapy (data pipeline) venv ready"
    else
        _log_core "Scrapy venv already exists"
    fi

    # Playwright (web automation)
    if [ ! -d "$VENVS_DIR/playwright" ]; then
        python3 -m venv "$VENVS_DIR/playwright"
        "$VENVS_DIR/playwright/bin/pip" install --upgrade pip -q
        "$VENVS_DIR/playwright/bin/pip" install playwright requests dnspython -q
        "$VENVS_DIR/playwright/bin/playwright" install chromium
        "$VENVS_DIR/playwright/bin/playwright" install-deps chromium
        _log_core "Playwright venv ready"
    else
        _log_core "Playwright venv already exists"
    fi
}

# ── CrewAI Studio ─────────────────────────────────────────────
install_crewai_studio() {
    _section_core "Installing CrewAI Studio"

    STUDIO_DIR="$HOME/CrewAI-Studio"

    if [ ! -d "$STUDIO_DIR" ]; then
        git clone https://github.com/strnad/CrewAI-Studio.git "$STUDIO_DIR"
        _log_core "CrewAI Studio cloned"
    else
        _log_core "CrewAI Studio already cloned"
    fi

    if [ ! -d "$STUDIO_DIR/venv" ]; then
        cd "$STUDIO_DIR"
        python3 -m venv venv
        source venv/bin/activate
        pip install --upgrade pip -q
        pip install -r requirements.txt -q
        deactivate
        cd "$HOME"
        _log_core "CrewAI Studio dependencies installed"
    else
        _log_core "CrewAI Studio venv already exists"
    fi
}

# ── Launcher Scripts ──────────────────────────────────────────
create_launchers() {
    _section_core "Creating Launcher Scripts"

    STUDIO_DIR="$HOME/CrewAI-Studio"

    # OpenWebUI
    cat > "$SCRIPTS_DIR/run-openwebui.sh" << 'EOF'
#!/bin/bash
export PATH="$HOME/.local/bin:$PATH"
export VECTOR_DB=qdrant
export QDRANT_URI=http://localhost:6333
export DATA_DIR="$HOME/.local/share/open-webui"
exec open-webui serve
EOF

    # n8n — with all required env vars for reverse proxy
    cat > "$SCRIPTS_DIR/run-n8n.sh" << NSCRIPT
#!/bin/bash
export NVM_DIR="\$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && \\. "\$NVM_DIR/nvm.sh"
export N8N_PORT=5678
export N8N_HOST=0.0.0.0
export N8N_PROTOCOL=http
export N8N_SECURE_COOKIE=false
export N8N_PATH=/n8n/
export N8N_EDITOR_BASE_URL=http://${LOCAL_DOMAIN}/n8n/
export WEBHOOK_URL=http://${LOCAL_DOMAIN}/n8n/
export N8N_USER_FOLDER="\$HOME/.n8n"
exec n8n start
NSCRIPT

    # Qdrant — must cd to data dir + set static content path
    cat > "$SCRIPTS_DIR/run-qdrant.sh" << 'EOF'
#!/bin/bash
export QDRANT__SERVICE__STATIC_CONTENT_DIR="$HOME/qdrant-data/static"
cd "$HOME/qdrant-data"
exec "$HOME/qdrant"
EOF

    # CrewAI Studio — cd to dir first (Streamlit needs cwd)
    cat > "$SCRIPTS_DIR/run-crewai-studio.sh" << CSSCRIPT
#!/bin/bash
cd "${STUDIO_DIR}"
exec "${STUDIO_DIR}/venv/bin/streamlit" run app/app.py \\
    --server.port 8501 \\
    --server.address 0.0.0.0 \\
    --server.headless true
CSSCRIPT

    # Aider
    cat > "$SCRIPTS_DIR/run-aider.sh" << 'EOF'
#!/bin/bash
source "$HOME/.venvs/aider/bin/activate"
MODEL="${1:-ollama/qwen2.5-coder:14b}"
exec aider --model "$MODEL" "${@:2}"
EOF

    # CrewAI runner
    cat > "$SCRIPTS_DIR/run-crew.sh" << 'EOF'
#!/bin/bash
source "$HOME/.venvs/crewai/bin/activate"
exec python3 "$@"
EOF

    # Open Interpreter
    cat > "$SCRIPTS_DIR/run-interpreter.sh" << 'EOF'
#!/bin/bash
source "$HOME/.venvs/interpreter/bin/activate"
MODEL="${1:-ollama/llama3.1:8b}"
exec interpreter --model "$MODEL"
EOF

    # Scrapy runner
    cat > "$SCRIPTS_DIR/run-scrapy.sh" << 'EOF'
#!/bin/bash
source "$HOME/.venvs/scrapy/bin/activate"
exec python3 "$@"
EOF

    # Playwright runner
    cat > "$SCRIPTS_DIR/run-playwright.sh" << 'EOF'
#!/bin/bash
source "$HOME/.venvs/playwright/bin/activate"
exec python3 "$@"
EOF

    chmod +x "$SCRIPTS_DIR"/*.sh
    _log_core "All launcher scripts created"
}

# ── Shell Aliases ─────────────────────────────────────────────
setup_aliases() {
    _section_core "Setting Up Shell Aliases"

    # Remove old block
    sed -i '/# AIOPS START/,/# AIOPS END/d' ~/.bashrc

    cat >> ~/.bashrc << BASHRC

# AIOPS START — Quantocos AI Labs v5.0.0
export PATH="\$HOME/.local/bin:\$PATH"
export NVM_DIR="\$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && \\. "\$NVM_DIR/nvm.sh"

# Service management
alias ai-status='pm2 status'
alias ai-start='pm2 resurrect'
alias ai-stop='pm2 stop all'
alias ai-restart='pm2 restart all'
alias ai-logs='pm2 logs'

# AI tools
alias aider='${SCRIPTS_DIR}/run-aider.sh'
alias crew='${SCRIPTS_DIR}/run-crew.sh'
alias interpreter='${SCRIPTS_DIR}/run-interpreter.sh'
alias scrape='${SCRIPTS_DIR}/run-scrapy.sh'
alias automate='${SCRIPTS_DIR}/run-playwright.sh'

# Quick chat
alias chat='ollama run qwen3:4b'
alias chat-coder='ollama run qwen2.5-coder:14b'
alias chat-reason='ollama run deepseek-r1:8b'
alias models='ollama list'

# PM2 auto-resurrect on terminal open
[[ -z \$(pm2 list 2>/dev/null | grep online) ]] && pm2 resurrect 2>/dev/null

# AIOPS END
BASHRC

    _log_core "Shell aliases written to ~/.bashrc"
}

# ── PM2 Services ──────────────────────────────────────────────
setup_pm2_services() {
    _section_core "Configuring PM2 Services"

    nvm_load

    # Clean start
    pm2 kill 2>/dev/null || true
    rm -f ~/.pm2/dump.pm2 2>/dev/null || true
    sleep 2

    # Clear ports
    for PORT in 5678 8080 6333 8501; do
        sudo fuser -k ${PORT}/tcp 2>/dev/null || true
    done
    sleep 2

    pm2 start "$SCRIPTS_DIR/run-n8n.sh"             --name n8n
    pm2 start "$SCRIPTS_DIR/run-openwebui.sh"        --name openwebui
    pm2 start "$SCRIPTS_DIR/run-qdrant.sh"           --name qdrant --cwd "$QDRANT_DIR"
    pm2 start "$SCRIPTS_DIR/run-crewai-studio.sh"    --name crewai-studio

    sleep 5
    pm2 save

    _log_core "PM2 services started and saved"
}

# ── Sample CrewAI script ──────────────────────────────────────
create_sample_crew() {
    _section_core "Creating Sample Files"

    cat > "$AGENTS_DIR/crews/sample_crew.py" << 'EOF'
"""
Sample CrewAI crew — Quantocos AI Labs
Tests connection to local Ollama
Run: crew ~/agents/crews/sample_crew.py
"""
from crewai import Agent, Task, Crew, LLM

llm = LLM(model="ollama/llama3.1:8b", base_url="http://localhost:11434")

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
EOF

    _log_core "Sample crew: $AGENTS_DIR/crews/sample_crew.py"
}

# ── Core install summary ──────────────────────────────────────
print_core_summary() {
    _section_core "Core Install Complete"

    echo -e "${BOLD}${GREEN}"
    echo "  ╔══════════════════════════════════════════════════╗"
    echo "  ║   AIOPS v5.0.0 — CORE STACK READY               ║"
    echo "  ╠══════════════════════════════════════════════════╣"
    echo "  ║   Service           Local          LAN           ║"
    echo "  ║   ──────────────────────────────────────────     ║"
    echo "  ║   OpenWebUI         :8080           /            ║"
    echo "  ║   n8n               :5678           /n8n         ║"
    echo "  ║   Qdrant            :6333           /qdrant      ║"
    echo "  ║   CrewAI Studio     :8501           /agents      ║"
    echo "  ║   Ollama            :11434          /ollama      ║"
    echo "  ╠══════════════════════════════════════════════════╣"
    echo "  ║   LAN domain: http://$LOCAL_DOMAIN"
    echo "  ║   Local IP:   $LOCAL_IP"
    echo "  ╚══════════════════════════════════════════════════╝"
    echo -e "${NC}"

    echo -e "${BOLD}Next Steps:${NC}"
    echo "  1. Pull models:   ollama pull qwen3:4b"
    echo "  2. Reload shell:  source ~/.bashrc"
    echo "  3. Check status:  ai-status"
    echo "  4. Open browser:  http://localhost:8080"
    echo ""
    echo -e "${CYAN}Core install log: $LOG_FILE${NC}"
    echo ""
}

# ============================================================
# PART 2 — ADDONS LOOP
# ============================================================

# ── Addon: Shared dependencies ────────────────────────────────
addon_dependencies() {
    _section_add "Installing Shared Dependencies"

    # PostgreSQL
    if ! command -v psql &>/dev/null; then
        sudo apt-get update -qq
        sudo apt-get install -y postgresql postgresql-contrib
        sudo systemctl enable postgresql
        sudo systemctl start postgresql
        _log_add "PostgreSQL installed"
    else
        _log_add "PostgreSQL already installed"
    fi

    # Redis
    if ! command -v redis-server &>/dev/null; then
        sudo apt-get install -y redis-server
        sudo systemctl enable redis-server
        sudo systemctl start redis-server
        _log_add "Redis installed"
    else
        _log_add "Redis already installed"
    fi

    # Firecrawl venv
    if [ ! -d "$VENVS_DIR/firecrawl" ]; then
        python3 -m venv "$VENVS_DIR/firecrawl"
        "$VENVS_DIR/firecrawl/bin/pip" install --upgrade pip -q
        "$VENVS_DIR/firecrawl/bin/pip" install firecrawl-py -q
        cat > "$SCRIPTS_DIR/run-firecrawl.sh" << FEOF
#!/bin/bash
exec "${VENVS_DIR}/firecrawl/bin/python3" "\$@"
FEOF
        chmod +x "$SCRIPTS_DIR/run-firecrawl.sh"
        _log_add "Firecrawl venv ready"
    else
        _log_add "Firecrawl venv already exists"
    fi
}

# ── Addon: Twenty CRM ─────────────────────────────────────────
addon_twenty_crm() {
    _section_add "Installing Twenty CRM"

    nvm_load

    TWENTY_DIR="$HOME/twenty"

    if [ ! -d "$TWENTY_DIR" ]; then
        git clone https://github.com/twentyhq/twenty.git "$TWENTY_DIR"
        _log_add "Twenty CRM cloned"
    else
        _log_add "Twenty CRM already cloned"
    fi

    # Database
    if ! sudo -u postgres psql -lqt 2>/dev/null | grep -q twenty; then
        sudo -u postgres psql -c \
            "CREATE USER twenty WITH PASSWORD 'twenty_password';" 2>/dev/null || true
        sudo -u postgres psql -c \
            "CREATE DATABASE twenty OWNER twenty;" 2>/dev/null || true
        _log_add "Twenty CRM database created"
    fi

    cd "$TWENTY_DIR"

    if [ ! -f ".env" ]; then
        APP_SECRET=$(openssl rand -base64 24 | tr -d '=+/' | head -c 32)
        cat > .env << ENVEOF
APP_SECRET=$APP_SECRET
DATABASE_URL=postgresql://twenty:twenty_password@localhost:5432/twenty
FRONT_BASE_URL=http://localhost:3000
REDIS_URL=redis://localhost:6379
ENVEOF
        _log_add ".env configured"
    fi

    _info_add "Installing Twenty CRM npm packages (may take a few minutes)..."
    npm install --legacy-peer-deps -q 2>/dev/null || npm install -q

    NPXBIN=$(which npx 2>/dev/null || echo "npx")
    cat > "$SCRIPTS_DIR/run-twenty.sh" << TSCRIPT
#!/bin/bash
export NVM_DIR="\$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && \\. "\$NVM_DIR/nvm.sh"
cd "${TWENTY_DIR}"
exec $NPXBIN nx start
TSCRIPT
    chmod +x "$SCRIPTS_DIR/run-twenty.sh"

    nvm_load
    pm2 start "$SCRIPTS_DIR/run-twenty.sh" --name twenty 2>/dev/null || true
    pm2 save
    cd "$HOME"

    _log_add "Twenty CRM installed"
    echo "  Local: http://localhost:3000"
    echo "  LAN:   http://$LOCAL_DOMAIN/crm"
}

# ── Addon: Listmonk ───────────────────────────────────────────
addon_listmonk() {
    _section_add "Installing Listmonk"

    LISTMONK_BIN="$HOME/listmonk"
    LISTMONK_DIR="$HOME/listmonk-data"
    mkdir -p "$LISTMONK_DIR"

    if [ ! -f "$LISTMONK_BIN" ]; then
        LISTMONK_URL=$(curl -s https://api.github.com/repos/knadh/listmonk/releases/latest \
            | grep "browser_download_url.*linux_amd64.tar.gz" \
            | cut -d'"' -f4 | head -1)

        [ -z "$LISTMONK_URL" ] && \
            LISTMONK_URL="https://github.com/knadh/listmonk/releases/download/v4.1.0/listmonk_4.1.0_linux_amd64.tar.gz"

        curl -L "$LISTMONK_URL" -o /tmp/listmonk.tar.gz
        tar -xzf /tmp/listmonk.tar.gz -C /tmp/
        mv /tmp/listmonk "$LISTMONK_BIN" 2>/dev/null || \
            find /tmp -name "listmonk" -type f | head -1 | xargs -I{} mv {} "$LISTMONK_BIN"
        chmod +x "$LISTMONK_BIN"
        rm -f /tmp/listmonk.tar.gz
        _log_add "Listmonk binary downloaded"
    else
        _log_add "Listmonk binary already exists"
    fi

    # Database
    if ! sudo -u postgres psql -lqt 2>/dev/null | grep -q listmonk; then
        sudo -u postgres psql -c \
            "CREATE USER listmonk WITH PASSWORD 'listmonk_password';" 2>/dev/null || true
        sudo -u postgres psql -c \
            "CREATE DATABASE listmonk OWNER listmonk;" 2>/dev/null || true
    fi

    if [ ! -f "$LISTMONK_DIR/config.toml" ]; then
        cat > "$LISTMONK_DIR/config.toml" << 'TOMLEOF'
[app]
address = "0.0.0.0:9000"
admin_username = "admin"
admin_password = "change_me_now"

[db]
host = "localhost"
port = 5432
user = "listmonk"
password = "listmonk_password"
database = "listmonk"
ssl_mode = "disable"
TOMLEOF
        _info_add "Running Listmonk first-time database install..."
        "$LISTMONK_BIN" --config "$LISTMONK_DIR/config.toml" --install --yes 2>/dev/null || true
        _log_add "Listmonk database installed"
    fi

    cat > "$SCRIPTS_DIR/run-listmonk.sh" << LSCRIPT
#!/bin/bash
exec "${LISTMONK_BIN}" --config "${LISTMONK_DIR}/config.toml"
LSCRIPT
    chmod +x "$SCRIPTS_DIR/run-listmonk.sh"

    nvm_load
    pm2 start "$SCRIPTS_DIR/run-listmonk.sh" --name listmonk 2>/dev/null || true
    pm2 save

    _log_add "Listmonk installed"
    echo "  Local:  http://localhost:9000"
    echo "  LAN:    http://$LOCAL_DOMAIN/mail"
    echo "  Login:  admin / change_me_now"
    echo "  ⚠  Change password immediately after first login"
}

# ── Addon: OpenFang ───────────────────────────────────────────
addon_openfang() {
    _section_add "Installing OpenFang"

    _warn_add "Checking OpenFang availability..."

    if curl -fsSL --max-time 10 https://openfang.sh/install -o /tmp/openfang-install.sh 2>/dev/null; then
        bash /tmp/openfang-install.sh
        rm -f /tmp/openfang-install.sh

        if command -v openfang &>/dev/null; then
            openfang hand activate lead       2>/dev/null || true
            openfang hand activate browser    2>/dev/null || true
            openfang hand activate researcher 2>/dev/null || true
            openfang hand activate twitter    2>/dev/null || true
            _log_add "OpenFang installed — all Hands activated"
            echo "  Hands:  Lead | Browser | Researcher | Twitter"
            echo "  Config: ~/.openfang/config.yaml"
        fi
    else
        # Fallback: pip
        if [ ! -d "$VENVS_DIR/openfang" ]; then
            python3 -m venv "$VENVS_DIR/openfang"
            "$VENVS_DIR/openfang/bin/pip" install --upgrade pip -q
            if "$VENVS_DIR/openfang/bin/pip" install openfang -q 2>/dev/null; then
                cat > "$SCRIPTS_DIR/run-openfang.sh" << OFSCRIPT
#!/bin/bash
exec "${VENVS_DIR}/openfang/bin/openfang" "\$@"
OFSCRIPT
                chmod +x "$SCRIPTS_DIR/run-openfang.sh"
                _log_add "OpenFang installed via pip"
            else
                _warn_add "OpenFang not yet available. Check https://github.com/openfang"
                _warn_add "Install manually when available: pip install openfang"
            fi
        fi
    fi
}

# ── Addon: Mautic ─────────────────────────────────────────────
addon_mautic() {
    _section_add "Installing Mautic (PHP Marketing Automation)"

    # PHP
    if ! command -v php &>/dev/null; then
        _info_add "Installing PHP 8.1..."
        sudo apt-get install -y \
            php8.1 php8.1-cli php8.1-fpm \
            php8.1-mysql php8.1-xml php8.1-mbstring \
            php8.1-curl php8.1-zip php8.1-gd \
            php8.1-intl php8.1-bcmath composer -q
        _log_add "PHP 8.1 installed"
    else
        _log_add "PHP: $(php -v | head -1 | cut -d' ' -f1-2)"
    fi

    # MariaDB
    if ! command -v mysql &>/dev/null; then
        sudo apt-get install -y mariadb-server -q
        sudo systemctl enable mariadb
        sudo systemctl start mariadb
        sudo mysql -e "CREATE DATABASE IF NOT EXISTS mautic CHARACTER SET utf8mb4;" 2>/dev/null || true
        sudo mysql -e "CREATE USER IF NOT EXISTS 'mautic'@'localhost' IDENTIFIED BY 'mautic_password';" 2>/dev/null || true
        sudo mysql -e "GRANT ALL PRIVILEGES ON mautic.* TO 'mautic'@'localhost';" 2>/dev/null || true
        sudo mysql -e "FLUSH PRIVILEGES;" 2>/dev/null || true
        _log_add "MariaDB configured"
    fi

    MAUTIC_DIR="$HOME/mautic"
    if [ ! -d "$MAUTIC_DIR" ]; then
        _info_add "Installing Mautic via Composer (takes a few minutes)..."
        composer create-project mautic/recommended-project:^5 "$MAUTIC_DIR" \
            --no-interaction -q 2>/dev/null || \
        composer create-project mautic/recommended-project "$MAUTIC_DIR" \
            --no-interaction
        cat > "$MAUTIC_DIR/.env.local" << 'MENV'
APP_URL=http://localhost:8100
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
cd "${MAUTIC_DIR}"
exec php -S 0.0.0.0:8100 -t public/
MSCRIPT
    chmod +x "$SCRIPTS_DIR/run-mautic.sh"

    nvm_load
    pm2 start "$SCRIPTS_DIR/run-mautic.sh" --name mautic 2>/dev/null || true
    pm2 save

    _log_add "Mautic running on :8100"
    echo "  Local:  http://localhost:8100"
    echo "  LAN:    http://$LOCAL_DOMAIN/mautic"
    echo "  Setup:  Complete wizard on first open"
}

# ── Addon: Chatwoot ───────────────────────────────────────────
addon_chatwoot() {
    _section_add "Installing Chatwoot (Unified Inbox)"

    CHATWOOT_DIR="$HOME/chatwoot"
    CHATWOOT_PORT=3100

    if ! command -v ruby &>/dev/null; then
        _info_add "Installing Ruby..."
        sudo apt-get install -y ruby ruby-dev -q 2>/dev/null || \
        { sudo apt-get install -y rbenv ruby-build -q && \
          rbenv install 3.2.2 && rbenv global 3.2.2; }
        _log_add "Ruby: $(ruby -v)"
    else
        _log_add "Ruby: $(ruby -v)"
    fi

    if [ ! -d "$CHATWOOT_DIR" ]; then
        git clone https://github.com/chatwoot/chatwoot.git "$CHATWOOT_DIR"
        _log_add "Chatwoot cloned"
    else
        _log_add "Chatwoot already cloned"
    fi

    cd "$CHATWOOT_DIR"

    if ! sudo -u postgres psql -lqt 2>/dev/null | grep -q chatwoot; then
        sudo -u postgres psql -c \
            "CREATE USER chatwoot WITH PASSWORD 'chatwoot_password';" 2>/dev/null || true
        sudo -u postgres psql -c \
            "CREATE DATABASE chatwoot OWNER chatwoot;" 2>/dev/null || true
    fi

    if [ ! -f ".env" ]; then
        cp .env.example .env
        SECRET_KEY=$(openssl rand -hex 64)
        sed -i "s|SECRET_KEY_BASE=.*|SECRET_KEY_BASE=$SECRET_KEY|" .env
        sed -i "s|DATABASE_URL=.*|DATABASE_URL=postgresql://chatwoot:chatwoot_password@localhost:5432/chatwoot|" .env
        sed -i "s|REDIS_URL=.*|REDIS_URL=redis://localhost:6379|" .env
        sed -i "s|PORT=3000|PORT=$CHATWOOT_PORT|" .env
        _log_add ".env configured"
    fi

    _info_add "Installing Chatwoot gems (this takes several minutes)..."
    bundle install -q 2>/dev/null || (gem install bundler && bundle install -q)

    RAILS_ENV=production bundle exec rails db:chatwoot_prepare 2>/dev/null || \
        RAILS_ENV=production bundle exec rails db:migrate 2>/dev/null || true

    BUNDLE_BIN=$(which bundle 2>/dev/null || echo "bundle")

    cat > "$SCRIPTS_DIR/run-chatwoot.sh" << CWSCRIPT
#!/bin/bash
cd "${CHATWOOT_DIR}"
export RAILS_ENV=production
exec $BUNDLE_BIN exec rails server -b 0.0.0.0 -p $CHATWOOT_PORT
CWSCRIPT

    cat > "$SCRIPTS_DIR/run-chatwoot-worker.sh" << CWWSCRIPT
#!/bin/bash
cd "${CHATWOOT_DIR}"
export RAILS_ENV=production
exec $BUNDLE_BIN exec sidekiq
CWWSCRIPT

    chmod +x "$SCRIPTS_DIR/run-chatwoot.sh" "$SCRIPTS_DIR/run-chatwoot-worker.sh"

    nvm_load
    pm2 start "$SCRIPTS_DIR/run-chatwoot.sh"        --name chatwoot
    pm2 start "$SCRIPTS_DIR/run-chatwoot-worker.sh" --name chatwoot-worker
    pm2 save
    cd "$HOME"

    _log_add "Chatwoot installed"
    echo "  Local:  http://localhost:$CHATWOOT_PORT"
    echo "  LAN:    http://$LOCAL_DOMAIN/inbox"
    echo "  Setup:  Register admin account on first open"
}

# ── Addon: Cal.com ────────────────────────────────────────────
addon_calcom() {
    _section_add "Installing Cal.com (Booking System)"

    nvm_load

    CALCOM_DIR="$HOME/calcom"
    CALCOM_PORT=3002

    if [ ! -d "$CALCOM_DIR" ]; then
        git clone https://github.com/calcom/cal.com.git "$CALCOM_DIR"
        _log_add "Cal.com cloned"
    else
        _log_add "Cal.com already cloned"
    fi

    if ! sudo -u postgres psql -lqt 2>/dev/null | grep -q calcom; then
        sudo -u postgres psql -c \
            "CREATE USER calcom WITH PASSWORD 'calcom_password';" 2>/dev/null || true
        sudo -u postgres psql -c \
            "CREATE DATABASE calcom OWNER calcom;" 2>/dev/null || true
    fi

    cd "$CALCOM_DIR"

    if [ ! -f ".env" ]; then
        cp .env.example .env 2>/dev/null || touch .env
        NEXTAUTH_SECRET=$(openssl rand -base64 32)
        cat >> .env << CAENV
DATABASE_URL=postgresql://calcom:calcom_password@localhost:5432/calcom
NEXTAUTH_SECRET=$NEXTAUTH_SECRET
NEXTAUTH_URL=http://localhost:$CALCOM_PORT
NEXT_PUBLIC_APP_URL=http://localhost:$CALCOM_PORT
PORT=$CALCOM_PORT
CAENV
        _log_add ".env configured"
    fi

    _info_add "Installing Cal.com npm packages..."
    npm install --legacy-peer-deps -q 2>/dev/null || npm install -q

    npx prisma generate 2>/dev/null || true
    npx prisma db push 2>/dev/null || true

    NPXBIN=$(which npx 2>/dev/null || echo "npx")
    cat > "$SCRIPTS_DIR/run-calcom.sh" << CASCRIPT
#!/bin/bash
export NVM_DIR="\$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && \\. "\$NVM_DIR/nvm.sh"
cd "${CALCOM_DIR}"
exec $NPXBIN next start -p $CALCOM_PORT
CASCRIPT
    chmod +x "$SCRIPTS_DIR/run-calcom.sh"

    pm2 start "$SCRIPTS_DIR/run-calcom.sh" --name calcom 2>/dev/null || true
    pm2 save
    cd "$HOME"

    _log_add "Cal.com installed"
    echo "  Local:  http://localhost:$CALCOM_PORT"
    echo "  LAN:    http://$LOCAL_DOMAIN/cal"
    echo "  Setup:  Register on first open"
}

# ── Addon: System monitors ────────────────────────────────────
addon_monitors() {
    _section_add "Installing System Monitors"

    sudo apt-get update -qq

    command -v htop  &>/dev/null && _log_add "htop already installed" || \
        { sudo apt-get install -y htop -q; _log_add "htop installed"; }

    command -v nvtop &>/dev/null && _log_add "nvtop already installed" || \
        { sudo apt-get install -y nvtop -q; _log_add "nvtop installed (GPU/VRAM monitor)"; }

    echo "  htop   → CPU cores, RAM, processes"
    echo "  nvtop  → GPU VRAM usage, temperature, model load"
}

# ── Addon: Netdata ────────────────────────────────────────────
addon_netdata() {
    _section_add "Installing Netdata"

    if command -v netdata &>/dev/null; then
        _log_add "Netdata already installed"
    else
        curl -fsSL https://my-netdata.io/kickstart.sh | sh -s -- --non-interactive 2>/dev/null || true
        _log_add "Netdata installed"
    fi

    # Bind to 0.0.0.0 for LAN access
    NETDATA_CONF=$(find /etc/netdata -name "netdata.conf" 2>/dev/null | head -1)
    if [ -n "$NETDATA_CONF" ]; then
        sudo sed -i 's/# *bind to.*/bind to = 0.0.0.0/' "$NETDATA_CONF" 2>/dev/null || true
        sudo sed -i 's/bind to = localhost/bind to = 0.0.0.0/' "$NETDATA_CONF" 2>/dev/null || true
        sudo systemctl restart netdata 2>/dev/null || true
    fi

    _log_add "Netdata configured"
    echo "  Local:  http://localhost:19999"
    echo "  LAN:    http://$LOCAL_DOMAIN/monitor"
}

# ── Addons: show menu ─────────────────────────────────────────
show_addons_menu() {
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║         AIOPS ADDONS — INSTALL MENU                 ║${NC}"
    echo -e "${BOLD}╠══════════════════════════════════════════════════════╣${NC}"
    echo -e "${BOLD}║  DEPENDENCIES                                        ║${NC}"
    echo "║  [d]  Shared deps        PostgreSQL, Redis, Firecrawl ║"
    echo -e "${BOLD}║                                                      ║${NC}"
    echo -e "${BOLD}║  GTM & CRM                                           ║${NC}"
    echo "║  [1]  Twenty CRM         Lead + deal management :3000 ║"
    echo "║  [2]  Listmonk           Email campaigns binary  :9000 ║"
    echo "║  [3]  OpenFang           AI agent Hands (Lead/X/Web)   ║"
    echo "║  [4]  Mautic             Full nurture (PHP)      :8100 ║"
    echo -e "${BOLD}║                                                      ║${NC}"
    echo -e "${BOLD}║  INBOX & BOOKING                                     ║${NC}"
    echo "║  [5]  Chatwoot           Unified inbox           :3100 ║"
    echo "║  [6]  Cal.com            Discovery booking        :3002 ║"
    echo -e "${BOLD}║                                                      ║${NC}"
    echo -e "${BOLD}║  MONITORING                                          ║${NC}"
    echo "║  [7]  Monitors           htop + nvtop                  ║"
    echo "║  [8]  Netdata            Full system dashboard   :19999║"
    echo -e "${BOLD}║                                                      ║${NC}"
    echo -e "${BOLD}║  BUNDLES                                             ║${NC}"
    echo "║  [a]  Core GTM           d + 1 + 2 + 3                ║"
    echo "║  [b]  Full GTM           d + 1 + 2 + 3 + 4 + 5 + 6    ║"
    echo "║  [m]  All monitors       7 + 8                         ║"
    echo -e "${BOLD}║                                                      ║${NC}"
    echo "║  [s]  Show PM2 status                                  ║"
    echo -e "${BOLD}║  [exit]  Exit installer                              ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ── Addons: run a selection ───────────────────────────────────
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
        a|A)
            addon_dependencies
            addon_twenty_crm
            addon_listmonk
            addon_openfang
            ;;
        b|B)
            addon_dependencies
            addon_twenty_crm
            addon_listmonk
            addon_openfang
            addon_mautic
            addon_chatwoot
            addon_calcom
            ;;
        m|M)
            addon_monitors
            addon_netdata
            ;;
        s|S)
            nvm_load
            pm2 status
            ;;
        "exit"|"EXIT"|"q"|"Q")
            return 1
            ;;
        *)
            echo -e "${YELLOW}[!] Unknown option: $1${NC}"
            ;;
    esac
    return 0
}

# ── Addons main loop ──────────────────────────────────────────
addons_loop() {
    banner_addons

    echo -e "${CYAN}Core installation is complete.${NC}"
    echo -e "${CYAN}You can now install optional tools.${NC}"
    echo -e "${YELLOW}Type 'exit' at any time to finish.${NC}"
    echo ""

    while true; do
        show_addons_menu

        read -rp "$(echo -e "${YELLOW}Enter choice (or 'exit' to finish): ${NC}")" raw_input

        # Trim whitespace
        choice=$(echo "$raw_input" | xargs 2>/dev/null || echo "$raw_input")

        # Check for exit
        if [[ "$choice" == "exit" || "$choice" == "EXIT" || \
              "$choice" == "q" || "$choice" == "Q" ]]; then
            echo ""
            echo -e "${BOLD}${GREEN}Exiting addon installer.${NC}"
            break
        fi

        # Handle space-separated multi-select (e.g. "d 1 2")
        if [[ "$choice" == *" "* ]]; then
            for item in $choice; do
                if [[ "$item" == "exit" || "$item" == "EXIT" ]]; then
                    echo -e "${BOLD}${GREEN}Exiting addon installer.${NC}"
                    return
                fi
                run_addon "$item" || return
            done
        else
            run_addon "$choice" || break
        fi

        echo ""
        echo -e "${CYAN}Done. Returning to menu...${NC}"
        sleep 1
    done
}

# ── Final summary ─────────────────────────────────────────────
print_final_summary() {
    echo ""
    echo -e "${BOLD}${GREEN}"
    echo "  ╔══════════════════════════════════════════════════════╗"
    echo "  ║   AIOPS v5.0.0 — SETUP COMPLETE                     ║"
    echo "  ╠══════════════════════════════════════════════════════╣"
    echo "  ║   CORE SERVICES                                      ║"
    echo "  ║   OpenWebUI      http://$LOCAL_DOMAIN               ║"
    echo "  ║   n8n            http://$LOCAL_DOMAIN/n8n           ║"
    echo "  ║   Qdrant         http://$LOCAL_DOMAIN/qdrant        ║"
    echo "  ║   CrewAI Studio  http://$LOCAL_DOMAIN/agents        ║"
    echo "  ║   Ollama         http://$LOCAL_DOMAIN/ollama        ║"
    echo "  ╠══════════════════════════════════════════════════════╣"
    echo "  ║   LOCAL IP: $LOCAL_IP"
    echo "  ╠══════════════════════════════════════════════════════╣"
    echo "  ║   QUICK COMMANDS                                     ║"
    echo "  ║   ai-status    pm2 status — check all services       ║"
    echo "  ║   ai-logs      pm2 logs — live log tailing           ║"
    echo "  ║   chat         ollama run qwen3:4b                   ║"
    echo "  ╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    echo -e "${BOLD}Logs:${NC}"
    echo "  Core install: $LOG_FILE"
    echo "  Addons:       $ADDONS_LOG"
    echo ""
    echo -e "${BOLD}Reload your shell:${NC}  source ~/.bashrc"
    echo ""
    echo -e "${BOLD}${CYAN}April | Chief AI Officer${NC}"
    echo -e "${CYAN}Quantocos AI Labs — Quantocos Global Systems LLP${NC}"
    echo -e "${CYAN}\"Build with intelligence. Operate with precision.\"${NC}"
    echo ""
}

# ============================================================
# MAIN
# ============================================================
main() {
    clear
    banner_core

    echo -e "${BOLD}AIOPS v5.0.0 — Full Stack Installer${NC}"
    echo ""
    echo "  PART 1 — Core stack (runs once):"
    echo "  • Node 22, Ollama, OpenWebUI, n8n"
    echo "  • Qdrant, CrewAI Studio, PM2"
    echo "  • Caddy reverse proxy, Avahi mDNS"
    echo "  • Python venvs: CrewAI, Aider, Interpreter, Scrapy, Playwright"
    echo ""
    echo "  PART 2 — Addons loop (install until you type 'exit'):"
    echo "  • Twenty CRM, Listmonk, OpenFang"
    echo "  • Mautic, Chatwoot, Cal.com"
    echo "  • htop, nvtop, Netdata"
    echo ""

    if ! confirm "Proceed with installation?"; then
        echo "Installation cancelled."
        exit 0
    fi

    # ── PART 1: Core ──────────────────────────────────────────
    preinit
    setup_config
    preflight
    setup_dirs
    install_system_deps
    setup_wsl_system
    setup_mdns
    install_caddy
    install_node
    install_pm2
    install_ollama
    install_n8n
    install_openwebui
    install_qdrant
    setup_venvs
    install_crewai_studio
    create_launchers
    setup_aliases
    setup_pm2_services
    create_sample_crew
    print_core_summary

    # ── PART 2: Addons loop ───────────────────────────────────
    addons_loop

    # ── Final ─────────────────────────────────────────────────
    print_final_summary
}

main "$@"
