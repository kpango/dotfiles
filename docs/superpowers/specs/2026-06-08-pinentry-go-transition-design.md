# Pinentry Go Transition Design

## Architecture / Changes

The existing `zfunc/pinentry-tmux` shell script replicates functionality that is already implemented in Go at `pinentry/tmux/main.go`. We will transition the environment to exclusively use the Go binary.

## Steps

1. Delete `zfunc/pinentry-tmux`.
2. Remove the symlink generation mapping `zfunc/pinentry-tmux /usr/local/bin/pinentry-tmux` from `Makefile.d/install.mk`.
3. (Intentionally skipped as requested by user) Modifying `sheldon.toml` and `05-functions.zsh` zcompile steps; the existing `-f` check will gracefully ignore the missing file.

## Testing

- Ensure `make install` or related targets don't fail due to the missing file.
- Verify `pinentry-tmux` builds via the `pinentry/install` target.
