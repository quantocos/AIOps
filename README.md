# AIOPS — Local AI Operations Server

```
   ____  _   _   _    _   _ _____ ___   ____  ___  ____
  / __ \| | | | / \  | \ | |_   _/ _ \ / ___|/ _ \/ ___|
 | |  | | | | |/ _ \ |  \| | | || | | | |   | | | \___ \
 | |__| | |_| / ___ \| |\  | | || |_| | |___| |_| |___) |
  \___\_\\___/_/   \_\_| \_| |_| \___/ \____|\___/|____/

  Local AI Operations Server  ·  Quantocos AI Labs  ·  v5.1.0
```

**A single-command installer that turns a WSL2 machine into a fully operational local AI stack** — chat UI, workflow automation, vector database, agent framework, and optional GTM tooling. No Docker. No cloud dependencies. Everything runs on your hardware.

---

## What It Installs

### Core Stack (Part 1 — automatic)

| Service | Version | Port | Purpose |
|---|---|---|---|
| [Ollama](https://ollama.com) | latest | 11434 | Local LLM inference |
| [OpenWebUI](https://openwebui.com) | 0.8.10 | 8080 | Chat interface → Ollama |
| [n8n](https://n8n.io) | latest | 5678 | Workflow automation |
| [Qdrant](https://qdrant.tech) | v1.17.0 | 6333 | Vector database + Web UI |
| [CrewAI Studio](https://github.com/strnad/CrewAI-Studio) | latest | 8501 | Visual agent builder |
| [PM2](https://pm2.keymetrics.io) | latest | — | Process manager |
| [Caddy](https://caddyserver.com) | v2.11+ | 80 | Reverse proxy |
| [Avahi](https://avahi.org) | — | — | mDNS `.local` LAN hostname |

**Python venvs (isolated):** CrewAI 1.10.1 · Aider 0.86.2 · Open Interpreter 0.4.3 · Scrapy · Playwright

---

### Addons (Part 2 — interactive menu)

| Key | Service | Port | Purpose |
|---|---|---|---|
| `d` | Shared deps | — | PostgreSQL · Redis · Firecrawl |
| `1` | [Twenty CRM](https://twenty.com) | 3000 | Lead and deal management |
| `2` | [Listmonk](https://listmonk.app) | 9000 | Email campaigns (binary, fast) |
| `3` | [OpenFang](https://openfang.sh) | — | AI agent Hands (Lead · Browser · Researcher · Twitter) |
| `4` | [Mautic](https://mautic.org) | 8100 | Full marketing automation (PHP) |
| `5` | [Chatwoot](https://chatwoot.com) | 3100 | Unified inbox |
| `6` | [Cal.com](https://cal.com) | 3002 | Booking and scheduling |
| `7` | htop + nvtop | — | CPU and GPU/VRAM monitoring |
| `8` | [Netdata](https://netdata.cloud) | 19999 | Full system dashboard |
| `a` | Core GTM bundle | — | `d + 1 + 2 + 3` |
| `b` | Full GTM bundle | — | `d + 1 + 2 + 3 + 4 + 5 + 6` |
| `m` | All monitors | — | `7 + 8` |

---

## Quick Start

### Linux / WSL2 (existing Ubuntu)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/quantocos/AIOps/main/aiops.sh)
```

### Windows (fresh machine)

1. Download [`aiops-windows.bat`](./aiops-windows.bat)
2. Right-click → **Run as administrator**
3. The script installs WSL2 + Ubuntu 24.04, configures resources, and launches the installer

---

## Requirements

### Linux / WSL2

| | Minimum | Recommended |
|---|---|---|
| **OS** | Ubuntu 22.04 | Ubuntu 24.04 LTS |
| **RAM** | 8GB | 32GB |
| **Disk** | 20GB free | 100GB free |
| **GPU** | None (CPU mode) | NVIDIA 8GB+ VRAM |
| **VRAM** | — | 8GB (RTX 3060 Ti class) |

### Windows (for `aiops-windows.bat`)

- Windows 10 Build 19041+ or Windows 11
- Virtualisation enabled in BIOS (Intel VT-x / AMD-V)
- Administrator rights
- Internet connection

---

## Models — Pull After Install

Open a terminal inside Ubuntu and run:

```bash
# Always pull — required for RAG/embeddings
ollama pull nomic-embed-text

# Fits 8GB VRAM (RTX 3060 Ti / 3070 class)
ollama pull qwen3:4b             # Fast chat — 2.5GB
ollama pull qwen2.5:7b           # Content and email — 4.7GB
ollama pull qwen2.5-coder:7b     # Coding — 4.7GB
ollama pull deepseek-r1:8b       # Reasoning — 5.2GB
ollama pull llama3.1:8b          # Agent tool use — 4.9GB

# Requires 10GB+ VRAM — will CPU-offload on 8GB cards
# ollama pull qwen2.5:14b
# ollama pull qwen2.5-coder:14b
```

---

## Directory Structure

After install:

```
~/
├── aiops-server/
│   ├── install.log          # Core install log
│   └── addons.log           # Addon install log
├── agents/
│   ├── crews/               # CrewAI crew scripts
│   ├── tasks/               # Task definitions
│   ├── tools/               # Custom tools
│   ├── outputs/             # Crew run outputs
│   └── configs/             # Agent configs
├── scripts/
│   ├── run-openwebui.sh
│   ├── run-n8n.sh
│   ├── run-qdrant.sh
│   ├── run-crewai-studio.sh
│   ├── run-aider.sh
│   ├── run-crew.sh
│   ├── run-interpreter.sh
│   └── ...
├── qdrant-data/
│   ├── static/              # Qdrant Web UI
│   └── storage/             # Vector data
├── .venvs/
│   ├── crewai/
│   ├── aider/
│   ├── interpreter/
│   ├── scrapy/
│   └── playwright/
└── CrewAI-Studio/
```

---

## Shell Aliases

After `source ~/.bashrc`:

```bash
# Service management
ai-status      # pm2 status — all services
ai-start       # pm2 resurrect — start saved processes
ai-stop        # pm2 stop all
ai-restart     # pm2 restart all
ai-logs        # pm2 logs — live tailing

# AI tools
aider          # Aider code assistant
crew           # Run a CrewAI script
interpreter    # Open Interpreter
scrape         # Scrapy runner
automate       # Playwright runner

# Chat shortcuts
chat           # ollama run qwen3:4b
chat-coder     # ollama run qwen2.5-coder:7b
chat-reason    # ollama run deepseek-r1:8b
models         # ollama list
```

---

## Architecture

### Per-Port Design

Every service owns its own port. No subpath proxying for WebSocket-heavy applications.

```
Windows / LAN Browser
        │
        ▼
   Caddy :80
        │
   ┌────┴──────────────────────┐
   │                           │
   /n8n   → strip → :5678     /agents → strip → :8501
   /qdrant → strip → :6333    /monitor → strip → :19999
   /ollama → strip → :11434   /* → :8080 (OpenWebUI)
   │
   Direct port access (no proxy needed):
   :6333  Qdrant UI + API    (SPA served at root — no asset path issues)
   :11434 Ollama API
   :3000  Twenty CRM
   :9000  Listmonk
   :8100  Mautic
   :3100  Chatwoot
   :3002  Cal.com
   :19999 Netdata
```

### WebSocket Handling

Caddy is configured with `Connection "Upgrade"` (literal string) for all WebSocket-capable routes. This fixes the WSOD (White Screen of Death) issues caused by the `{http.headers.Connection}` placeholder which does not reliably forward upgrade requests.

### Streamlit (CrewAI Studio)

Streamlit runs with `--server.baseUrlPath /agents` so it generates correct WebSocket URLs (`/agents/_stcore/stream`). Caddy strips the `/agents` prefix before proxying, so Streamlit receives requests at its own root.

---

## Troubleshooting

### White screen on n8n / CrewAI Studio

Check PM2 and logs:

```bash
ai-status
pm2 logs n8n --lines 50
pm2 logs crewai-studio --lines 50
```

Restart Caddy if routing broke:

```bash
sudo systemctl restart caddy
sudo caddy validate --config /etc/caddy/Caddyfile
```

### OpenWebUI not starting

```bash
pm2 logs openwebui --lines 30
# If binary not found:
which open-webui || find ~/.local/bin -name open-webui
# Edit launcher with correct path:
nano ~/scripts/run-openwebui.sh
pm2 restart openwebui
```

### Ollama not responding

```bash
sudo systemctl status ollama
sudo systemctl restart ollama
# Test:
curl http://localhost:11434/api/tags
```

### Port already in use

```bash
sudo fuser -k 8080/tcp   # Replace with conflicting port
pm2 restart openwebui
```

### WSL2 memory issues

Edit `~/.wslconfig` on Windows (or `%USERPROFILE%\.wslconfig`):

```ini
[wsl2]
memory=16GB
processors=8
swap=8GB
```

Then restart WSL: `wsl --shutdown` from PowerShell.

### Chatwoot gems missing

```bash
cd ~/chatwoot
RUBY_MINOR=$(ruby -e 'puts RUBY_VERSION.split(".")[0..1].join(".")')
export PATH="$HOME/.gem/ruby/${RUBY_MINOR}.0/bin:$PATH"
gem install bundler --user-install
bundle install
pm2 restart chatwoot chatwoot-worker
```

### Twenty CRM / Cal.com npm errors

Both use pnpm monorepos. If you see `ERESOLVE` or `workspace:*` errors:

```bash
npm install -g pnpm
cd ~/twenty && pnpm install
# or
cd ~/calcom && pnpm install
pm2 restart twenty
pm2 restart calcom
```

---

## Version History

### v5.1.0 — Current
- **Fixed:** Per-port architecture — WebSocket-heavy apps no longer routed via subpath
- **Fixed:** OpenWebUI PM2 launch — absolute binary path resolves `~/.local/bin` not in PM2 daemon PATH
- **Fixed:** n8n WSOD — `Connection "Upgrade"` literal in Caddy; `uri strip_prefix /n8n` added
- **Fixed:** Qdrant UI WSOD — SPA served at root on `:6333`; no broken asset path resolution
- **Fixed:** CrewAI Studio WSOD — `--server.baseUrlPath /agents` + `uri strip_prefix /agents` + correct WS headers
- **Fixed:** Twenty CRM — `pnpm install` replaces `npm install` (resolves `@wyw-in-js` dependency conflict)
- **Fixed:** Cal.com — `pnpm install` replaces `npm install` (resolves `workspace:*` protocol error)
- **Fixed:** Chatwoot — `gem install bundler --user-install` for system Ruby on Ubuntu 24.04
- **Fixed:** OpenFang — `export PATH` in-session after install so hand activation runs in same shell
- **Fixed:** Mautic — `php -S 0.0.0.0:8100 public/index.php` (Symfony front controller, not `-t public/`)
- **Added:** `install_pnpm()` to core stack (required for Twenty and Cal.com addons)
- **Added:** `aiops-windows.bat` — Windows bootstrap with WSL2 install, `.wslconfig`, port forwarding, scheduled task
- **Added:** QUANTOCOS ASCII art header

### v5.0.0
- Initial release with core stack + full GTM addon suite
- Subpath Caddy routing (introduced WebSocket WSOD bugs — fixed in v5.1.0)

---

## License

MIT — see [LICENSE](./LICENSE)

---

## Author

**Quantocos AI Labs**  
Part of the [Quantocos](https://quantocos.com) ecosystem.  
*"Build with intelligence. Operate with precision."*
