#!/bin/bash
# ============================================================
# AIOPS.SH — Local AI Operations Server
# Version:    6.0.0
# Author:     Quantocos AI Labs
# Compatible: Ubuntu 22.04/24.04 (native + WSL2) · macOS 12+
# Usage:      bash <(curl -fsSL https://raw.githubusercontent.com/quantocos/AIOps/main/aiops.sh)
# ============================================================

set +e  # Never exit on error — we handle everything explicitly

# ── Colors ───────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Static paths ─────────────────────────────────────────────
AIOPS_HOME="$HOME/aiops-server"
AIOPS_CONF="$AIOPS_HOME/aiops.conf"
SCRIPTS_DIR="$HOME/scripts"
AGENTS_DIR="$HOME/agents"
VENVS_DIR="$HOME/.venvs"
QDRANT_DIR="$HOME/qdrant-data"
LOG_FILE="$AIOPS_HOME/install.log"
ADDONS_LOG="$AIOPS_HOME/addons.log"

# ── Pinned versions ──────────────────────────────────────────
NODE_VERSION="22"
# OpenWebUI: always install latest stable — pinning causes pip conflicts on new Python
OPEN_WEBUI_VERSION="latest"
# Qdrant: use "latest" redirect — never pin a version that may not exist
# The download function resolves the real version at install time
QDRANT_VERSION="latest"
QDRANT_WEBUI_VERSION="latest"
CREWAI_VERSION="0.80.0"
CREWAI_TOOLS_VERSION="0.14.0"
AIDER_VERSION="0.66.0"
OPEN_INTERPRETER_VERSION="0.3.17"
N8N_VERSION="1.69.2"

# ── Runtime globals ──────────────────────────────────────────
OS_TYPE=""        # linux | mac
IS_WSL=false
PKG_MGR=""        # apt | brew
PIP_FLAGS=""
PYTHON_BIN=""
INSTALL_FAILURES=()

# ── Logging ──────────────────────────────────────────────────
mkdir -p "$AIOPS_HOME"
touch "$LOG_FILE" "$ADDONS_LOG" 2>/dev/null

_log()     { echo -e "${GREEN}[+]${NC} $1" | tee -a "$LOG_FILE"; }
_warn()    { echo -e "${YELLOW}[!]${NC} $1" | tee -a "$LOG_FILE"; }
_error()   { echo -e "${RED}[x]${NC} $1" | tee -a "$LOG_FILE"; }
_info()    { echo -e "${CYAN}[>]${NC} $1" | tee -a "$LOG_FILE"; }
_section() { echo -e "\n${BOLD}${BLUE}=== $1 ===${NC}\n" | tee -a "$LOG_FILE"; }
_section_add() { echo -e "\n${BOLD}${CYAN}=== $1 ===${NC}\n" | tee -a "$ADDONS_LOG"; }
_log_add() { echo -e "${GREEN}[+]${NC} $1" | tee -a "$ADDONS_LOG"; }
_warn_add(){ echo -e "${YELLOW}[!]${NC} $1" | tee -a "$ADDONS_LOG"; }
_fail()    { INSTALL_FAILURES+=("$1"); _error "FAILED: $1 — continuing"; }

confirm() {
    local msg="$1"
    local default="${2:-n}"
    local prompt
    [ "$default" = "y" ] && prompt="[Y/n]" || prompt="[y/N]"
    read -rp "$(echo -e "${YELLOW}${msg} ${prompt}: ${NC}")" r
    case "$r" in
        [Yy]*) return 0 ;;
        [Nn]*) return 1 ;;
        "")    [ "$default" = "y" ] && return 0 || return 1 ;;
        *)     return 1 ;;
    esac
}

nvm_load() {
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" 2>/dev/null
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion" 2>/dev/null
}

conf_load() {
    [ -f "$AIOPS_CONF" ] && source "$AIOPS_CONF" 2>/dev/null
}

# ── OS Detection ─────────────────────────────────────────────
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        OS_TYPE="mac"
        PKG_MGR="brew"
        PIP_FLAGS=""
        _log "OS: macOS detected"
    elif grep -qi "ubuntu\|debian" /etc/os-release 2>/dev/null; then
        OS_TYPE="linux"
        PKG_MGR="apt"
        local ver
        ver=$(grep VERSION_ID /etc/os-release | cut -d= -f2 | tr -d '"')
        # Ubuntu 24.04+ needs --break-system-packages for pip installs outside venv
        if awk "BEGIN {exit !($ver >= 23.0)}"; then
            PIP_FLAGS="--break-system-packages"
        fi
        _log "OS: Ubuntu $ver detected"
    else
        _error "Unsupported OS. This script supports Ubuntu 22.04+, 24.04+, and macOS 12+."
        exit 1
    fi

    if grep -qi "microsoft" /proc/version 2>/dev/null; then
        IS_WSL=true
        _log "Environment: WSL2 detected"
    fi
}

# ============================================================
# BANNER
# ============================================================
show_banner() {
    clear
    echo -e "${BOLD}${CYAN}"
    cat << 'BANNER'

   ____  _   _   _    _   _ _____ ___   ____  ___  ____
  / __ \| | | | / \  | \ | |_   _/ _ \ / ___|/ _ \/ ___|
 | |  | | | | |/ _ \ |  \| | | || | | | |   | | | \___ \
 | |__| | |_| / ___ \| |\  | | || |_| | |___| |_| |___) |
  \___\_\\___/_/   \_\_| \_| |_| \___/ \____|\___/|____/

BANNER
    echo -e "${NC}"
    echo -e "  ${BOLD}Local AI Operations Server  |  Quantocos AI Labs  |  v6.0.0${NC}"
    echo    "  ─────────────────────────────────────────────────────────────"
    echo ""
}

# ============================================================
# STEP 1 — MODE SELECTION
# ============================================================
select_mode() {
    _section "Installation Mode"
    echo "  What would you like to install?"
    echo ""
    echo "  [1] Core Stack only"
    echo "      Ollama, OpenWebUI, n8n, Qdrant, CrewAI Studio"
    echo ""
    echo "  [2] Addons only"
    echo "      Twenty CRM, Listmonk, Mautic, Chatwoot, Cal.com,"
    echo "      Langfuse, Netdata  (requires Core already installed)"
    echo ""
    echo "  [3] Full install — Core + Addons"
    echo ""
    local choice
    while true; do
        read -rp "$(echo -e "${YELLOW}  Enter choice [1/2/3]: ${NC}")" choice
        case "$choice" in
            1) INSTALL_MODE="core";   break ;;
            2) INSTALL_MODE="addons"; break ;;
            3) INSTALL_MODE="full";   break ;;
            *) echo "  Please enter 1, 2, or 3" ;;
        esac
    done
    _log "Mode: $INSTALL_MODE"
}

# ============================================================
# STEP 2 — DOMAIN NAME
# ============================================================
setup_domain() {
    _section "Domain Name"
    echo -e "  ${CYAN}Choose a name for accessing your services on this network.${NC}"
    echo -e "  ${CYAN}Example: 'myserver' gives you http://myserver.local${NC}"
    echo -e "  ${CYAN}Press Enter to use the default: aiops${NC}"
    echo ""
    local domain_input
    read -rp "$(echo -e "${YELLOW}  Domain name (default: aiops): ${NC}")" domain_input
    domain_input="${domain_input%.local}"
    [ -z "$domain_input" ] && domain_input="aiops"
    AIOPS_DOMAIN="${domain_input}.local"
    _log "Domain: $AIOPS_DOMAIN"
}

# ============================================================
# STEP 3 — STREAMLIT EMAIL
# ============================================================
setup_streamlit_email() {
    _section "CrewAI Studio Setup"
    echo -e "  ${CYAN}CrewAI Studio asks for an email address on first run.${NC}"
    echo -e "  ${CYAN}You can leave this blank by pressing Enter.${NC}"
    echo ""
    local email_input
    read -rp "$(echo -e "${YELLOW}  Email address (or press Enter to skip): ${NC}")" email_input
    mkdir -p "$HOME/.streamlit"
    cat > "$HOME/.streamlit/credentials.toml" << EOF
[general]
email = "${email_input}"
EOF
    _log "Streamlit credentials configured"
}

