#!/bin/bash
# ============================================================
# AIOPS.SH — Local AI Operations Server Setup
# Compatible: WSL2 Ubuntu 22.04 / 24.04
# Author: Quantocos
# Version: 1.0.0
# Usage: bash aiops.sh
# ============================================================

set -e  # Exit on any error

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
LOG_FILE="$AIOPS_HOME/install.log"

# ── Versions (pinned to avoid conflicts) ────────────────────
NODE_VERSION="22"
PYTHON_MIN="3.10"
OPEN_WEBUI_VERSION="0.8.10"
QDRANT_VERSION="v1.17.0"
QDRANT_WEBUI_VERSION="v0.2.7"
CREWAI_VERSION="1.10.1"
CREWAI_TOOLS_VERSION="1.10.1"
OPEN_INTERPRETER_VERSION="0.4.3"
AIDER_VERSION="0.86.2"

# ── Ubuntu Version Detection ─────────────────────────────────
# Detected in preflight(), used globally by pip installs
# Ubuntu 24.04+ uses externally-managed Python — requires --break-system-packages
# Ubuntu 22.04 and below — flag does not exist, omit it
UBUNTU_VERSION="0"
PIP_FLAGS=""

# ── Helpers ──────────────────────────────────────────────────
log()     { echo -e "${GREEN}[✓]${NC} $1" | tee -a "$LOG_FILE"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1" | tee -a "$LOG_FILE"; }
error()   { echo -e "${RED}[✗]${NC} $1" | tee -a "$LOG_FILE"; exit 1; }
info()    { echo -e "${CYAN}[→]${NC} $1" | tee -a "$LOG_FILE"; }
section() { echo -e "\n${BOLD}${BLUE}══ $1 ══${NC}\n" | tee -a "$LOG_FILE"; }

banner() {
cat << 'EOF'
   _   ___ ___  ___  ___ 
  /_\ |_ _/ _ \| _ \/ __|
 / _ \ | | (_) |  _/\__ \
/_/ \_\___\___/|_|  |___/

  Local AI Operations Server
  by Quantocos — v1.0.0
  WSL2 Ubuntu 22.04 / 24.04

EOF
}

confirm() {
    read -rp "$(echo -e "${YELLOW}$1 [y/N]:${NC} ")" response
    [[ "$response" =~ ^[Yy]$ ]]
}

# ── Preflight Checks ─────────────────────────────────────────
preflight() {
    section "Preflight Checks"

    # OS Check
    if ! grep -qi "ubuntu" /etc/os-release 2>/dev/null; then
        error "This script requires Ubuntu. Detected: $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '\"')"
    fi

    # Ubuntu version detection — controls pip behaviour globally
    UBUNTU_VERSION=$(lsb_release -rs 2>/dev/null || grep VERSION_ID /etc/os-release | cut -d= -f2 | tr -d '"')

    case "$UBUNTU_VERSION" in
        24.04)
            log "OS: Ubuntu 24.04 LTS — fully supported"
            PIP_FLAGS="--break-system-packages"
            ;;
        22.04)
            log "OS: Ubuntu 22.04 LTS — supported"
            PIP_FLAGS=""
            ;;
        20.04)
            warn "OS: Ubuntu 20.04 LTS — Python 3.8 default. Some packages may fail."
            warn "Recommend upgrading to Ubuntu 22.04 or 24.04 for best results."
            PIP_FLAGS=""
            ;;
        *)
            warn "OS: Ubuntu $UBUNTU_VERSION — untested. Proceeding but errors may occur."
            warn "Tested and supported: Ubuntu 22.04 LTS and Ubuntu 24.04 LTS"
            # Assume 24.04+ behaviour if version is higher
            if awk "BEGIN {exit !($UBUNTU_VERSION >= 24.04)}"; then
                PIP_FLAGS="--break-system-packages"
            else
                PIP_FLAGS=""
            fi
            ;;
    esac

    # WSL Check
    if grep -qi "microsoft" /proc/version 2>/dev/null; then
        log "Environment: WSL2 detected"
    else
        warn "Not running in WSL — script optimised for WSL2 but continuing"
    fi

    # Internet Check
    if ! curl -s --max-time 5 https://google.com > /dev/null; then
        error "No internet connection. Please check your network."
    fi
    log "Internet: Connected"

    # Disk space (need at least 20GB)
    AVAILABLE=$(df ~ | awk 'NR==2 {print $4}')
    if [ "$AVAILABLE" -lt 20971520 ]; then
        warn "Low disk space: $(df -h ~ | awk 'NR==2 {print $4}') available. Recommend 20GB+"
    else
        log "Disk space: $(df -h ~ | awk 'NR==2 {print $4}') available"
    fi

    # RAM check
    TOTAL_RAM=$(free -g | awk 'NR==2 {print $2}')
    if [ "$TOTAL_RAM" -lt 16 ]; then
        warn "RAM: ${TOTAL_RAM}GB detected. 16GB+ recommended for running 14B models"
    else
        log "RAM: ${TOTAL_RAM}GB detected"
    fi
}

