@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul 2>&1

:: ============================================================
:: AIOPS-WINDOWS.BAT — Local AI Operations Server
:: Version:    5.1.0
:: Author:     Quantocos AI Labs
:: Compatible: Windows 10 21H2+ / Windows 11 with WSL2
:: Usage:      Double-click or run as Administrator
::
:: What this does:
::   1. Checks prerequisites (WSL2, Ubuntu, admin rights)
::   2. Installs WSL2 + Ubuntu 24.04 if not present
::   3. Configures WSL2 memory/CPU limits via .wslconfig
::   4. Forwards the aiops.sh script into the WSL2 environment
::   5. Launches aiops.sh inside Ubuntu
:: ============================================================

:: ── ANSI color codes (Windows 10 1511+ / Windows 11) ────────
set "ESC="
for /f %%a in ('echo prompt $E ^| cmd') do set "ESC=%%a"
set "RED=%ESC%[31m"
set "GREEN=%ESC%[32m"
set "YELLOW=%ESC%[33m"
set "CYAN=%ESC%[36m"
set "BOLD=%ESC%[1m"
set "NC=%ESC%[0m"

:: ── Config ───────────────────────────────────────────────────
set "AIOPS_VERSION=5.1.0"
set "UBUNTU_DISTRO=Ubuntu-24.04"
set "UBUNTU_APPX=ubuntu2404"
set "AIOPS_SCRIPT_URL=https://raw.githubusercontent.com/quantocos/AIOps/main/aiops.sh"
set "WSL_USER=quantocos"

:: ── RAM/CPU limits written to .wslconfig ─────────────────────
:: Adjust based on your host machine. These are conservative defaults.
:: 8GB RAM host  → memory=4GB  processors=4
:: 16GB RAM host → memory=8GB  processors=6
:: 32GB RAM host → memory=16GB processors=8
set "WSL_MEMORY=16GB"
set "WSL_PROCESSORS=8"
set "WSL_SWAP=8GB"

cls

:: ============================================================
:: BANNER
:: ============================================================
echo.
echo %BOLD%%CYAN%   ____  _   _   _    _   _ _____ ___   ____  ___  ____%NC%
echo %BOLD%%CYAN%  / __ \^| ^| ^| ^| / \  ^| \ ^| ^|_   _/ _ \ / ___^|/ _ \/ ___^|%NC%
echo %BOLD%%CYAN% ^| ^|  ^| ^| ^| ^| ^|/ _ \ ^|  \^| ^| ^| ^|^| ^| ^| ^| ^|   ^| ^| ^| \___ \%NC%
echo %BOLD%%CYAN% ^| ^|__^| ^| ^|_^| / ___ \^| ^|\  ^| ^| ^|^| ^|_^| ^| ^|___^| ^|_^| ^|___) ^|%NC%
echo %BOLD%%CYAN%  \___\_\\___/_/   \_\_^| \_^| ^|_^| \___/ \____^|\___/^|____/%NC%
echo.
echo %BOLD%  Local AI Operations Server  ^|  Quantocos AI Labs  ^|  v%AIOPS_VERSION%%NC%
echo %BOLD%%CYAN%  Windows Bootstrap — WSL2 Ubuntu 24.04%NC%
echo  ─────────────────────────────────────────────────────────
echo.

:: ============================================================
:: STEP 1 — Administrator check
:: ============================================================
echo %CYAN%[^>]%NC% Checking administrator privileges...
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo %YELLOW%[!]%NC% Not running as Administrator.
    echo %YELLOW%[!]%NC% WSL2 installation requires elevated privileges.
    echo.
    echo     Right-click this file and select "Run as administrator"
    echo     or press any key to attempt UAC elevation now.
    echo.
    pause
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b 0
)
echo %GREEN%[✓]%NC% Running as Administrator

:: ============================================================
:: STEP 2 — Windows version check
:: ============================================================
echo %CYAN%[^>]%NC% Checking Windows version...
for /f "tokens=4-5 delims=. " %%i in ('ver') do (
    set WIN_BUILD=%%j
)
:: WSL2 requires build 19041+ (Windows 10 2004 / 20H1)
if !WIN_BUILD! LSS 19041 (
    echo %RED%[✗]%NC% Windows build !WIN_BUILD! detected.
    echo %RED%[✗]%NC% WSL2 requires Windows 10 Build 19041+ or Windows 11.
    echo     Update Windows and re-run this script.
    pause
    exit /b 1
)
echo %GREEN%[✓]%NC% Windows build !WIN_BUILD! — WSL2 compatible