# ============================================================
# STEP 4 — WRITE CONFIG
# ============================================================
write_config() {
    mkdir -p "$AIOPS_HOME"
    cat > "$AIOPS_CONF" << CONF
# ============================================================
# AIOPS Configuration — Quantocos AI Labs v6.0.0
# Generated: $(date)
# Edit this file, then run: pm2 restart all
# ============================================================

AIOPS_DOMAIN="${AIOPS_DOMAIN}"

AIOPS_PORT_OPENWEBUI=8080
AIOPS_PORT_N8N=5678
AIOPS_PORT_QDRANT=6333
AIOPS_PORT_CREWAI=8501
AIOPS_PORT_TWENTY=3000
AIOPS_PORT_LISTMONK=9000
AIOPS_PORT_MAUTIC=8100
AIOPS_PORT_CHATWOOT=3100
AIOPS_PORT_CALCOM=3002
AIOPS_PORT_LANGFUSE=3004
AIOPS_PORT_NETDATA=19999
AIOPS_PORT_OLLAMA=11434

AIOPS_HOME="${AIOPS_HOME}"
AIOPS_CONF="${AIOPS_CONF}"
AIOPS_SCRIPTS_DIR="${SCRIPTS_DIR}"
AIOPS_AGENTS_DIR="${AGENTS_DIR}"
AIOPS_VENVS_DIR="${VENVS_DIR}"
AIOPS_QDRANT_DIR="${QDRANT_DIR}"
AIOPS_LOG="${LOG_FILE}"
CONF
    chmod 600 "$AIOPS_CONF"
    conf_load
    _log "Config written: $AIOPS_CONF"
}

# ============================================================
# STEP 5 — PREFLIGHT
# ============================================================
preflight() {
    _section "Preflight Checks"
    local pass=true

    # Internet
    echo -n "  Internet connectivity ... "
    if curl -s --max-time 8 https://google.com > /dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        echo ""
        echo -e "  ${RED}No internet connection detected.${NC}"
        echo -e "  ${RED}Please check your network and try again.${NC}"
        exit 1
    fi

    # Disk space
    echo -n "  Disk space (need 20GB) ... "
    local available
    available=$(df "$HOME" | awk 'NR==2 {print $4}')
    local available_gb=$(( available / 1024 / 1024 ))
    if [ "$available_gb" -ge 20 ]; then
        echo -e "${GREEN}${available_gb}GB free${NC}"
    else
        echo -e "${YELLOW}${available_gb}GB free (low, recommend 20GB+)${NC}"
    fi

    # RAM
    echo -n "  RAM ... "
    local ram_gb
    if [ "$OS_TYPE" = "mac" ]; then
        ram_gb=$(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 ))
    else
        ram_gb=$(free -g | awk 'NR==2 {print $2}')
    fi
    if [ "$ram_gb" -ge 8 ]; then
        echo -e "${GREEN}${ram_gb}GB${NC}"
    else
        echo -e "${YELLOW}${ram_gb}GB (8GB+ recommended)${NC}"
    fi

    # GPU
    echo -n "  GPU (NVIDIA) ... "
    if command -v nvidia-smi &>/dev/null; then
        local gpu_name; gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
        local vram; vram=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader 2>/dev/null | head -1)
        echo -e "${GREEN}${gpu_name} (${vram})${NC}"
    else
        echo -e "${YELLOW}Not detected — Ollama will run on CPU${NC}"
    fi

    # WSL2 systemd
    if $IS_WSL; then
        echo -n "  WSL2 systemd ... "
        if systemctl status > /dev/null 2>&1; then
            echo -e "${GREEN}enabled${NC}"
        else
            echo -e "${YELLOW}not enabled — enabling now${NC}"
            sudo tee -a /etc/wsl.conf > /dev/null 2>/dev/null << 'EOF'
[boot]
systemd=true
EOF
        fi
    fi

    echo ""
    confirm "  Everything looks good. Proceed with installation?" "y" || exit 0
}

# ============================================================
# CORE INSTALLERS
# ============================================================

# ── Homebrew (Mac only) ───────────────────────────────────────
install_homebrew() {
    [ "$OS_TYPE" != "mac" ] && return
    if ! command -v brew &>/dev/null; then
        _info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        # Add brew to PATH for Apple Silicon
        if [ -f "/opt/homebrew/bin/brew" ]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        fi
    fi
    _log "Homebrew ready"
}

# ── System packages ───────────────────────────────────────────
install_system_deps() {
    _section "System Dependencies"

    if [ "$OS_TYPE" = "linux" ]; then
        _info "Updating package lists..."
        sudo apt-get update -qq 2>/dev/null

        _info "Installing system packages..."
        sudo apt-get install -y \
            curl wget git unzip zip \
            build-essential \
            python3 python3-pip python3-venv python3-dev \
            lsof ffmpeg zstd \
            ca-certificates gnupg lsb-release \
            htop nvtop \
            avahi-daemon avahi-utils libnss-mdns \
            2>/dev/null || true

        # Python 3.11+ check and install via deadsnakes if needed
        _ensure_python311_linux

    elif [ "$OS_TYPE" = "mac" ]; then
        brew install curl wget git python@3.11 htop 2>/dev/null || true
        PYTHON_BIN=$(brew --prefix)/bin/python3.11
        _log "System packages installed"
    fi

    _log "System dependencies ready"
}

_ensure_python311_linux() {
    # Check if python3.11+ already available
    local pyver
    pyver=$(python3 -c 'import sys; print(sys.version_info.minor)' 2>/dev/null || echo "0")
    local pymaj
    pymaj=$(python3 -c 'import sys; print(sys.version_info.major)' 2>/dev/null || echo "0")

    if [ "$pymaj" -ge 3 ] && [ "$pyver" -ge 11 ]; then
        PYTHON_BIN=$(which python3)
        _log "Python $(python3 --version) ready"
        return
    fi

    _info "Python 3.11+ required, installing via deadsnakes PPA..."
    sudo apt-get install -y software-properties-common -qq 2>/dev/null || true
    sudo add-apt-repository -y ppa:deadsnakes/ppa 2>/dev/null || true
    sudo apt-get update -qq 2>/dev/null
    sudo apt-get install -y python3.11 python3.11-venv python3.11-dev python3.11-distutils 2>/dev/null || true

    # Install pip for 3.11
    curl -sS https://bootstrap.pypa.io/get-pip.py | python3.11 2>/dev/null || true

    # Make python3.11 the default python3 if possible
    sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 2>/dev/null || true
    PYTHON_BIN=$(which python3.11 2>/dev/null || which python3)
    _log "Python $($PYTHON_BIN --version 2>&1) ready"
}

# ── Node via NVM ──────────────────────────────────────────────
install_node() {
    _section "Node.js + pnpm + PM2"

    nvm_load
    if command -v node &>/dev/null; then
        local ver; ver=$(node -v | cut -d. -f1 | tr -d 'v')
        if [ "$ver" -ge "$NODE_VERSION" ] 2>/dev/null; then
            _log "Node.js $(node -v) already installed"
            _ensure_pnpm_pm2
            return
        fi
    fi

    _info "Installing NVM..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.2/install.sh 2>/dev/null | bash
    export NVM_DIR="$HOME/.nvm"
    \. "$NVM_DIR/nvm.sh" 2>/dev/null

    _info "Installing Node.js $NODE_VERSION..."
    nvm install "$NODE_VERSION" 2>/dev/null
    nvm alias default "$NODE_VERSION" 2>/dev/null
    nvm use "$NODE_VERSION" 2>/dev/null
    _log "Node.js $(node -v) ready"

    _ensure_pnpm_pm2
}

_ensure_pnpm_pm2() {
    nvm_load
    command -v pnpm &>/dev/null || npm install -g pnpm 2>/dev/null
    command -v pm2  &>/dev/null || npm install -g pm2  2>/dev/null
    _log "pnpm $(pnpm -v 2>/dev/null) ready"
    _log "PM2 $(pm2 -v 2>/dev/null) ready"
}

