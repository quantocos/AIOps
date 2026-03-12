# AIOPS — Local AI Operations Server

A three-file installer for a complete, private, locally-run AI stack.  
No cloud. No Docker. No API costs. Your data never leaves your machine.

Built for **WSL2 Ubuntu 24.04**.

---

## Files

| File | Platform | Run As | Purpose |
|---|---|---|---|
| `aiops.sh` | WSL2 / Ubuntu | Normal user | Installs the full AI stack |
| `aiops-windows.bat` | Windows | Administrator | Port forwarding + LAN autostart |
| `aiops-tools.sh` | WSL2 / Ubuntu | Normal user | Optional tools — CRM, email, agents, inbox, booking |

Run them in that order. Each is idempotent — safe to re-run if interrupted.

---

## Quick Start

```bash
# 1. Clone the repo
git clone https://github.com/quantocos/AIOps.git
cd aiops

# 2. Run the main installer (WSL2 terminal)
bash aiops.sh

# 3. Follow the prompts — you will be asked for:
#    - Your preferred .local domain name (e.g. myrig → myrig.local)
#    - A Streamlit email (press Enter to skip)

# 4. When complete, restart WSL from PowerShell:
#    wsl --shutdown
#    wsl

# 5. On Windows — run as Administrator:
#    aiops-windows.bat
#    (enter the same domain name you used in step 3)
```

Or install directly without cloning:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/quantocos/AIOps/refs/heads/main/aiops.sh)
```

---

## What Gets Installed

### Core Stack — `aiops.sh`

| Tool | Purpose | Local Port | LAN Route |
|---|---|---|---|
| Ollama | Local LLM server | 11434 | `/ollama` |
| OpenWebUI | Chat UI + RAG | 8080 | `/` (default) |
| n8n | Workflow automation | 5678 | `/n8n` |
| Qdrant | Vector database | 6333 | `/qdrant` |
| CrewAI Studio | Visual agent builder | 8501 | `/agents` |
| Caddy | Reverse proxy | 80 | — |
| Avahi mDNS | `yourname.local` on all LAN devices | — | — |
| PM2 | Process manager + auto-resurrect | — | — |

### Python Venvs (isolated — no dependency conflicts)

| Venv | Tool | Version |
|---|---|---|
| `~/.venvs/crewai` | CrewAI + crewai-tools | 1.10.1 |
| `~/.venvs/aider` | Aider coding agent | 0.86.2 |
| `~/.venvs/interpreter` | Open Interpreter | 0.4.3 |
| `~/.venvs/scrapy` | Scrapy + pandas + dedupe + email-validator | latest |
| `~/.venvs/playwright` | Playwright + Chromium | latest |

---

## System Requirements

| | Minimum | Recommended |
|---|---|---|
| OS | WSL2 Ubuntu 22.04 | WSL2 Ubuntu 24.04 |
| RAM | 16 GB | 32 GB |
| VRAM | 6 GB | 8 GB+ |
| Disk | 40 GB free | 80 GB+ |
| Python | 3.10+ | 3.12 |
| Internet | Required for install | — |

---

## Pulling Models

Model selection depends on your available VRAM. Pull after WSL restarts.

```bash
# Always pull this — powers RAG in OpenWebUI (274MB)
ollama pull nomic-embed-text

# 6GB VRAM
ollama pull qwen3:4b
ollama pull qwen2.5-coder:7b
ollama pull deepseek-r1:7b

# 8GB VRAM
ollama pull qwen3:4b
ollama pull qwen2.5:14b
ollama pull qwen2.5-coder:14b
ollama pull deepseek-r1:8b
ollama pull llama3.1:8b

# 16GB+ VRAM
ollama pull qwen3:14b
ollama pull qwen2.5-coder:14b
ollama pull deepseek-r1:14b
```

> **Note:** 14B models require 8GB+ VRAM. If a model offloads to RAM it will run slowly. Use `nvtop` or `nvidia-smi` to monitor VRAM usage.

---

## LAN Access

After running `aiops-windows.bat`, all services are accessible from any device on your network — no hosts file edits required on any device.

| Service | URL |
|---|---|
| OpenWebUI | `http://yourname.local` |
| n8n | `http://yourname.local/n8n` |
| CrewAI Studio | `http://yourname.local/agents` |
| Qdrant | `http://yourname.local/qdrant` |
| Ollama API | `http://yourname.local/ollama` |

