#!/usr/bin/env bash
#
# SysInfo — Interactive System Information CLI
#
# Usage: ./SysInfo.sh [options]
#
# Options:
#   -h, --help        Show this help message
#   -v, --version     Show version information
#       --no-color    Disable colored output
#   -j, --json        Output system info as JSON (non-interactive)
#   -o, --output FILE     Write JSON output to FILE
#   -t, --text-output FILE Write interactive output to FILE in output/
#       --no-save         Disable automatic report saving to output/
#   -c, --check           Check required dependencies and exit
#
# License: MIT (https://opensource.org/licenses/MIT)
# Repository: https://github.com/itxdeeni/Systeminfo

set -o pipefail
set -Euo pipefail

VERSION="1.0.0"
JSON_MODE=0

# ── Dependencies ─────────────────────────────────────────────
DEPS=(hostname grep cut tr uname uptime ps)
OPTIONAL_DEPS=(lscpu lspci dmidecode sensors nvidia-smi ip resolvectl free df lsblk)

# ── Color setup ──────────────────────────────────────────────
if [[ -t 1 ]] && [[ "${NO_COLOR:-}" != "1" ]]; then
  R="\033[1;31m"  G="\033[1;32m"  Y="\033[1;33m"
  B="\033[1;34m"  M="\033[1;35m"  C="\033[1;36m"
  W="\033[1;37m"  D="\033[0;90m"  N="\033[0m"
else
  R= G= Y= B= M= C= W= D= N=
fi

# ── Helpers ──────────────────────────────────────────────────
banner() {
  [[ "$JSON_MODE" == "1" ]] && return
  clear
  local dt
  dt=$(date '+%Y-%m-%d %H:%M')
  printf "${C}╔═══════════════════════════════════════════════╗${N}\n"
  printf "${C}║        ${W}SYSINFO — System Information Tool${C}        ║${N}\n"
  printf "${C}║${D}          %s${D}            ${C}║${N}\n" "$dt"
  printf "${C}╚═══════════════════════════════════════════════╝${N}\n"
  printf "\n"
}

section() {
  [[ "$JSON_MODE" == "1" ]] && return
  printf "\n"
  printf "${C}┌──────────────────────────────────────────────┐${N}\n"
  printf "${C}│${N} ${W}%s${N}\n" "$1"
  printf "${C}└──────────────────────────────────────────────┘${N}\n"
}

err() {
  printf "  ${R}✗${N} %s\n" "$1" >&2
}

ok() {
  [[ "$JSON_MODE" == "1" ]] && return
  printf "  ${G}✓${N} %s\n" "$1"
}

info() {
  [[ "$JSON_MODE" == "1" ]] && return
  printf "  ${C}→${N} %s\n" "$1"
}

hr() {
  [[ "$JSON_MODE" == "1" ]] && return
  printf "${D}  ∙ ∙ ∙ ∙ ∙ ∙ ∙ ∙ ∙ ∙ ∙ ∙ ∙ ∙ ∙ ∙ ∙ ∙ ∙ ∙ ∙ ∙ ∙${N}\n"
}

label_val() {
  [[ "$JSON_MODE" == "1" ]] && return
  printf "  ${Y}%-20s${N} %s\n" "$1:" "$2"
}

run_cmd() {
  local label="$1" cmd="$2"
  if [[ "$JSON_MODE" == "1" ]]; then
    local output
    output=$(eval "$cmd" 2>/dev/null) && printf "%s" "$output"
    return
  fi
  printf "  ${Y}%s${N}\n" "$label"
  local output
  if output=$(eval "$cmd" 2>/dev/null); then
    printf "%s\n" "$output" | sed 's/^/    /'
  else
    err "not available (command not found or permission denied)"
  fi
}

need_sudo() {
  if [[ $EUID -ne 0 ]]; then
    err "requires root privileges — try running with ${W}sudo${N}"
    return 1
  fi
  return 0
}



json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  printf "%s" "$s"
}

NL=$'\n'

json_write() {
  [[ "$JSON_MODE" != "1" ]] && return
  printf "%s" "$1"
}

json_obj_start()   { json_write "{${NL}"; }
json_obj_end()     { json_write "}${NL}"; }

json_kv() {
  local key="$1" val="$2"
  json_write "  \"$(json_escape "$key")\": \"$(json_escape "$val")\",${NL}"
}

json_sec_start() { json_write "  \"$(json_escape "$1")\": {${NL}"; }
json_sec_end()   { json_write "  },${NL}"; }