# ── Ollama ────────────────────────────────────────────────────
install_ollama() {
    _section "Ollama"
    conf_load

    if command -v ollama &>/dev/null; then
        _log "Ollama already installed"
    else
        _info "Installing Ollama..."
        # zstd already installed above — this prevents the common install failure
        if [ "$OS_TYPE" = "linux" ]; then
            curl -fsSL https://ollama.com/install.sh 2>/dev/null | sh
        elif [ "$OS_TYPE" = "mac" ]; then
            brew install ollama 2>/dev/null || true
        fi
    fi

    if ! command -v ollama &>/dev/null; then
        _fail "Ollama"
        return
    fi

    # Configure to listen on all interfaces
    if [ "$OS_TYPE" = "linux" ]; then
        sudo mkdir -p /etc/systemd/system/ollama.service.d
        sudo tee /etc/systemd/system/ollama.service.d/override.conf > /dev/null << 'EOF'
[Service]
Environment="OLLAMA_HOST=0.0.0.0"
EOF
        sudo systemctl daemon-reload 2>/dev/null || true
        sudo systemctl enable ollama 2>/dev/null || true
        sudo systemctl restart ollama 2>/dev/null || (ollama serve > /dev/null 2>&1 &)
    elif [ "$OS_TYPE" = "mac" ]; then
        export OLLAMA_HOST=0.0.0.0
        ollama serve > /dev/null 2>&1 &
    fi

    # Wait for Ollama to be ready
    _info "Waiting for Ollama to start..."
    local attempts=0
    until curl -s "http://localhost:${AIOPS_PORT_OLLAMA}/api/tags" > /dev/null 2>&1; do
        sleep 2
        attempts=$((attempts + 1))
        [ "$attempts" -ge 15 ] && { _fail "Ollama (timeout)"; return; }
    done
    _log "Ollama running on port ${AIOPS_PORT_OLLAMA}"

    echo ""
    echo -e "  ${BOLD}Recommended models for 8GB VRAM:${NC}"
    echo ""
    echo "  ollama pull nomic-embed-text     # Embeddings / RAG (274MB)"
    echo "  ollama pull qwen3:4b             # General chat, fast (2.6GB)"
    echo "  ollama pull qwen2.5:7b           # Writing, emails (4.7GB)"
    echo "  ollama pull qwen2.5-coder:7b     # Code generation (4.7GB)"
    echo "  ollama pull deepseek-r1:8b       # Reasoning, analysis (5.2GB)"
    echo "  ollama pull llama3.1:8b          # Agent tool use (4.9GB)"
    echo ""
    echo -e "  ${YELLOW}Pull models after install using the commands above.${NC}"
    echo -e "  ${YELLOW}Do not run more than one 7-8B model at the same time on 8GB VRAM.${NC}"
    echo ""
}

# ── Qdrant ────────────────────────────────────────────────────
install_qdrant() {
    _section "Qdrant Vector Database"
    conf_load

    local qdrant_bin="$HOME/qdrant"

    if [ ! -f "$qdrant_bin" ]; then
        _info "Downloading Qdrant (latest)..."

        # Resolve the real download URL via GitHub latest redirect
        # This avoids pinning a version that may not exist
        local dl_url
        if [ "$OS_TYPE" = "mac" ]; then
            local arch; arch=$(uname -m)  # x86_64 or arm64
            dl_url="https://github.com/qdrant/qdrant/releases/latest/download/qdrant-${arch}-apple-darwin.tar.gz"
        else
            dl_url="https://github.com/qdrant/qdrant/releases/latest/download/qdrant-x86_64-unknown-linux-gnu.tar.gz"
        fi

        curl -fsSL "$dl_url" -o /tmp/qdrant.tar.gz 2>/dev/null
        if [ ! -s /tmp/qdrant.tar.gz ]; then
            _fail "Qdrant (download failed)"
            return 1
        fi

        # Extract to a temp dir first — archive structure varies by release
        rm -rf /tmp/qdrant-extract
        mkdir -p /tmp/qdrant-extract
        tar -xzf /tmp/qdrant.tar.gz -C /tmp/qdrant-extract 2>/dev/null

        # Find the binary regardless of directory structure in the archive
        local extracted_bin
        extracted_bin=$(find /tmp/qdrant-extract -name "qdrant" -type f 2>/dev/null | head -1)

        if [ -z "$extracted_bin" ]; then
            _fail "Qdrant (binary not found in archive)"
            rm -rf /tmp/qdrant.tar.gz /tmp/qdrant-extract
            return 1
        fi

        cp "$extracted_bin" "$qdrant_bin"
        chmod +x "$qdrant_bin"
        rm -rf /tmp/qdrant.tar.gz /tmp/qdrant-extract
        _log "Qdrant binary ready: $qdrant_bin"
    else
        _log "Qdrant binary already exists"
    fi

    mkdir -p "$QDRANT_DIR"/{config,static,storage,snapshots}

    # Qdrant Web UI
    if [ ! -f "$QDRANT_DIR/static/index.html" ]; then
        _info "Downloading Qdrant Web UI..."
        curl -L "https://github.com/qdrant/qdrant-web-ui/releases/download/${QDRANT_WEBUI_VERSION}/dist-qdrant.zip" \
            -o /tmp/qdrant-webui.zip 2>/dev/null
        unzip -q /tmp/qdrant-webui.zip -d /tmp/qdrant-webui-tmp 2>/dev/null
        # Handle different zip structures
        if [ -d "/tmp/qdrant-webui-tmp/dist" ]; then
            cp -r /tmp/qdrant-webui-tmp/dist/. "$QDRANT_DIR/static/"
        else
            cp -r /tmp/qdrant-webui-tmp/. "$QDRANT_DIR/static/"
        fi
        rm -rf /tmp/qdrant-webui.zip /tmp/qdrant-webui-tmp
        _log "Qdrant Web UI installed"
    else
        _log "Qdrant Web UI already exists"
    fi

    # Create launcher — sources config at runtime
    cat > "$SCRIPTS_DIR/run-qdrant.sh" << QDSCRIPT
#!/bin/bash
source "${AIOPS_CONF}"
export QDRANT__SERVICE__STATIC_CONTENT_DIR="\${AIOPS_QDRANT_DIR}/static"
export QDRANT__SERVICE__HTTP_PORT="\${AIOPS_PORT_QDRANT}"
cd "\${AIOPS_QDRANT_DIR}"
exec "\$HOME/qdrant"
QDSCRIPT
    chmod +x "$SCRIPTS_DIR/run-qdrant.sh"

    _start_and_verify "qdrant" "$SCRIPTS_DIR/run-qdrant.sh" "$QDRANT_DIR" "${AIOPS_PORT_QDRANT}" "Qdrant"
}

# ── OpenWebUI ─────────────────────────────────────────────────
# KEY FIX: Dedicated venv, launched via `python -m open_webui`.
# No entry-point binary. No PATH issues. No binary discovery.
# Venv Python path is absolute and fixed — PM2 calls it directly.
install_openwebui() {
    _section "OpenWebUI"
    conf_load

    local venv="$VENVS_DIR/openwebui"

    if [ ! -d "$venv" ]; then
        _info "Creating OpenWebUI venv (Python: $($PYTHON_BIN --version 2>&1))..."
        "$PYTHON_BIN" -m venv "$venv"
        "$venv/bin/pip" install --upgrade pip setuptools wheel -q 2>/dev/null
    fi

    if ! "$venv/bin/python" -c "import open_webui" 2>/dev/null; then
        _info "Installing OpenWebUI (latest stable — this takes a few minutes)..."
        # Always install latest — pinning specific versions causes pip conflicts
        # on different Python versions and Ubuntu releases
        "$venv/bin/pip" install open-webui -q 2>/dev/null
        if ! "$venv/bin/python" -c "import open_webui" 2>/dev/null; then
            # Try with no cache if first attempt failed
            _warn "First attempt failed, retrying without cache..."
            "$venv/bin/pip" install open-webui --no-cache-dir 2>/dev/null
        fi
    else
        _log "OpenWebUI already installed in venv"
    fi

    if ! "$venv/bin/python" -c "import open_webui" 2>/dev/null; then
        _fail "OpenWebUI"
        return
    fi

    # Launcher — uses venv Python directly, no binary, no PATH dependency
    cat > "$SCRIPTS_DIR/run-openwebui.sh" << OWSCRIPT
#!/bin/bash
source "${AIOPS_CONF}"

# Use venv Python directly — no binary discovery, no PATH dependency
VENV_PYTHON="${venv}/bin/python"

if [ ! -x "\$VENV_PYTHON" ]; then
    echo "[x] OpenWebUI venv Python not found at \$VENV_PYTHON"
    echo "    Run: ${venv}/bin/pip install open-webui"
    exit 1
fi

export VECTOR_DB=qdrant
export QDRANT_URI="http://localhost:\${AIOPS_PORT_QDRANT}"
export DATA_DIR="\$HOME/.local/share/open-webui"
export PORT="\${AIOPS_PORT_OPENWEBUI}"

exec "\$VENV_PYTHON" -m open_webui serve --port "\${AIOPS_PORT_OPENWEBUI}"
OWSCRIPT
    chmod +x "$SCRIPTS_DIR/run-openwebui.sh"

    _start_and_verify "openwebui" "$SCRIPTS_DIR/run-openwebui.sh" "$HOME" "${AIOPS_PORT_OPENWEBUI}" "OpenWebUI"
}

