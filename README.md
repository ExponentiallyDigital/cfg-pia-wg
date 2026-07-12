# pia-wireguard-cfg

[![Release](https://img.shields.io/github/v/release/ExponentiallyDigital/pia-wireguard-cfg?style=flat-square&color=blue)](https://github.com/ExponentiallyDigital/pia-wireguard-cfg/releases)
[![Linux](https://img.shields.io/badge/Platform-Linux-FCC624?style=flat-square&logo=linux&logoColor=black)](https://www.linux.org/)
[![Windows](https://img.shields.io/badge/Platform-Windows-0078D4?style=flat-square&logo=windows&logoColor=white)](https://www.microsoft.com/)
[![License](https://img.shields.io/github/license/ExponentiallyDigital/pia-wireguard-cfg?style=flat-square)](https://github.com/ExponentiallyDigital/pia-wireguard-cfg/blob/main/LICENSE)
[![Downloads](https://img.shields.io/github/downloads/ExponentiallyDigital/pia-wireguard-cfg/total?style=flat-square&color=success)](https://github.com/ExponentiallyDigital/pia-wireguard-cfg/releases)
[![Total Commits](https://img.shields.io/github/commit-activity/t/ExponentiallyDigital/pia-wireguard-cfg?style=flat-square&color=blueviolet)](https://github.com/ExponentiallyDigital/pia-wireguard-cfg/commits/main)
[![Top Language](https://img.shields.io/github/languages/top/ExponentiallyDigital/pia-wireguard-cfg?style=flat-square&color=orange)](https://github.com/ExponentiallyDigital/pia-wireguard-cfg)
[![Last Commit](https://img.shields.io/github/last-commit/ExponentiallyDigital/pia-wireguard-cfg?style=flat-square&color=important)](https://github.com/ExponentiallyDigital/pia-wireguard-cfg/commits/main)
[![Code Size](https://img.shields.io/github/languages/code-size/ExponentiallyDigital/pia-wireguard-cfg?style=flat-square&color=lightgrey)](https://github.com/ExponentiallyDigital/pia-wireguard-cfg)

A lightweight command-line tool written in Go that generates a ready-to-use WireGuard configuration file for the Private Internet Access (PIA) VPN service. It authenticates with PIA's official provisioning API, selects the lowest-latency server in your chosen region, generates a fresh WireGuard keypair, and writes a complete `.conf` file to your Windows desktop or current directory on Android.

## Why use this?

Manually creating a PIA WireGuard configuration requires authenticating against multiple APIs, parsing server lists, performing key exchange, and assembling the config by hand. **pia-wireguard-cfg** automates the entire process end-to-end in a single command.

- **No manual API calls:** the full PIA WireGuard provisioning flow is handled automatically
- **Fresh keypair every run:** a new WireGuard keypair is cryptographically generated each time
- **Lowest-latency server selection:** TCP latency is measured against all available servers in the region before connecting
- **Router and Android compatible:** config files are written with Unix line endings as required by WireGuard
- **No credentials stored:** your PIA password is entered interactively and never written to disk
- **Cross-platform:** runs on Windows 11 and Android (via Termux)

## Features

- **Automatic server selection:** measures TCP latency to all WireGuard servers in the chosen region and selects the fastest one
- **Full region support:** works with any PIA region -- use `-list-regions` to display all options
- **Interactive or flag-driven:** supply username and region via command-line flags or be prompted interactively for each
- **Configurable DNS:** use any DNS servers you choose, with Quad9 as the default
- **Verbose diagnostic mode:** optionally prints server IP, CN, measured latency, and raw PIA registration response for troubleshooting
- **Safe overwrite handling:** prompts before overwriting an existing config file
- **Single binary:** compiles to a single executable with no runtime dependencies
- **Android/Termux support:** works on ARM64 Android devices with correct DNS and TLS handling for the Android environment

## Requirements

- Go 1.21 or later (for building)
- Windows 11 or Android (via Termux) for running
- A valid Private Internet Access account with an active subscription
- Android only: `pkg install ca-certificates` in Termux

## Installation

Clone the repository and build both binaries using the included build script:

```
git clone https://github.com/ExponentiallyDigital/pia-wireguard-cfg.git
cd pia-wireguard-cfg
go mod tidy
build.bat
```

This produces:

- `pia-wireguard-cfg.exe` -- Windows binary
- `pia-wireguard-cfg` -- Linux/Android ARM64 binary

Both binaries can be placed anywhere on your system. No installer is required.

## Android/Termux setup

1. Install Termux from [F-Droid](https://f-droid.org/packages/com.termux/) (not the Play Store version)
2. In Termux, install CA certificates: `pkg install ca-certificates`
3. Transfer `pia-wireguard-cfg` to your device (via USB, `scp`, or any file manager)
4. In Termux, make it executable: `chmod +x pia-wireguard-cfg`
5. Run it from your Termux home directory (`~/`) so the output file is written to an accessible location

## Usage

**Windows:**

```
pia-wireguard-cfg.exe [-username PIA_username] [-region region_id] [-list-regions]
                      [-dns "dns_servers"] [-verbose] [-help] [-?]
```

**Android/Termux:**

```
./pia-wireguard-cfg [-username PIA_username] [-region region_id] [-list-regions]
                    [-dns "dns_servers"] [-verbose] [-help]
```

With no arguments, you will be prompted interactively for the region, username, and password.

## Command-line options

| Option                          | Description                                                                                                                                              |
| ------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-username`                     | Your PIA account username (e.g. `p1234567`). If omitted you will be prompted interactively.                                                              |
| `-region`                       | PIA region ID to connect through (e.g. `aus_melbourne`). If omitted you will be prompted interactively. Run `-list-regions` to see all valid region IDs. |
| `-list-regions`                 | Prints all available PIA regions and their WireGuard server counts, sorted alphabetically, then exits. Does not require credentials.                     |
| `-dns`                          | DNS servers to write into the config file, comma-separated. Default: `9.9.9.9, 149.112.112.112` (Quad9).                                                 |
| `-verbose`                      | Prints diagnostic output to stderr: resolved server IP and CN, measured latency, and raw PIA registration response.                                      |
| `-help` / `-?` / `/help` / `/?` | Shows the help message and exits.                                                                                                                        |

## Examples

Generate a config for Melbourne, Australia, prompting for all credentials:

```
pia-wireguard-cfg.exe -region aus_melbourne
```

Supply username on the command line (password is always prompted):

```
pia-wireguard-cfg.exe -username p1234567 -region aus_melbourne
```

Use a different region:

```
pia-wireguard-cfg.exe -username p1234567 -region us_new_york_city
```

Use Cloudflare DNS instead of the default Quad9:

```
pia-wireguard-cfg.exe -username p1234567 -region aus_melbourne -dns "1.1.1.1, 1.0.0.1"
```

Use Google DNS with verbose output for troubleshooting:

```
pia-wireguard-cfg.exe -username p1234567 -region aus_melbourne -dns "8.8.8.8, 8.8.4.4" -verbose
```

Display all available PIA regions before choosing one:

```
pia-wireguard-cfg.exe -list-regions
```

## DNS options

The default DNS servers are Quad9, a privacy-focused, malware-blocking resolver:

| Server          | Address           |
| --------------- | ----------------- |
| Quad9 primary   | `9.9.9.9`         |
| Quad9 secondary | `149.112.112.112` |

Common alternatives:

| Provider   | Primary   | Secondary |
| ---------- | --------- | --------- |
| Cloudflare | `1.1.1.1` | `1.0.0.1` |
| Google     | `8.8.8.8` | `8.8.4.4` |

Pass multiple servers as a quoted comma-separated string: `-dns "1.1.1.1, 1.0.0.1"`

## Output

The generated config file is written to a platform-specific location:

| Platform       | Output path                                     |
| -------------- | ----------------------------------------------- |
| Windows        | `%USERPROFILE%\Desktop\pia-<region>.conf`       |
| Android/Termux | `<current working directory>/pia-<region>.conf` |

For example, selecting region `aus_melbourne` produces `pia-aus_melbourne.conf`. If a file with that name already exists, you will be prompted before it is overwritten.

The config file follows this structure, with all dynamic fields populated from the PIA registration response:

```ini
[Interface]
PrivateKey = <freshly generated private key>
Address    = <client IP assigned by PIA>
DNS        = <from -dns flag or default>
MTU        = 1420

[Peer]
PublicKey           = <server public key from PIA>
Endpoint            = <server IP:port from PIA>
PersistentKeepalive = 25
AllowedIPs          = 0.0.0.0/0
```

## Authentication

- Your PIA password is **always** entered interactively at runtime and is **never** stored, logged, or written to disk
- Credentials are used solely to obtain a short-lived PIA authentication token for the WireGuard key registration step
- The WireGuard private key is written only to the output `.conf` file -- treat this file as a secret

## How it works

1. Fetches the PIA server list from `serverlist.piaservers.net/vpninfo/servers/v6`
2. Filters servers to the chosen region and measures TCP latency to port 1337 on each candidate
3. Authenticates against the PIA token API using your credentials to obtain a short-lived token
4. Generates a fresh WireGuard keypair using `golang.org/x/crypto/curve25519` with correct RFC 7748 scalar clamping
5. Fetches PIA's CA certificate dynamically from the PIA manual-connections repository (always current, never hardcoded)
6. Registers the generated public key with the lowest-latency server via its local HTTPS API (port 1337), using PIA's own CA certificate for TLS verification
7. Assembles the complete WireGuard config from the registration response and writes it to the output path

This follows the same provisioning flow as PIA's official open-source manual connection scripts at [github.com/pia-foss/manual-connections](https://github.com/pia-foss/manual-connections).

## Technical details

- **Key generation:** uses `golang.org/x/crypto/curve25519` directly; no dependency on the `wg` binary or kernel WireGuard modules
- **PIA CA certificate:** fetched dynamically at runtime from the PIA manual-connections repository so it is always current; never hardcoded
- **TLS:** the port 1337 registration API uses HTTPS with PIA's own CA certificate and `ServerName` set to the server's CN from the server list
- **Android DNS:** Android does not run a local DNS resolver, so all HTTP clients and TCP latency probes use a custom dialer that bypasses the system resolver and uses Google DNS (`8.8.8.8`) directly
- **Android TLS:** Android does not store CA certificates in standard Linux locations; the app loads certificates from all known locations including the Termux-specific path (`/data/data/com.termux/files/usr/etc/tls/cert.pem`) which is hardcoded because the `$PREFIX` environment variable is not reliably inherited by child processes on Android
- **Line endings:** the output config file always uses Unix line endings (`\n`) regardless of platform
- **Timeouts:** 10-second timeout on all HTTP clients; 2-second timeout on TCP latency probes
- **Cross-compilation:** both binaries are built from Windows using `CGO_ENABLED=0` via `build.bat`

## Contributing

Contributions are welcome. To contribute:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Ensure the code passes `go vet` cleanly
5. Submit a pull request with a clear description of the change

## Bugs and feature requests

Found a bug or want to request a feature?
[Open an issue here](https://github.com/ExponentiallyDigital/pia-wireguard-cfg/issues)

## Support

This tool is unsupported and may cause objects in mirrors to be closer than they appear. Batteries not included.

## License

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program. If not, see <https://www.gnu.org/licenses/>.

Copyright (C) 2026 Andrew Newbury