# ── Directory Structure ───────────────────────────────────────
setup_dirs() {
    section "Creating Directory Structure"

    mkdir -p "$AIOPS_HOME"
    mkdir -p "$LOG_FILE" 2>/dev/null || true
    : > "$LOG_FILE"

    mkdir -p "$SCRIPTS_DIR"
    mkdir -p "$AGENTS_DIR"/{crews,tasks,tools,outputs,configs}
    mkdir -p "$VENVS_DIR"
    mkdir -p "$QDRANT_DIR"/{config,static,storage,snapshots}

    log "Directory structure created"
    info "AIOPS Home:  $AIOPS_HOME"
    info "Scripts:     $SCRIPTS_DIR"
    info "Agents:      $AGENTS_DIR"
    info "Venvs:       $VENVS_DIR"
    info "Qdrant Data: $QDRANT_DIR"
}

# ── System Dependencies ───────────────────────────────────────
install_system_deps() {
    section "Installing System Dependencies"

    sudo apt-get update -qq
    sudo apt-get install -y \
        curl wget git unzip \
        python3 python3-pip python3-venv \
        build-essential \
        ffmpeg \
        lsof \
        ca-certificates gnupg \
        2>/dev/null

    log "System dependencies installed"
}

# ── NVM + Node 22 ─────────────────────────────────────────────
install_node() {
    section "Installing Node.js $NODE_VERSION via NVM"

    if command -v node &>/dev/null; then
        CURRENT_NODE=$(node -v | cut -d. -f1 | tr -d 'v')
        if [ "$CURRENT_NODE" -ge "$NODE_VERSION" ]; then
            log "Node.js $(node -v) already installed — skipping"
            return
        fi
    fi

    # Install NVM
    info "Installing NVM..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.2/install.sh | bash

    # Load NVM
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    # Install Node
    nvm install "$NODE_VERSION"
    nvm alias default "$NODE_VERSION"

    log "Node.js $(node -v) installed via NVM"
    log "NPM $(npm -v) ready"
}

# ── PM2 ───────────────────────────────────────────────────────
install_pm2() {
    section "Installing PM2 Process Manager"

    # Load NVM first
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    if command -v pm2 &>/dev/null; then
        log "PM2 $(pm2 -v) already installed — skipping"
        return
    fi

    npm install -g pm2
    log "PM2 $(pm2 -v) installed"
}

# ── Ollama ────────────────────────────────────────────────────
install_ollama() {
    section "Installing Ollama"

    if command -v ollama &>/dev/null; then
        log "Ollama $(ollama -v 2>/dev/null | head -1) already installed — skipping"
        return
    fi

    curl -fsSL https://ollama.com/install.sh | sh
    log "Ollama installed"

    # Start Ollama service
    ollama serve &>/dev/null &
    sleep 3
    log "Ollama service started"

    warn "NOTE: Model pulling is intentionally excluded from this script"
    warn "Pull models manually based on your VRAM:"
    echo ""
    echo "  Recommended stack (8GB VRAM):"
    echo "  ollama pull qwen3:4b           # fast chat"
    echo "  ollama pull qwen2.5:14b        # content/general"
    echo "  ollama pull qwen2.5-coder:14b  # coding"
    echo "  ollama pull deepseek-r1:8b     # reasoning"
    echo "  ollama pull llama3.1:8b        # agents/tools"
    echo "  ollama pull nomic-embed-text   # RAG embeddings"
    echo ""
}

# ── n8n ───────────────────────────────────────────────────────
install_n8n() {
    section "Installing n8n"

    # Load NVM
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    if command -v n8n &>/dev/null; then
        log "n8n $(n8n --version 2>/dev/null) already installed — skipping"
        return
    fi

    npm install -g n8n
    log "n8n installed"
}

