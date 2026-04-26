# Network Directory Refactoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Organize the `network/` directory into logical, technology-based subdirectories and update dependent scripts.

**Architecture:** We are categorizing scattered network files into `sysctl`, `nm`, `dns`, `unifi`, and `scripts` folders. Hardcoded paths in `alias` and `Makefile.d/arch.mk` will be updated to match the new structure.

**Tech Stack:** Bash, Make.

---

### Task 1: Create Subdirectories

**Files:**

- Create: `network/sysctl/`
- Create: `network/nm/`
- Create: `network/dns/`
- Create: `network/unifi/`
- Create: `network/scripts/`

- [ ] **Step 1: Create the directories**

```bash
mkdir -p network/sysctl network/nm network/dns network/unifi network/scripts
```

- [ ] **Step 2: Commit**

```bash
git add network/
git commit -m "chore(network): create logical subdirectories"
```

---

### Task 2: Move Files to Subdirectories

**Files:**

- Modify: `network/*`

- [ ] **Step 1: Move Sysctl files**

```bash
git mv network/sysctl.conf network/sysctl2.conf network/tr-sysctl.conf network/unifi-sysctl.conf network/sysctl/
```

- [ ] **Step 2: Move NetworkManager files**

```bash
git mv network/NetworkManager.conf network/NetworkManager-dispatcher.service network/nmcli-bond-auto-connect.sh network/nmcli-wifi-eth-autodetect.sh network/nm/
git mv network/desk network/nm/desk
```

- [ ] **Step 3: Move DNS files**

```bash
git mv network/dnsmasq.conf network/resolv.dnsmasq.conf network/dns/
```

- [ ] **Step 4: Move Unifi files**

```bash
git mv network/config.gateway.json network/unifi/
```

- [ ] **Step 5: Move Script files**

```bash
git mv network/mac.sh network/mtu.sh network/ntp.sh network/scripts/
```

- [ ] **Step 6: Commit**

```bash
git commit -m "refactor(network): move files into logical subdirectories"
```

---

### Task 3: Update paths in `alias` file

**Files:**

- Modify: `alias`

- [ ] **Step 1: Update path mapping**
      Replace references to `network/sysctl.conf` with `network/sysctl/sysctl.conf` inside the `alias` file.

```bash
sed -i 's|network/sysctl.conf|network/sysctl/sysctl.conf|g' alias
```

- [ ] **Step 2: Verify modification**
      Run: `grep -E 'network/sysctl/sysctl.conf' alias`
      Expected: Output showing the updated mount paths.

- [ ] **Step 3: Commit**

```bash
git add alias
git commit -m "fix(alias): update paths for relocated sysctl config"
```

---

### Task 4: Update paths in `Makefile.d/arch.mk`

**Files:**

- Modify: `Makefile.d/arch.mk`

- [ ] **Step 1: Update map paths**
      Replace the old `network/` paths in the mapping blocks with the new nested paths.

```bash
sed -i -e 's|network/dnsmasq.conf|network/dns/dnsmasq.conf|g' \
       -e 's|network/NetworkManager.conf|network/nm/NetworkManager.conf|g' \
       -e 's|network/resolv.dnsmasq.conf|network/dns/resolv.dnsmasq.conf|g' \
       -e 's|network/sysctl.conf|network/sysctl/sysctl.conf|g' \
       -e 's|network/NetworkManager-dispatcher.service|network/nm/NetworkManager-dispatcher.service|g' \
       -e 's|network/nmcli-wifi-eth-autodetect.sh|network/nm/nmcli-wifi-eth-autodetect.sh|g' \
       -e 's|network/nmcli-bond-auto-connect.sh|network/nm/nmcli-bond-auto-connect.sh|g' \
       -e 's|network/desk/|network/nm/desk/|g' Makefile.d/arch.mk
```

- [ ] **Step 2: Verify modifications**
      Run: `grep -E 'network/nm|network/dns|network/sysctl' Makefile.d/arch.mk`
      Expected: Output showing the updated `Makefile` mappings.

- [ ] **Step 3: Commit**

```bash
git add Makefile.d/arch.mk
git commit -m "fix(arch): update hardcoded network paths to match refactored structure"
```