:: ============================================================
:: STEP 3 — Check virtualisation
:: ============================================================
echo %CYAN%[^>]%NC% Checking Hyper-V / virtualisation...
powershell -Command "if ((Get-WmiObject Win32_Processor).VirtualizationFirmwareEnabled) { exit 0 } else { exit 1 }" >nul 2>&1
if %errorLevel% neq 0 (
    echo %YELLOW%[!]%NC% Virtualisation may be disabled in BIOS/UEFI.
    echo %YELLOW%[!]%NC% If WSL2 fails to install, enable Intel VT-x or AMD-V in BIOS.
) else (
    echo %GREEN%[✓]%NC% Virtualisation enabled
)

:: ============================================================
:: STEP 4 — Enable WSL and Virtual Machine Platform features
:: ============================================================
echo.
echo %BOLD%══ WSL2 Setup ══%NC%
echo.

:: Check if WSL is already installed
wsl --status >nul 2>&1
if %errorLevel% equ 0 (
    echo %GREEN%[✓]%NC% WSL already installed
    goto :check_ubuntu
)

echo %CYAN%[^>]%NC% Enabling Windows Subsystem for Linux...
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart >nul 2>&1
if %errorLevel% neq 0 (
    echo %YELLOW%[!]%NC% DISM feature enable returned non-zero — may already be enabled
)

echo %CYAN%[^>]%NC% Enabling Virtual Machine Platform...
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart >nul 2>&1

echo %CYAN%[^>]%NC% Setting WSL default version to 2...
wsl --set-default-version 2 >nul 2>&1

echo %CYAN%[^>]%NC% Updating WSL kernel...
wsl --update >nul 2>&1
if %errorLevel% neq 0 (
    echo %YELLOW%[!]%NC% WSL kernel update failed — downloading manually...
    powershell -Command "Invoke-WebRequest -Uri 'https://wslstorestorage.blob.core.windows.net/wslblob/wsl_update_x64.msi' -OutFile '%TEMP%\wsl_update.msi'"
    msiexec /i "%TEMP%\wsl_update.msi" /quiet /norestart
)

echo %GREEN%[✓]%NC% WSL2 features enabled

:: ============================================================
:: STEP 5 — Install Ubuntu 24.04
:: ============================================================
:check_ubuntu
echo.
echo %CYAN%[^>]%NC% Checking for Ubuntu 24.04...

wsl -d %UBUNTU_DISTRO% -- echo "check" >nul 2>&1
if %errorLevel% equ 0 (
    echo %GREEN%[✓]%NC% Ubuntu 24.04 already installed
    goto :configure_wsl
)

echo %CYAN%[^>]%NC% Installing Ubuntu 24.04 (this may take several minutes)...
echo %YELLOW%[!]%NC% You will be prompted to create a UNIX username and password.
echo %YELLOW%[!]%NC% Username recommendation: quantocos
echo.

:: Try winget first (Windows 11 / updated Win10)
winget --version >nul 2>&1
if %errorLevel% equ 0 (
    echo %CYAN%[^>]%NC% Installing via winget...
    winget install --id Canonical.Ubuntu.2404 --source winget --accept-package-agreements --accept-source-agreements
    goto :ubuntu_installed
)

:: Fallback: wsl --install
echo %CYAN%[^>]%NC% Installing via wsl --install...
wsl --install -d Ubuntu-24.04
echo.
echo %YELLOW%[!]%NC% Ubuntu installation may require a system restart.
echo %YELLOW%[!]%NC% After restart, re-run this script to continue.
echo.
pause

:ubuntu_installed
echo %GREEN%[✓]%NC% Ubuntu 24.04 installed

:: ============================================================
:: STEP 6 — Configure .wslconfig (memory, CPU, swap)
:: ============================================================
:configure_wsl
echo.
echo %BOLD%══ WSL2 Resource Configuration ══%NC%
echo.

set "WSLCONFIG=%USERPROFILE%\.wslconfig"

if exist "%WSLCONFIG%" (
    echo %YELLOW%[!]%NC% Existing .wslconfig found at %WSLCONFIG%
    echo %YELLOW%[!]%NC% Backing up to .wslconfig.bak
    copy "%WSLCONFIG%" "%WSLCONFIG%.bak" >nul 2>&1
)

echo %CYAN%[^>]%NC% Writing .wslconfig...
(
    echo ; ============================================================
    echo ; .wslconfig — Quantocos AI Labs — AIOPS v%AIOPS_VERSION%
    echo ; Location: %USERPROFILE%\.wslconfig
    echo ; Apply: wsl --shutdown then restart WSL
    echo ; ============================================================
    echo [wsl2]
    echo ; Memory limit — set to ~50%% of host RAM for AI workloads
    echo memory=%WSL_MEMORY%
    echo ; CPU cores — leave 2 for Windows
    echo processors=%WSL_PROCESSORS%
    echo ; Swap — useful when models exceed RAM
    echo swap=%WSL_SWAP%
    echo ; Localhost forwarding — access WSL services via localhost on Windows
    echo localhostForwarding=true
    echo ; Nested virtualisation — needed for some GPU passthrough setups
    echo nestedVirtualization=true
    echo ; GUI apps support ^(WSLg^)
    echo guiApplications=true
    echo [experimental]
    echo ; Auto memory reclaim — release unused WSL2 memory back to Windows
    echo autoMemoryReclaim=gradual
    echo ; Sparse VHD — disk grows on demand rather than pre-allocating
    echo sparseVhd=true
) > "%WSLCONFIG%"

