#!/usr/bin/env bash
# swarm-evolve の Drafter/Checker 独立性を構造的に隔離する(SWARM.md §2 既知の未機械化ギャップ:
# 「Drafterの主観的理由づけをCheckerに渡すこと」の禁止が現状prompt指示のみで機械強制が無い)。
# draft Markdown から指定した提案の `evidence`/`target`/`diff_type`/diff コードブロックのみを
# 機械的に抜き出し、`pattern`(Drafterの理由づけ)を含む地の文は一切出力しない。呼び出し側
# (swarm-evolve本体)はこのスクリプトの出力だけをCheckerへ渡す — draft全体やpattern文言を
# 手で編集して渡す余地を無くす。
# usage: extract-checker-input.sh <draft.md> <heading-substring>
set -euo pipefail

draft="${1:?usage: extract-checker-input.sh <draft.md> <heading-substring>}"
heading="${2:?usage: extract-checker-input.sh <draft.md> <heading-substring>}"
[ -f "$draft" ] || { echo "NOT_FOUND: draft file '$draft' does not exist" >&2; exit 1; }

python3 - "$draft" "$heading" <<'PYEOF'
import re, sys

draft_path, heading = sys.argv[1], sys.argv[2]
text = open(draft_path, encoding="utf-8").read()

# "## " 見出し単位でセクション分割 (draftの規約: 1提案 = 1つの "## 提案 N: ..." 見出し)
parts = re.split(r"(?m)^## ", text)
target = None
for p in parts[1:]:
    first_line = p.split("\n", 1)[0]
    if heading in first_line:
        target = "## " + p
        break

if target is None:
    print(f"NOT_FOUND: no '## ' heading contains '{heading}'", file=sys.stderr)
    sys.exit(1)

lines = target.split("\n")

KEEP_BULLETS = ("- **evidence**", "- **target**", "- **diff_type**")
DROP_BULLETS = ("- **pattern**",)

out = []
in_code = False
in_kept_bullet = False
for line in lines:
    stripped = line.strip()
    if stripped.startswith("```"):
        in_code = not in_code
        out.append(line)
        continue
    if in_code:
        out.append(line)
        continue
    if stripped.startswith(KEEP_BULLETS):
        in_kept_bullet = True
        out.append(line)
        continue
    if stripped.startswith(DROP_BULLETS):
        in_kept_bullet = False
        continue
    if stripped.startswith("- **") and not stripped.startswith(KEEP_BULLETS):
        # 未知のbullet(例: pattern以外の将来の新フィールド)は安全側に倒して除外する
        in_kept_bullet = False
        continue
    if in_kept_bullet:
        out.append(line)
        continue
    # bulletの外側の見出し行(## 提案 N: ...)自体は文脈として残す
    if line.startswith("## "):
        out.append(line)

result = "\n".join(out)
# evidence bullet と diff コードブロックはCheckerが判定するための最重要2要素であり、draftが
# proposed_diffの規約(pattern/evidence/target/diff_type/proposed_diff)に従っていない場合
# (例: 散文の「実装概要」節で書かれている等)、この2つが欠落したまま無警告でCheckerへ渡ってしまう
# (実際にこのミッションのround 11 draftで発生した自己適用ギャップ)。欠落時はstderrへ警告する
# (fail-openで出力自体は続ける — Checker側が気づいて呼び出し元へ差し戻す判断材料にする)。
has_evidence = any(l.strip().startswith("- **evidence**") for l in out)
has_code_block = any(l.strip().startswith("```") for l in out)
if not has_evidence or not has_code_block:
    missing = []
    if not has_evidence:
        missing.append("evidence bullet")
    if not has_code_block:
        missing.append("diff code block")
    print(
        f"WARNING: extraction for '{heading}' is missing {' and '.join(missing)} — "
        f"draft may not follow the pattern/evidence/target/diff_type/proposed_diff schema "
        f"(swarm-evolve/SKILL.md Step 2). Checker input may be insufficient to judge.",
        file=sys.stderr,
    )

print(result)
PYEOF
