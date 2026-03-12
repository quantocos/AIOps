#!/bin/bash
# ============================================================
# AIOPS.SH — Local AI Operations Server Setup
# Compatible: WSL2 Ubuntu 24.04
# Author: Quantocos AI Labs
# Version: 3.0.0
# Usage: bash aiops.sh
# ============================================================

set -e

# ── Colors ──────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Config ───────────────────────────────────────────────────
AIOPS_HOME="$HOME/aiops-server"
SCRIPTS_DIR="$HOME/scripts"
AGENTS_DIR="$HOME/agents"
VENVS_DIR="$HOME/.venvs"
QDRANT_DIR="$HOME/qdrant-data"
STUDIO_DIR="$HOME/CrewAI-Studio"
LOG_FILE="$AIOPS_HOME/install.log"

# ── Versions (pinned) ────────────────────────────────────────
NODE_VERSION="22"
OPEN_WEBUI_VERSION="0.8.10"
QDRANT_VERSION="v1.17.0"
QDRANT_WEBUI_VERSION="v0.2.7"
CREWAI_VERSION="1.10.1"
CREWAI_TOOLS_VERSION="1.10.1"
OPEN_INTERPRETER_VERSION="0.4.3"
AIDER_VERSION="0.86.2"

# ── Runtime vars (populated in setup_config) ─────────────────
LOCAL_DOMAIN=""
LOCAL_HOSTNAME=""
STREAMLIT_EMAIL=""

