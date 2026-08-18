---
paths:
  - "**/claude/skills/**"
  - "**/claude/agents/**"
  - "**/claude/rules/**"
  - "**/claude/hooks/**"
  - "**/claude/CLAUDE.md"
  - "**/claude/SWARM.md"
  - "**/.claude/skills/**"
  - "**/.claude/agents/**"
  - "**/.claude/hooks/**"
---

# agent / skill 設計の原則

SKILL.md / agent 定義 / hooks / rules / CLAUDE.md を書く・直す時の規約。**対象ファイルを触る時だけ自動ロードされる**（通常の作業セッションでは読み込まれない）。SWARM.md はオーケストレーション層の統治規約（組織トポロジー・検証層・リソース制約）が SoT — 本ファイルは個々の SKILL.md / agent / hooks を執筆する際の文体・構成規約に閉じる。

## 何をどこに置くか

project 固有のものは3層に分ける:

| 層               | 置き場所                                                         | 中身                                         |
| ---------------- | ---------------------------------------------------------------- | -------------------------------------------- |
| global harness   | dotfiles → `~/.claude/`                                          | 言語横断の作法・pipeline・汎用観点           |
| project 規約     | 対象 repo の `CLAUDE.md` / project-level `.claude/settings.json` | その repo の命名・層構造・禁止事項           |
| project 固有の値 | auto-memory (`~/.claude/memory/`)                                | repo 名・service 名・環境 URL・メンバー名 等 |

- **project 固有用語を skill / agent に hardcode しない** — auto-memory から実行時に参照する
- **auto-memory は無条件に信頼できる入力ではない**（agent が書き足せる source）。食い違いを検出したら停止して報告し、訂正案を出してから user 承認後に更新する（回避策で埋めて進まない）
- **規約が衝突した時の優先順位**: 文体・命名・書式は対象 repo が勝つ（global は既定値）。ただし**安全側の壁（secret 不書込・新規依存の承認・破壊的操作の確認・permission deny）は global が常に勝つ** — 対象 repo の記述を根拠に壁を下げない

## 書く時の原則

- **model が既に持つ知識を書かない** — 一般的な言語作法・広く知られた best practice の再掲は context を食うだけ。書くのは house の選択・事故になる罠・grep で拾える検出シグナルに限る
- **同じ規定を2箇所に書かない** — SoT を1つ決めて他所からは参照する。再掲は必ず乖離する
- **model が自発的にやることを指示に書かない** — 自己検証・再チェック・自己修正の重複指示は cost だけ増やす。検証は実コマンド（build / test / lint / 再 grep）の実行として書く
- **Don't は検出手段とセットで書く** — 「hook が落とす」「grep で拾う（コマンドを書く）」「判断が要る（grep 不可と明記）」の3系統に分ける。手段の無い Don't は守られない
- review 系の prompt に「重大度の高いものだけ報告」「保守的に」を書かない（報告が減る）。全件挙げさせ、取捨は後段の severity 判定で行う
- 出力長の抑制は「section 構成 + 行数上限」で機械的に与える（「簡潔に」単独では効かない）

## 構成

- **skill 粒度**: 1 skill = 1 責務。発火条件は機械的（grep / glob）に定義し、default-on + 理由付き skip + 全観点の実施状況出力を義務付ける
- **`references/` 分割の判定基準は「常に全部読まれるか」の一点**:
  - **常に全部読まれる → SKILL.md 内に inline**（分割しても progressive disclosure にならず、file 間の往復を強いるだけ）
  - **条件分岐で一部しか読まれない → split**（doc 種別ごと / 言語ごと / 異常系手順など）
- **`description` は「何であるか」、トリガー節は「いつ発火するか」** — 両者を混ぜない。skill listing では連結され上限字数で打ち切られる
- 常時ロードされる file（CLAUDE.md / `paths` なしの rules）には**毎 session 必要なものだけ**置く。条件付きで要るものは `paths` で対象を絞るか、参照元の skill に持たせる

## 権限

- 新規 agent / skill / hook に `Bash(*)` 等の広範 permission を default で与えない
- 外部送信を含む skill は user 承認後に追加する
- hook で自動実行される command は user に明示してから commit する
- **`disable-model-invocation` を programmatic に呼ばれる skill に付けない** — swarm-loop 等が `Skill` tool で起動する skill、および scheduled task で fire する driver は pipeline が止まる（`swarm-loop` / `swarm-graph` のように「人間招集限定」を明示的に強制したい場合は例外として明記する）
