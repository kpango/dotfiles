# cp/rm: prefer cpz/rmz (fuc) when installed; use $(CP)/$(RM) instead of a bare
# cp/rm in recipes. Resolved to absolute paths so `sudo $(RM)` works even though the
# cargo bin dir is outside sudo's secure_path. rmz is always recursive (no -r flag),
# and cpz refuses to overwrite without -f, so -f keeps plain cp/rm -rf semantics.
# Its own file because download.mk is also run standalone (`make -f /mk/download.mk`
# in dockers/*.Dockerfile) without variables.mk; without this, $(RM) there is GNU
# make's built-in `rm -f` (fails on directories) and $(CP) is empty.
CPZ := $(shell command -v cpz 2>/dev/null)
RMZ := $(shell command -v rmz 2>/dev/null)
CP := $(if $(CPZ),$(CPZ) -f,cp -rf)
RM := $(if $(RMZ),$(RMZ) -f,rm -rf)