json_array_start() {
  local name="$1"
  json_write "  \"$(json_escape "$name")\": [${NL}"
}
json_array_append() {
  local val="$1"
  json_write "  \"$(json_escape "$val")\",${NL}"
}
json_array_end() {
  json_write "  ]${NL}"
}

json_finish() {
  perl -0777 -pe 's/,\n(\s*})/\n$1/g' 2>/dev/null ||
  python3 -c "import sys,re; print(re.sub(r',\n(\s*})', r'\n\1', sys.stdin.read()), end='')" 2>/dev/null ||
  cat
}

check_commands() {
  local missing=0
  for cmd in "${DEPS[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
      err "missing required dependency: $cmd"
      missing=1
    fi
  done

  if [[ "$missing" == "1" ]]; then
    printf "\n  Install missing dependencies and try again.\n" >&2
    exit 1
  fi
}

check_optional() {
  for cmd in "${OPTIONAL_DEPS[@]}"; do
    if command -v "$cmd" &>/dev/null; then
      ok "found: ${cmd}"
    else
      info "not found: ${cmd}"
    fi
  done
}

# ── Info Modules ────────────────────────────────────────────

_json_host_info() {
  json_sec_start "host"
  json_kv "hostname" "$(hostname 2>/dev/null || echo "unknown")"
  json_kv "static_hostname" "$(hostnamectl status --static 2>/dev/null || echo "unknown")"
  json_sec_end
}

_json_dmidecode_system() {
  if [[ $EUID -ne 0 ]] || ! command -v dmidecode &>/dev/null; then return; fi
  local data line key val
  data=$(dmidecode -t system 2>/dev/null | grep -E 'Manufacturer|Product Name|Version|Serial Number|UUID|Family')
  json_sec_start "system_dmi"
  while IFS= read -r line; do
    key=$(printf "%s" "$line" | sed 's/^[[:space:]]*//;s/:.*//')
    val=$(printf "%s" "$line" | sed 's/^[[:space:]]*[^:]*:[[:space:]]*//')
    [[ -n "$key" ]] && json_kv "$key" "$val"
  done <<< "$data"
  json_sec_end
}

_json_cpu_info() {
  if ! command -v lscpu &>/dev/null; then return; fi
  local data line key val
  data=$(lscpu 2>/dev/null | grep -E 'Model name|Socket|CPU\(s\)|Thread|Core|MHz')
  json_sec_start "cpu"
  while IFS= read -r line; do
    key=$(printf "%s" "$line" | sed 's/^[[:space:]]*//;s/:.*//')
    val=$(printf "%s" "$line" | sed 's/^[[:space:]]*[^:]*:[[:space:]]*//')
    [[ -n "$key" ]] && json_kv "$key" "$val"
  done <<< "$data"
  json_sec_end
}

_json_memory_modules() {
  if [[ $EUID -ne 0 ]] || ! command -v dmidecode &>/dev/null; then return; fi
  local data line key val
  data=$(dmidecode -t memory 2>/dev/null | grep -E 'Size|Type|Speed|Manufacturer|Locator|Maximum Capacity' | sed '/No Module Installed/d')
  json_sec_start "memory_modules"
  while IFS= read -r line; do
    key=$(printf "%s" "$line" | sed 's/^[[:space:]]*//;s/:.*//')
    val=$(printf "%s" "$line" | sed 's/^[[:space:]]*[^:]*:[[:space:]]*//')
    [[ -n "$key" ]] && json_kv "$key" "$val"
  done <<< "$data"
  json_sec_end
}

_json_ram_summary() {
  if ! command -v free &>/dev/null; then return; fi
  local data headers vals
  data=$(free -h 2>/dev/null)
  json_sec_start "memory_summary"
  read -ra headers <<< "$(printf "%s" "$data" | sed -n '1p')"
  read -ra vals <<< "$(printf "%s" "$data" | sed -n '2p')"
  for i in "${!headers[@]}"; do
    [[ -n "${headers[$i]}" && -n "${vals[$i]}" ]] && json_kv "${headers[$i]}" "${vals[$i]}"
  done
  json_sec_end
}

_json_storage() {
  json_sec_start "storage"
  command -v lsblk &>/dev/null && json_kv "block_devices" "$(lsblk -o NAME,SIZE,TYPE,MODEL,MOUNTPOINT 2>/dev/null)"
  command -v df &>/dev/null && json_kv "disk_usage" "$(df -h -x tmpfs -x devtmpfs 2>/dev/null)"
  json_sec_end
}

