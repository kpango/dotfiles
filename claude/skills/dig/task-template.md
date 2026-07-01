# TDAD Task Template

Use this template for each task in `docs/superpowers/plans/`. Fill ALL fields — no placeholders (TBD/TODO 禁止).

---

### Task N: [Component Name]

**Complexity:** trivial | simple | standard | complex

<!-- trivial: 1ファイル・15行以下・新ロジックなし → オーケストレーター直接実行 -->
<!-- simple: 30行以下・1関数・既存パターン → haiku Subagent -->
<!-- standard: 複数ファイル or 新ロジック → sonnet Subagent -->
<!-- complex: 複数システム or 新抽象化 → opusplan Subagent -->

**Model:** trivial=N/A | simple=haiku | standard=sonnet | complex=opusplan

**Files:**

- Create: `exact/path/to/file.go`
- Modify: `exact/path/to/existing.go:L123-L145`
- Test: `exact/path/to/file_test.go`

**Success Criteria:**

```bash
<test command> -run TestXxx -v
# Expected: PASS
# Coverage: 80%+
```

- [ ] **Step 1: RED — 失敗するテストを書く**

```go
// テストコード（言語に合わせて記述）
// ルール:
//   - テスト名は「何をすべきか」を説明する（"test1" 禁止）
//   - 1テスト = 1振る舞い（複数の振る舞いを1テストに詰め込まない）
//   - モックは Integration/Unit 境界を超える場合のみ
func TestXxx(t *testing.T) {
    // arrange
    // act
    // assert
}
```

- [ ] **Step 2: Verify RED — 期待した理由で失敗することを確認**

```bash
<test command> -run TestXxx -v
```

Expected: FAIL — `"undefined: FunctionName"` or `"not implemented"`  
**タイポ・構文エラーが理由なら Step 1 に戻って修正する（機能未実装が理由であること）**

```bash
git add <test_file>
git commit -m "test: add reproducer for <feature>"
```

- [ ] **Step 3: GREEN — 最小限の実装を書く**

```go
// 実装コード
// ルール:
//   - テストを通すための最小限のみ（YAGNI）
//   - テストが要求しない機能を追加しない
//   - 完璧さより「グリーンにすること」を優先する
```

- [ ] **Step 4: Verify GREEN — 全テスト通過を確認**

```bash
<test command> ./...
```

Expected: PASS（このタスクのテスト + 既存の全テストがグリーン）

```bash
git add <implementation_file> <test_file>
git commit -m "feat: <description>"
```

- [ ] **Step 5: REFACTOR — テストをグリーンに保ちながら改善**

テストを変えずに内部品質を改善する:

- 重複の除去（DRY）
- 命名の改善
- パフォーマンス最適化（テストが要求する範囲のみ）

```bash
<test command> ./...  # 全テストがグリーンであることを再確認
git add <changed_files>
git commit -m "refactor: clean up after <feature>"
```

- [ ] **Step 6: Coverage — 80%以上を確認**

```bash
# Go
go test ./... -cover -coverprofile=/tmp/cover.out && go tool cover -func=/tmp/cover.out | tail -1
# Rust
cargo test && cargo tarpaulin --out Stdout 2>/dev/null | tail -5
# Python
pytest --cov=<pkg> --cov-report=term-missing | tail -5
```

Target: 80%+ (branch / function / line)

---

## Dependency Map Example

独立タスクを明示して並行実行を最大化する:

```
Task 1 (独立) ─────┐
Task 2 (独立) ─────┼──→ Task 4 (Task 1+2 完了後)
Task 3 (独立) ─────┘
```

## Output Schema（全サブエージェント共通）

```json
{
  "task_id": "N",
  "status": "DONE | DONE_WITH_CONCERNS | NEEDS_CONTEXT | BLOCKED",
  "files_changed": ["path/to/file.go"],
  "tests_passing": true,
  "commit_sha": "abc123",
  "concerns": "(DONE_WITH_CONCERNS の場合のみ)",
  "blocker": "(BLOCKED の場合のみ)"
}
```
