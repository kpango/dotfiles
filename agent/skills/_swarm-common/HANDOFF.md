# Handoff Contract — swarm-\* 共通（正典）

他 skill へ渡す／最終報告する出力の末尾に、下記ブロックを 1 つ付ける。本文の代替ではなく、受け手が最初に読む要約。

```yaml
handoff:
  v: 1
  from: swarm-<name> # 必須
  to: <呼び出し元 skill | human> # 必須
  goal: "<1行>" # 必須
  status: done|partial|blocked # 必須。done の定義は各 skill の「完了条件」行
  confidence: high|medium|low # 必須。件数でなく証拠の質。evidence が空の high は無効(low 扱い)
  evidence: ["path:line"] # done なら必須
  open_questions: []
  next_action: "<1行>" # 必須。送り手の推奨(受け手は従わなくてよい)
  autonomy: auto # 既定 auto
```

## 規則

- 受け手: `confidence: low` または `status != done` のとき、先に `open_questions` を処理する。
  それ以外は本文を読み直さず `next_action` から着手してよい。
- 同調性対策: 複数出典でも証拠が無ければ `confidence` を上げない（SWARM_REFERENCES.md）。
- `autonomy: auto` は「判断のたびに人間へ聞かない」ことだけを意味する。`human_required` にしてよいのは
  **OS・システム設定の変更、シークレット・認証情報の扱い、Hard Floor（`security-rules.json`）該当操作のみ**。
- Hard Floor・Tier B 書込ゲート(grant)・swarm-release-gate の人間最終承認は本契約で緩めない。

## 完了時の stats 記録（件数・時間・失敗署名のみ。失敗しても本処理は止めない）

```
~/.claude/skills/swarm-implement/scripts/stats-record.sh swarm-<name> <ok|fail|partial> [duration_ms] [signature] [called_by]
```

Bash を持たない skill（swarm-secretary 等）は呼び出し元がまとめて記録してよい。