echo %GREEN%[✓]%NC% .wslconfig written: memory=%WSL_MEMORY% processors=%WSL_PROCESSORS% swap=%WSL_SWAP%
echo %CYAN%[^>]%NC% Location: %WSLCONFIG%

:: ============================================================
:: STEP 7 — GPU passthrough check (NVIDIA)
:: ============================================================
echo.
echo %BOLD%══ GPU Check ══%NC%
echo.

where nvidia-smi >nul 2>&1
if %errorLevel% equ 0 (
    echo %GREEN%[✓]%NC% NVIDIA GPU detected
    for /f "tokens=*" %%g in ('nvidia-smi --query-gpu=name --format=csv^,noheader 2^>nul') do (
        echo %GREEN%[✓]%NC% GPU: %%g
    )
    for /f "tokens=*" %%m in ('nvidia-smi --query-gpu=memory.total --format=csv^,noheader 2^>nul') do (
        echo %GREEN%[✓]%NC% VRAM: %%m
    )
    echo %CYAN%[^>]%NC% NVIDIA GPU will be available in WSL2 via CUDA passthrough
    echo %CYAN%[^>]%NC% Ensure NVIDIA WSL2 driver is installed:
    echo     https://developer.nvidia.com/cuda/wsl
) else (
    echo %YELLOW%[!]%NC% No NVIDIA GPU detected or nvidia-smi not in PATH
    echo %YELLOW%[!]%NC% Ollama will run on CPU — expect slower inference
    echo %YELLOW%[!]%NC% For GPU support install NVIDIA Driver 525+ with WSL2 support
)

:: ============================================================
:: STEP 8 — Port forwarding (access WSL2 services from Windows)
:: ============================================================
echo.
echo %BOLD%══ Windows Port Forwarding ══%NC%
echo.
echo %CYAN%[^>]%NC% Setting up port forwarding from Windows to WSL2...

:: Get WSL2 IP dynamically
for /f "tokens=*" %%i in ('wsl -d %UBUNTU_DISTRO% -- ip route get 1 2^>nul ^| awk "{print $7; exit}"') do (
    set "WSL_IP=%%i"
)

if "!WSL_IP!"=="" (
    echo %YELLOW%[!]%NC% Could not detect WSL2 IP — skipping port forwarding
    echo %YELLOW%[!]%NC% Run this script again after Ubuntu is fully set up
    goto :skip_portfwd
)

echo %CYAN%[^>]%NC% WSL2 IP: !WSL_IP!

:: Forward all AIOPS service ports
set PORTS=8080 5678 6333 8501 11434 9000 3000 3100 3002 8100 19999

for %%p in (%PORTS%) do (
    netsh interface portproxy delete v4tov4 listenport=%%p listenaddress=0.0.0.0 >nul 2>&1
    netsh interface portproxy add v4tov4 listenport=%%p listenaddress=0.0.0.0 connectport=%%p connectaddress=!WSL_IP! >nul 2>&1
)

:: Add Windows Firewall rules
netsh advfirewall firewall delete rule name="AIOPS WSL2" >nul 2>&1
netsh advfirewall firewall add rule name="AIOPS WSL2" dir=in action=allow protocol=TCP localport=8080,5678,6333,8501,11434,9000,3000,3100,3002,8100,19999 >nul 2>&1

echo %GREEN%[✓]%NC% Port forwarding configured for all AIOPS services
echo %GREEN%[✓]%NC% Firewall rules added
echo.
echo     Service       Windows URL
echo     ───────────── ─────────────────────────────
echo     OpenWebUI     http://localhost:8080
echo     n8n           http://localhost:5678
echo     Qdrant        http://localhost:6333
echo     CrewAI Studio http://localhost:8501
echo     Ollama        http://localhost:11434
echo     Listmonk      http://localhost:9000

:skip_portfwd

:: ============================================================
:: STEP 9 — Create WSL2 startup task (auto port-forward on boot)
:: ============================================================
echo.
echo %BOLD%══ Startup Task ══%NC%
echo.
echo %CYAN%[^>]%NC% Creating Windows Task Scheduler entry for port forwarding...

