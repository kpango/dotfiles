#!/usr/bin/env bash
# swarm-write-scope-gate.sh (hook) と budget-guard.sh --write-scope-grant の両方が source する
# 単一ソース。PROTECTED判定とキー導出を2箇所に重複させない(重複実装は食い違いによる
# 「保護されるはずが保護されない」バグを生むため)。
#
# 判定は2種類のパターンを組み合わせる:
#  (a) サフィックスパターン(*/claude/...): ~/.claude/{hooks,skills,SWARM.md,SWARM_REFERENCES.md,CLAUDE.md,
#      settings*.json} は dotfiles/claude/ 配下への symlink であり、realpath解決後の絶対パスは
#      常に ".../claude/..." という構造になる(保護される理由はsymlink解決、サフィックス構造の
#      一致それ自体ではない)。dotfiles自体をworktree化した場合も同じ内部構造が再現されるため、
#      サフィックス一致で自動的に保護される。**移植性の限界**: ~/.claude が実ディレクトリ(symlink
#      でない)の環境では本パターンは一致せず、hookは全パスでno-opになる。
#      `*/claude/agents/*`(サブエージェント定義)・`*/claude/skills/*/*.md`(SKILL.md含む各skill
#      root直下の任意.md、例: swarm-implement/task-template.md)も同じsymlink経由で保護される。
#  (b) 固定絶対パス: dotfiles/vald の project-level `.claude/settings.json`・`.claude/settings.local.json`
#      (いずれもNOT symlink、SWARM.md §6のclosed-loop hookをそのリポジトリで有効化する配線ファイル)
#      は(a)のパターンに一致しないため個別に列挙する(worktree変種も含む)。
# harness-lint.sh の PROTECTED 正規表現(事前lint・任意テキストへの部分文字列照合)とは実装を
# 共有できない(判定対象が解決済みファイルパスか任意テキストかで異なる)。**保護範囲は同一集合では
# ない**(write-scope側は settings.json/settings.local.json/CLAUDE.md/skills配下scripts全体を含む
# 点で上回るが、harness-lint側の裸文字列"SKILL.md"照合は任意テキスト中の任意SKILL.mdパスに反応する
# 点で上回る — 真部分集合関係ではなく、独立した2本の防御線である。一方の変更がもう一方に自動追随
# する保証は無いため、保護漏れの懸念があれば両方を個別に確認すること。
#
# **設計上の限界**: 本grant機構はgrantファイル名に埋め込まれたキーをそのまま信用して消費する —
# クライアント制御可能な識別子を認証済みセッションと照合しない点は、なりすまし耐性が無い設計である。
# 単一ユーザー・単一セッション内の速度制限(偶発的編集の防止)目的であり認証境界を跨がないため実害は
# 無いが、マルチユーザー・マルチセッション環境へ拡張する場合はこの前提を再設計する必要がある。
write_scope_is_protected() { # <realpath> -> return 0 if protected
  local p="$1"
  case "$p" in
    */claude/hooks/*) return 0 ;;
    */claude/skills/*/SKILL.md) return 0 ;;
    */claude/skills/*/scripts/*) return 0 ;;
    */claude/SWARM.md) return 0 ;;
    */claude/SWARM_REFERENCES.md) return 0 ;;
    */claude/CLAUDE.md) return 0 ;;
    */claude/settings.json) return 0 ;;
    */claude/settings.local.json) return 0 ;;
    */claude/agents/*) return 0 ;;
    */claude/skills/*/*.md) return 0 ;;
    "$HOME/go/src/github.com/kpango/dotfiles/.claude/settings.json") return 0 ;;
    "$HOME"/go/src/github.com/kpango/dotfiles/.claude/worktrees/*/.claude/settings.json) return 0 ;;
    "$HOME/go/src/github.com/kpango/dotfiles/.claude/settings.local.json") return 0 ;;
    "$HOME"/go/src/github.com/kpango/dotfiles/.claude/worktrees/*/.claude/settings.local.json) return 0 ;;
    "$HOME/go/src/github.com/vdaas/vald/.claude/settings.json") return 0 ;;
    "$HOME"/go/src/github.com/vdaas/vald/.claude/worktrees/*/.claude/settings.json) return 0 ;;
    "$HOME/go/src/github.com/vdaas/vald/.claude/settings.local.json") return 0 ;;
    "$HOME"/go/src/github.com/vdaas/vald/.claude/worktrees/*/.claude/settings.local.json) return 0 ;;
    *) return 1 ;;
  esac
}

write_scope_key() { # <realpath> -> sanitized stable key (先頭の / を除去し残りの / を _ に置換)
  local p="$1"
  p="${p#/}"
  printf '%s' "${p//\//_}"
}
