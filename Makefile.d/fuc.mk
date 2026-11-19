# cp/rm: prefer cpz/rmz (fuc) when installed; use $(CP)/$(RM) instead of a bare
# cp/rm in recipes. Resolved to absolute paths so `sudo $(RM)` works even though the
# cargo bin dir is outside sudo's secure_path. rmz is always recursive (no -r flag),
# and cpz refuses to overwrite without -f, so -f keeps plain cp/rm -rf semantics.
# Its own file because download.mk is also run standalone (`make -f /mk/download.mk`
# in dockers/*.Dockerfile) without variables.mk; without this, $(RM) there is GNU
# make's built-in `rm -f` (fails on directories) and $(CP) is empty.
# fuc's cpz/rmz call unshare(CLONE_FILES), which a restricted sandbox (e.g. a BuildKit RUN step
# on a CI runner) rejects with EPERM ("Failed to unshare FD table"). Use them only when a
# multi-file/directory smoke run (the shape the install recipes use) really works here (RMZ/CPZ probes); otherwise fall back to cp/rm.
RMZ := $(shell p=$$(command -v rmz 2>/dev/null) || exit 0; d=$$(mktemp -d) || exit 0; mkdir "$$d/s"; for i in 1 2 3 4 5 6 7 8 9; do : > "$$d/f$$i"; : > "$$d/s/f$$i"; done; if "$$p" -f "$$d"/f? "$$d/s" >/dev/null 2>&1 && [ ! -e "$$d/s" ] && [ ! -e "$$d/f9" ]; then echo "$$p"; fi; rm -rf "$$d")
CPZ := $(shell p=$$(command -v cpz 2>/dev/null) || exit 0; d=$$(mktemp -d) || exit 0; mkdir -p "$$d/s/sub"; for i in $$(seq 1 40); do echo x > "$$d/s/f$$i"; echo x > "$$d/s/sub/f$$i"; done; if "$$p" -f "$$d/s/" "$$d/c" >/dev/null 2>&1 && [ -f "$$d/c/sub/f40" ] && [ -f "$$d/c/f40" ]; then echo "$$p"; fi; rm -rf "$$d")
CP := $(if $(CPZ),$(CPZ) -f,cp -rf)
RM := $(if $(RMZ),$(RMZ) -f,rm -rf)
