#!/usr/bin/env python3
"""
f2886q-apply.py — idempotent reproduction of the F2886Q IPv6 PD configuration
required by the NURO sub-/64 scheme (see memory udm-pro-nuro-v6-ndp-proxy).

Enforced state on the ZTE F2886Q (https://10.0.1.1/, admin / pass nuro-f2886q):

  LAN > LAN > IPv6
    - Static Prefix "UDM_PD" = 240d:f:fc4:29f0::/60
    - DHCPv6 Server > PrefixMode = Manual, IsDelegation ticked for UDM_PD
    - RA Service      > PrefixMode = Manual, IsDelegation ticked for UDM_PD

Why this script exists: the ONU is an external device so dotfiles cannot
touch it with the usual tar+ssh. If the ONU is factory reset, swapped, or
has its firmware updated, the Static Prefix and Manual settings have to be
re-applied by hand. This script replays them exactly, matching the human
UI flow and skipping fields that are already correct.

Modes:
  plan   — read-only: print current F2886Q state vs desired state, no writes
  apply  — write changes, atomic per section; skip sections already correct

Driven by `make unifi/f2886q-plan` / `make unifi/f2886q-apply`, which wrap
venv setup and credential fetch. The script itself can be invoked directly
once a venv with python-playwright is on PATH; see --help.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass

try:
    from playwright.sync_api import sync_playwright, Page
except ImportError:
    sys.stderr.write(
        "playwright not importable. Use `make unifi/f2886q-apply`, which sets\n"
        "up an ephemeral venv, instead of running this script directly.\n"
    )
    sys.exit(2)


URL = "https://10.0.1.1/"
USERNAME = "admin"
# Known Chrome locations in preference order. python-playwright can also use
# its bundled Chromium if "chromium" is specified via --browser; local Chrome
# avoids the ~150 MB extra download.
CHROME_PATHS = (
    "/opt/google/chrome-beta/chrome",
    "/opt/google/chrome/chrome",
    "/opt/google/chrome-stable/chrome",
    "/usr/bin/google-chrome",
    "/usr/bin/google-chrome-stable",
    "/usr/bin/chromium",
    "/usr/bin/chromium-browser",
)


@dataclass
class Desired:
    """Everything we want enforced on the F2886Q."""
    alias: str = "UDM_PD"
    prefix: str = "240d:f:fc4:29f0::"
    prefix_len: str = "60"


def find_chrome() -> str:
    for p in CHROME_PATHS:
        if os.path.isfile(p) and os.access(p, os.X_OK):
            return p
    sys.stderr.write(
        "no system Chrome found at any of:\n  " + "\n  ".join(CHROME_PATHS) + "\n"
        "install chrome / chromium, or point --browser-exec at a working binary.\n"
    )
    sys.exit(3)


def fetch_password() -> str:
    """Read the F2886Q admin password from `pass`.

    Isolating this in one place keeps the plaintext password from touching
    the Python arg vector or the script's docstring. The subprocess sees
    the secret via its stdout only; nothing is written to disk.
    """
    try:
        out = subprocess.run(
            ["pass", "show", "nuro-f2886q"],
            check=True, capture_output=True, text=True,
        ).stdout
    except (FileNotFoundError, subprocess.CalledProcessError) as e:
        sys.stderr.write(f"failed to read `pass show nuro-f2886q`: {e}\n")
        sys.exit(4)
    pw = out.strip().splitlines()[0] if out.strip() else ""
    if not pw:
        sys.stderr.write("empty password from pass show nuro-f2886q\n")
        sys.exit(4)
    return pw


# ----------------------------------------------------------------------------
# UI navigation helpers — mirror the human click path that was reverse-
# engineered during the 2026-10-20 setup session (see trajectory logs).
# ----------------------------------------------------------------------------

def login(page: Page, password: str) -> None:
    page.goto(URL, wait_until="networkidle", timeout=20000)
    page.fill("#Frm_Username", USERNAME)
    page.fill("#Frm_Password", password)
    page.click("#LoginId")
    page.wait_for_load_state("networkidle", timeout=20000)
    page.wait_for_timeout(2000)


def nav_lan_ipv6(page: Page) -> None:
    page.click("#localnet"); page.wait_for_timeout(700)
    page.click("#lanConfig"); page.wait_for_timeout(700)
    page.click("#lanMgrIpv6"); page.wait_for_timeout(2500)
    for bar in ("PrefixMgrBar", "IPv6DHCPServerBar", "RAServiceBar"):
        try:
            page.click(f"#{bar}", timeout=3000)
            page.wait_for_timeout(600)
        except Exception:
            pass
    page.wait_for_timeout(1500)


def read_state(page: Page, desired: Desired) -> dict:
    """Snapshot the three UI knobs that we care about."""
    static_prefix_present = page.evaluate(
        """({alias, prefix}) => {
            // Static Prefix section lists entries with id=instName_PrefixMgr:N
            // and the title attribute holding the alias (unique).
            return !!Array.from(document.querySelectorAll('[id^=instName_PrefixMgr]'))
                .find(el => (el.getAttribute('title') || '') === alias);
        }""",
        {"alias": desired.alias, "prefix": desired.prefix},
    )
    dhcp_mode = page.evaluate(
        """() => (document.querySelector('select[name="PrefixMode:IPv6DHCPServer"]') || {}).value"""
    ) or "Auto"
    ra_mode = page.evaluate(
        """() => (document.querySelector('select[name="PrefixMode:RAService"]') || {}).value"""
    ) or "Auto"
    # IsDelegation lives inside the PrefixPool table that each section renders;
    # same id in both tables. Collect every non-template checkbox.
    delegations = page.evaluate(
        """() => Array.from(document.querySelectorAll('input[type=checkbox][id^=IsDelegation]'))
            .filter(c => c.closest('.colorTblRow')?.id !== 'template_PrefixPool')
            .map(c => ({ id: c.id, parent: c.closest('.colorTblRow')?.id, checked: c.checked }))
        """
    ) or []
    delegated = all(d["checked"] for d in delegations) if delegations else False
    return {
        "static_prefix_present": static_prefix_present,
        "dhcp_mode": dhcp_mode,
        "ra_mode": ra_mode,
        "delegations": delegations,
        "delegated_all": delegated,
    }


def add_static_prefix(page: Page, desired: Desired) -> None:
    page.fill('input[name="Alias:PrefixMgr:0"]', desired.alias)
    page.fill('input[name="Prefix:PrefixMgr:0"]', desired.prefix)
    page.fill('input[name="PrefixLen:PrefixMgr:0"]', desired.prefix_len)
    page.wait_for_timeout(500)
    page.click('button[id="Btn_apply_PrefixMgr:0"]', timeout=5000)
    page.wait_for_timeout(3000)


def tick_delegation(page: Page, bar_id: str) -> None:
    """Tick IsDelegation:0 under the given section's PrefixPool table."""
    page.evaluate(
        f"""(barId) => {{
            const bar = document.getElementById(barId);
            if (!bar) return;
            let el = bar.nextElementSibling;
            while (el && !el.classList.contains('collapBarWithDataTrans')) {{
                const cbs = el.querySelectorAll('input[type=checkbox][id^=IsDelegation]');
                for (const cb of cbs) {{
                    const row = cb.closest('.colorTblRow');
                    if (row && row.id !== 'template_PrefixPool') {{
                        cb.checked = true;
                        cb.dispatchEvent(new Event('change', {{bubbles: true}}));
                        cb.dispatchEvent(new Event('click', {{bubbles: true}}));
                        return;
                    }}
                }}
                el = el.nextElementSibling;
            }}
        }}""",
        bar_id,
    )
    page.wait_for_timeout(500)


