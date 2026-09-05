"""SessionStart時のメモリコンテキスト合成ロジックの正典実装。

claude/hooks/session-start.sh・agy/hooks/session-start.sh は独立に「MEMORY.md索引 + トピック別
*.mdファイル + ローカルoverrideファイル」を1つのcontext文字列へ合成するロジックを再実装しており、
以下のような意図的/非意図的な差異が蓄積していた:

- claude: メモリdirは `~/.claude/memory` の1つのみ。ローカルoverrideは `CLAUDE.local.md` のみ、
  行数制限なし(cat全文)。トピックファイルにヘッダなし(`---`区切りのみ)。
- agy: メモリdirは `~/.gemini/memory` と `~/.claude/memory` の2つ(ファイル名で重複排除)。
  ローカルoverrideは `AGENTS.local.md`・`CLAUDE.local.md` の両方(存在する分だけ両方とも追加)、
  各150行まで。トピックファイルに `## Memory: <fname>` ヘッダあり。MEMORY.md索引にも
  `# Memory Index (<dirname>/MEMORY.md)` ヘッダあり(複数dir区別のため)。

判定ロジック(どのdir/fileをどの順で読むか)自体は同じ目的の実装が2回独立に発散するリスクを持つため、
本モジュールへ統合する(2026-09-03、hooks本体統合Phase1-3のsecurity-gate/vald-law/graphify-hintと
同じ設計判断)。一方でヘッダ有無・行数制限・ローカルoverrideファイル名リストは各ツールの既存の
意図的な差異としてパラメータ化して保持する(scope_mode等と同じ精神)。
"""
from __future__ import annotations

import os
import subprocess


def _locale_sort(files: list[str]) -> list[str]:
    """旧bash実装(claude/agyとも `find ... -print0 | sort -z`)と同じ順序を返す。

    GNU `sort` はホストのlocale照合順序(典型的なen_US.UTF-8等では大文字小文字の別だけでなく
    `-`/`_`のような記号の重みも軽く扱う辞書順)を使う。Python純正の `sorted()` はUnicode符号点順
    (大文字が小文字より前、`-`と`_`の相対順も符号点依存)になり、実データに対しこの2つが異なる
    順序を返すことを実測で確認した(例: "BENCHMARK_*.md"/"benchmark_*.md"の前後関係、
    "feedback_x"/"feedback-y"の前後関係が入れ替わる)。手元でlocale照合ルールを再実装するより、
    実際に`sort`コマンドを呼んでホストのlocaleへ委譲する方が正確かつ機種非依存(ホストのlocale
    設定が変わってもそれに追従する)。`sort`が使えない場合のみ大小文字無視の近似(`str.lower`)へ
    fallbackする(表示順序のみへの影響、内容の欠落・重複ではないため致命的ではない)。
    """
    if not files:
        return []
    try:
        proc = subprocess.run(
            ["sort"], input="\n".join(files), capture_output=True, text=True, timeout=5,
        )
        if proc.returncode == 0:
            sorted_files = [line for line in proc.stdout.split("\n") if line]
            if sorted(sorted_files) == sorted(files):
                return sorted_files
    except Exception:
        pass
    return sorted(files, key=str.lower)


def _read_head(path: str, max_lines: int | None) -> str:
    """先頭max_lines行を返す(Noneなら全文)。読めなければ空文字。"""
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            if max_lines is None:
                return f.read().strip()
            lines = []
            for i, line in enumerate(f):
                if i >= max_lines:
                    break
                lines.append(line)
            return "".join(lines).strip()
    except Exception:
        return ""


def compose_memory_context(
    memory_dirs: list[str],
    local_files: list[str],
    cwd: str,
    index_head: int = 200,
    topic_head: int = 150,
    local_head: int | None = None,
    multi_dir_labels: bool = False,
    local_all_matches: bool = False,
) -> dict:
    """メモリコンテキストを合成する。

    memory_dirs: 走査するディレクトリのリスト(順序通り走査)。同名のトピックファイルは
      最初に見つかったdirのものを採用し、以降のdirでは重複排除する(agyの既存dedup設計)。
    local_files: cwd直下で確認するローカルoverrideファイル名の候補リスト。
      local_all_matches=False(claude方式)なら最初に見つかった1件のみ、
      local_all_matches=True(agy方式)なら存在する分だけ全て追加する。
    index_head/topic_head: MEMORY.md索引・トピックファイルそれぞれの先頭何行まで読むか。
    local_head: ローカルoverrideファイルの先頭何行まで読むか(Noneなら全文 — claudeの既存挙動)。
    multi_dir_labels: Trueならメモリ索引に"# Memory Index (<dir>/MEMORY.md)"ヘッダ・
      トピックファイルに"## Memory: <fname>"ヘッダを付与する(agy方式、複数dir区別のため)。
      Falseならヘッダなしで"---"区切りのみ(claude方式)。

    戻り値: {"context": str, "file_count": int, "byte_count": int}
    """
    context_parts: list[str] = []
    loaded_files: set[str] = set()
    file_count = 0

    for mem_dir in memory_dirs:
        if not mem_dir or not os.path.isdir(mem_dir):
            continue

        index_path = os.path.join(mem_dir, "MEMORY.md")
        if os.path.isfile(index_path):
            idx_content = _read_head(index_path, index_head)
            if idx_content:
                if multi_dir_labels:
                    dirname = os.path.basename(mem_dir.rstrip("/"))
                    context_parts.append(f"# Memory Index ({dirname}/MEMORY.md)\n{idx_content}")
                else:
                    context_parts.append(idx_content)

        try:
            topic_files = _locale_sort([
                f for f in os.listdir(mem_dir)
                if f.endswith(".md") and f != "MEMORY.md" and os.path.isfile(os.path.join(mem_dir, f))
            ])
        except Exception:
            topic_files = []

        for fname in topic_files:
            if fname in loaded_files:
                continue
            loaded_files.add(fname)
            content = _read_head(os.path.join(mem_dir, fname), topic_head)
            if content:
                if multi_dir_labels:
                    context_parts.append(f"---\n## Memory: {fname}\n{content}")
                else:
                    context_parts.append(f"---\n{content}")
                file_count += 1

    matched_local = False
    for local_name in local_files:
        local_path = os.path.join(cwd, local_name)
        if not os.path.isfile(local_path):
            continue
        local_content = _read_head(local_path, local_head)
        if local_content:
            if multi_dir_labels:
                context_parts.append(f"---\n## Local Project Rules ({local_name})\n{local_content}")
            else:
                context_parts.append(local_content)
        matched_local = True
        if not local_all_matches:
            break

    context = "\n\n".join(context_parts)
    return {"context": context, "file_count": file_count, "byte_count": len(context), "matched_local": matched_local}
