#!/bin/bash
# ============================================================
# AIOPS-TOOLS.SH -- Optional Tools Installer
# Run AFTER aiops.sh is complete and WSL has been restarted
# Compatible: WSL2 Ubuntu 24.04
# Quantocos AI Labs -- v1.0.0
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
SCRIPTS_DIR="$HOME/scripts"
VENVS_DIR="$HOME/.venvs"
AIOPS_LOG="$HOME/aiops-server/install.log"
TOOLS_LOG="$HOME/aiops-server/tools-install.log"

# ── Runtime vars ─────────────────────────────────────────────
LOCAL_DOMAIN=""

# ── Helpers ──────────────────────────────────────────────────
log()     { echo -e "${GREEN}[OK]${NC} $1" | tee -a "$TOOLS_LOG"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1" | tee -a "$TOOLS_LOG"; }
error()   { echo -e "${RED}[X]${NC} $1" | tee -a "$TOOLS_LOG"; }
info()    { echo -e "${CYAN}[>]${NC} $1" | tee -a "$TOOLS_LOG"; }
section() { echo -e "\n${BOLD}${BLUE}== $1 ==${NC}\n" | tee -a "$TOOLS_LOG"; }

confirm() {
    read -rp "$(echo -e "${YELLOW}$1 [y/N]: ${NC}")" r
    [[ "$r" =~ ^[Yy]$ ]]
}

banner() {
cat << 'BANNER'
   _   ___ ___  ___  ___ 
  /_\ |_ _/ _ \| _ \/ __|
 / _ \ | | (_) |  _/\__ \
/_/ \_\___\___/|_|  |___/

  Optional Tools Installer
  Quantocos AI Labs -- v1.0.0

BANNER
}

# ── Preflight ─────────────────────────────────────────────────
preflight() {
    # Check aiops.sh has been run
    if [ ! -d "$SCRIPTS_DIR" ]; then
        echo -e "${RED}[X] Run aiops.sh first before running this script.${NC}"
        exit 1
    fi

    # Check PM2 is available
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    if ! command -v pm2 &>/dev/null; then
        echo -e "${RED}[X] PM2 not found. Run aiops.sh first.${NC}"
        exit 1
    fi

    # Get domain
    echo ""
    echo -e "${CYAN}Enter the .local domain you set in aiops.sh (e.g. myrig)${NC}"
    read -rp "$(echo -e "${YELLOW}Domain name (without .local, Enter for 'aiops'): ${NC}")" domain_input
    if [ -z "$domain_input" ]; then
        LOCAL_DOMAIN="aiops.local"
    else
        LOCAL_DOMAIN="${domain_input%.local}.local"
    fi
    log "Domain: $LOCAL_DOMAIN"
}

# ============================================================
# DEPENDENCY LAYER (must install before tool-specific installs)
# ============================================================

install_dependencies() {
    section "Installing Shared Dependencies"

    # PostgreSQL -- required by Twenty CRM, Chatwoot, Listmonk
    if ! command -v psql &>/dev/null; then
        info "Installing PostgreSQL..."
        sudo apt-get update -qq
        sudo apt-get install -y postgresql postgresql-contrib
        sudo systemctl enable postgresql
        sudo systemctl start postgresql
        log "PostgreSQL installed"
    else
        log "PostgreSQL already installed"
    fi

    # Redis -- required by Chatwoot, Cal.com, n8n queues
    if ! command -v redis-server &>/dev/null; then
        info "Installing Redis..."
        sudo apt-get install -y redis-server
        sudo systemctl enable redis-server
        sudo systemctl start redis-server
        log "Redis installed"
    else
        log "Redis already installed"
    fi

    # Firecrawl venv -- AI web enrichment (used by multiple tools)
    if [ ! -d "$VENVS_DIR/firecrawl" ]; then
        info "Creating Firecrawl venv..."
        python3 -m venv "$VENVS_DIR/firecrawl"
        "$VENVS_DIR/firecrawl/bin/pip" install --upgrade pip -q
        "$VENVS_DIR/firecrawl/bin/pip" install firecrawl-py -q
        log "Firecrawl venv ready"
    else
        log "Firecrawl venv already exists"
    fi

    # Firecrawl launcher
    cat > "$SCRIPTS_DIR/run-firecrawl.sh" << LAUNCHEREOF
#!/bin/bash
exec "${VENVS_DIR}/firecrawl/bin/python3" "\$@"
LAUNCHEREOF
    chmod +x "$SCRIPTS_DIR/run-firecrawl.sh"

    log "Shared dependencies ready"
}

# ============================================================
# TOOL 1 -- Twenty CRM
# TypeScript CRM. No Docker. npm install.
# Port: 3000. Caddy route: /crm
# ============================================================

install_twenty_crm() {
    section "Installing Twenty CRM"

    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    TWENTY_DIR="$HOME/twenty"

    if [ ! -d "$TWENTY_DIR" ]; then
        info "Cloning Twenty CRM..."
        git clone https://github.com/twentyhq/twenty.git "$TWENTY_DIR"
        log "Twenty CRM cloned"
    else
        log "Twenty CRM already cloned"
    fi

    # Create database
    if ! sudo -u postgres psql -lqt 2>/dev/null | grep -q twenty; then
        info "Creating Twenty CRM database..."
        sudo -u postgres psql -c "CREATE USER twenty WITH PASSWORD 'twenty_password';" 2>/dev/null || true
        sudo -u postgres psql -c "CREATE DATABASE twenty OWNER twenty;" 2>/dev/null || true
        log "Database created"
    fi

    cd "$TWENTY_DIR"

    if [ ! -f ".env" ]; then
        cp .env.example .env 2>/dev/null || cat > .env << 'ENVEOF'
APP_SECRET=change_me_to_random_string_32chars
DATABASE_URL=postgresql://twenty:twenty_password@localhost:5432/twenty
FRONT_BASE_URL=http://localhost:3000
REDIS_URL=redis://localhost:6379
ENVEOF
        # Generate a real secret
        APP_SECRET=$(openssl rand -base64 24 | tr -d '=+/' | head -c 32)
        sed -i "s/change_me_to_random_string_32chars/$APP_SECRET/" .env
        log ".env configured"
    fi

    info "Installing Twenty CRM dependencies (this takes a few minutes)..."
    npm install --legacy-peer-deps -q 2>/dev/null || npm install -q

    # PM2 launcher
    TWENTY_BIN=$(which npx 2>/dev/null || echo "npx")
    cat > "$SCRIPTS_DIR/run-twenty.sh" << LAUNCHEREOF
#!/bin/bash
export NVM_DIR="\$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && \\. "\$NVM_DIR/nvm.sh"
cd "$TWENTY_DIR"
exec $TWENTY_BIN nx start
LAUNCHEREOF
    chmod +x "$SCRIPTS_DIR/run-twenty.sh"

    pm2 start "$SCRIPTS_DIR/run-twenty.sh" --name twenty 2>/dev/null || true
    pm2 save
    cd "$HOME"

    log "Twenty CRM installed"
    echo ""
    echo "  Local:  http://localhost:3000"
    echo "  LAN:    http://$LOCAL_DOMAIN/crm"
    echo "  Login:  Create account on first open"
    echo ""
}

# ============================================================
# TOOL 2 -- Listmonk
# Single Go binary. Fast. No Docker.
# Port: 9000. Caddy route: /mail
# ============================================================

install_listmonk() {
    section "Installing Listmonk"

    LISTMONK_BIN="$HOME/listmonk"
    LISTMONK_DIR="$HOME/listmonk-data"
    mkdir -p "$LISTMONK_DIR"

    if [ ! -f "$LISTMONK_BIN" ]; then
        info "Downloading Listmonk binary..."
        LISTMONK_URL=$(curl -s https://api.github.com/repos/knadh/listmonk/releases/latest \
            | grep "browser_download_url.*linux_amd64.tar.gz" \
            | cut -d'"' -f4 | head -1)

        if [ -z "$LISTMONK_URL" ]; then
            LISTMONK_URL="https://github.com/knadh/listmonk/releases/download/v4.1.0/listmonk_4.1.0_linux_amd64.tar.gz"
        fi

        curl -L "$LISTMONK_URL" -o /tmp/listmonk.tar.gz
        tar -xzf /tmp/listmonk.tar.gz -C /tmp/
        mv /tmp/listmonk "$LISTMONK_BIN" 2>/dev/null || \
            find /tmp -name "listmonk" -type f 2>/dev/null | head -1 | xargs -I{} mv {} "$LISTMONK_BIN"
        chmod +x "$LISTMONK_BIN"
        rm -f /tmp/listmonk.tar.gz
        log "Listmonk binary downloaded"
    else
        log "Listmonk binary already exists"
    fi

    # Create database
    if ! sudo -u postgres psql -lqt 2>/dev/null | grep -q listmonk; then
        sudo -u postgres psql -c "CREATE USER listmonk WITH PASSWORD 'listmonk_password';" 2>/dev/null || true
        sudo -u postgres psql -c "CREATE DATABASE listmonk OWNER listmonk;" 2>/dev/null || true
        log "Listmonk database created"
    fi

    # Generate config
    if [ ! -f "$LISTMONK_DIR/config.toml" ]; then
        cd "$LISTMONK_DIR"
        "$LISTMONK_BIN" --new-config 2>/dev/null || true

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
        fi

        # Fix db settings in generated config
        sed -i 's/user = "listmonk"/user = "listmonk"/' "$LISTMONK_DIR/config.toml" 2>/dev/null || true
        sed -i "s/password = .*/password = \"listmonk_password\"/" "$LISTMONK_DIR/config.toml" 2>/dev/null || true

        info "Running Listmonk first-time install..."
        "$LISTMONK_BIN" --config "$LISTMONK_DIR/config.toml" --install --yes 2>/dev/null || true
        cd "$HOME"
        log "Listmonk configured"
    fi

    # PM2 launcher
    cat > "$SCRIPTS_DIR/run-listmonk.sh" << LAUNCHEREOF
#!/bin/bash
exec "${LISTMONK_BIN}" --config "${LISTMONK_DIR}/config.toml"
LAUNCHEREOF
    chmod +x "$SCRIPTS_DIR/run-listmonk.sh"

    pm2 start "$SCRIPTS_DIR/run-listmonk.sh" --name listmonk 2>/dev/null || true
    pm2 save

    log "Listmonk installed"
    echo ""
    echo "  Local:  http://localhost:9000"
    echo "  LAN:    http://$LOCAL_DOMAIN/mail"
    echo "  Login:  admin / change_me_now (change immediately)"
    echo "  SMTP:   Configure in Listmonk admin > Settings > SMTP"
    echo ""
}

# ============================================================
# TOOL 3 -- OpenFang
# Autonomous agent hands: Lead, Browser, Researcher, Twitter
# ============================================================

install_openfang() {
    section "Installing OpenFang"

    warn "OpenFang is an emerging tool -- checking availability..."

    # Try official install
    if curl -fsSL --max-time 10 https://openfang.sh/install -o /tmp/openfang-install.sh 2>/dev/null; then
        bash /tmp/openfang-install.sh
        rm -f /tmp/openfang-install.sh

        if command -v openfang &>/dev/null; then
            log "OpenFang installed via official installer"
            openfang hand activate lead      2>/dev/null || true
            openfang hand activate browser   2>/dev/null || true
            openfang hand activate researcher 2>/dev/null || true
            openfang hand activate twitter   2>/dev/null || true
            log "All OpenFang Hands activated"

            echo ""
            echo "  Hands active: Lead | Browser | Researcher | Twitter"
            echo "  Config: ~/.openfang/config.yaml"
            echo "  Docs:   openfang --help"
            echo ""
        fi
    else
        warn "OpenFang installer not reachable -- installing from source or fallback"

        # Fallback: check PyPI
        if [ ! -d "$VENVS_DIR/openfang" ]; then
            python3 -m venv "$VENVS_DIR/openfang"
            "$VENVS_DIR/openfang/bin/pip" install --upgrade pip -q
            if "$VENVS_DIR/openfang/bin/pip" install openfang -q 2>/dev/null; then
                log "OpenFang installed via pip"
            else
                warn "OpenFang not yet available via pip or official installer"
                warn "Check https://github.com/openfang for updates"
                warn "Once available, install with: pip install openfang"
                return
            fi
        fi

        cat > "$SCRIPTS_DIR/run-openfang.sh" << LAUNCHEREOF
#!/bin/bash
exec "${VENVS_DIR}/openfang/bin/openfang" "\$@"
LAUNCHEREOF
        chmod +x "$SCRIPTS_DIR/run-openfang.sh"
    fi
}

# ============================================================
# TOOL 4 -- Mautic
# PHP marketing automation. Requires PHP + MySQL/MariaDB.
# Port: 8100. Caddy route: /mautic
# ============================================================

install_mautic() {
    section "Installing Mautic"

    warn "Mautic requires PHP 8.1 + MariaDB -- installing dependencies..."

    # PHP
    if ! command -v php &>/dev/null; then
        sudo apt-get install -y php8.1 php8.1-cli php8.1-fpm php8.1-mysql \
            php8.1-xml php8.1-mbstring php8.1-curl php8.1-zip php8.1-gd \
            php8.1-intl php8.1-bcmath php8.1-imap composer -q
        log "PHP 8.1 installed"
    else
        log "PHP already installed: $(php -v | head -1)"
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
        log "MariaDB installed and configured"
    else
        log "MariaDB already installed"
    fi

    MAUTIC_DIR="$HOME/mautic"

    if [ ! -d "$MAUTIC_DIR" ]; then
        info "Installing Mautic via Composer..."
        composer create-project mautic/recommended-project "$MAUTIC_DIR" --no-interaction -q 2>/dev/null || \
            composer create-project mautic/recommended-project:^5 "$MAUTIC_DIR" --no-interaction

        # Configure
        cat > "$MAUTIC_DIR/.env.local" << 'ENVEOF'
APP_URL=http://localhost:8100
DB_HOST=localhost
DB_PORT=3306
DB_NAME=mautic
DB_USER=mautic
DB_PASSWD=mautic_password
ENVEOF
        log "Mautic installed"
    else
        log "Mautic already installed"
    fi

    # PHP built-in server launcher (no nginx/apache needed)
    cat > "$SCRIPTS_DIR/run-mautic.sh" << LAUNCHEREOF
#!/bin/bash
cd "${MAUTIC_DIR}"
exec php -S 0.0.0.0:8100 -t public/
LAUNCHEREOF
    chmod +x "$SCRIPTS_DIR/run-mautic.sh"

    pm2 start "$SCRIPTS_DIR/run-mautic.sh" --name mautic 2>/dev/null || true
    pm2 save

    log "Mautic installed on port 8100"
    echo ""
    echo "  Local:  http://localhost:8100"
    echo "  Setup:  Complete wizard at first open"
    echo "  Note:   Add /mautic* route to Caddyfile for LAN access"
    echo ""
}

# ============================================================
# TOOL 5 -- Chatwoot
# Unified inbox. Ruby + PostgreSQL + Redis.
# Port: 3100. Caddy route: /inbox
# Assessing Docker risk: Ruby on WSL2 = no Docker needed
# ============================================================

install_chatwoot() {
    section "Installing Chatwoot"

    CHATWOOT_DIR="$HOME/chatwoot"
    CHATWOOT_PORT=3100

    # Ruby dependency
    if ! command -v ruby &>/dev/null; then
        info "Installing Ruby via rbenv..."
        sudo apt-get install -y rbenv ruby-build -q 2>/dev/null || true
        # Fallback to direct ruby install
        if ! command -v ruby &>/dev/null; then
            sudo apt-get install -y ruby ruby-dev -q
        fi
        log "Ruby installed: $(ruby -v)"
    else
        log "Ruby: $(ruby -v)"
    fi

    if [ ! -d "$CHATWOOT_DIR" ]; then
        info "Cloning Chatwoot..."
        git clone https://github.com/chatwoot/chatwoot.git "$CHATWOOT_DIR"
        log "Chatwoot cloned"
    else
        log "Chatwoot already cloned"
    fi

    cd "$CHATWOOT_DIR"

    # Create database
    if ! sudo -u postgres psql -lqt 2>/dev/null | grep -q chatwoot; then
        sudo -u postgres psql -c "CREATE USER chatwoot WITH PASSWORD 'chatwoot_password';" 2>/dev/null || true
        sudo -u postgres psql -c "CREATE DATABASE chatwoot OWNER chatwoot;" 2>/dev/null || true
    fi

    if [ ! -f ".env" ]; then
        cp .env.example .env
        SECRET_KEY=$(openssl rand -hex 64)
        sed -i "s|SECRET_KEY_BASE=.*|SECRET_KEY_BASE=$SECRET_KEY|" .env
        sed -i "s|DATABASE_URL=.*|DATABASE_URL=postgresql://chatwoot:chatwoot_password@localhost:5432/chatwoot|" .env
        sed -i "s|REDIS_URL=.*|REDIS_URL=redis://localhost:6379|" .env
        sed -i "s|PORT=3000|PORT=$CHATWOOT_PORT|" .env
        log ".env configured"
    fi

    info "Installing Chatwoot gems (this takes several minutes)..."
    bundle install -q 2>/dev/null || gem install bundler && bundle install -q

    info "Setting up Chatwoot database..."
    RAILS_ENV=production bundle exec rails db:chatwoot_prepare 2>/dev/null || \
        RAILS_ENV=production bundle exec rails db:migrate 2>/dev/null || true

    CHATWOOT_BIN=$(which bundle 2>/dev/null || echo "bundle")
    cat > "$SCRIPTS_DIR/run-chatwoot.sh" << LAUNCHEREOF
#!/bin/bash
cd "${CHATWOOT_DIR}"
export RAILS_ENV=production
exec $CHATWOOT_BIN exec rails server -b 0.0.0.0 -p $CHATWOOT_PORT
LAUNCHEREOF
    chmod +x "$SCRIPTS_DIR/run-chatwoot.sh"

    # Sidekiq worker for background jobs
    cat > "$SCRIPTS_DIR/run-chatwoot-worker.sh" << LAUNCHEREOF
#!/bin/bash
cd "${CHATWOOT_DIR}"
export RAILS_ENV=production
exec $CHATWOOT_BIN exec sidekiq
LAUNCHEREOF
    chmod +x "$SCRIPTS_DIR/run-chatwoot-worker.sh"

    pm2 start "$SCRIPTS_DIR/run-chatwoot.sh"        --name chatwoot
    pm2 start "$SCRIPTS_DIR/run-chatwoot-worker.sh" --name chatwoot-worker
    pm2 save
    cd "$HOME"

    log "Chatwoot installed"
    echo ""
    echo "  Local:  http://localhost:$CHATWOOT_PORT"
    echo "  LAN:    http://$LOCAL_DOMAIN/inbox"
    echo "  Setup:  Register at first open"
    echo ""
}

# ============================================================
# TOOL 6 -- Cal.com
# TypeScript booking system. npm install.
# Port: 3002. Caddy route: /cal
# ============================================================

install_calcom() {
    section "Installing Cal.com"

    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    CALCOM_DIR="$HOME/calcom"
    CALCOM_PORT=3002

    if [ ! -d "$CALCOM_DIR" ]; then
        info "Cloning Cal.com..."
        git clone https://github.com/calcom/cal.com.git "$CALCOM_DIR"
        log "Cal.com cloned"
    else
        log "Cal.com already cloned"
    fi

    cd "$CALCOM_DIR"

    # Create database
    if ! sudo -u postgres psql -lqt 2>/dev/null | grep -q calcom; then
        sudo -u postgres psql -c "CREATE USER calcom WITH PASSWORD 'calcom_password';" 2>/dev/null || true
        sudo -u postgres psql -c "CREATE DATABASE calcom OWNER calcom;" 2>/dev/null || true
    fi

    if [ ! -f ".env" ]; then
        cp .env.example .env 2>/dev/null || touch .env
        NEXTAUTH_SECRET=$(openssl rand -base64 32)
        CALCOM_LICENSE=$(openssl rand -hex 16)
        cat >> .env << ENVEOF
DATABASE_URL=postgresql://calcom:calcom_password@localhost:5432/calcom
NEXTAUTH_SECRET=$NEXTAUTH_SECRET
NEXTAUTH_URL=http://localhost:$CALCOM_PORT
NEXT_PUBLIC_APP_URL=http://localhost:$CALCOM_PORT
CALCOM_LICENSE_KEY=$CALCOM_LICENSE
PORT=$CALCOM_PORT
ENVEOF
        log ".env configured"
    fi

    info "Installing Cal.com dependencies..."
    npm install --legacy-peer-deps -q 2>/dev/null || npm install -q

    info "Running Cal.com database setup..."
    npx prisma generate 2>/dev/null || true
    npx prisma db push 2>/dev/null || true

    NPXBIN=$(which npx 2>/dev/null || echo "npx")
    cat > "$SCRIPTS_DIR/run-calcom.sh" << LAUNCHEREOF
#!/bin/bash
export NVM_DIR="\$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && \\. "\$NVM_DIR/nvm.sh"
cd "${CALCOM_DIR}"
exec $NPXBIN next start -p $CALCOM_PORT
LAUNCHEREOF
    chmod +x "$SCRIPTS_DIR/run-calcom.sh"

    pm2 start "$SCRIPTS_DIR/run-calcom.sh" --name calcom 2>/dev/null || true
    pm2 save
    cd "$HOME"

    log "Cal.com installed"
    echo ""
    echo "  Local:  http://localhost:$CALCOM_PORT"
    echo "  LAN:    http://$LOCAL_DOMAIN/cal"
    echo "  Setup:  Register at first open"
    echo ""
}

# ============================================================
# UPDATE CADDYFILE with new tool routes
# ============================================================

update_caddy() {
    local tool=$1
    local port=$2
    local path=$3

    # Check if route already exists
    if grep -q "handle /${path}" /etc/caddy/Caddyfile 2>/dev/null; then
        log "Caddy route /$path already exists"
        return
    fi

    # Add before the catch-all /* route
    sudo sed -i "/# OpenWebUI -- default catch-all/i\\    # $tool\\n    handle /${path}* {\\n        reverse_proxy localhost:${port} {\\n            header_up Host {host}\\n        }\\n    }\\n" \
        /etc/caddy/Caddyfile 2>/dev/null || true

    sudo caddy validate --config /etc/caddy/Caddyfile 2>/dev/null && \
        sudo systemctl reload caddy 2>/dev/null || true

    log "Caddy updated: /$path -> :$port"
}

# ============================================================
# MENU
# ============================================================

show_menu() {
    echo ""
    echo -e "${BOLD}Select tools to install:${NC}"
    echo ""
    echo "  DEPENDENCIES (install these first if installing any tool below)"
    echo "  [d] Install shared dependencies (PostgreSQL, Redis, Firecrawl)"
    echo ""
    echo "  CRM & OUTREACH"
    echo "  [1] Twenty CRM          — Lead + deal management          :3000  /crm"
    echo "  [2] Listmonk            — Email campaigns, single binary  :9000  /mail"
    echo "  [3] OpenFang            — AI agent hands (Lead/Browser/X)"
    echo "  [4] Mautic              — Full nurture sequences (PHP)    :8100  /mautic"
    echo ""
    echo "  INBOX & BOOKING"
    echo "  [5] Chatwoot            — Unified inbox (email/WA/TG)    :3100  /inbox"
    echo "  [6] Cal.com             — Discovery call booking         :3002  /cal"
    echo ""
    echo "  BUNDLES"
    echo "  [a] Core GTM stack      — Dependencies + 1 + 2 + 3"
    echo "  [b] Full stack          — Everything above"
    echo ""
    echo "  [q] Quit"
    echo ""
    read -rp "$(echo -e "${YELLOW}Enter choice(s), space-separated (e.g. d 1 2): ${NC}")" -a CHOICES
}

# ============================================================
# MAIN
# ============================================================

main() {
    mkdir -p "$HOME/aiops-server"
    touch "$TOOLS_LOG"

    clear
    banner

    echo -e "${BOLD}AIOPS Optional Tools Installer${NC}"
    echo ""
    echo -e "${YELLOW}Prerequisite: aiops.sh must be complete and WSL restarted.${NC}"
    echo ""

    preflight

    show_menu

    for choice in "${CHOICES[@]}"; do
        case "$choice" in
            d|D) install_dependencies ;;
            1)   install_twenty_crm ;;
            2)   install_listmonk ;;
            3)   install_openfang ;;
            4)   install_mautic ;;
            5)   install_chatwoot ;;
            6)   install_calcom ;;
            a|A)
                install_dependencies
                install_twenty_crm
                install_listmonk
                install_openfang
                ;;
            b|B)
                install_dependencies
                install_twenty_crm
                install_listmonk
                install_openfang
                install_mautic
                install_chatwoot
                install_calcom
                ;;
            q|Q) echo "Exiting."; exit 0 ;;
            *)   echo -e "${YELLOW}[!] Unknown option: $choice${NC}" ;;
        esac
    done

    echo ""
    section "Installation Summary"
    pm2 status
    echo ""
    echo -e "${CYAN}All tools log: $TOOLS_LOG${NC}"
    echo ""
    echo -e "${BOLD}${YELLOW}Run aiops-windows.bat again to add new ports to Windows port forwarding.${NC}"
    echo ""
}

main "$@"