# ── n8n ───────────────────────────────────────────────────────
install_n8n() {
    _section "n8n Workflow Automation"
    conf_load
    nvm_load

    if ! command -v n8n &>/dev/null; then
        _info "Installing n8n ${N8N_VERSION}..."
        npm install -g "n8n@${N8N_VERSION}" 2>/dev/null \
            || npm install -g n8n 2>/dev/null
    else
        _log "n8n already installed"
    fi

    if ! command -v n8n &>/dev/null; then
        _fail "n8n"
        return
    fi

    cat > "$SCRIPTS_DIR/run-n8n.sh" << N8NSCRIPT
#!/bin/bash
source "${AIOPS_CONF}"
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
N8NSCRIPT
    chmod +x "$SCRIPTS_DIR/run-n8n.sh"

    _start_and_verify "n8n" "$SCRIPTS_DIR/run-n8n.sh" "$HOME" "${AIOPS_PORT_N8N}" "n8n"
}

# ── CrewAI + CrewAI Studio ────────────────────────────────────
install_crewai() {
    _section "CrewAI + CrewAI Studio"
    conf_load

    # ── CrewAI library venv ───────────────────────────────────
    local crewai_venv="$VENVS_DIR/crewai"
    if [ ! -d "$crewai_venv" ]; then
        _info "Creating CrewAI venv..."
        "$PYTHON_BIN" -m venv "$crewai_venv"
        "$crewai_venv/bin/pip" install --upgrade pip -q 2>/dev/null
    fi

    if ! "$crewai_venv/bin/python" -c "import crewai" 2>/dev/null; then
        _info "Installing CrewAI ${CREWAI_VERSION}..."
        "$crewai_venv/bin/pip" install "crewai==${CREWAI_VERSION}" "crewai-tools==${CREWAI_TOOLS_VERSION}" -q 2>/dev/null \
            || "$crewai_venv/bin/pip" install crewai crewai-tools -q 2>/dev/null
        _log "CrewAI installed"
    else
        _log "CrewAI already installed"
    fi

    # ── CrewAI Studio venv ────────────────────────────────────
    local studio_dir="$HOME/CrewAI-Studio"
    local studio_venv="$studio_dir/venv"

    if [ ! -d "$studio_dir" ]; then
        _info "Cloning CrewAI Studio..."
        git clone https://github.com/strnad/CrewAI-Studio.git "$studio_dir" 2>/dev/null
    else
        _log "CrewAI Studio already cloned"
    fi

    if [ ! -d "$studio_venv" ]; then
        _info "Installing CrewAI Studio dependencies..."
        cd "$studio_dir"
        "$PYTHON_BIN" -m venv "$studio_venv"
        "$studio_venv/bin/pip" install --upgrade pip -q 2>/dev/null

        # FIX: Pin snowflake-connector-python to avoid yanked version warning/failure
        # The yanked 4.1.0 version causes install issues — pin to last stable
        "$studio_venv/bin/pip" install "snowflake-connector-python==3.12.4" -q 2>/dev/null || true

        # Now install requirements — snowflake already satisfied, won't re-download yanked
        if [ -f "requirements.txt" ]; then
            "$studio_venv/bin/pip" install -r requirements.txt -q 2>/dev/null || \
            "$studio_venv/bin/pip" install -r requirements.txt --no-deps -q 2>/dev/null || true
        fi
        cd "$HOME"
        _log "CrewAI Studio dependencies installed"
    else
        _log "CrewAI Studio venv already exists"
    fi

    # ── Folder structure only, no sample scripts ──────────────
    mkdir -p "$AGENTS_DIR"/{crews,tasks,tools,outputs,configs,knowledge}
    _log "Agent folders created"

    # ── Launcher ──────────────────────────────────────────────
    cat > "$SCRIPTS_DIR/run-crewai-studio.sh" << CREWSCRIPT
#!/bin/bash
source "${AIOPS_CONF}"
cd "${studio_dir}"
# Use venv Python directly — no PATH dependency
exec "${studio_venv}/bin/python" -m streamlit run app/app.py \\
    --server.port "\${AIOPS_PORT_CREWAI}" \\
    --server.address 0.0.0.0 \\
    --server.headless true \\
    --server.baseUrlPath /agents
CREWSCRIPT
    chmod +x "$SCRIPTS_DIR/run-crewai-studio.sh"

    _start_and_verify "crewai-studio" "$SCRIPTS_DIR/run-crewai-studio.sh" "$studio_dir" "${AIOPS_PORT_CREWAI}" "CrewAI Studio"
}

# ── Playwright ────────────────────────────────────────────────
install_playwright() {
    _section "Playwright"

    local pw_venv="$VENVS_DIR/playwright"
    if [ ! -d "$pw_venv" ]; then
        "$PYTHON_BIN" -m venv "$pw_venv"
        "$pw_venv/bin/pip" install --upgrade pip -q 2>/dev/null
        "$pw_venv/bin/pip" install playwright requests -q 2>/dev/null
        "$pw_venv/bin/playwright" install chromium 2>/dev/null || true
        "$pw_venv/bin/playwright" install-deps chromium 2>/dev/null || true
    fi

    cat > "$SCRIPTS_DIR/run-playwright.sh" << PWSCRIPT
#!/bin/bash
source "${AIOPS_CONF}"
source "${pw_venv}/bin/activate"
exec python3 "\$@"
PWSCRIPT
    chmod +x "$SCRIPTS_DIR/run-playwright.sh"
    _log "Playwright ready"
}

# ── Optional AI Tools ─────────────────────────────────────────
install_optional_tools() {
    _section "Optional AI Tools"
    echo ""
    echo -e "  ${CYAN}Select which AI coding/agent tools to install.${NC}"
    echo -e "  ${CYAN}Press Enter to skip any tool.${NC}"
    echo ""

    # Aider
    echo -e "  ${BOLD}[1] Aider${NC} — AI pair programmer, works in your terminal"
    if confirm "      Install Aider?" "n"; then
        local aider_venv="$VENVS_DIR/aider"
        "$PYTHON_BIN" -m venv "$aider_venv" 2>/dev/null
        "$aider_venv/bin/pip" install --upgrade pip -q 2>/dev/null
        "$aider_venv/bin/pip" install "aider-chat==${AIDER_VERSION}" -q 2>/dev/null \
            || "$aider_venv/bin/pip" install aider-chat -q 2>/dev/null
        cat > "$SCRIPTS_DIR/run-aider.sh" << AIDSCRIPT
#!/bin/bash
source "${AIOPS_CONF}"
source "${aider_venv}/bin/activate"
exec aider "\$@"
AIDSCRIPT
        chmod +x "$SCRIPTS_DIR/run-aider.sh"
        _log "Aider installed"
    else
        _info "Skipping Aider"
    fi

    # Open Interpreter
    echo ""
    echo -e "  ${BOLD}[2] Open Interpreter${NC} — lets AI run code on your computer"
    if confirm "      Install Open Interpreter?" "n"; then
        local oi_venv="$VENVS_DIR/interpreter"
        "$PYTHON_BIN" -m venv "$oi_venv" 2>/dev/null
        "$oi_venv/bin/pip" install --upgrade pip -q 2>/dev/null
        "$oi_venv/bin/pip" install "open-interpreter==${OPEN_INTERPRETER_VERSION}" -q 2>/dev/null \
            || "$oi_venv/bin/pip" install open-interpreter -q 2>/dev/null
        cat > "$SCRIPTS_DIR/run-interpreter.sh" << OISCRIPT
#!/bin/bash
source "${AIOPS_CONF}"
source "${oi_venv}/bin/activate"
exec interpreter "\$@"
OISCRIPT
        chmod +x "$SCRIPTS_DIR/run-interpreter.sh"
        _log "Open Interpreter installed"
    else
        _info "Skipping Open Interpreter"
    fi

    # OpenFang
    echo ""
    echo -e "  ${BOLD}[3] OpenFang${NC} — AI agent with browser, search and social hands"
    if confirm "      Install OpenFang?" "n"; then
        if curl -fsSL --max-time 15 https://openfang.sh/install -o /tmp/openfang-install.sh 2>/dev/null; then
            bash /tmp/openfang-install.sh 2>/dev/null || true
            rm -f /tmp/openfang-install.sh
            export PATH="$HOME/.openfang/bin:$PATH"
            if command -v openfang &>/dev/null; then
                openfang hand activate lead      2>/dev/null || true
                openfang hand activate browser   2>/dev/null || true
                openfang hand activate researcher 2>/dev/null || true
                openfang hand activate twitter   2>/dev/null || true
                _log "OpenFang installed and hands activated"
            else
                _warn "OpenFang installed but binary not in PATH yet — restart shell to use"
            fi
        else
            _warn "OpenFang installer not reachable — skipping"
        fi
    else
        _info "Skipping OpenFang"
    fi

    # OpenClaw
    echo ""
    echo -e "  ${BOLD}[4] OpenClaw${NC} — AI computer use agent"
    if confirm "      Install OpenClaw?" "n"; then
        local oc_venv="$VENVS_DIR/openclaw"
        "$PYTHON_BIN" -m venv "$oc_venv" 2>/dev/null
        "$oc_venv/bin/pip" install --upgrade pip -q 2>/dev/null
        "$oc_venv/bin/pip" install openclaw -q 2>/dev/null \
            && { cat > "$SCRIPTS_DIR/run-openclaw.sh" << OCSCRIPT
#!/bin/bash
source "${AIOPS_CONF}"
source "${oc_venv}/bin/activate"
exec openclaw "\$@"
OCSCRIPT
            chmod +x "$SCRIPTS_DIR/run-openclaw.sh"
            _log "OpenClaw installed"; } \
            || _warn "OpenClaw not available yet — skipping"
    else
        _info "Skipping OpenClaw"
    fi
}