def set_prefix_mode_manual(page: Page, select_name: str, bar_id: str, apply_btn_id: str) -> None:
    try:
        page.select_option(f'select[name="{select_name}"]', value="Manual", timeout=5000)
    except Exception:
        page.select_option(f'select[name="{select_name}"]', label="マニュアル")
    page.wait_for_timeout(2000)
    tick_delegation(page, bar_id)
    page.click(f'input[id="{apply_btn_id}"]', timeout=5000)
    page.wait_for_timeout(4000)


# ----------------------------------------------------------------------------
# Entrypoint
# ----------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(
        description="Idempotent F2886Q IPv6 PD configurator.",
        epilog="Prefer `make unifi/f2886q-plan` / `make unifi/f2886q-apply`.",
    )
    ap.add_argument("mode", choices=("plan", "apply"), help="plan prints diff only; apply writes.")
    ap.add_argument("--browser-exec", default=None, help="Path to Chrome/Chromium (default: autodetect)")
    args = ap.parse_args()

    desired = Desired()
    chrome = args.browser_exec or find_chrome()
    password = fetch_password()

    with sync_playwright() as p:
        browser = p.chromium.launch(
            executable_path=chrome, headless=True,
            args=["--ignore-certificate-errors", "--no-sandbox"],
        )
        ctx = browser.new_context(ignore_https_errors=True, viewport={"width": 1600, "height": 2500})
        page = ctx.new_page()

        login(page, password)
        nav_lan_ipv6(page)
        before = read_state(page, desired)

        print("current F2886Q state:")
        print(json.dumps(before, indent=2, ensure_ascii=False))

        actions: list[str] = []
        if not before["static_prefix_present"]:
            actions.append(f"add static prefix {desired.alias}={desired.prefix}/{desired.prefix_len}")
        if before["dhcp_mode"] != "Manual" or not before["delegated_all"]:
            actions.append("set DHCPv6 Server PrefixMode=Manual, tick UDM_PD delegation")
        if before["ra_mode"] != "Manual" or not before["delegated_all"]:
            actions.append("set RA Service PrefixMode=Manual, tick UDM_PD delegation")

        if not actions:
            print("already converged; nothing to do.")
            browser.close()
            return 0

        print("\nplanned actions:")
        for a in actions:
            print(f"  - {a}")

        if args.mode == "plan":
            browser.close()
            return 0

        print("\napplying...")
        if not before["static_prefix_present"]:
            add_static_prefix(page, desired)
            # Re-expand bars after the save re-rendered the section tree.
            nav_lan_ipv6(page)

        if before["dhcp_mode"] != "Manual" or not before["delegated_all"]:
            set_prefix_mode_manual(
                page,
                select_name="PrefixMode:IPv6DHCPServer",
                bar_id="IPv6DHCPServerBar",
                apply_btn_id="Btn_apply_IPv6DHCPServer",
            )

        if before["ra_mode"] != "Manual" or not before["delegated_all"]:
            set_prefix_mode_manual(
                page,
                select_name="PrefixMode:RAService",
                bar_id="RAServiceBar",
                apply_btn_id="Btn_apply_RAService",
            )

        after = read_state(page, desired)
        print("\npost-apply state:")
        print(json.dumps(after, indent=2, ensure_ascii=False))

        browser.close()

        ok = (
            after["static_prefix_present"]
            and after["dhcp_mode"] == "Manual"
            and after["ra_mode"] == "Manual"
            and after["delegated_all"]
        )
        return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
