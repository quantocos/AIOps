# AIOPS — Local AI Operations Server

```
   ____  _   _   _    _   _ _____ ___   ____  ___  ____
  / __ \| | | | / \  | \ | |_   _/ _ \ / ___|/ _ \/ ___|
 | |  | | | | |/ _ \ |  \| | | || | | | |   | | | \___ \
 | |__| | |_| / ___ \| |\  | | || |_| | |___| |_| |___) |
  \___\_\\___/_/   \_\_| \_| |_| \___/ \____|\___/|____/

  Local AI Operations Server  ·  Quantocos AI Labs  ·  v5.3.0
```

A single-command installer that turns any Ubuntu machine or WSL2 environment into a fully operational local AI stack. Chat UI, workflow automation, vector database, agent framework, and optional GTM tooling — all running on your own hardware with no Docker and no cloud dependency.

All configuration lives in one file. All ports are changeable. Works on any username, any machine, any network.

---

## Quick Start

### Linux / WSL2

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/quantocos/AIOps/main/aiops.sh)
```

### Windows (fresh machine)

1. Download [`aiops-windows.bat`](./aiops-windows.bat)
2. Right-click → **Run as administrator**
3. Installs WSL2 + Ubuntu 24.04, configures `.wslconfig`, sets up port forwarding, then launches `aiops.sh` inside Ubuntu automatically

---

## What Gets Installed

### Core Stack — Part 1 (automatic)

| Service | Version | Default Port | Purpose |
|---|---|---|---|
| [Ollama](https://ollama.com) | latest | 11434 | Local LLM inference |
| [OpenWebUI](https://openwebui.com) | 0.8.10 | 8080 | Chat UI → Ollama |
| [n8n](https://n8n.io) | latest | 5678 | Workflow automation |
| [Qdrant](https://qdrant.tech) | v1.17.0 | 6333 | Vector database + dashboard |
| [CrewAI Studio](https://github.com/strnad/CrewAI-Studio) | latest | 8501 | Visual agent builder |
| [PM2](https://pm2.keymetrics.io) | latest | — | Process manager |
| [Caddy](https://caddyserver.com) | v2.11+ | 80 | Reverse proxy + LAN routing |
| [Avahi](https://avahi.org) | — | — | mDNS `.local` hostname on LAN |
| pnpm | latest | — | Required for monorepo addons |

**Python venvs (isolated per tool):** CrewAI 1.10.1 · Aider 0.86.2 · Open Interpreter 0.4.3 · Scrapy · Playwright

All default ports are defined in `~/aiops-server/aiops.conf` and can be changed without reinstalling.

---

### Addons — Part 2 (interactive menu)

| Key | Service | Default Port | Purpose |
|---|---|---|---|
| `d` | Shared deps | — | PostgreSQL · Redis · Firecrawl venv |
| `1` | [Twenty CRM](https://twenty.com) | 3000 | Lead and deal management |
| `2` | [Listmonk](https://listmonk.app) | 9000 | Email campaigns (single binary) |
| `3` | [OpenFang](https://openfang.sh) | — | AI agent Hands (Lead · Browser · Researcher · Twitter) |
| `4` | [Mautic](https://mautic.org) | 8100 | Full marketing automation |
| `5` | [Chatwoot](https://chatwoot.com) | 3100 | Unified inbox |
| `6` | [Cal.com](https://cal.com) | 3002 | Booking and scheduling |
| `7` | htop + nvtop | — | CPU and GPU/VRAM monitoring |
| `8` | [Netdata](https://netdata.cloud) | 19999 | Full system dashboard |
| `a` | Core GTM bundle | — | `d + 1 + 2 + 3` |
| `b` | Full GTM bundle | — | `d + 1 + 2 + 3 + 4 + 5 + 6` |
| `m` | All monitors | — | `7 + 8` |

Multiple addons can be installed in one step by space-separating choices: `d 1 2 3`

---

## Requirements

### Linux / WSL2

| | Minimum | Recommended |
|---|---|---|
| **OS** | Ubuntu 22.04 | Ubuntu 24.04 LTS |
| **RAM** | 8GB | 16GB+ |
| **Disk** | 20GB free | 100GB free |
| **GPU** | None (CPU inference) | NVIDIA with 8GB+ VRAM |

### Windows (for `aiops-windows.bat`)

- Windows 10 Build 19041+ or Windows 11
- Virtualisation enabled in BIOS (Intel VT-x / AMD-V)
- Administrator rights

---

## Configuration

All runtime settings are stored in a single file generated at install time:

```
~/aiops-server/aiops.conf
```

### What it contains

```bash
AIOPS_DOMAIN="myserver.local"    # your chosen .local hostname