# ── Caddy ─────────────────────────────────────────────────────
# Installed AFTER all services verified — no 502s on startup
install_caddy() {
    _section "Caddy Reverse Proxy"
    conf_load

    if ! command -v caddy &>/dev/null; then
        if [ "$OS_TYPE" = "linux" ]; then
            sudo apt-get install -y debian-keyring debian-archive-keyring apt-transport-https -qq 2>/dev/null
            curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
                | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null
            curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
                | sudo tee /etc/apt/sources.list.d/caddy-stable.list > /dev/null 2>/dev/null
            sudo apt-get update -qq 2>/dev/null
            sudo apt-get install -y caddy 2>/dev/null
        elif [ "$OS_TYPE" = "mac" ]; then
            brew install caddy 2>/dev/null
        fi
        _log "Caddy installed: $(caddy version 2>/dev/null)"
    else
        _log "Caddy already installed: $(caddy version 2>/dev/null)"
    fi

    _write_caddyfile
}

_write_caddyfile() {
    conf_load

    sudo tee /etc/caddy/Caddyfile > /dev/null << CADDY
# ============================================================
# Caddyfile — Quantocos AI Labs — AIOPS v6.0.0
# Regenerate: source ~/aiops-server/aiops.conf && aiops-caddy-regen
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

    # n8n — owns root on its port, Caddy strips prefix
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

    # CrewAI Studio — Streamlit with baseUrlPath=/agents
    handle /agents* {
        uri strip_prefix /agents
        reverse_proxy localhost:${AIOPS_PORT_CREWAI} {
            header_up Host       {host}
            header_up Upgrade    {http.upgrade}
            header_up Connection "Upgrade"
        }
    }

    # Qdrant REST API via proxy — UI accessed directly at :PORT_QDRANT
    handle /qdrant* {
        uri strip_prefix /qdrant
        reverse_proxy localhost:${AIOPS_PORT_QDRANT}
    }

    # Ollama API
    handle /ollama* {
        uri strip_prefix /ollama
        reverse_proxy localhost:${AIOPS_PORT_OLLAMA}
    }

    # Netdata
    handle /monitor* {
        uri strip_prefix /monitor
        reverse_proxy localhost:${AIOPS_PORT_NETDATA}
    }

    # OpenWebUI — catch-all (must be last)
    handle /* {
        reverse_proxy localhost:${AIOPS_PORT_OPENWEBUI} {
            header_up Host      {host}
            header_up X-Real-IP {remote_host}
            header_up Upgrade   {http.upgrade}
            header_up Connection "Upgrade"
        }
    }
}
CADDY

    if sudo caddy validate --config /etc/caddy/Caddyfile 2>/dev/null; then
        sudo systemctl enable caddy 2>/dev/null || true
        sudo systemctl reload caddy 2>/dev/null || sudo systemctl restart caddy 2>/dev/null || true
        _log "Caddyfile written and reloaded"
    else
        _warn "Caddyfile validation failed — check /etc/caddy/Caddyfile"
    fi
}

# ── Avahi mDNS ────────────────────────────────────────────────
setup_mdns() {
    _section "Network Discovery"
    conf_load

    local hostname="${AIOPS_DOMAIN%.local}"

    if [ "$OS_TYPE" = "linux" ]; then
        # Configure Avahi
        sudo tee /etc/avahi/avahi-daemon.conf > /dev/null << AVAHI
[server]
host-name=${hostname}
domain-name=local
use-ipv4=yes
use-ipv6=no
allow-interfaces=eth0,eth1,wlan0
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
            || sudo sed -i 's/^hosts:.*/hosts:          files mdns4_minimal [NOTFOUND=return] dns/' \
               /etc/nsswitch.conf 2>/dev/null || true

        sudo systemctl enable avahi-daemon 2>/dev/null || true
        sudo systemctl restart avahi-daemon 2>/dev/null || true
    fi

    # Write /etc/hosts fallback — works everywhere including WSL2
    # This ensures the domain always resolves even when mDNS fails
    local hosts_entry="127.0.0.1 ${AIOPS_DOMAIN} ${AIOPS_DOMAIN%.local}"
    if ! grep -q "${AIOPS_DOMAIN}" /etc/hosts 2>/dev/null; then
        echo "$hosts_entry" | sudo tee -a /etc/hosts > /dev/null
        _log "Added ${AIOPS_DOMAIN} to /etc/hosts"
    fi

    # WSL2: also write to Windows hosts file for browser access from Windows
    if $IS_WSL; then
        local win_hosts="/mnt/c/Windows/System32/drivers/etc/hosts"
        if [ -w "$win_hosts" ] 2>/dev/null; then
            if ! grep -q "${AIOPS_DOMAIN}" "$win_hosts" 2>/dev/null; then
                echo "$hosts_entry" >> "$win_hosts" 2>/dev/null
                _log "Added ${AIOPS_DOMAIN} to Windows hosts file"
            fi
        else
            _warn "Cannot write to Windows hosts file — run this in PowerShell as Admin:"
            _warn "  Add-Content C:\\Windows\\System32\\drivers\\etc\\hosts '127.0.0.1 ${AIOPS_DOMAIN}'"
        fi
    fi

    _log "mDNS + hosts fallback configured for ${AIOPS_DOMAIN}"
}

# ── PM2 startup + save ────────────────────────────────────────
setup_pm2_startup() {
    _section "PM2 Process Management"
    nvm_load

    pm2 save 2>/dev/null || true

    # Set up PM2 to start on system boot
    if [ "$OS_TYPE" = "linux" ]; then
        local startup_cmd
        startup_cmd=$(pm2 startup systemd -u "$USER" --hp "$HOME" 2>/dev/null | grep "sudo env")
        if [ -n "$startup_cmd" ]; then
            eval "$startup_cmd" 2>/dev/null || true
        fi
    elif [ "$OS_TYPE" = "mac" ]; then
        pm2 startup 2>/dev/null | tail -1 | bash 2>/dev/null || true
    fi

    pm2 save 2>/dev/null || true
    _log "PM2 startup configured"
}