`.local` domains resolve automatically on macOS, iOS, Android, and Windows 10+ via mDNS (Bonjour protocol). No router config needed.

---

## Windows — What `aiops-windows.bat` Does

Run once as Administrator after `aiops.sh` completes and WSL has restarted.

1. Asks for your domain name (must match what you entered in `aiops.sh`)
2. Creates `C:\autostart\wsl-portproxy.ps1` — detects WSL IP and forwards all ports
3. Registers a Task Scheduler boot task (`AIOPS-PortProxy`) — runs automatically on every Windows reboot as SYSTEM, no UAC prompt
4. Adds Windows Firewall rules for all AIOPS ports
5. Runs the port proxy immediately — LAN access works right now

If your WSL IP changes after a reboot and services stop responding, just re-run `aiops-windows.bat`. The boot task handles this automatically from then on.

---

## Optional Tools — `aiops-tools.sh`

Run after `aiops.sh` is complete and WSL has been restarted.

```bash
bash aiops-tools.sh
```

Interactive menu — install one tool or a full bundle:

```
[d] Shared dependencies     PostgreSQL, Redis, Firecrawl venv
[1] Twenty CRM              Lead and deal management          :3000  /crm
[2] Listmonk                Email campaigns, single binary    :9000  /mail
[3] OpenFang                AI agent hands (Lead/Browser/X)
[4] Mautic                  Nurture sequences + lead scoring  :8100  /mautic
[5] Chatwoot                Unified inbox                     :3100  /inbox
[6] Cal.com                 Discovery call booking            :3002  /cal

[a] Core GTM bundle         d + 1 + 2 + 3
[b] Full stack              Everything above
```

Install order matters. Always run `[d]` before any numbered option if this is a fresh install.

---

## Shell Aliases

Added to `~/.bashrc` by `aiops.sh`:

```bash
ai-status       # pm2 status
ai-start        # pm2 resurrect
ai-stop         # pm2 stop all
ai-restart      # pm2 restart all
ai-logs         # pm2 logs

chat            # ollama run qwen3:4b
chat-coder      # ollama run qwen2.5-coder:14b
chat-reason     # ollama run deepseek-r1:8b
models          # ollama list

aider           # Aider coding agent
crew            # Run a CrewAI script
interpreter     # Open Interpreter
scrape          # Scrapy runner
browser-auto    # Playwright runner
```

---

## Directory Structure After Install

```
~/
├── scripts/                    # PM2 launcher scripts (all absolute paths)
│   ├── run-openwebui.sh
│   ├── run-n8n.sh
│   ├── run-qdrant.sh
│   ├── run-crewai-studio.sh
│   ├── run-aider.sh
│   ├── run-crew.sh
│   ├── run-interpreter.sh
│   ├── run-scrapy.sh
│   └── run-playwright.sh
│
├── agents/                     # CrewAI workspace
│   ├── crews/                  # Crew scripts
│   ├── tasks/                  # Reusable task definitions
│   ├── tools/                  # Custom tools
│   ├── outputs/                # Agent outputs
│   └── configs/                # Model configs
│
├── qdrant-data/                # Qdrant persistent storage
│   ├── static/                 # Dashboard UI files
│   ├── storage/                # Vector collections
│   └── snapshots/
│
├── CrewAI-Studio/              # Visual agent builder
│   └── venv/                   # Isolated Python env
│
├── .venvs/                     # All isolated Python envs
│   ├── crewai/
│   ├── aider/
│   ├── interpreter/
│   ├── scrapy/
│   └── playwright/
│
└── aiops-server/
    ├── install.log
    └── tools-install.log
```

---

## Pinned Versions

These versions are tested and confirmed working together with zero dependency conflicts.