# ── OpenWebUI ─────────────────────────────────────────────────
install_openwebui() {
    section "Installing OpenWebUI $OPEN_WEBUI_VERSION"

    if pip show open-webui &>/dev/null 2>&1; then
        log "OpenWebUI already installed — skipping"
        return
    fi

    # Install with pinned version
    pip install "open-webui==$OPEN_WEBUI_VERSION" $PIP_FLAGS

    # Install qdrant client for OpenWebUI
    pip install qdrant-client $PIP_FLAGS

    # Ensure PATH includes local bin
    export PATH="$HOME/.local/bin:$PATH"

    log "OpenWebUI $OPEN_WEBUI_VERSION installed"
}

# ── Qdrant ────────────────────────────────────────────────────
install_qdrant() {
    section "Installing Qdrant $QDRANT_VERSION"

    QDRANT_BIN="$HOME/qdrant"

    if [ -f "$QDRANT_BIN" ]; then
        log "Qdrant binary already exists — skipping download"
    else
        info "Downloading Qdrant binary..."
        curl -L "https://github.com/qdrant/qdrant/releases/download/$QDRANT_VERSION/qdrant-x86_64-unknown-linux-gnu.tar.gz" \
            -o /tmp/qdrant.tar.gz

        tar -xzf /tmp/qdrant.tar.gz -C "$HOME"
        rm /tmp/qdrant.tar.gz
        chmod +x "$QDRANT_BIN"
        log "Qdrant binary downloaded"
    fi

    # Download Web UI
    if [ -f "$QDRANT_DIR/static/index.html" ]; then
        log "Qdrant Web UI already exists — skipping"
    else
        info "Downloading Qdrant Web UI..."
        curl -L "https://github.com/qdrant/qdrant-web-ui/releases/download/$QDRANT_WEBUI_VERSION/dist-qdrant.zip" \
            -o /tmp/qdrant-webui.zip

        sudo apt-get install -y unzip -qq
        unzip -q /tmp/qdrant-webui.zip -d /tmp/qdrant-webui-temp
        cp -r /tmp/qdrant-webui-temp/dist/. "$QDRANT_DIR/static/"
        rm -rf /tmp/qdrant-webui.zip /tmp/qdrant-webui-temp
        log "Qdrant Web UI installed"
    fi
}

# ── Python Venvs ──────────────────────────────────────────────
setup_venvs() {
    section "Setting Up Python Virtual Environments"

    # CrewAI venv
    if [ ! -d "$VENVS_DIR/crewai" ]; then
        info "Creating CrewAI venv..."
        python3 -m venv "$VENVS_DIR/crewai"
        "$VENVS_DIR/crewai/bin/pip" install --upgrade pip -q
        "$VENVS_DIR/crewai/bin/pip" install \
            "crewai==$CREWAI_VERSION" \
            "crewai-tools==$CREWAI_TOOLS_VERSION" \
            -q
        log "CrewAI $CREWAI_VERSION venv ready"
    else
        log "CrewAI venv already exists — skipping"
    fi

    # Aider venv
    if [ ! -d "$VENVS_DIR/aider" ]; then
        info "Creating Aider venv..."
        python3 -m venv "$VENVS_DIR/aider"
        "$VENVS_DIR/aider/bin/pip" install --upgrade pip -q
        "$VENVS_DIR/aider/bin/pip" install "aider-chat==$AIDER_VERSION" -q
        log "Aider $AIDER_VERSION venv ready"
    else
        log "Aider venv already exists — skipping"
    fi

    # Open Interpreter venv
    if [ ! -d "$VENVS_DIR/interpreter" ]; then
        info "Creating Open Interpreter venv..."
        python3 -m venv "$VENVS_DIR/interpreter"
        "$VENVS_DIR/interpreter/bin/pip" install --upgrade pip -q
        "$VENVS_DIR/interpreter/bin/pip" install "open-interpreter==$OPEN_INTERPRETER_VERSION" -q
        log "Open Interpreter $OPEN_INTERPRETER_VERSION venv ready"
    else
        log "Open Interpreter venv already exists — skipping"
    fi
}