AIOPS_PORT_OPENWEBUI=8080        # change any port here
AIOPS_PORT_N8N=5678
AIOPS_PORT_QDRANT=6333
AIOPS_PORT_CREWAI=8501
# ... all service ports

AIOPS_SCRIPTS_DIR="~/scripts"
AIOPS_VENVS_DIR="~/.venvs"
AIOPS_QDRANT_DIR="~/qdrant-data"
```

### Changing ports or domain

```bash
ai-config          # opens aiops.conf in nano
# edit the values
pm2 restart all    # launchers re-read config on next start
```

No reinstall needed. Every launcher sources this file at runtime — nothing is baked into script text.

---

## Models

Pull models after install based on available VRAM:

```bash
# Embeddings — pull this regardless of GPU
ollama pull nomic-embed-text

# 4–6GB VRAM or CPU-only
ollama pull qwen3:4b             # fast general chat
ollama pull qwen2.5:7b           # content, email, general
ollama pull qwen2.5-coder:7b     # coding
ollama pull deepseek-r1:8b       # reasoning
ollama pull llama3.1:8b          # agent tool use

# 10GB+ VRAM
ollama pull qwen2.5:14b
ollama pull qwen2.5-coder:14b
```

List available models: `ollama list`

---

## Shell Commands

After `source ~/.bashrc`:

```bash
# Service management
ai-status                # PM2 process list
ai-start                 # resurrect all saved processes
ai-stop                  # stop all
ai-restart               # restart all
ai-logs                  # live log tailing
ai-urls                  # print current service URLs (resolved at runtime)
ai-config                # edit ~/aiops-server/aiops.conf
aiops-caddy-regen        # regenerate Caddyfile after port changes

# AI tools
aider                    # code assistant
crew <script.py>         # run a CrewAI crew
interpreter              # Open Interpreter session
scrape <script.py>       # Scrapy runner
automate <script.py>     # Playwright runner

