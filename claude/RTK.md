# RTK - Rust Token Killer

**Usage**: Token-optimized CLI proxy (60-90% savings on dev operations)

Install on Arch: `paru -S rtk-ai-bin`

## Meta Commands (always use rtk directly)

```bash
rtk gain              # Show token savings analytics
rtk gain --history    # Show command usage history with savings
rtk discover          # Analyze Claude Code history for missed opportunities
rtk proxy <cmd>       # Execute raw command without filtering (for debugging)
```

## Installation Verification

```bash
rtk --version         # Should show: rtk X.Y.Z
rtk gain              # Should work (not "command not found")
which rtk             # Verify correct binary
```

## Hook-Based Usage

All bash commands are automatically rewritten by the Claude Code hook.
Example: `git status` → `rtk git status` (transparent, 0 tokens overhead)

## Top Savings (60-90% per call)

| Command         | Savings |
| --------------- | ------- |
| `go test ./...` | 90%     |
| `cargo test`    | 90%     |
| `git diff`      | 80%     |
| `git status`    | 80%     |
| `docker logs`   | 80%     |
| `cargo clippy`  | 80%     |
