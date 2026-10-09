#!/usr/bin/env python3
"""Check a built XBPS package against the Debian package it came from.

Usage: check-package.py DEB XBPS

Fails when:
- a file from the .deb is missing from the .xbps, or differs in content or mode;
- chrome-sandbox is not mode 4755;
- the package-owned Void additions are missing;
- app.asar no longer contains the Cowork paths that the Void package relies on
  (OVMF firmware and virtiofsd locations, /dev/kvm and /dev/vhost-vsock checks).
"""
import hashlib
import io
import subprocess
import sys
import tarfile

if len(sys.argv) != 3:
    sys.exit(__doc__)
deb, xbps = sys.argv[1:]
ASAR = "usr/lib/claude-desktop/resources/app.asar"
COWORK_STRINGS = [b"/usr/share/OVMF/OVMF_CODE_4M.fd", b"/usr/libexec/virtiofsd",
                  b"/dev/kvm", b"/dev/vhost-vsock"]
VOID_FILES = ["INSTALL", "REMOVE", "usr/share/edk2/OVMF_CODE_4M.fd",
              "usr/share/edk2/OVMF_VARS_4M.fd", "usr/lib/modules-load.d/claude-desktop.conf",
              "usr/share/licenses/claude-desktop/copyright"]


def members(fileobj, mode, keep=None):
    files, kept = {}, None
    with tarfile.open(fileobj=fileobj, mode=mode) as archive:
        for member in archive:
            name = member.name.removeprefix("./")
            if member.isdir():
                continue
            if member.isfile():
                data = archive.extractfile(member).read()
                digest = hashlib.sha256(data).hexdigest()
                if name == keep:
                    kept = data
            else:
                digest = "link:" + member.linkname
            files[name] = (digest, member.mode & 0o7777)
    return files, kept


names = subprocess.run(["ar", "t", deb], capture_output=True, text=True, check=True).stdout.split()
data_member = next(name for name in names if name.startswith("data.tar"))
data = subprocess.run(["ar", "p", deb, data_member], capture_output=True, check=True).stdout
upstream, _ = members(io.BytesIO(data), "r:*")
with subprocess.Popen(["zstd", "-dc", xbps], stdout=subprocess.PIPE) as zstd:
    packaged, asar = members(zstd.stdout, "r|", keep=ASAR)

failures = []
missing = [n for n in upstream if n not in packaged and not n.startswith("usr/share/lintian/")]
changed = [n for n in upstream if n in packaged and upstream[n] != packaged[n]]
failures += [f"missing from xbps: {n}" for n in missing]
failures += [f"content or mode differs: {n}" for n in changed]
sandbox = packaged.get("usr/lib/claude-desktop/chrome-sandbox")
if not sandbox or sandbox[1] != 0o4755:
    failures.append(f"chrome-sandbox mode is {oct(sandbox[1]) if sandbox else 'missing'}, expected 0o4755")
failures += [f"Void addition missing: {n}" for n in VOID_FILES if n not in packaged]
if asar is None:
    failures.append("app.asar not found")
else:
    failures += [f"app.asar no longer mentions {s.decode()}" for s in COWORK_STRINGS if s not in asar]

print(f"{len(upstream)} upstream files checked, {len(packaged)} files in xbps")
if failures:
    print("\n".join(f"FAIL: {f}" for f in failures))
    sys.exit(1)
print("PASS: payload identical, chrome-sandbox 4755, Void additions present, Cowork paths unchanged")
