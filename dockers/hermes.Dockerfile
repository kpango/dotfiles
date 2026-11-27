# syntax=docker/dockerfile:1@sha256:572cebbc2b15e6f84c077742952674889cb63cd5e9b80abdffcbe587b6f19183
# Hermes Agent v0.23.4, official linux/amd64 runtime and prebuilt Desktop Webapp.
FROM nousresearch/hermes-agent@sha256:3bc37fd8546e90fc41fe0d29511b4052840c281617cbcec6093bfe03d86a4ad9 AS official
FROM kpango/dev@sha256:da42821b7b180834e4fad6b8cbf2deddd09c8e31a8588b42a7e59a17f87f3eaf

USER root
COPY --from=official /opt/hermes /opt/hermes
COPY --from=official /usr/local/lib/libsqlite3.so.3.53.4 /opt/hermes/lib/libsqlite3.so.3.53.4
# Keep the official runtime self-contained without replacing the base image's Python.
RUN --mount=type=bind,target=/opt/dotfiles,readonly \
    make -C /opt/dotfiles hermes/docker/install ROOTDIR=/opt/dotfiles HOME=/home/kpango USER_ID=1000 GROUP_ID=1000 && \
    ln -s libsqlite3.so.3.53.4 /opt/hermes/lib/libsqlite3.so.0 && \
    ln -sfn /opt/hermes/tools/python-3.14.9+20261021-linux-x64/bin/python3.14 /opt/hermes/.venv/bin/python

ENV HERMES_HOME=/home/kpango/.hermes \
    HERMES_RUNTIME_DIR=/opt/hermes/tools \
    HERMES_PYTHON=/opt/hermes/.venv/bin/python \
    HERMES_WEB_DIST=/opt/hermes/hermes_cli/web_dist \
    LD_LIBRARY_PATH=/opt/hermes/lib \
    PATH=/opt/hermes/.venv/bin:${PATH} \
    XDG_CACHE_HOME=/tmp/hermes-cache \
    PYTHONPYCACHEPREFIX=/tmp/hermes-pycache \
    DO_NOT_TRACK=1

# Apply deployment settings to the copies only. A wildcard container bind
# requires upstream Webapp authentication; the runner publishes on host loopback.
RUN --mount=type=bind,target=/opt/dotfiles,readonly /opt/hermes/.venv/bin/python - <<'PY'
from pathlib import Path

from ruamel.yaml import YAML

home = Path('/home/kpango/.hermes')
source = Path('/opt/dotfiles/agent/harnesses/hermes/profiles')
expected = {'chief', 'ops', 'perf', 'researcher', 'sec-reviewer', 'swe'}
if {p.name for p in source.iterdir() if p.is_dir()} != expected:
    raise SystemExit('Hermes source does not contain the six expected profiles')
profiles = sorted((home / 'profiles').iterdir())
if {p.name for p in profiles} != expected:
    raise SystemExit('Hermes profile projection is incomplete')
for profile in profiles:
    for name in ('config.yaml', 'profile.yaml', 'SOUL.md'):
        path = profile / name
        if profile.is_symlink() or path.is_symlink() or not path.is_file():
            raise SystemExit(f'Missing regular Hermes profile file: {profile.name}/{name}')
yaml = YAML()
for path in [home / 'config.yaml', *(p / 'config.yaml' for p in profiles)]:
    data = yaml.load(path.read_text())
    data.setdefault('auth', {})['adopt_external_logins'] = False
    data.setdefault('terminal', {})['cwd'] = '/home/kpango/go/src'
    if path.parent == home:
        data['webapp'] = {
            'enabled': True, 'host': '0.0.0.0', 'port': 19120,
            'public_url': 'http://127.0.0.1:19120',
        }
    with path.open('w') as stream:
        yaml.dump(data, stream)
PY

# Last, so editing the entrypoint rebuilds only this tiny layer.
COPY --chmod=0644 agent/scripts/bot/hermes-container-entrypoint.py /opt/hermes/dotfiles-entrypoint.py

USER 1000:1000
WORKDIR /opt/hermes
ENTRYPOINT ["/opt/hermes/.venv/bin/python", "-I", "/opt/hermes/dotfiles-entrypoint.py"]
CMD ["gateway", "run"]