# ── Shell aliases ─────────────────────────────────────────────
setup_aliases() {
    _section "Shell Aliases"
    conf_load

    # Remove any previous AIOPS block
    sed -i '/# AIOPS START/,/# AIOPS END/d' ~/.bashrc 2>/dev/null || true
    [ -f ~/.zshrc ] && sed -i '/# AIOPS START/,/# AIOPS END/d' ~/.zshrc 2>/dev/null || true

    local alias_block
    alias_block=$(cat << ALIASES

# AIOPS START — Quantocos AI Labs v6.0.0
export PATH="\$HOME/.local/bin:\$HOME/.openfang/bin:\$PATH"
export NVM_DIR="\$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && \\. "\$NVM_DIR/nvm.sh"
[ -f "${AIOPS_CONF}" ] && source "${AIOPS_CONF}"

alias ai-status='pm2 status'
alias ai-start='pm2 resurrect'
alias ai-stop='pm2 stop all'
alias ai-restart='pm2 restart all'
alias ai-logs='pm2 logs'
alias ai-config='nano ${AIOPS_CONF}'
alias aiops-caddy-regen='source ${AIOPS_CONF} && _write_caddyfile'
alias models='ollama list'
alias chat='ollama run qwen3:4b'
alias ai-urls='source ${AIOPS_CONF} && echo "" && echo "  OpenWebUI   http://\${AIOPS_DOMAIN}" && echo "  n8n         http://\${AIOPS_DOMAIN}/n8n" && echo "  Qdrant      http://localhost:\${AIOPS_PORT_QDRANT}" && echo "  CrewAI      http://\${AIOPS_DOMAIN}/agents" && echo "  Ollama      http://localhost:\${AIOPS_PORT_OLLAMA}" && echo ""'

[ -x "${SCRIPTS_DIR}/run-aider.sh" ]       && alias aider='${SCRIPTS_DIR}/run-aider.sh'
[ -x "${SCRIPTS_DIR}/run-interpreter.sh" ] && alias interpreter='${SCRIPTS_DIR}/run-interpreter.sh'
[ -x "${SCRIPTS_DIR}/run-playwright.sh" ]  && alias automate='${SCRIPTS_DIR}/run-playwright.sh'
[ -x "${SCRIPTS_DIR}/run-openclaw.sh" ]    && alias openclaw='${SCRIPTS_DIR}/run-openclaw.sh'

[[ -z \$(pm2 list 2>/dev/null | grep online) ]] && pm2 resurrect 2>/dev/null || true
# AIOPS END
ALIASES
)

    echo "$alias_block" >> ~/.bashrc
    [ -f ~/.zshrc ] && echo "$alias_block" >> ~/.zshrc

    _log "Aliases written"
}

# ── Service helper: start via PM2 and verify port ─────────────
# Never proceeds if a previous critical service failed.
# Tries to start, waits for port, marks failure if timeout.
_start_and_verify() {
    local pm2_name="$1"
    local script="$2"
    local cwd="$3"
    local port="$4"
    local label="$5"

    nvm_load

    # Stop existing instance cleanly
    pm2 delete "$pm2_name" 2>/dev/null || true
    sleep 1

    # Kill anything on the port
    sudo fuser -k "${port}/tcp" 2>/dev/null || true
    sleep 1

    _info "Starting ${label}..."
    pm2 start "$script" --name "$pm2_name" --cwd "$cwd" 2>/dev/null

    # Wait for port to respond
    local attempts=0
    local max=30  # 60 seconds max
    while ! curl -s "http://localhost:${port}" > /dev/null 2>&1 \
       && ! curl -s "http://localhost:${port}/api/tags" > /dev/null 2>&1 \
       && ! curl -s "http://localhost:${port}/healthz" > /dev/null 2>&1; do
        sleep 2
        attempts=$((attempts + 1))
        if [ "$attempts" -ge "$max" ]; then
            _fail "${label} (port ${port} not responding)"
            pm2 logs "$pm2_name" --lines 10 --nostream 2>/dev/null | tail -10
            return 1
        fi
    done

    _log "${label} running on port ${port}"
    pm2 save 2>/dev/null || true
    return 0
}

# ============================================================
# ADDONS
# ============================================================

_ensure_shared_deps() {
    # PostgreSQL
    if ! command -v psql &>/dev/null; then
        _info "Installing PostgreSQL..."
        if [ "$OS_TYPE" = "linux" ]; then
            sudo apt-get install -y postgresql postgresql-contrib -qq 2>/dev/null
            sudo systemctl enable postgresql 2>/dev/null || true
            sudo systemctl start postgresql 2>/dev/null || true
        elif [ "$OS_TYPE" = "mac" ]; then
            brew install postgresql@15 2>/dev/null
            brew services start postgresql@15 2>/dev/null || true
        fi
        _log_add "PostgreSQL ready"
    fi

    # Redis
    if ! command -v redis-server &>/dev/null; then
        _info "Installing Redis..."
        if [ "$OS_TYPE" = "linux" ]; then
            sudo apt-get install -y redis-server -qq 2>/dev/null
            sudo systemctl enable redis-server 2>/dev/null || true
            sudo systemctl start redis-server 2>/dev/null || true
        elif [ "$OS_TYPE" = "mac" ]; then
            brew install redis 2>/dev/null
            brew services start redis 2>/dev/null || true
        fi
        _log_add "Redis ready"
    fi
}

addon_twenty_crm() {
    _section_add "Twenty CRM"
    conf_load
    nvm_load
    _ensure_shared_deps

    local dir="$HOME/twenty"
    [ ! -d "$dir" ] && git clone https://github.com/twentyhq/twenty.git "$dir" 2>/dev/null

    sudo -u postgres psql -lqt 2>/dev/null | grep -q twenty || {
        sudo -u postgres psql -c "CREATE USER twenty WITH PASSWORD 'twenty_password';" 2>/dev/null || true
        sudo -u postgres psql -c "CREATE DATABASE twenty OWNER twenty;" 2>/dev/null || true
    }

    cd "$dir"
    [ ! -f ".env" ] && {
        local secret; secret=$(openssl rand -base64 24 | tr -d '=+/' | head -c 32)
        cat > .env << TENV
APP_SECRET=${secret}
DATABASE_URL=postgresql://twenty:twenty_password@localhost:5432/twenty
FRONT_BASE_URL=http://localhost:${AIOPS_PORT_TWENTY}
REDIS_URL=redis://localhost:6379
TENV
    }

    _info "Installing Twenty CRM (pnpm — this takes a few minutes)..."
    pnpm install 2>/dev/null || true

    cat > "$SCRIPTS_DIR/run-twenty.sh" << TSCRIPT
#!/bin/bash
source "${AIOPS_CONF}"
export NVM_DIR="\$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && \\. "\$NVM_DIR/nvm.sh"
cd "${dir}"
exec pnpm nx start
TSCRIPT
    chmod +x "$SCRIPTS_DIR/run-twenty.sh"
    _start_and_verify "twenty" "$SCRIPTS_DIR/run-twenty.sh" "$dir" "${AIOPS_PORT_TWENTY}" "Twenty CRM"
    cd "$HOME"
}

addon_listmonk() {
    _section_add "Listmonk Email Campaigns"
    conf_load
    _ensure_shared_deps

    local bin="$HOME/listmonk"
    local dir="$HOME/listmonk-data"
    mkdir -p "$dir"

    if [ ! -f "$bin" ]; then
        local url
        url=$(curl -s https://api.github.com/repos/knadh/listmonk/releases/latest \
            | grep "browser_download_url.*linux_amd64.tar.gz" | cut -d'"' -f4 | head -1)
        [ -z "$url" ] && url="https://github.com/knadh/listmonk/releases/download/v4.1.0/listmonk_4.1.0_linux_amd64.tar.gz"
        curl -L "$url" -o /tmp/listmonk.tar.gz 2>/dev/null
        tar -xzf /tmp/listmonk.tar.gz -C /tmp/ 2>/dev/null
        find /tmp -maxdepth 2 -name "listmonk" -type f 2>/dev/null | head -1 | xargs -I{} mv {} "$bin"
        chmod +x "$bin"
        rm -f /tmp/listmonk.tar.gz
    fi

    sudo -u postgres psql -lqt 2>/dev/null | grep -q listmonk || {
        sudo -u postgres psql -c "CREATE USER listmonk WITH PASSWORD 'listmonk_password';" 2>/dev/null || true
        sudo -u postgres psql -c "CREATE DATABASE listmonk OWNER listmonk;" 2>/dev/null || true
    }

    [ ! -f "$dir/config.toml" ] && {
        cat > "$dir/config.toml" << TOML
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
        "$bin" --config "$dir/config.toml" --install --yes 2>/dev/null || true
    }

    cat > "$SCRIPTS_DIR/run-listmonk.sh" << LSCRIPT
#!/bin/bash
source "${AIOPS_CONF}"
exec "${bin}" --config "${dir}/config.toml"
LSCRIPT
    chmod +x "$SCRIPTS_DIR/run-listmonk.sh"
    _start_and_verify "listmonk" "$SCRIPTS_DIR/run-listmonk.sh" "$dir" "${AIOPS_PORT_LISTMONK}" "Listmonk"
    _warn_add "Change Listmonk password after first login (admin / change_me_now)"
}