| Package | Version | Note |
|---|---|---|
| open-webui | 0.8.10 | Pinned — newer versions break qdrant-client |
| qdrant | v1.17.0 | Binary release |
| qdrant-web-ui | v0.2.7 | Static dashboard files |
| crewai | 1.10.1 | Isolated venv |
| crewai-tools | 1.10.1 | Isolated venv |
| aider-chat | 0.86.2 | Isolated venv |
| open-interpreter | 0.4.3 | Isolated venv |
| Node.js | 22 | Via NVM |
| PM2 | latest | Via NVM npm |

---

## Why Isolated Python Venvs?

OpenWebUI, CrewAI, Aider, and Open Interpreter all conflict on shared packages:

| Package | OpenWebUI needs | Aider needs | Result |
|---|---|---|---|
| fastapi | 0.135.1 | 0.128.8 | Conflict |
| aiohttp | 3.13.2 | 3.13.3 | Conflict |
| starlette | 0.52.1 | <0.38.0 | Conflict |
| tiktoken | ~0.8.0 | 0.12.0 | Conflict |

Installing anything globally breaks something else. Every AI tool in its own venv = zero conflicts, clean installs, easy rebuilds.

---

## Troubleshooting

**Services not starting after WSL restart**
```bash
source ~/.bashrc
ai-status
# If nothing is online:
ai-start
```

**OpenWebUI broken after pip update**
```bash
pip install "fastapi==0.135.1" "aiohttp==3.13.2" --break-system-packages --force-reinstall
pm2 restart openwebui
```

**n8n editor loads blank / white screen**
```bash
# Verify env vars in launcher
cat ~/scripts/run-n8n.sh
# N8N_PATH and N8N_EDITOR_BASE_URL must be set
pm2 restart n8n
pm2 logs n8n --lines 20 --nostream
```

**CrewAI Studio crash loop**
```bash
pm2 stop crewai-studio
cd ~/CrewAI-Studio && rm -rf venv
python3 -m venv venv
source venv/bin/activate && pip install -r requirements.txt
pm2 start crewai-studio
```

**Qdrant dashboard 404**
```bash
ls ~/qdrant-data/static/index.html  # must exist
cat ~/scripts/run-qdrant.sh         # must have STATIC_CONTENT_DIR set
pm2 restart qdrant
```

**Port already in use**
```bash
sudo fuser -k 8080/tcp   # replace with the conflicting port
pm2 restart openwebui
```

**LAN devices can't reach yourname.local**
```bash
# On Windows (PowerShell as Admin):
# Re-run aiops-windows.bat
# Or manually:
$wslIP = (wsl hostname -I).Trim().Split()[0]
netsh interface portproxy reset
netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=80 connectaddress=$wslIP connectport=80
```

**PM2 duplicate processes**
```bash
pm2 kill
rm ~/.pm2/dump.pm2
pm2 start ~/scripts/run-n8n.sh --name n8n
pm2 start ~/scripts/run-openwebui.sh --name openwebui
pm2 start ~/scripts/run-qdrant.sh --name qdrant
pm2 start ~/scripts/run-crewai-studio.sh --name crewai-studio
pm2 save
```

---

## Architecture

```
Operator (HITL — approves all outputs)
         |
         v
  deepseek-r1 (Supervisor / Planner)
         |
    _____|_____
   |           |
qwen2.5:14b   llama3.1:8b
(content/email) (tool calls/agents)
         |
   ______|______
  |      |      |
 n8n  CrewAI  Interpreter
  |
Qdrant (RAG / knowledge base)
```

---

## Roadmap

- [ ] macOS Apple Silicon support
- [ ] Ubuntu Server / VPS variant
- [ ] Auto VRAM detection for model recommendations
- [ ] Cloudflare Tunnel integration for public access
- [ ] HITL dashboard UI (React on n8n webhooks)
- [ ] Web-based health dashboard

---

## License

MIT — use freely, modify freely, share freely.

---

*Quantocos AI Labs — AIOPS v3.0.0*