_json_gpu_info() {
  json_sec_start "gpu"
  if command -v lspci &>/dev/null; then
    json_kv "pci_vga" "$(lspci 2>/dev/null | grep -i vga | head -1)"
  fi
  if command -v nvidia-smi &>/dev/null; then
    local data line i=0
    data=$(nvidia-smi --query-gpu=name,temperature.gpu,utilization.gpu,memory.used,memory.total --format=csv,noheader 2>/dev/null | head -5)
    while IFS= read -r line; do
      json_kv "nvidia_gpu_$i" "$line"
      i=$((i + 1))
    done <<< "$data"
  fi
  json_sec_end
}

_json_os_info() {
  json_sec_start "os"
  json_kv "kernel" "$(uname -a 2>/dev/null || echo 'unknown')"
  if [[ -f /etc/os-release ]]; then
    local key val
    while IFS='=' read -r key val; do
      [[ -n "$key" ]] && json_kv "$key" "$(printf "%s" "$val" | tr -d '"')"
    done < <(grep -E '^(PRETTY_NAME|NAME|VERSION|VERSION_ID|ID|ID_LIKE)' /etc/os-release)
  fi
  json_sec_end
}

_json_uptime_info() {
  json_sec_start "uptime"
  json_kv "uptime" "$(uptime -p 2>/dev/null | sed 's/^up //' || echo 'unknown')"
  json_kv "load" "$(uptime 2>/dev/null | awk -F'load average:' '{print $2}' | xargs || echo 'unknown')"
  json_sec_end
}

_json_network_info() {
  json_sec_start "network"
  command -v ip &>/dev/null && json_kv "ip_addresses" "$(ip -br addr 2>/dev/null)"
  command -v resolvectl &>/dev/null && json_kv "dns_servers" "$(resolvectl status 2>/dev/null | grep 'DNS Servers' | head -3)"
  json_sec_end
}

_json_battery_info() {
  if ! ls /sys/class/power_supply/*/capacity &>/dev/null 2>&1; then return; fi
  local name cap status
  json_sec_start "battery"
  for bat in /sys/class/power_supply/*/; do
    name=$(basename "$bat")
    cap=$(cat "$bat/capacity" 2>/dev/null || echo "N/A")
    status=$(cat "$bat/status" 2>/dev/null || echo "N/A")
    json_kv "$name" "${cap}% (${status})"
  done
  json_sec_end
}

_json_temperature_info() {
  if ! command -v sensors &>/dev/null; then return; fi
  local data line key val
  data=$(sensors 2>/dev/null | grep -E '°C|°F')
  json_sec_start "temperatures"
  while IFS= read -r line; do
    key=$(printf "%s" "$line" | sed 's/:.*//' | xargs)
    val=$(printf "%s" "$line" | sed 's/^[^:]*://' | xargs)
    [[ -n "$key" ]] && json_kv "$key" "$val"
  done <<< "$data"
  json_sec_end
}

_json_process_summary() {
  local data line i=0
  json_sec_start "top_processes"
  data=$(ps aux --sort=-%mem 2>/dev/null | head -6 | tail -5)
  while IFS= read -r line; do
    json_kv "process_$i" "$(printf "%s" "$line" | tr -s ' ' | cut -d' ' -f11- | xargs)"
    i=$((i + 1))
  done <<< "$data"
  json_sec_end
}

# ── Interactive modules (non-JSON) ──────────────────────────

host_info() {
  section "HOST INFO"
  run_cmd "hostnamectl" "hostnamectl 2>/dev/null || hostname"
}

dmidecode_system() {
  section "SYSTEM (DMIDECODE)"
  if need_sudo; then
    run_cmd "dmidecode" "dmidecode -t system 2>/dev/null | grep -E 'Manufacturer|Product Name|Version|Serial Number|UUID|Family'"
  fi
}

cpu_info() {
  section "CPU INFO"
  run_cmd "lscpu" "lscpu 2>/dev/null | grep -E 'Model name|Socket|CPU\\(s\\)|Thread|Core|MHz'"
}

memory_modules() {
  section "MEMORY MODULES"
  if need_sudo; then
    run_cmd "dmidecode" "dmidecode -t memory 2>/dev/null | grep -E 'Size|Type|Speed|Manufacturer|Locator|Maximum Capacity' | sed '/No Module Installed/d'"
  fi
}

ram_summary() {
  section "RAM SUMMARY"
  run_cmd "free -h" "free -h"
}

storage() {
  section "STORAGE DEVICES"
  run_cmd "lsblk" "lsblk -o NAME,SIZE,TYPE,MODEL,MOUNTPOINT 2>/dev/null"
  printf "\n"
  info "Disk Usage (mounted):"
  df -h -x tmpfs -x devtmpfs 2>/dev/null | sed 's/^/    /'
}