addon_mautic() {
    _section_add "Mautic Marketing Automation"
    conf_load

    # PHP
    command -v php &>/dev/null || {
        sudo apt-get install -y \
            php8.1 php8.1-cli php8.1-fpm php8.1-mysql php8.1-xml \
            php8.1-mbstring php8.1-curl php8.1-zip php8.1-gd \
            php8.1-intl php8.1-bcmath composer -q 2>/dev/null || true
    }

    # MariaDB
    command -v mysql &>/dev/null || {
        sudo apt-get install -y mariadb-server -q 2>/dev/null
        sudo systemctl enable mariadb 2>/dev/null || true
        sudo systemctl start mariadb 2>/dev/null || true
        sudo mysql -e "CREATE DATABASE IF NOT EXISTS mautic CHARACTER SET utf8mb4;" 2>/dev/null || true
        sudo mysql -e "CREATE USER IF NOT EXISTS 'mautic'@'localhost' IDENTIFIED BY 'mautic_password';" 2>/dev/null || true
        sudo mysql -e "GRANT ALL ON mautic.* TO 'mautic'@'localhost';" 2>/dev/null || true
        sudo mysql -e "FLUSH PRIVILEGES;" 2>/dev/null || true
    }

    local dir="$HOME/mautic"
    [ ! -d "$dir" ] && {
        composer create-project mautic/recommended-project:^5 "$dir" --no-interaction -q 2>/dev/null \
            || composer create-project mautic/recommended-project "$dir" --no-interaction 2>/dev/null || true
        cat > "$dir/.env.local" << MENV
APP_URL=http://localhost:${AIOPS_PORT_MAUTIC}
APP_ENV=prod
DB_HOST=localhost
DB_PORT=3306
DB_NAME=mautic
DB_USER=mautic
DB_PASSWD=mautic_password
MENV
    }

    cat > "$SCRIPTS_DIR/run-mautic.sh" << MSCRIPT
#!/bin/bash
source "${AIOPS_CONF}"
cd "${dir}"
export APP_ENV=prod
exec php -S 0.0.0.0:\${AIOPS_PORT_MAUTIC} public/index.php
MSCRIPT
    chmod +x "$SCRIPTS_DIR/run-mautic.sh"
    _start_and_verify "mautic" "$SCRIPTS_DIR/run-mautic.sh" "$dir" "${AIOPS_PORT_MAUTIC}" "Mautic"
}

addon_netdata() {
    _section_add "Netdata System Monitor"
    conf_load

    command -v netdata &>/dev/null || {
        curl -fsSL https://my-netdata.io/kickstart.sh 2>/dev/null \
            | sh -s -- --non-interactive 2>/dev/null || true
    }

    local nd_conf; nd_conf=$(find /etc/netdata -name "netdata.conf" 2>/dev/null | head -1)
    [ -n "$nd_conf" ] && {
        sudo sed -i 's/# *bind to.*/bind to = 0.0.0.0/' "$nd_conf" 2>/dev/null || true
        sudo sed -i 's/^bind to = localhost/bind to = 0.0.0.0/' "$nd_conf" 2>/dev/null || true
        sudo systemctl restart netdata 2>/dev/null || true
    }
    _log_add "Netdata running on port ${AIOPS_PORT_NETDATA}"
}

addon_langfuse() {
    _section_add "Langfuse LLM Observability"
    conf_load
    _ensure_shared_deps

    local dir="$HOME/langfuse"
    [ ! -d "$dir" ] && {
        git clone https://github.com/langfuse/langfuse.git "$dir" 2>/dev/null
    }

    sudo -u postgres psql -lqt 2>/dev/null | grep -q langfuse || {
        sudo -u postgres psql -c "CREATE USER langfuse WITH PASSWORD 'langfuse_password';" 2>/dev/null || true
        sudo -u postgres psql -c "CREATE DATABASE langfuse OWNER langfuse;" 2>/dev/null || true
    }

    cd "$dir"
    [ ! -f ".env" ] && {
        local secret; secret=$(openssl rand -base64 32)
        local salt; salt=$(openssl rand -base64 32)
        cat > .env << LFENV
NODE_ENV=production
DATABASE_URL=postgresql://langfuse:langfuse_password@localhost:5432/langfuse
NEXTAUTH_URL=http://localhost:${AIOPS_PORT_LANGFUSE}
NEXTAUTH_SECRET=${secret}
SALT=${salt}
PORT=${AIOPS_PORT_LANGFUSE}
LFENV
    }

    _info "Installing Langfuse (pnpm)..."
    pnpm install 2>/dev/null || true
    pnpm build 2>/dev/null || true

    cat > "$SCRIPTS_DIR/run-langfuse.sh" << LFSCRIPT
#!/bin/bash
source "${AIOPS_CONF}"
export NVM_DIR="\$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && \\. "\$NVM_DIR/nvm.sh"
cd "${dir}"
exec pnpm start
LFSCRIPT
    chmod +x "$SCRIPTS_DIR/run-langfuse.sh"
    _start_and_verify "langfuse" "$SCRIPTS_DIR/run-langfuse.sh" "$dir" "${AIOPS_PORT_LANGFUSE}" "Langfuse"
    cd "$HOME"
}

addon_chatwoot() {
    _section_add "Chatwoot Unified Inbox"
    conf_load
    _ensure_shared_deps

    # Ruby — user gem space to avoid permission issues
    command -v ruby &>/dev/null || {
        sudo apt-get install -y ruby ruby-dev -q 2>/dev/null
    }
    local ruby_minor; ruby_minor=$(ruby -e 'puts RUBY_VERSION.split(".")[0..1].join(".")' 2>/dev/null || echo "3.2")
    local gem_bin="$HOME/.gem/ruby/${ruby_minor}.0/bin"
    mkdir -p "$gem_bin"
    command -v bundle &>/dev/null || [ -f "$gem_bin/bundle" ] \
        || gem install bundler --user-install 2>/dev/null || true
    export PATH="$gem_bin:$PATH"

    local dir="$HOME/chatwoot"
    [ ! -d "$dir" ] && git clone https://github.com/chatwoot/chatwoot.git "$dir" 2>/dev/null

    sudo -u postgres psql -lqt 2>/dev/null | grep -q chatwoot || {
        sudo -u postgres psql -c "CREATE USER chatwoot WITH PASSWORD 'chatwoot_password';" 2>/dev/null || true
        sudo -u postgres psql -c "CREATE DATABASE chatwoot OWNER chatwoot;" 2>/dev/null || true
    }

    cd "$dir"
    [ ! -f ".env" ] && {
        cp .env.example .env 2>/dev/null || true
        local secret; secret=$(openssl rand -hex 64)
        sed -i "s|SECRET_KEY_BASE=.*|SECRET_KEY_BASE=${secret}|" .env 2>/dev/null || true
        sed -i "s|DATABASE_URL=.*|DATABASE_URL=postgresql://chatwoot:chatwoot_password@localhost:5432/chatwoot|" .env 2>/dev/null || true
        sed -i "s|REDIS_URL=.*|REDIS_URL=redis://localhost:6379|" .env 2>/dev/null || true
        sed -i "s|PORT=3000|PORT=${AIOPS_PORT_CHATWOOT}|" .env 2>/dev/null || true
    }

    _info "Installing Chatwoot gems (this takes a while)..."
    bundle install -q 2>/dev/null || true
    RAILS_ENV=production bundle exec rails db:chatwoot_prepare 2>/dev/null || \
        RAILS_ENV=production bundle exec rails db:migrate 2>/dev/null || true

    local bundle_bin; bundle_bin=$(command -v bundle 2>/dev/null || echo "$gem_bin/bundle")

    cat > "$SCRIPTS_DIR/run-chatwoot.sh" << CWSCRIPT
#!/bin/bash
source "${AIOPS_CONF}"
export PATH="${gem_bin}:\$PATH"
cd "${dir}"
export RAILS_ENV=production
exec ${bundle_bin} exec rails server -b 0.0.0.0 -p \${AIOPS_PORT_CHATWOOT}
CWSCRIPT

    cat > "$SCRIPTS_DIR/run-chatwoot-worker.sh" << CWWSCRIPT
#!/bin/bash
source "${AIOPS_CONF}"
export PATH="${gem_bin}:\$PATH"
cd "${dir}"
export RAILS_ENV=production
exec ${bundle_bin} exec sidekiq
CWWSCRIPT

    chmod +x "$SCRIPTS_DIR/run-chatwoot.sh" "$SCRIPTS_DIR/run-chatwoot-worker.sh"
    nvm_load
    pm2 start "$SCRIPTS_DIR/run-chatwoot-worker.sh" --name chatwoot-worker 2>/dev/null || true
    _start_and_verify "chatwoot" "$SCRIPTS_DIR/run-chatwoot.sh" "$dir" "${AIOPS_PORT_CHATWOOT}" "Chatwoot"
    cd "$HOME"
}

