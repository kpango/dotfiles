# SKILL.state — swarm-\* 共通の説明（正典）

SKILL.state（arXiv:2608.26263）は長い手続き型 skill の実行状態モデル。Pi/OMP ハーネスでは既定の作業パターン:
実行開始時に各 skill の `## SKILL.state Schema` の JSON で `skill_state_declare` し、各 Phase 後に ΔΣ を
`skill_state_update` で送る（null 削除マージ、実行時検証、失敗時 rollback-retry）。有界の Σ ダイジェストが毎ターン
自動注入されるため、履歴全体を再導出しない。replace 型フィールドは O(1)、append/union 型は保持件数に応じて増え、
上限管理は skill 側の責任。`skill_state` ツールの無いハーネスでは無効（読み飛ばしてよい）。

**Σ は従属的な射影であり、各 skill の既存の正典状態ファイルを置き換えない。** 食い違えば正典が常に優先する。
参考: `agent/harnesses/omp/extensions/SKILL_STATE.md`。
