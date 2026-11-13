"""Fetch the convaiinnovations/laya English checkpoint into the HF cache at an exact,
pinned commit, verify the downloaded snapshot really is that commit (fail closed on any
mismatch), and always (re)write refs/main so the runtime's revision-less
snapshot_download() call can resolve it offline. Run at build time by
dockers/laya.Dockerfile's laya-fetch stage; not part of the runtime image.

LAYA_HF_REVISION must be a full 40-character commit sha, not a branch/tag name (T16
trial 4): the earlier "resolve main, compare against a separately-tracked expected sha"
design broke every time upstream's main moved (observed 5 times across this file's own
review trials) even though nothing about the pinned checkpoint's *content* had changed
for this image. Requesting the commit sha directly as the revision sidesteps that
entirely -- there is no floating ref for upstream to move out from under us -- and
collapses what used to be two args that could disagree (LAYA_HF_REVISION,
LAYA_HF_EXPECTED_SHA) into one. This is also a hard correctness requirement, not just a
build-stability one: laya-calibration.json (see dockers/laya.Dockerfile's ARG
LAYA_HF_REVISION comment) calibrates its outputs against one specific commit, so baking
in a different commit under the same "main" name would silently apply that calibration
to a different model.

Why refs/main is always (re)written: laya's own Agent.__init__ (laya/agent.py) calls
huggingface_hub.snapshot_download(model_id_or_path, allow_patterns=[...]) with NO
`revision` argument, so at container-start preload time (HF_HUB_OFFLINE=1, no network) it
always resolves the literal ref name "main" from the local cache's refs/ directory.
huggingface_hub only auto-writes that file when the download itself requested the named
ref "main" -- requesting a raw commit sha instead (as this script now always does) would
otherwise leave refs/main missing and the container would crash-loop on every start
under `--restart always`.
"""
import os
import re
import sys

from huggingface_hub import snapshot_download

REPO_ID = "convaiinnovations/laya"
# Exactly the allow_patterns laya/agent.py's Agent.__init__ uses for the (subfolder-less)
# English checkpoint: the repo's top-level files, not the sibling multilingual/
# typed-decisions checkpoints or the .py helper modules it also ships (Agent.load()
# never fetches those either).
ALLOW_PATTERNS = ["rl_agent_config.json", "model.safetensors", "tokenizer/*", "encoder/*"]

_COMMIT_SHA_RE = re.compile(r"^[0-9a-f]{40}$")


def main() -> None:
    revision = os.environ.get("LAYA_HF_REVISION", "")

    if not _COMMIT_SHA_RE.match(revision):
        sys.exit(
            "LAYA_HF_REVISION must be a full 40-character git commit sha (got %r) -- "
            "branch/tag names (including \"main\") are rejected and an empty value is "
            "rejected too (fail closed): a floating ref can silently move the checkpoint "
            "out from under a pin, and laya-calibration.json calibrates against one exact "
            "commit, so deploying a different commit under the same name would silently "
            "apply that calibration to a different model. Pass the commit sha itself." % (revision,)
        )

    path = snapshot_download(REPO_ID, revision=revision, allow_patterns=ALLOW_PATTERNS)
    commit_hash = os.path.basename(os.path.normpath(path))
    print("resolved %s@%s -> %s" % (REPO_ID, revision, commit_hash), file=sys.stderr)

    if commit_hash != revision:
        # Should be unreachable in practice (a commit sha resolves to itself), but a
        # library behavior change here would otherwise silently bake in the wrong
        # snapshot under the requested revision's name -- fail closed instead.
        sys.exit(
            "snapshot_download resolved %s@%s to commit %r, which does not match the "
            "requested revision itself -- refusing to bake in an unexpected commit." % (
                REPO_ID, revision, commit_hash,
            )
        )

    # Always (re)write refs/main, whichever revision was actually requested above -- see
    # the module docstring for why.
    repo_folder = os.path.dirname(os.path.dirname(path))  # .../snapshots/<hash> -> repo root
    refs_dir = os.path.join(repo_folder, "refs")
    os.makedirs(refs_dir, exist_ok=True)
    with open(os.path.join(refs_dir, "main"), "w") as fh:
        fh.write(commit_hash)
    print("wrote refs/main -> %s" % commit_hash, file=sys.stderr)


if __name__ == "__main__":
    main()