addon_calcom() {
    _section_add "Cal.com Booking"
    conf_load
    nvm_load
    _ensure_shared_deps

    local dir="$HOME/calcom"
    [ ! -d "$dir" ] && git clone https://github.com/calcom/cal.com.git "$dir" 2>/dev/null

    sudo -u postgres psql -lqt 2>/dev/null | grep -q calcom || {
        sudo -u postgres psql -c "CREATE USER calcom WITH PASSWORD 'calcom_password';" 2>/dev/null || true
        sudo -u postgres psql -c "CREATE DATABASE calcom OWNER calcom;" 2>/dev/null || true
    }

    cd "$dir"
    [ ! -f ".env" ] && {
        cp .env.example .env 2>/dev/null || touch .env
        local secret; secret=$(openssl rand -base64 32)
        cat >> .env << CAENV
DATABASE_URL=postgresql://calcom:calcom_password@localhost:5432/calcom
NEXTAUTH_SECRET=${secret}
NEXTAUTH_URL=http://localhost:${AIOPS_PORT_CALCOM}
NEXT_PUBLIC_APP_URL=http://localhost:${AIOPS_PORT_CALCOM}
PORT=${AIOPS_PORT_CALCOM}
CAENV
    }

    _info "Installing Cal.com (pnpm)..."
    pnpm install 2>/dev/null || true
    pnpm prisma generate 2>/dev/null || true
    pnpm prisma db push 2>/dev/null || true

    cat > "$SCRIPTS_DIR/run-calcom.sh" << CASCRIPT
#!/bin/bash
source "${AIOPS_CONF}"
export NVM_DIR="\$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && \\. "\$NVM_DIR/nvm.sh"
cd "${dir}"
exec pnpm next start -p \${AIOPS_PORT_CALCOM}
CASCRIPT
    chmod +x "$SCRIPTS_DIR/run-calcom.sh"
    _start_and_verify "calcom" "$SCRIPTS_DIR/run-calcom.sh" "$dir" "${AIOPS_PORT_CALCOM}" "Cal.com"
    cd "$HOME"
}

# ── Addons menu ───────────────────────────────────────────────
run_addons_menu() {
    while true; do
        echo ""
        echo -e "${BOLD}${CYAN}============================================${NC}"
        echo -e "${BOLD}  ADDONS MENU${NC}"
        echo -e "${BOLD}${CYAN}============================================${NC}"
        echo "  [1]  Twenty CRM      — Lead and deal management"
        echo "  [2]  Listmonk        — Email campaigns"
        echo "  [3]  Mautic          — Full marketing automation"
        echo "  [4]  Netdata         — System monitoring dashboard"
        echo "  [5]  Langfuse        — LLM observability"
        echo "  [6]  Chatwoot        — Unified inbox"
        echo "  [7]  Cal.com         — Booking and scheduling"
        echo ""
        echo "  [a]  Install all addons"
        echo "  [s]  Show PM2 status"
        echo "  [exit] Finish"
        echo ""
        read -rp "$(echo -e "${YELLOW}  Choice (or space-separate multiple e.g. '1 2 3'): ${NC}")" choice

        [[ "$choice" =~ ^(exit|EXIT|q|Q)$ ]] && break

        [ "$choice" = "a" ] && {
            addon_twenty_crm; addon_listmonk; addon_mautic
            addon_netdata; addon_langfuse; addon_chatwoot; addon_calcom
            break
        }

        [ "$choice" = "s" ] && { nvm_load; pm2 status; continue; }

        for item in $choice; do
            case "$item" in
                1) addon_twenty_crm ;;
                2) addon_listmonk ;;
                3) addon_mautic ;;
                4) addon_netdata ;;
                5) addon_langfuse ;;
                6) addon_chatwoot ;;
                7) addon_calcom ;;
                *) echo "  Unknown option: $item" ;;
            esac
        done
    done
}

# ============================================================
# FINAL SUMMARY
# ============================================================
print_summary() {
    conf_load
    nvm_load

    echo ""
    echo -e "${BOLD}${GREEN}"
    echo "  ============================================"
    echo "  AIOPS v6.0.0 — READY"
    echo "  ============================================"
    echo ""
    echo "  Open these URLs in your browser:"
    echo ""
    printf "  %-20s http://%s\n"  "OpenWebUI (Chat)"  "${AIOPS_DOMAIN}"
    printf "  %-20s http://%s\n"  "n8n (Automation)"  "${AIOPS_DOMAIN}/n8n"
    printf "  %-20s http://%s\n"  "CrewAI Studio"     "${AIOPS_DOMAIN}/agents"
    printf "  %-20s http://%s\n"  "Qdrant UI"         "localhost:${AIOPS_PORT_QDRANT}"
    printf "  %-20s http://%s\n"  "Ollama API"        "localhost:${AIOPS_PORT_OLLAMA}"

    # Show addon URLs if installed
    pm2 list 2>/dev/null | grep -q twenty    && printf "  %-20s http://%s\n" "Twenty CRM"    "localhost:${AIOPS_PORT_TWENTY}"
    pm2 list 2>/dev/null | grep -q listmonk  && printf "  %-20s http://%s\n" "Listmonk"      "localhost:${AIOPS_PORT_LISTMONK}"
    pm2 list 2>/dev/null | grep -q mautic    && printf "  %-20s http://%s\n" "Mautic"        "localhost:${AIOPS_PORT_MAUTIC}"
    pm2 list 2>/dev/null | grep -q langfuse  && printf "  %-20s http://%s\n" "Langfuse"      "localhost:${AIOPS_PORT_LANGFUSE}"
    pm2 list 2>/dev/null | grep -q chatwoot  && printf "  %-20s http://%s\n" "Chatwoot"      "localhost:${AIOPS_PORT_CHATWOOT}"
    pm2 list 2>/dev/null | grep -q calcom    && printf "  %-20s http://%s\n" "Cal.com"       "localhost:${AIOPS_PORT_CALCOM}"
    command -v netdata &>/dev/null           && printf "  %-20s http://%s\n" "Netdata"       "localhost:${AIOPS_PORT_NETDATA}"

    echo ""
    echo "  ============================================"
    echo -e "${NC}"

    # Report any failures
    if [ "${#INSTALL_FAILURES[@]}" -gt 0 ]; then
        echo -e "${YELLOW}  The following items had issues (everything else is working):${NC}"
        for f in "${INSTALL_FAILURES[@]}"; do
            echo -e "  ${YELLOW}  - $f${NC}"
        done
        echo -e "${YELLOW}  See $LOG_FILE for details.${NC}"
        echo ""
    fi

    echo -e "  ${CYAN}To pull an AI model:   ollama pull qwen3:4b${NC}"
    echo -e "  ${CYAN}To check services:     ai-status${NC}"
    echo -e "  ${CYAN}To see URLs again:     ai-urls${NC}"
    echo ""
    echo -e "  ${BOLD}Reload your terminal:  source ~/.bashrc${NC}"
    echo ""
    echo -e "${BOLD}${CYAN}  Quantocos AI Labs — Build with intelligence. Operate with precision.${NC}"
    echo ""
}

# ============================================================
# MAIN
# ============================================================
main() {
    show_banner
    detect_os

    select_mode
    setup_domain
    setup_streamlit_email
    write_config
    preflight

    mkdir -p "$SCRIPTS_DIR" "$AGENTS_DIR" "$VENVS_DIR"

    if [[ "$INSTALL_MODE" == "core" || "$INSTALL_MODE" == "full" ]]; then
        install_homebrew        # Mac only, no-op on Linux
        install_system_deps
        install_node
        install_ollama
        install_qdrant
        install_openwebui
        install_n8n
        install_crewai
        install_playwright
        install_optional_tools
        setup_mdns
        install_caddy           # Last — after all services verified
        setup_pm2_startup
        setup_aliases
    fi

    if [[ "$INSTALL_MODE" == "addons" || "$INSTALL_MODE" == "full" ]]; then
        run_addons_menu
    fi

    print_summary
}

main "$@"