gpu_info() {
  section "GPU INFO"
  run_cmd "lspci | grep VGA" "lspci 2>/dev/null | grep -i vga"
  if command -v nvidia-smi &>/dev/null; then
    printf "\n"
    run_cmd "nvidia-smi (GPU stats)" "nvidia-smi --query-gpu=name,temperature.gpu,utilization.gpu,memory.used,memory.total --format=csv,noheader 2>/dev/null | head -5"
  fi
}

os_info() {
  section "OS INFO"
  run_cmd "uname" "uname -a"
  if [[ -f /etc/os-release ]]; then
    printf "\n"
    run_cmd "os-release" "grep -E '^PRETTY_NAME=' /etc/os-release | cut -d= -f2 | tr -d '\"'"
  fi
}

uptime_info() {
  section "UPTIME & LOAD"
  run_cmd "uptime" "uptime"
}

network_info() {
  section "NETWORK"
  run_cmd "IP addresses" "ip -br addr 2>/dev/null"
  printf "\n"
  run_cmd "DNS" "resolvectl status 2>/dev/null | grep 'DNS Servers' | head -3"
}

battery_info() {
  if ls /sys/class/power_supply/*/capacity &>/dev/null 2>&1; then
    section "BATTERY"
    for bat in /sys/class/power_supply/*/; do
      name=$(basename "$bat")
      cap=$(cat "$bat/capacity" 2>/dev/null)
      status=$(cat "$bat/status" 2>/dev/null)
      printf "    ${Y}%s${N}: %s%% (%s)\n" "$name" "$cap" "$status"
    done
  fi
}

temperature_info() {
  if command -v sensors &>/dev/null; then
    section "TEMPERATURES"
    sensors 2>/dev/null | grep -E '°C|°F' | sed 's/^/    /'
  fi
}

process_summary() {
  section "TOP PROCESSES (by memory)"
  ps aux --sort=-%mem 2>/dev/null | head -6 | sed 's/^/    /'
}