# ── CrewAI Studio ─────────────────────────────────────────────
install_crewai_studio() {
    section "Installing CrewAI Studio"

    STUDIO_DIR="$HOME/CrewAI-Studio"

    if [ -d "$STUDIO_DIR" ]; then
        log "CrewAI Studio already exists — skipping clone"
    else
        git clone https://github.com/strnad/CrewAI-Studio.git "$STUDIO_DIR"
        log "CrewAI Studio cloned"
    fi

    if [ ! -d "$STUDIO_DIR/venv" ]; then
        info "Installing CrewAI Studio dependencies..."
        cd "$STUDIO_DIR"
        python3 -m venv venv
        source venv/bin/activate
        pip install --upgrade pip -q
        pip install -r requirements.txt -q
        deactivate
        cd ~
        log "CrewAI Studio dependencies installed"
    else
        log "CrewAI Studio venv already exists — skipping"
    fi
}

# ── Launcher Scripts ──────────────────────────────────────────
create_launchers() {
    section "Creating Launcher Scripts"

    # OpenWebUI launcher
    cat > "$SCRIPTS_DIR/run-openwebui.sh" << 'EOF'
#!/bin/bash
export PATH="$HOME/.local/bin:$PATH"
export VECTOR_DB=qdrant
export QDRANT_URI=http://localhost:6333
export DATA_DIR="$HOME/.local/share/open-webui"
exec open-webui serve
EOF

    # n8n launcher
    cat > "$SCRIPTS_DIR/run-n8n.sh" << 'SCRIPT'
#!/bin/bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
exec n8n start
SCRIPT

    # Qdrant launcher
    cat > "$SCRIPTS_DIR/run-qdrant.sh" << 'EOF'
#!/bin/bash
export QDRANT__SERVICE__STATIC_CONTENT_DIR="$HOME/qdrant-data/static"
cd "$HOME/qdrant-data"
exec "$HOME/qdrant"
EOF

    # CrewAI Studio launcher
    cat > "$SCRIPTS_DIR/run-crewai-studio.sh" << 'EOF'
#!/bin/bash
cd "$HOME/CrewAI-Studio"
source venv/bin/activate
exec streamlit run app/app.py --server.port 8501
EOF

    # Aider launcher
    cat > "$SCRIPTS_DIR/run-aider.sh" << 'EOF'
#!/bin/bash
source "$HOME/.venvs/aider/bin/activate"
MODEL="${1:-ollama/qwen2.5-coder:14b}"
exec aider --model "$MODEL" "${@:2}"
EOF

    # CrewAI script runner
    cat > "$SCRIPTS_DIR/run-crew.sh" << 'EOF'
#!/bin/bash
source "$HOME/.venvs/crewai/bin/activate"
exec python3 "$@"
EOF

    # Open Interpreter launcher
    cat > "$SCRIPTS_DIR/run-interpreter.sh" << 'EOF'
#!/bin/bash
source "$HOME/.venvs/interpreter/bin/activate"
MODEL="${1:-ollama/llama3.1:8b}"
exec interpreter --model "$MODEL"
EOF

    # Make all scripts executable
    chmod +x "$SCRIPTS_DIR"/*.sh

    log "Launcher scripts created in $SCRIPTS_DIR"
}

# ── Shell Aliases ─────────────────────────────────────────────
setup_aliases() {
    section "Setting Up Shell Aliases"

    # Remove old aiops block if exists
    sed -i '/# AIOPS START/,/# AIOPS END/d' ~/.bashrc

    cat >> ~/.bashrc << ALIASES

# AIOPS START
export PATH="\$HOME/.local/bin:\$PATH"
export NVM_DIR="\$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && \. "\$NVM_DIR/nvm.sh"

# AI Tools
alias aider='$SCRIPTS_DIR/run-aider.sh'
alias crew='$SCRIPTS_DIR/run-crew.sh'
alias interpreter='$SCRIPTS_DIR/run-interpreter.sh'
alias ai-status='pm2 status'
alias ai-start='pm2 resurrect'
alias ai-stop='pm2 stop all'
alias ai-logs='pm2 logs'

# Quick model chat
alias chat='ollama run qwen3:4b'
alias chat-coder='ollama run qwen2.5-coder:14b'
alias chat-reason='ollama run deepseek-r1:8b'

# PM2 auto-resurrect on terminal open
[[ -z \$(pm2 list 2>/dev/null | grep online) ]] && pm2 resurrect 2>/dev/null

# AIOPS END
ALIASES

    log "Shell aliases added to ~/.bashrc"
}

# ── PM2 Services ──────────────────────────────────────────────
setup_pm2_services() {
    section "Configuring PM2 Services"

    # Load NVM
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    # Kill any existing PM2 and start fresh
    pm2 kill 2>/dev/null || true
    rm -f ~/.pm2/dump.pm2 2>/dev/null || true
    sleep 2

    # Kill any processes holding our ports
    for PORT in 5678 8080 6333 8501; do
        sudo fuser -k ${PORT}/tcp 2>/dev/null || true
    done
    sleep 2

    # Start services
    info "Starting n8n..."
    pm2 start "$SCRIPTS_DIR/run-n8n.sh" --name n8n

    info "Starting OpenWebUI..."
    pm2 start "$SCRIPTS_DIR/run-openwebui.sh" --name openwebui

    info "Starting Qdrant..."
    pm2 start "$SCRIPTS_DIR/run-qdrant.sh" --name qdrant --cwd "$QDRANT_DIR"

    info "Starting CrewAI Studio..."
    pm2 start "$SCRIPTS_DIR/run-crewai-studio.sh" --name crewai-studio

    # Save PM2 state
    sleep 5
    pm2 save

    log "All PM2 services started and saved"
}

# ── Sample CrewAI Script ──────────────────────────────────────
create_sample_crew() {
    section "Creating Sample CrewAI Script"

    cat > "$AGENTS_DIR/crews/sample_crew.py" << 'EOF'
"""
Sample CrewAI crew — Quantocos AIOPS
Tests connection to local Ollama models
"""
from crewai import Agent, Task, Crew, LLM

# Connect to local Ollama
llm = LLM(
    model="ollama/llama3.1:8b",
    base_url="http://localhost:11434"
)

researcher = Agent(
    role="Research Analyst",
    goal="Research and summarize information accurately",
    backstory="Expert researcher with attention to detail",
    llm=llm,
    verbose=True
)

writer = Agent(
    role="Content Writer",
    goal="Write clear engaging content",
    backstory="Professional business content writer",
    llm=llm,
    verbose=True
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

crew = Crew(
    agents=[researcher, writer],
    tasks=[research_task, write_task],
    verbose=True
)

if __name__ == "__main__":
    result = crew.kickoff()
    print("\n=== OUTPUT ===")
    print(result)
EOF

    log "Sample crew script created at $AGENTS_DIR/crews/sample_crew.py"
}

# ── Final Summary ─────────────────────────────────────────────
print_summary() {
    section "Installation Complete"

    # Get local IP
    LOCAL_IP=$(ip route get 1 2>/dev/null | awk '{print $7; exit}' || echo "YOUR_IP")

    echo -e "${BOLD}${GREEN}"
    echo "  ╔═══════════════════════════════════════════╗"
    echo "  ║      AIOPS SERVER — READY                 ║"
    echo "  ╠═══════════════════════════════════════════╣"
    echo "  ║  Service         URL                      ║"
    echo "  ║  ─────────────────────────────────────    ║"
    echo "  ║  n8n             :5678                    ║"
    echo "  ║  OpenWebUI       :8080                    ║"
    echo "  ║  Qdrant          :6333                    ║"
    echo "  ║  Qdrant UI       :6333/dashboard          ║"
    echo "  ║  CrewAI Studio   :8501                    ║"
    echo "  ╠═══════════════════════════════════════════╣"
    echo "  ║  Local IP: $LOCAL_IP                      ║"
    echo "  ╚═══════════════════════════════════════════╝"
    echo -e "${NC}"

    echo -e "${BOLD}Next Steps:${NC}"
    echo "  1. Pull Ollama models: ollama pull qwen3:4b"
    echo "  2. Reload shell:       source ~/.bashrc"
    echo "  3. Check services:     ai-status"
    echo "  4. Test crew:          crew ~/agents/crews/sample_crew.py"
    echo "  5. Open browser:       http://localhost:8080"
    echo ""
    echo -e "${CYAN}Install log saved to: $LOG_FILE${NC}"
    echo ""
}

# ── Main ──────────────────────────────────────────────────────
main() {
    clear
    banner

    echo -e "${BOLD}This script will install the complete AIOPS stack:${NC}"
    echo "  • Node 22 (via NVM)    • n8n"
    echo "  • Ollama               • OpenWebUI"
    echo "  • Qdrant + Web UI      • CrewAI Studio"
    echo "  • Python venvs         • Aider, CrewAI, Interpreter"
    echo ""

    if ! confirm "Proceed with installation?"; then
        echo "Installation cancelled."
        exit 0
    fi

    preflight
    setup_dirs
    install_system_deps
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