# Chat
chat                     # ollama run qwen3:4b
chat-coder               # ollama run qwen2.5-coder:7b
chat-reason              # ollama run deepseek-r1:8b
models                   # ollama list
```

---

## Directory Structure

```
~/
├── aiops-server/
│   ├── aiops.conf           # single source of truth for all config
│   ├── install.log
│   └── addons.log
├── agents/
│   ├── crews/               # CrewAI scripts
│   ├── tasks/
│   ├── tools/
│   ├── outputs/
│   └── configs/
├── scripts/
│   ├── run-openwebui.sh     # all launchers source aiops.conf at runtime
│   ├── run-n8n.sh
│   ├── run-qdrant.sh
│   ├── run-crewai-studio.sh
│   ├── run-aider.sh
│   ├── run-crew.sh
│   ├── run-interpreter.sh
│   ├── run-scrapy.sh
│   └── run-playwright.sh
├── qdrant-data/
│   ├── static/              # Qdrant web UI
│   └── storage/             # vector data
├── .venvs/
│   ├── crewai/
│   ├── aider/
│   ├── interpreter/
│   ├── scrapy/
│   └── playwright/
└── CrewAI-Studio/
```

---

## Architecture

### Routing

Caddy listens on `:80` and routes by path prefix. Every service runs on its own port — no subpath proxying for WebSocket-heavy applications.

```
Browser / LAN device
        │
   Caddy :80
        │
   /n8n*     → strip /n8n    → :PORT_N8N      (WebSocket: Connection "Upgrade")
   /agents*  → strip /agents → :PORT_CREWAI   (WebSocket: Connection "Upgrade")
   /qdrant*  → strip /qdrant → :PORT_QDRANT   (REST API only via Caddy)
   /monitor* → strip         → :PORT_NETDATA
   /ollama*  → strip         → :PORT_OLLAMA
   /*                        → :PORT_OPENWEBUI

   Direct port access (bypass Caddy):
   :PORT_QDRANT    → Qdrant UI + API (SPA served at root)
   :PORT_OLLAMA    → Ollama API
   :PORT_TWENTY    → Twenty CRM
   :PORT_LISTMONK  → Listmonk
   :PORT_MAUTIC    → Mautic
   :PORT_CHATWOOT  → Chatwoot
   :PORT_CALCOM    → Cal.com
   :PORT_NETDATA   → Netdata
```

All `PORT_*` values come from `aiops.conf`. After changing ports, run `aiops-caddy-regen` to regenerate the Caddyfile.

### WebSocket

Caddy uses `Connection "Upgrade"` as a literal string for all WebSocket-capable routes. The `{http.headers.Connection}` placeholder does not reliably forward upgrade requests and causes white screens on n8n and Streamlit.

### Streamlit (CrewAI Studio)

Launched with `--server.baseUrlPath /agents` so Streamlit generates WebSocket URLs at `/agents/_stcore/stream`. Caddy strips the `/agents` prefix before proxying, so Streamlit sees requests at its own root.

### Config-file model

No IPs, domain names, or usernames are baked into launcher scripts. Every launcher does:

```bash
source ~/aiops-server/aiops.conf
exec service --port ${AIOPS_PORT_SERVICE}
```

IP is never stored anywhere — it is discovered at display time via `ip route get 1`. The stack works correctly after reboots, network changes, and on any machine regardless of username or DHCP assignment.

---

## Troubleshooting

### Services not starting

```bash
ai-status                         # check which processes are errored
pm2 logs <service> --lines 50     # read the actual error
```

### White screen on n8n or CrewAI Studio

Check Caddy and restart:

```bash
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl restart caddy
pm2 restart n8n crewai-studio
```

If you changed ports in `aiops.conf` without regenerating the Caddyfile:

```bash
aiops-caddy-regen
```

### OpenWebUI not starting

```bash
pm2 logs openwebui --lines 30
# Binary missing — reinstall:
pip install open-webui==0.8.10 --break-system-packages
pm2 restart openwebui
```

### Ollama not responding

```bash
sudo systemctl status ollama
sudo systemctl restart ollama
curl http://localhost:11434/api/tags
```

### Port conflict

```bash
sudo fuser -k <PORT>/tcp    # free the port
pm2 restart <service>
# Or change the port in aiops.conf and restart
```

### Twenty CRM or Cal.com install errors

Both are pnpm monorepos. If you see `ERESOLVE` or `workspace:*` errors:

```bash
cd ~/twenty && pnpm install && pm2 restart twenty
cd ~/calcom  && pnpm install && pm2 restart calcom
```

### Chatwoot — missing gems

```bash
cd ~/chatwoot
RUBY_MINOR=$(ruby -e 'puts RUBY_VERSION.split(".")[0..1].join(".")')
export PATH="$HOME/.gem/ruby/${RUBY_MINOR}.0/bin:$PATH"
gem install bundler --user-install
bundle install
pm2 restart chatwoot chatwoot-worker
```

### WSL2 memory pressure

Edit `%USERPROFILE%\.wslconfig` on Windows:

```ini
[wsl2]
memory=16GB
processors=8
swap=8GB
```

Then from PowerShell: `wsl --shutdown`, reopen Ubuntu.

---

## Version History

### v5.3.0 — Current
- **Architecture:** Config-file model — all ports, domain, and paths live in `~/aiops-server/aiops.conf`; every launcher sources it at runtime; nothing hardcoded into script text
- **Added:** `ai-config`, `ai-urls`, `aiops-caddy-regen` aliases
- **Added:** `write_caddyfile()` callable standalone to regenerate Caddy config after port changes
- **Fixed:** IP never stored; discovered at runtime via `ip route get 1`

### v5.2.0
- **Fixed:** OpenWebUI binary discovery fully runtime — `find_owu()` function in launcher searches all known pip locations; no install-time path resolution

### v5.1.0
- **Fixed:** Per-port architecture — WebSocket apps no longer white-screened by subpath proxy
- **Fixed:** n8n, CrewAI Studio — `Connection "Upgrade"` literal + correct strip_prefix
- **Fixed:** Qdrant UI — SPA served at root on its own port
- **Fixed:** Twenty CRM / Cal.com — `pnpm install` (both are pnpm monorepos; npm fails)
- **Fixed:** Chatwoot — `gem install bundler --user-install` for system Ruby on Ubuntu 24.04
- **Fixed:** OpenFang — PATH exported in-session so hand activation runs without shell reload
- **Fixed:** Mautic — PHP routes through `public/index.php` Symfony front controller
- **Added:** pnpm to core stack; `aiops-windows.bat` Windows bootstrap

### v5.0.0
- Initial release — core stack + GTM addon suite

---

## License

MIT — see [LICENSE](./LICENSE)

---

**Quantocos AI Labs**  
*"Build with intelligence. Operate with precision."*