# ── Helpers ──────────────────────────────────────────────────
log()     { echo -e "${GREEN}[OK]${NC} $1" | tee -a "$LOG_FILE"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1" | tee -a "$LOG_FILE"; }
error()   { echo -e "${RED}[X]${NC} $1" | tee -a "$LOG_FILE"; exit 1; }
info()    { echo -e "${CYAN}[>]${NC} $1" | tee -a "$LOG_FILE"; }
section() { echo -e "\n${BOLD}${BLUE}== $1 ==${NC}\n" | tee -a "$LOG_FILE"; }

confirm() {
    read -rp "$(echo -e "${YELLOW}$1 [y/N]: ${NC}")" response
    [[ "$response" =~ ^[Yy]$ ]]
}

banner() {
cat << 'BANNER'
   _   ___ ___  ___  ___ 
  /_\ |_ _/ _ \| _ \/ __|
 / _ \ | | (_) |  _/\__ \
/_/ \_\___\___/|_|  |___/

  Local AI Operations Server
  Quantocos AI Labs -- v3.0.0
  WSL2 Ubuntu 24.04

BANNER
}

# ============================================================
# SECTION 1 -- CONFIGURATION (runs first, used by all functions)
# ============================================================

setup_config() {
    section "Configuration"

    echo -e "${BOLD}Two questions before installation starts.${NC}"
    echo ""

    # Domain name
    echo -e "${CYAN}Your .local domain lets every LAN device open your services"
    echo -e "without hosts file edits. Example: myrig.local${NC}"
    echo ""
    read -rp "$(echo -e "${YELLOW}Enter domain name (without .local, Enter for default 'aiops'): ${NC}")" domain_input

    if [ -z "$domain_input" ]; then
        LOCAL_HOSTNAME="aiops"
    else
        LOCAL_HOSTNAME="${domain_input%.local}"
    fi
    LOCAL_DOMAIN="${LOCAL_HOSTNAME}.local"

    echo ""

    # Streamlit email
    echo -e "${CYAN}Streamlit asks for an email on first launch."
    echo -e "Enter yours or press Enter to skip.${NC}"
    echo ""
    read -rp "$(echo -e "${YELLOW}Streamlit email (Enter to skip): ${NC}")" STREAMLIT_EMAIL

    echo ""
    echo -e "${BOLD}Settings:${NC}"
    echo "  Domain:          $LOCAL_DOMAIN"
    echo "  Hostname:        $LOCAL_HOSTNAME"
    echo "  Streamlit email: ${STREAMLIT_EMAIL:-skipped}"
    echo ""

    if ! confirm "Continue with these settings?"; then
        echo "Cancelled. Re-run to change settings."
        exit 0
    fi

    export LOCAL_DOMAIN LOCAL_HOSTNAME STREAMLIT_EMAIL
}

# ============================================================
# SECTION 2 -- PREFLIGHT
# ============================================================

preflight() {
    section "Preflight Checks"

    if ! grep -qi "ubuntu" /etc/os-release 2>/dev/null; then
        error "Requires Ubuntu."
    fi
    log "OS: Ubuntu"

    if grep -qi "microsoft" /proc/version 2>/dev/null; then
        log "Environment: WSL2"
    else
        warn "Not WSL2 -- continuing anyway"
    fi

    if ! curl -s --max-time 5 https://google.com > /dev/null; then
        error "No internet connection."
    fi
    log "Internet: OK"

    AVAIL=$(df ~ | awk 'NR==2 {print $4}')
    if [ "$AVAIL" -lt 20971520 ]; then
        warn "Low disk: $(df -h ~ | awk 'NR==2 {print $4}') -- 20GB+ recommended"
    else
        log "Disk: $(df -h ~ | awk 'NR==2 {print $4}') free"
    fi

    RAM=$(free -g | awk 'NR==2 {print $2}')
    if [ "$RAM" -lt 16 ]; then
        warn "RAM: ${RAM}GB -- 16GB+ recommended for 14B models"
    else
        log "RAM: ${RAM}GB"
    fi
}

# ============================================================
# SECTION 3 -- DIRECTORIES
# ============================================================

setup_dirs() {
    section "Creating Directory Structure"

    mkdir -p "$AIOPS_HOME" "$SCRIPTS_DIR" "$VENVS_DIR"
    mkdir -p "$AGENTS_DIR"/{crews,tasks,tools,outputs,configs}
    mkdir -p "$QDRANT_DIR"/{config,static,storage,snapshots}

    log "Directories ready"
}

# ============================================================
# SECTION 4 -- SYSTEM DEPS
# ============================================================

install_system_deps() {
    section "Installing System Dependencies"

    sudo apt-get update -qq
    sudo apt-get install -y \
        curl wget git unzip zstd \
        python3 python3-pip python3-venv \
        build-essential ffmpeg lsof \
        ca-certificates gnupg \
        avahi-daemon avahi-utils libnss-mdns \
        apt-transport-https \
        2>/dev/null

    log "System dependencies installed"
}

# ============================================================
# SECTION 5 -- WSL SYSTEM CONFIG
# ============================================================

setup_wsl_system() {
    section "Configuring WSL (systemd + hostname)"

    if ! grep -q "systemd=true" /etc/wsl.conf 2>/dev/null; then
        sudo tee /etc/wsl.conf > /dev/null << WSLCONF
[boot]
systemd=true

[network]
hostname=$LOCAL_HOSTNAME
generateHosts=false
WSLCONF
        log "WSL systemd enabled"
    else
        log "WSL systemd already configured"
    fi

    if [ "$(hostname)" != "$LOCAL_HOSTNAME" ]; then
        echo "$LOCAL_HOSTNAME" | sudo tee /etc/hostname > /dev/null
        sudo hostname "$LOCAL_HOSTNAME" 2>/dev/null || true
    fi
    log "Hostname: $LOCAL_HOSTNAME"
}

# ============================================================
# SECTION 6 -- AVAHI mDNS
# Makes domain.local resolve on all LAN devices without
# hosts file edits on any device. macOS/iOS/Android/Win10+
# all support .local via mDNS natively.
# ============================================================

setup_mdns() {
    section "Setting Up mDNS ($LOCAL_DOMAIN)"

    sudo tee /etc/avahi/avahi-daemon.conf > /dev/null << AVAHICONF
[server]
host-name=$LOCAL_HOSTNAME
domain-name=local
use-ipv4=yes
use-ipv6=no
allow-interfaces=eth0
deny-interfaces=lo

[wide-area]
enable-wide-area=no

[publish]
publish-addresses=yes
publish-hinfo=no
publish-workstation=no
publish-aaaa-on-ipv4=no

[reflector]
enable-reflector=no

[rlimits]
rlimit-core=0
rlimit-data=4194304
rlimit-fsize=0
rlimit-nofile=768
rlimit-stack=4194304
rlimit-nproc=3
AVAHICONF

    if ! grep -q "mdns4_minimal" /etc/nsswitch.conf 2>/dev/null; then
        sudo sed -i 's/^hosts:.*/hosts:          files mdns4_minimal [NOTFOUND=return] dns/' \
            /etc/nsswitch.conf
    fi

    sudo systemctl enable avahi-daemon 2>/dev/null || true
    sudo systemctl restart avahi-daemon 2>/dev/null || \
        sudo service avahi-daemon restart 2>/dev/null || true

    log "Avahi mDNS configured -- $LOCAL_DOMAIN broadcasts on LAN"
}

# ============================================================
# SECTION 7 -- CADDY REVERSE PROXY
# Single entry point for all services. Websocket support
# for n8n and Streamlit. Routes all /path traffic correctly.
# ============================================================

install_caddy() {
    section "Installing Caddy Reverse Proxy"

    if ! command -v caddy &>/dev/null; then
        info "Installing Caddy..."
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
            | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
            | sudo tee /etc/apt/sources.list.d/caddy-stable.list
        sudo apt-get update -qq
        sudo apt-get install -y caddy
        log "Caddy installed"
    else
        log "Caddy already installed -- updating config"
    fi

    sudo tee /etc/caddy/Caddyfile > /dev/null << CADDYEOF
# ============================================================
# Caddyfile -- AIOPS Stack
# Domain: $LOCAL_DOMAIN
# Generated by aiops.sh v3.0.0
# ============================================================

:80 {

    # Global headers (required for LAN devices)
    header {
        Access-Control-Allow-Origin "*"
        Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS"
        Access-Control-Allow-Headers "*"
        -X-Frame-Options
        X-Content-Type-Options "nosniff"
        -Server
    }

    # n8n -- websocket required for editor, path prefix required for sub-path serving
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

    # CrewAI Studio (Streamlit) -- websocket required for live UI
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

    # Twenty CRM (installed via aiops-tools.sh)
    handle /crm* {
        reverse_proxy localhost:3000 {
            header_up Host {host}
        }
    }

    # Listmonk email (installed via aiops-tools.sh)
    handle /mail* {
        reverse_proxy localhost:9000 {
            header_up Host {host}
        }
    }

    # Chatwoot inbox (installed via aiops-tools.sh)
    handle /inbox* {
        reverse_proxy localhost:3100 {
            header_up Upgrade {http.upgrade}
            header_up Connection {http.headers.Connection}
            header_up Host {host}
        }
    }

    # Cal.com booking (installed via aiops-tools.sh)
    handle /cal* {
        reverse_proxy localhost:3002 {
            header_up Host {host}
        }
    }

    # OpenWebUI -- default catch-all
    handle /* {
        reverse_proxy localhost:8080 {
            header_up Host {host}
            header_up X-Real-IP {remote_host}
            header_up X-Forwarded-For {remote_host}
            header_up X-Forwarded-Proto {scheme}
        }
    }
}
CADDYEOF

    sudo caddy validate --config /etc/caddy/Caddyfile
    sudo systemctl enable caddy
    sudo systemctl restart caddy
    log "Caddy running -- all services routed via :80"
}

# ============================================================
# SECTION 8 -- NODE + PM2
# ============================================================

install_node() {
    section "Installing Node.js $NODE_VERSION via NVM"

    export NVM_DIR="$HOME/.nvm"

    if [ -d "$NVM_DIR" ]; then
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        if node -v 2>/dev/null | grep -q "^v$NODE_VERSION"; then
            log "Node.js $(node -v) already installed"
            return
        fi
    fi

    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.2/install.sh | bash
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    nvm install "$NODE_VERSION"
    nvm alias default "$NODE_VERSION"
    log "Node.js $(node -v) installed"
}

install_pm2() {
    section "Installing PM2"

    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    if command -v pm2 &>/dev/null; then
        log "PM2 $(pm2 -v) already installed"
        return
    fi

    npm install -g pm2
    log "PM2 $(pm2 -v) installed"
}

# ============================================================
# SECTION 9 -- OLLAMA
# ============================================================

install_ollama() {
    section "Installing Ollama"

    if ! command -v ollama &>/dev/null; then
        curl -fsSL https://ollama.com/install.sh | sh
        log "Ollama installed"
    else
        log "Ollama already installed"
    fi

    # Make accessible on all interfaces (LAN, MacBook)
    sudo mkdir -p /etc/systemd/system/ollama.service.d
    sudo tee /etc/systemd/system/ollama.service.d/override.conf > /dev/null << 'OLLAMAEOF'
[Service]
Environment="OLLAMA_HOST=0.0.0.0"
OLLAMAEOF

    sudo systemctl daemon-reload
    sudo systemctl enable ollama
    sudo systemctl restart ollama 2>/dev/null || true
    sleep 3
    log "Ollama running on 0.0.0.0:11434"

    warn "Pull models after WSL restart based on your VRAM:"
    echo ""
    echo "  ollama pull nomic-embed-text   # RAG (pull this first)"
    echo "  ollama pull qwen3:4b           # fast chat"
    echo "  ollama pull qwen2.5:14b        # content/email/SEO"
    echo "  ollama pull qwen2.5-coder:14b  # coding"
    echo "  ollama pull deepseek-r1:8b     # reasoning"
    echo "  ollama pull llama3.1:8b        # agents/tool calls"
    echo ""
}

# ============================================================
# SECTION 10 -- n8n + OpenWebUI + Qdrant
# ============================================================

install_n8n() {
    section "Installing n8n"

    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    if command -v n8n &>/dev/null; then
        log "n8n already installed"
        return
    fi

    npm install -g n8n
    log "n8n installed"
}

install_openwebui() {
    section "Installing OpenWebUI $OPEN_WEBUI_VERSION"

    if pip show open-webui &>/dev/null 2>&1; then
        log "OpenWebUI already installed"
        return
    fi

    pip install "open-webui==$OPEN_WEBUI_VERSION" --break-system-packages
    pip install qdrant-client --break-system-packages
    export PATH="$HOME/.local/bin:$PATH"
    log "OpenWebUI installed"
}

install_qdrant() {
    section "Installing Qdrant $QDRANT_VERSION"

    if [ ! -f "$HOME/qdrant" ]; then
        info "Downloading Qdrant binary..."
        curl -L "https://github.com/qdrant/qdrant/releases/download/$QDRANT_VERSION/qdrant-x86_64-unknown-linux-gnu.tar.gz" \
            -o /tmp/qdrant.tar.gz
        tar -xzf /tmp/qdrant.tar.gz -C "$HOME"
        rm /tmp/qdrant.tar.gz
        chmod +x "$HOME/qdrant"
        log "Qdrant binary ready"
    else
        log "Qdrant binary already exists"
    fi

    if [ ! -f "$QDRANT_DIR/static/index.html" ]; then
        info "Downloading Qdrant Web UI..."
        curl -L "https://github.com/qdrant/qdrant-web-ui/releases/download/$QDRANT_WEBUI_VERSION/dist-qdrant.zip" \
            -o /tmp/qdrant-webui.zip
        unzip -q /tmp/qdrant-webui.zip -d /tmp/qdrant-webui-temp
        cp -r /tmp/qdrant-webui-temp/dist/. "$QDRANT_DIR/static/"
        rm -rf /tmp/qdrant-webui.zip /tmp/qdrant-webui-temp
        log "Qdrant Web UI installed"
    else
        log "Qdrant Web UI already exists"
    fi
}

# ============================================================
# SECTION 11 -- PYTHON VENVS
# Every AI tool in isolation -- no global pip for AI tools.
# ============================================================

setup_venvs() {
    section "Setting Up Python Virtual Environments"

    _make_venv() {
        local name=$1; shift
        if [ ! -d "$VENVS_DIR/$name" ]; then
            info "Creating $name venv..."
            python3 -m venv "$VENVS_DIR/$name"
            "$VENVS_DIR/$name/bin/pip" install --upgrade pip -q
            "$VENVS_DIR/$name/bin/pip" install "$@" -q
            log "$name venv ready"
        else
            log "$name venv already exists -- skipping"
        fi
    }

    _make_venv crewai \
        "crewai==$CREWAI_VERSION" "crewai-tools==$CREWAI_TOOLS_VERSION"

    _make_venv aider \
        "aider-chat==$AIDER_VERSION"

    _make_venv interpreter \
        "open-interpreter==$OPEN_INTERPRETER_VERSION"

    _make_venv scrapy \
        scrapy pandas dedupe email-validator phonenumbers tqdm python-dotenv

    if [ ! -d "$VENVS_DIR/playwright" ]; then
        info "Creating playwright venv..."
        python3 -m venv "$VENVS_DIR/playwright"
        "$VENVS_DIR/playwright/bin/pip" install --upgrade pip -q
        "$VENVS_DIR/playwright/bin/pip" install playwright requests dnspython -q
        "$VENVS_DIR/playwright/bin/playwright" install chromium
        "$VENVS_DIR/playwright/bin/playwright" install-deps chromium
        log "playwright venv ready"
    else
        log "playwright venv already exists -- skipping"
    fi
}

# ============================================================
# SECTION 12 -- CREWAI STUDIO
# ============================================================

install_crewai_studio() {
    section "Installing CrewAI Studio"

    if [ ! -d "$STUDIO_DIR" ]; then
        git clone https://github.com/strnad/CrewAI-Studio.git "$STUDIO_DIR"
        log "CrewAI Studio cloned"
    else
        log "CrewAI Studio already exists"
    fi

    if [ ! -d "$STUDIO_DIR/venv" ]; then
        info "Installing Studio dependencies..."
        cd "$STUDIO_DIR"
        python3 -m venv venv
        source venv/bin/activate
        pip install --upgrade pip -q
        pip install -r requirements.txt -q
        deactivate
        cd "$HOME"
        log "CrewAI Studio dependencies installed"
    else
        log "CrewAI Studio venv already exists"
    fi

    # Suppress Streamlit email prompt
    mkdir -p "$HOME/.streamlit"
    cat > "$HOME/.streamlit/credentials.toml" << TOML
[general]
email = "${STREAMLIT_EMAIL}"
TOML
    log "Streamlit credentials set"
}

# ============================================================
# SECTION 13 -- LAUNCHERS
# All launchers use absolute binary paths.
# PM2 does not inherit PATH or venv state -- absolute paths only.
# ============================================================

create_launchers() {
    section "Creating PM2 Launcher Scripts"

    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    # Resolve binaries at install time
    N8N_BIN=$(which n8n 2>/dev/null || \
        find "$HOME/.nvm" -name "n8n" -type f 2>/dev/null | head -1 || echo "n8n")
    OPENWEBUI_BIN=$(which open-webui 2>/dev/null || \
        echo "$HOME/.local/bin/open-webui")

    info "n8n binary: $N8N_BIN"
    info "OpenWebUI binary: $OPENWEBUI_BIN"

    # OpenWebUI
    cat > "$SCRIPTS_DIR/run-openwebui.sh" << LAUNCHEREOF
#!/bin/bash
export PATH="\$HOME/.local/bin:\$PATH"
export VECTOR_DB=qdrant
export QDRANT_URI=http://localhost:6333
export DATA_DIR="\$HOME/.local/share/open-webui"
exec ${OPENWEBUI_BIN} serve
LAUNCHEREOF

    # n8n -- N8N_PATH + N8N_EDITOR_BASE_URL critical for sub-path serving
    cat > "$SCRIPTS_DIR/run-n8n.sh" << LAUNCHEREOF
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
exec ${N8N_BIN} start
LAUNCHEREOF

    # Qdrant -- cd is required for config file resolution
    cat > "$SCRIPTS_DIR/run-qdrant.sh" << 'LAUNCHEREOF'
#!/bin/bash
export QDRANT__SERVICE__STATIC_CONTENT_DIR="$HOME/qdrant-data/static"
cd "$HOME/qdrant-data"
exec "$HOME/qdrant"
LAUNCHEREOF

    # CrewAI Studio -- cd MANDATORY (img/crewai_logo.png relative path)
    cat > "$SCRIPTS_DIR/run-crewai-studio.sh" << LAUNCHEREOF
#!/bin/bash
# cd is mandatory -- Streamlit resolves img/ relative to working directory
cd "${STUDIO_DIR}"
exec "${STUDIO_DIR}/venv/bin/streamlit" run \\
    "${STUDIO_DIR}/app/app.py" \\
    --server.port 8501 \\
    --server.address 0.0.0.0 \\
    --server.headless true
LAUNCHEREOF

    # Tool launchers (absolute venv paths -- no source/activate)
    cat > "$SCRIPTS_DIR/run-aider.sh" << LAUNCHEREOF
#!/bin/bash
MODEL="\${1:-ollama/qwen2.5-coder:14b}"
exec "${VENVS_DIR}/aider/bin/aider" --model "\$MODEL" "\${@:2}"
LAUNCHEREOF

    cat > "$SCRIPTS_DIR/run-crew.sh" << LAUNCHEREOF
#!/bin/bash
exec "${VENVS_DIR}/crewai/bin/python3" "\$@"
LAUNCHEREOF

    cat > "$SCRIPTS_DIR/run-interpreter.sh" << LAUNCHEREOF
#!/bin/bash
MODEL="\${1:-ollama/llama3.1:8b}"
exec "${VENVS_DIR}/interpreter/bin/interpreter" --model "\$MODEL"
LAUNCHEREOF

    cat > "$SCRIPTS_DIR/run-scrapy.sh" << LAUNCHEREOF
#!/bin/bash
exec "${VENVS_DIR}/scrapy/bin/python3" "\$@"
LAUNCHEREOF

    cat > "$SCRIPTS_DIR/run-playwright.sh" << LAUNCHEREOF
#!/bin/bash
exec "${VENVS_DIR}/playwright/bin/python3" "\$@"
LAUNCHEREOF

    chmod +x "$SCRIPTS_DIR"/*.sh
    log "All launchers created with absolute paths"
}

# ============================================================
# SECTION 14 -- SHELL ALIASES
# ============================================================

setup_aliases() {
    section "Setting Up Shell Aliases"

    sed -i '/# AIOPS START/,/# AIOPS END/d' ~/.bashrc

    cat >> ~/.bashrc << ALIASEOF

# AIOPS START
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
alias browser-auto='${SCRIPTS_DIR}/run-playwright.sh'

# Quick Ollama chat
alias chat='ollama run qwen3:4b'
alias chat-coder='ollama run qwen2.5-coder:14b'
alias chat-reason='ollama run deepseek-r1:8b'
alias models='ollama list'

# PM2 auto-resurrect on terminal open
[[ -z \$(pm2 list 2>/dev/null | grep online) ]] && pm2 resurrect 2>/dev/null || true

# AIOPS END
ALIASEOF

    log "Aliases added to ~/.bashrc"
}

# ============================================================
# SECTION 15 -- PM2 SERVICES
# ============================================================

setup_pm2_services() {
    section "Starting PM2 Services"

    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    pm2 kill 2>/dev/null || true
    rm -f ~/.pm2/dump.pm2 2>/dev/null || true
    sleep 2

    for PORT in 5678 8080 6333 8501; do
        sudo fuser -k ${PORT}/tcp 2>/dev/null || true
    done
    sleep 2

    pm2 start "$SCRIPTS_DIR/run-n8n.sh"          --name n8n
    pm2 start "$SCRIPTS_DIR/run-openwebui.sh"     --name openwebui
    pm2 start "$SCRIPTS_DIR/run-qdrant.sh"        --name qdrant
    pm2 start "$SCRIPTS_DIR/run-crewai-studio.sh" --name crewai-studio

    sleep 5
    pm2 save
    log "PM2 services started and saved"
}

# ============================================================
# SECTION 16 -- SAMPLE CREW
# ============================================================

create_sample_crew() {
    section "Creating Sample CrewAI Script"

    cat > "$AGENTS_DIR/crews/sample_crew.py" << 'CREWEOF'
"""
Sample CrewAI crew -- AIOPS Stack
Tests local Ollama connection
"""
from crewai import Agent, Task, Crew, LLM

llm = LLM(model="ollama/llama3.1:8b", base_url="http://localhost:11434")

crew = Crew(
    agents=[
        Agent(role="Research Analyst",
              goal="Research and summarize accurately",
              backstory="Expert researcher",
              llm=llm, verbose=True),
        Agent(role="Content Writer",
              goal="Write clear engaging content",
              backstory="Professional writer",
              llm=llm, verbose=True)
    ],
    tasks=[
        Task(description="List 3 benefits of local AI for SMBs",
             expected_output="3 bullet points",
             agent=None),
        Task(description="Write a 100 word LinkedIn post from the research",
             expected_output="Ready-to-post LinkedIn update",
             agent=None)
    ],
    verbose=True
)

if __name__ == "__main__":
    result = crew.kickoff()
    print("\n=== OUTPUT ===\n", result)
CREWEOF

    log "Sample crew created: $AGENTS_DIR/crews/sample_crew.py"
}

# ============================================================
# SECTION 17 -- FINAL SUMMARY
# ============================================================

print_summary() {
    section "Installation Complete"

    LOCAL_IP=$(ip route get 1 2>/dev/null | awk '{print $7; exit}' || echo "YOUR_IP")

    echo ""
    echo -e "${BOLD}${GREEN}  +=====================================================+"
    echo "  |  AIOPS SERVER -- READY                              |"
    echo "  +=====================================================+"
    echo "  |  Service         Local URL    LAN URL               |"
    echo "  |  -----------------------------------------------    |"
    echo "  |  OpenWebUI       :8080        http://$LOCAL_DOMAIN  |"
    echo "  |  n8n             :5678        /$LOCAL_DOMAIN/n8n    |"
    echo "  |  CrewAI Studio   :8501        /$LOCAL_DOMAIN/agents |"
    echo "  |  Qdrant          :6333        /$LOCAL_DOMAIN/qdrant |"
    echo "  |  Ollama API      :11434       /$LOCAL_DOMAIN/ollama |"
    echo "  +=====================================================+"
    echo -e "  |  WSL IP: $LOCAL_IP                                    |"
    echo -e "  +=====================================================+${NC}"
    echo ""
    echo -e "${BOLD}Immediate next steps:${NC}"
    echo "  1. source ~/.bashrc"
    echo "  2. ollama pull nomic-embed-text"
    echo "  3. On Windows: run aiops-windows.bat as Administrator"
    echo ""

    echo -e "${BOLD}${YELLOW}+======================================================+"
    echo "| WARNING -- WSL RESTART REQUIRED                      |"
    echo "+======================================================+"
    echo "|                                                      |"
    echo "| Systemd, Avahi mDNS, Ollama, and hostname changes    |"
    echo "| need a full WSL restart to activate.                 |"
    echo "|                                                      |"
    echo "| Run in PowerShell (any window, no admin needed):     |"
    echo "|                                                      |"
    echo "|   wsl --shutdown                                     |"
    echo "|   wsl                                                |"
    echo "|                                                      |"
    echo "| After restart:                                       |"
    echo "|   - PM2 services come up automatically               |"
    echo "|   - $LOCAL_DOMAIN resolves on all LAN devices        |"
    echo "|   - Run aiops-windows.bat for port forwarding        |"
    echo "|                                                      |"
    echo -e "+======================================================+${NC}"
    echo ""
    echo -e "${CYAN}Log: $LOG_FILE${NC}"
    echo ""
}

# ============================================================
# MAIN
# ============================================================

main() {
    mkdir -p "$AIOPS_HOME"
    touch "$LOG_FILE"

    clear
    banner

    echo -e "${BOLD}AIOPS v3.0 -- Complete Local AI Stack Installer${NC}"
    echo ""
    echo "  Core:     Ollama | OpenWebUI | n8n | Qdrant | CrewAI Studio"
    echo "  Venvs:    CrewAI | Aider | Interpreter | Scrapy | Playwright"
    echo "  Network:  Caddy | Avahi mDNS | LAN access on any device"
    echo ""

    setup_config

    if ! confirm "Start installation?"; then
        echo "Cancelled."
        exit 0
    fi

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
    print_summary
}

main "$@"
