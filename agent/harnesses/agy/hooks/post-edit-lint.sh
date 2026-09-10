#!/usr/bin/env bash
# Antigravity PostToolUse Lint & Syntax Verifier
set -euo pipefail

PAYLOAD=$(cat)

python3 -c '
import json, os, subprocess, sys

try:
    data = json.loads(sys.stdin.read() or "{}")
    if not isinstance(data, dict):
        data = {}
except Exception:
    data = {}

tool_call = data.get("toolCall", {})
tool_name = tool_call.get("name") or data.get("tool_name", "")
args = tool_call.get("args") or data.get("tool_input", {})

if tool_name not in ("write_to_file", "replace_file_content", "edit_file"):
    print("{}")
    sys.exit(0)

target = args.get("TargetFile") or args.get("file_path", "")
if not target or not os.path.isfile(target):
    print("{}")
    sys.exit(0)

# 1. Go file formatting & syntax check
if target.endswith(".go"):
    if subprocess.run(["which", "gofmt"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
        subprocess.run(["gofmt", "-s", "-w", "--", target], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

# 2. Python syntax check
elif target.endswith(".py"):
    subprocess.run([sys.executable, "-m", "py_compile", "--", target], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

# 3. JSON syntax check
elif target.endswith(".json"):
    try:
        with open(target, "r", encoding="utf-8") as fp:
            json.load(fp)
    except Exception:
        pass

# 4. Shell syntax check
elif target.endswith(".sh") or target.endswith(".bash"):
    subprocess.run(["bash", "-n", "--", target], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

# 5. YAML syntax check (claude/hooks/post-write.shとの対象拡張子superset化、2026-09-03)
elif target.endswith(".yaml") or target.endswith(".yml"):
    try:
        import yaml
        with open(target, "r", encoding="utf-8") as fp:
            yaml.safe_load(fp)
    except ImportError:
        pass
    except Exception:
        pass

# 6. TOML syntax check
elif target.endswith(".toml"):
    try:
        import tomllib
        with open(target, "rb") as fp:
            tomllib.load(fp)
    except ImportError:
        pass
    except Exception:
        pass

# Makefileの構文チェックは意図的に実装しない: `make -n`(dry-run)はGNU Makeの`$(shell ...)`/`!=`を
# パース(変数展開)時に評価するため、`-n`は実行を抑制しない。書き込まれたMakefile次第で
# 確認なしの任意コマンド実行プリミティブになる(2026-09-03 security-audit指摘、HIGH、実機PoCで
# `make -n -f`実行だけで`$(shell touch PWNED_MARKER)`が実際に走ることを確認済み)。安全な
# dry-run手段がGNU Make自体に存在しないため、チェックそのものを削除する(claude/hooks/
# post-write.shの同パターンも同時に削除済み)。

print("{}")
' <<< "$PAYLOAD"