system_summary() {
  local hostname os kernel uptime_str
  hostname=$(hostname 2>/dev/null || echo "unknown")
  os=$(grep -E '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "unknown")
  kernel=$(uname -r 2>/dev/null || echo "unknown")
  uptime_str=$(uptime -p 2>/dev/null | sed 's/^up //' || echo "unknown")

  section "SYSTEM SUMMARY"
  label_val "Hostname" "$hostname"
  label_val "OS" "$os"
  label_val "Kernel" "$kernel"
  label_val "Uptime" "$uptime_str"
}

# ── JSON Full Report ────────────────────────────────────────

json_full_report() {
  JSON_MODE=1
  local hostname os kernel uptime_str
  hostname=$(hostname 2>/dev/null || echo "unknown")
  os=$(grep -E '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "unknown")
  kernel=$(uname -r 2>/dev/null || echo "unknown")
  uptime_str=$(uptime -p 2>/dev/null | sed 's/^up //' || echo "unknown")

  {
    json_obj_start
    json_kv "hostname" "$hostname"
    json_kv "os" "$os"
    json_kv "kernel" "$kernel"
    json_kv "uptime" "$uptime_str"

    _json_host_info
    _json_dmidecode_system
    _json_cpu_info
    _json_memory_modules
    _json_ram_summary
    _json_storage
    _json_gpu_info
    _json_os_info
    _json_uptime_info
    _json_network_info
    _json_battery_info
    _json_temperature_info
    _json_process_summary

    json_obj_end
  } | json_finish
}

# ── Menu ────────────────────────────────────────────────────

menu() {
  banner
  printf "  ${G}1${N}   Everything (full report)\n"
  printf "  ${G}2${N}   Host & System\n"
  printf "  ${G}3${N}   CPU\n"
  printf "  ${G}4${N}   Memory (modules + summary)\n"
  printf "  ${G}5${N}   Storage (devices + usage)\n"
  printf "  ${G}6${N}   GPU\n"
  printf "  ${G}7${N}   OS & Uptime\n"
  printf "  ${G}8${N}   Network\n"
  printf "  ${G}9${N}   Battery & Temperature\n"
  printf "  ${G}10${N}  Top Processes\n"
  printf "\n"
  printf "  ${G}s${N}   Save full report to output/\n"
  printf "  ${G}q${N}   Quit\n"
  printf "\n"
  printf "${C}Choose an option [1-10]: ${N}"
  read -r choice
  printf "\n"
}

# ── Main ────────────────────────────────────────────────────

_full_report_body() {
  system_summary
  echo ""; hr
  host_info; hr
  dmidecode_system; hr
  cpu_info; hr
  memory_modules; hr
  ram_summary; hr
  storage; hr
  gpu_info; hr
  os_info; hr
  uptime_info; hr
  network_info; hr
  battery_info; hr
  temperature_info; hr
  process_summary
  printf "\n"
  printf "${D}  ── Report finished at %s ──${N}\n" "$(date '+%H:%M:%S')"
}

main() {
  local output_file=""
  local text_output_file=""
  local NO_SAVE=""
  local TEE_PID=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        sed -n '4,15p' "$0" | sed 's/^# \?//'
        exit 0
        ;;
      -v|--version)
        printf "SysInfo version %s\n" "$VERSION"
        exit 0
        ;;
      --no-color)
        R= G= Y= B= M= C= W= D= N=
        shift
        ;;
      -j|--json)
        JSON_MODE=1
        shift
        ;;
      -o|--output)
        output_file="$2"
        JSON_MODE=1
        shift 2
        ;;
      -t|--text-output)
        text_output_file="$2"
        shift 2
        ;;
      --no-save)
        NO_SAVE="yes"
        shift
        ;;
      -c|--check)
        check_commands
        printf "\n${C}Optional dependencies:${N}\n"
        check_optional
        exit 0
        ;;
      *)
        printf "${R}Unknown option:${N} %s\n" "$1" >&2
        printf "Use ${G}--help${N} for usage information.\n" >&2
        exit 1
        ;;
    esac
  done

  # Check required commands
  check_commands

  # Trap for clean exit
  trap '[[ -n "$TEE_PID" ]] && wait "$TEE_PID" 2>/dev/null; printf "\n${Y}Bye!${N}\n"; exit 0' INT TERM

  # JSON mode
  if [[ "$JSON_MODE" == "1" ]]; then
    if [[ -n "$output_file" ]]; then
      json_full_report > "$output_file"
      printf "${G}Report written to:${N} %s\n" "$output_file"
    else
      json_full_report
    fi
    exit 0
  fi

  # ── Interactive mode ────────────────────────────────────────

  # Create output directory
  mkdir -p output

  # Text output mode — tee everything to a file
  if [[ -n "$text_output_file" ]]; then
    local report_path="output/${text_output_file}"
    touch "$report_path"
    exec > >(tee -a "$report_path") 2>&1
    TEE_PID=$!
    printf "${G}All output saved to:${N} %s\n" "$report_path"
  fi

  local choice=""
  while true; do
    menu
    case "$choice" in
      1)
        banner
        if [[ "$NO_SAVE" != "yes" ]]; then
          local save_path="output/full_report_$(date '+%Y%m%d_%H%M%S').txt"
          _full_report_body | tee "$save_path"
          printf "\n${G}Report saved to:${N} %s\n" "$save_path"
        else
          _full_report_body
        fi
        printf "\n${D}Press Enter to continue...${N}"
        read -r
        ;;
      2)
        banner
        host_info
        dmidecode_system
        printf "\n"
        printf "${D}Press Enter to continue...${N}"
        read -r
        ;;
      3)
        banner
        cpu_info
        printf "\n"
        printf "${D}Press Enter to continue...${N}"
        read -r
        ;;
      4)
        banner
        memory_modules
        ram_summary
        printf "\n"
        printf "${D}Press Enter to continue...${N}"
        read -r
        ;;
      5)
        banner
        storage
        printf "\n"
        printf "${D}Press Enter to continue...${N}"
        read -r
        ;;
      6)
        banner
        gpu_info
        printf "\n"
        printf "${D}Press Enter to continue...${N}"
        read -r
        ;;
      7)
        banner
        os_info
        uptime_info
        printf "\n"
        printf "${D}Press Enter to continue...${N}"
        read -r
        ;;
      8)
        banner
        network_info
        printf "\n"
        printf "${D}Press Enter to continue...${N}"
        read -r
        ;;
      9)
        banner
        battery_info
        temperature_info
        printf "\n"
        printf "${D}Press Enter to continue...${N}"
        read -r
        ;;
      10)
        banner
        process_summary
        printf "\n"
        printf "${D}Press Enter to continue...${N}"
        read -r
        ;;
      s|S)
        local save_path="output/full_report_$(date '+%Y%m%d_%H%M%S').txt"
        banner
        _full_report_body | tee "$save_path"
        printf "\n${G}Report saved to:${N} %s\n" "$save_path"
        printf "\n"
        printf "${D}Press Enter to continue...${N}"
        read -r
        ;;
      q|Q)
        printf "${Y}Bye!${N}\n"
        exit 0
        ;;
      *)
        printf "${R}Invalid option:${N} %s\n" "$choice"
        sleep 1
        ;;
    esac
  done
}

main "$@"
