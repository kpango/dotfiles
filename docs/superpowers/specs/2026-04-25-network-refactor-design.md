# Network Directory Refactoring Design

## Overview

The `network/` directory currently contains a mix of Sysctl configurations, NetworkManager dispatcher scripts, DNS configurations, and general utility scripts at the root level. This structure makes it difficult to locate specific configurations. This design aims to organize the `network/` directory into logical, technology-based subdirectories.

## Architecture & Implementation

We will create the following subdirectory structure inside `network/` and distribute the existing files accordingly:

### 1. `network/sysctl/`

Focuses purely on kernel parameter tuning.

- `sysctl.conf`
- `sysctl2.conf`
- `tr-sysctl.conf`
- `unifi-sysctl.conf`

### 2. `network/nm/`

Focuses on NetworkManager configurations, connection profiles, and dispatcher scripts.

- `NetworkManager.conf`
- `NetworkManager-dispatcher.service`
- `nmcli-bond-auto-connect.sh`
- `nmcli-wifi-eth-autodetect.sh`
- `desk/` (Moves the entire `desk` directory containing `.nmconnection` files and udev rules into `nm/desk/`)

### 3. `network/dns/`

Focuses on local DNS resolution and caching.

- `dnsmasq.conf`
- `resolv.dnsmasq.conf`

### 4. `network/unifi/`

Focuses on Ubiquiti Unifi gateway provisioning configurations.

- `config.gateway.json`

### 5. `network/scripts/`

Focuses on standalone bash utilities for network management.

- `mac.sh`
- `mtu.sh`
- `ntp.sh`

## Testing Strategy

This refactor primarily consists of `git mv` operations.
Validation will involve verifying the directory tree against the planned structure to ensure no files were lost or misplaced.
If any Makefiles or installation scripts reference these files via hardcoded paths, those scripts will also need to be updated.
