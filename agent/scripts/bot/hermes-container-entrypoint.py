"""Entrypoint for the dedicated dotfiles Hermes image."""

import base64
import ctypes
import errno
import faulthandler
import os
from pathlib import Path
import platform
import re
from stat import S_IMODE
import sys

from hermes_cli.env_loader import _parse_dotenv_file
from ruamel.yaml import YAML, YAMLError

HOME = Path('/home/kpango/.hermes')
PYTHON = '/opt/hermes/.venv/bin/python'
ENV_FILES = (HOME / '.env', HOME / '.op.env', Path('/opt/hermes/.env'))


def isolate_workspace_sockets():
    # Linux/amd64 only (the syscall numbers below). Landlock ABI 9+ lets this
    # process handle RESOLVE_UNIX with no rules: from now on, this process and its
    # descendants cannot connect to any pathname Unix socket created outside this
    # sandbox, including host sockets that appear later in the workspace bind.
    # Sockets they create themselves still work. `docker exec` shells are not covered.
    if platform.machine() != 'x86_64':
        raise SystemExit('Workspace socket isolation supports Linux x86_64 only')
    libc = ctypes.CDLL(None, use_errno=True)
    libc.syscall.restype = ctypes.c_long
    libc.prctl.restype = ctypes.c_int
    resolve_unix = ctypes.c_uint64(1 << 16)
    fd = libc.syscall(ctypes.c_long(444), ctypes.byref(resolve_unix),
                      ctypes.c_size_t(ctypes.sizeof(resolve_unix)), ctypes.c_uint32(0))
    if fd < 0:
        code = ctypes.get_errno()
        raise SystemExit(f'Landlock ABI 9+ is required to isolate workspace sockets: '
                         f'{errno.errorcode.get(code, code)} (ENOSYS/EOPNOTSUPP: disabled; EINVAL: ABI too old)')
    try:
        # restrict_self needs no-new-privileges; do not depend on the Docker flag alone.
        if libc.prctl(ctypes.c_int(38), ctypes.c_ulong(1), ctypes.c_ulong(0),
                      ctypes.c_ulong(0), ctypes.c_ulong(0)) != 0:
            raise SystemExit(f'Cannot set no-new-privileges: {errno.errorcode.get(ctypes.get_errno())}')
        if libc.syscall(ctypes.c_long(446), ctypes.c_int(fd), ctypes.c_uint32(0)) != 0:
            raise SystemExit(f'Cannot restrict workspace sockets with Landlock: '
                             f'{errno.errorcode.get(ctypes.get_errno())}')
    finally:
        os.close(fd)


def check_environment(config):
    file_keys = set()
    for dotenv in ENV_FILES:
        if dotenv.is_symlink() or (dotenv.exists() and not dotenv.is_file()):
            raise SystemExit('Hermes startup env files must be regular files')
        if dotenv.is_file():
            if b'\0' in dotenv.read_bytes():
                raise SystemExit('Hermes startup env files must be text without NULs')
            file_keys.update(key for key, _ in _parse_dotenv_file(dotenv))
    env_keys = set(os.environ) | file_keys
    if file_keys & {'HERMES_WEB_DIST', 'HERMES_WEBAPP_DIST'}:
        raise SystemExit('Startup env files must not redirect the served Webapp bundle')
    if any(key.startswith('HERMES_DASHBOARD_') for key in env_keys):
        raise SystemExit('Remove dashboard environment overrides; use hermes/container/password')
    deployment_keys = {'HERMES_CONFIG_BACKEND', 'HERMES_CONFIG_PATH', 'HERMES_MANAGED_DIR'}
    if (file_keys & {'HERMES_HOME', 'HERMES_PROFILE'} or env_keys & deployment_keys
            or Path('/etc/hermes').is_dir() or config.get('secrets')):
        raise SystemExit('Managed or alternate secret/config sources are unsupported by this image')


def valid_password_hash(encoded):
    # Match the format emitted by this pinned version's dashboard password CLI.
    if not isinstance(encoded, str):
        return False
    fields = encoded.split('$')
    if len(fields) != 6 or fields[:4] != ['scrypt', '16384', '8', '1']:
        return False
    try:
        salt = base64.b64decode(fields[4], validate=True)
        digest = base64.b64decode(fields[5], validate=True)
    except ValueError:
        return False
    return len(salt) == 16 and len(digest) == 32


def check_webapp():
    # PID 1 ignores TERM, so bound this check from the inside. exit=True uses _exit().
    faulthandler.dump_traceback_later(30, exit=True)
    path = HOME / 'config.yaml'
    isolate_workspace_sockets()
    try:
        if not path.is_file() or path.is_symlink() or S_IMODE(path.stat().st_mode) != 0o600:
            raise SystemExit('Hermes config.yaml must be a private regular file (0600)')
        config = YAML(typ='safe').load(path.read_text())
        check_environment(config)
        auth = config.get('dashboard', {}).get('basic_auth', {})
        web = config.get('webapp', {})
        if not isinstance(auth, dict) or not isinstance(web, dict):
            raise TypeError
    except (AttributeError, OSError, TypeError, UnicodeError, YAMLError):
        raise SystemExit('Cannot read the private Hermes configuration') from None

    if (auth.get('username') != 'hermes' or not valid_password_hash(auth.get('password_hash'))
            or auth.get('password') not in (None, '')):
        raise SystemExit('First run make hermes/container/password with the same HERMES_CONTAINER_IMAGE_ID')
    secret = auth.get('secret')
    if (not isinstance(secret, str) or len(secret) < 32 or secret != secret.strip()
            or any(marker in secret for marker in ('$(', '`', 'openssl rand'))):
        raise SystemExit('Webapp signing key must be 32+ characters without shell text; remove '
                         'dashboard.basic_auth.secret and rerun the password command to replace it')
    # `==` alone would accept 1 for True and 19120.0 for 19120, which the listener rejects.
    if (web.get('enabled') is not True or type(web.get('port')) is not int
            or web != {'enabled': True, 'host': '0.0.0.0', 'port': 19120, 'public_url': 'http://127.0.0.1:19120'}):
        raise SystemExit('Unexpected Webapp bind configuration in the private volume')


def main(args):
    if args == ['--check-landlock']:
        isolate_workspace_sockets()
        return
    if args == ['--check-webapp']:
        check_webapp()
        return
    if args[:2] == ['gateway', 'run']:
        check_webapp()
    os.execv(PYTHON, [PYTHON, '-I', '-m', 'hermes_cli.main', *args])


if __name__ == '__main__':
    main(sys.argv[1:])
