# SysInfo — Interactive System Information CLI

A colorful, interactive bash script that displays detailed system information — CPU, memory, storage, GPU, network, temperatures, battery, and more. Runs in interactive mode with a menu, or outputs JSON for scripting.

## Quick Start

```bash
chmod +x SysInfo.sh
./SysInfo.sh
```

No installation required. Just bash and a handful of common Linux utilities.

## Features

- **Interactive menu** — pick individual sections or dump everything
- **JSON export** — machine-readable output for scripts and monitoring tools
- **Auto-save** — full reports are automatically saved to `output/` with timestamps
- **Text logging** — `-t` flag tees all terminal output to a file
- **Color-coded** — section headers, labels, and status indicators (disable with `--no-color` or `NO_COLOR=1`)
- **Graceful degradation** — optional tools like `nvidia-smi`, `sensors`, `dmidecode` are skipped when unavailable
- **Portable** — pure bash, no dependencies beyond coreutils

## Usage

```
./SysInfo.sh [options]
```

### Options

| Flag | Description |
|------|-------------|
| `-h`, `--help` | Show help message |
| `-v`, `--version` | Show version |
| `--no-color` | Disable colored output (also respects `NO_COLOR=1`) |
| `-j`, `--json` | Output full system report as JSON (non-interactive) |
| `-o`, `--output FILE` | Write JSON report to FILE (implies `--json`) |
| `-t`, `--text-output FILE` | Tee all interactive output to `output/FILE` |
| `--no-save` | Disable automatic report saving to `output/` |
| `-c`, `--check` | List found/missing optional dependencies |

### Interactive Menu

When run without flags, SysInfo shows a numbered menu:

| Option | Description |
|--------|-------------|
| `1` | Everything — full report (auto-saved to `output/`) |
| `2` | Hostname + DMI system info |
| `3` | CPU model, cores, threads, frequencies |
| `4` | Memory modules (DMI) + RAM summary (`free -h`) |
| `5` | Block devices (`lsblk`) + disk usage (`df`) |
| `6` | GPU (PCI vendor + nvidia-smi stats) |
| `7` | OS release + kernel + uptime |
| `8` | IP addresses + DNS servers |
| `9` | Battery charge + sensor temperatures |
| `10` | Top 5 processes by memory |
| `s` | Save a timestamped full report to `output/` |
| `q` | Quit |

### Examples

```bash
# Interactive mode (full report auto-saves to output/)
./SysInfo.sh

# Quick JSON dump to stdout
./SysInfo.sh --json

# Save JSON report to a file
./SysInfo.sh --output system.json

# Log an entire interactive session
./SysInfo.sh --text-output mysession.log

# Full report without auto-saving
./SysInfo.sh --no-save

# Check which optional tools are installed
./SysInfo.sh --check
```

## Output Directory

When you run the interactive menu, an `output/` directory is created automatically. Full reports from option **1** and the **s** key are saved there as `full_report_YYYYMMDD_HHMMSS.txt`.

The directory is listed in `.gitignore` so saved reports won't be accidentally committed.

## What Each Section Shows

### 1. System Summary
Quick overview: hostname, OS name, kernel version, uptime.

### 2. Host & System
- `hostnamectl` output (static hostname, chassis, machine ID, boot ID)
- DMI data (sudo): manufacturer, product name, version, serial number, UUID, family

### 3. CPU
- Model name, socket count, total/logical cores, threads per core
- Min/max/scaling MHz, NUMA topology

### 4. Memory
- **Modules** (sudo): per-slot size, type, speed, manufacturer, locator
- **Summary**: total, used, free, shared, buff/cache, available (from `free -h`)

### 5. Storage
- Block devices: name, size, type, model, mount point (`lsblk`)
- Mounted filesystem usage (`df -h`)

### 6. GPU
- PCI VGA controller from `lspci`
- NVIDIA GPU stats (if nvidia-smi available): name, temperature, utilization, memory

### 7. OS & Uptime
- Full `uname -a`, PRETTY_NAME from `/etc/os-release`
- Human-readable uptime + load averages

### 8. Network
- Interface IPs (`ip -br addr`)
- DNS server addresses (`resolvectl status`)

### 9. Battery & Temperature
- Battery: capacity percentage + charging status (from sysfs)
- Temperatures: CPU cores, package, NVMe, GPU (from `sensors`)

### 10. Top Processes
- 5 most memory-hungry processes (from `ps aux --sort=-%mem`)

## JSON Output

The `--json` / `-o` flags produce a JSON document with all sections:

```json
{
  "hostname": "myhost",
  "os": "Linux Mint 22",
  "kernel": "6.8.0-124-generic",
  "uptime": "2 hours, 15 minutes",
  "host": { ... },
  "system_dmi": { ... },
  "cpu": { ... },
  "memory_modules": { ... },
  "memory_summary": { ... },
  "storage": { ... },
  "gpu": { ... },
  "os": { ... },
  "uptime": { ... },
  "network": { ... },
  "battery": { ... },
  "temperatures": { ... },
  "top_processes": { ... }
}
```

Pipe to `jq` for pretty-printing or filtering:
```bash
./SysInfo.sh --json | jq '.cpu'
```

## Dependencies

### Required (available on virtually every Linux system)
`hostname`, `grep`, `cut`, `tr`, `uname`, `uptime`, `ps`

### Optional
| Tool | Used for |
|------|----------|
| `lscpu` | CPU details (model, cores, MHz) |
| `lspci` | GPU PCI identification |
| `dmidecode` | DMI system info, memory modules (requires sudo) |
| `sensors` | CPU/GPU/NVMe temperatures |
| `nvidia-smi` | NVIDIA GPU stats |
| `ip` | Network interface addresses |
| `resolvectl` | DNS server addresses |
| `free` | RAM summary |
| `df` | Disk usage |
| `lsblk` | Block device listing |
| `perl` | JSON finalization (falls back to `sed -z`) |

## Exit Codes

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | Missing required dependency or unknown option |

## License

MIT — see [LICENSE](LICENSE).