:: Write the port forward refresh script
set "PFWD_SCRIPT=%USERPROFILE%\aiops-portforward.ps1"
(
    echo # AIOPS Port Forwarder — Quantocos AI Labs
    echo # Runs at login to refresh WSL2 IP and re-apply port rules
    echo $wslIp = ^(wsl -d Ubuntu-24.04 -- ip route get 1 2^>$null ^| Select-String '\d+\.\d+\.\d+\.\d+' ^| ForEach-Object { $_.Matches[0].Value }^)[1]
    echo if ^(-not $wslIp^) { exit 1 }
    echo $ports = @^(8080,5678,6333,8501,11434,9000,3000,3100,3002,8100,19999^)
    echo foreach ^($port in $ports^) {
    echo     netsh interface portproxy delete v4tov4 listenport=$port listenaddress=0.0.0.0 ^| Out-Null
    echo     netsh interface portproxy add v4tov4 listenport=$port listenaddress=0.0.0.0 connectport=$port connectaddress=$wslIp ^| Out-Null
    echo }
) > "%PFWD_SCRIPT%"

:: Register scheduled task
schtasks /delete /tn "AIOPS-PortForward" /f >nul 2>&1
schtasks /create /tn "AIOPS-PortForward" /tr "powershell -WindowStyle Hidden -File \"%PFWD_SCRIPT%\"" /sc onlogon /ru "%USERNAME%" /rl highest /f >nul 2>&1
if %errorLevel% equ 0 (
    echo %GREEN%[✓]%NC% Startup task created — port forwarding refreshes on every login
) else (
    echo %YELLOW%[!]%NC% Task creation failed — run aiops-portforward.ps1 manually after each restart
)

:: ============================================================
:: STEP 10 — Confirm and launch aiops.sh
:: ============================================================
echo.
echo %BOLD%══ Launching AIOPS Installer in WSL2 ══%NC%
echo.
echo %CYAN%[^>]%NC% All prerequisites satisfied.
echo %CYAN%[^>]%NC% Opening Ubuntu 24.04 and running aiops.sh v%AIOPS_VERSION%...
echo.
echo %YELLOW%[!]%NC% The Ubuntu terminal will open in a new window.
echo %YELLOW%[!]%NC% Follow the on-screen prompts inside the Ubuntu window.
echo.
echo  What happens next:
echo    1. aiops.sh downloads and runs inside Ubuntu
echo    2. You'll be asked for a .local domain name
echo    3. Core stack installs automatically
echo    4. Addons menu appears — choose what to install
echo    5. Come back to this window when done
echo.

set /p "LAUNCH=Press Enter to launch Ubuntu and start AIOPS install, or Ctrl+C to cancel..."

:: Launch Ubuntu with aiops.sh in a new window
:: Uses wt.exe (Windows Terminal) if available, falls back to cmd
where wt >nul 2>&1
if %errorLevel% equ 0 (
    echo %GREEN%[✓]%NC% Opening in Windows Terminal...
    start wt.exe wsl -d %UBUNTU_DISTRO% -- bash -c "bash <(curl -fsSL %AIOPS_SCRIPT_URL%); exec bash"
) else (
    echo %CYAN%[^>]%NC% Opening in standard console...
    start "" wsl -d %UBUNTU_DISTRO% -- bash -c "bash <(curl -fsSL %AIOPS_SCRIPT_URL%); exec bash"
)

:: ============================================================
:: STEP 11 — Post-launch info
:: ============================================================
echo.
echo %GREEN%[✓]%NC% Ubuntu launched — AIOPS installer is running
echo.
echo %BOLD%══ After Install Completes ══%NC%
echo.
echo  Access your services from Windows:
echo.
echo    OpenWebUI      http://localhost:8080
echo    n8n            http://localhost:5678
echo    Qdrant UI      http://localhost:6333
echo    CrewAI Studio  http://localhost:8501
echo    Ollama         http://localhost:11434
echo.
echo  Useful WSL2 commands (run in PowerShell/cmd):
echo.
echo    wsl                          Open Ubuntu shell
echo    wsl --shutdown               Stop all WSL2 instances
echo    wsl --status                 Show WSL2 status
echo    wsl -d Ubuntu-24.04          Open specific distro
echo.
echo  Inside Ubuntu after install:
echo.
echo    ai-status                    PM2 service status
echo    ai-logs                      Live log tailing
echo    ai-restart                   Restart all services
echo    chat                         Quick Ollama chat
echo    ollama list                  Show pulled models
echo.
echo %BOLD%Logs:%NC%
echo    Core:    ~/aiops-server/install.log   ^(inside Ubuntu^)
echo    Addons:  ~/aiops-server/addons.log    ^(inside Ubuntu^)
echo.
echo %BOLD%%CYAN%Quantocos AI Labs%NC%
echo %CYAN%"Build with intelligence. Operate with precision."%NC%
echo.
echo ─────────────────────────────────────────────────────────
echo.
pause
endlocal
