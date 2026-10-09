#!/usr/bin/env python3
"""Boot a supplied Cowork bundle through the installed native helper."""
import argparse
import json
import os
from pathlib import Path
import socket
import struct
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("bundle", type=Path)
args = parser.parse_args()
bundle = args.bundle.resolve()
resources = Path("/usr/lib/claude-desktop/resources")
report_dir = Path(__file__).resolve().parent / "build"
report_dir.mkdir(exist_ok=True)


def receive(connection):
    def read(size):
        data = b""
        while len(data) < size:
            chunk = connection.recv(size - len(data))
            if not chunk:
                raise RuntimeError("Helper closed the RPC connection")
            data += chunk
        return data
    return json.loads(read(struct.unpack(">I", read(4))[0]))


with tempfile.TemporaryDirectory(prefix="claude-void-cowork-") as temporary:
    root = Path(temporary)
    address = str(root / "helper.sock")
    environment = dict(os.environ, HOME=str(root), XDG_CONFIG_HOME=str(root / "config"),
                       XDG_CACHE_HOME=str(root / "cache"), XDG_RUNTIME_DIR=str(root))
    log = (report_dir / "cowork-helper.log").open("wb")
    helper = subprocess.Popen([str(resources / "cowork-linux-helper"), "-socket", address],
                              env=environment, stdin=subprocess.PIPE, stdout=log,
                              stderr=subprocess.STDOUT)

    def rpc(method, params=None):
        with socket.socket(socket.AF_UNIX) as connection:
            connection.settimeout(120)
            connection.connect(address)
            request = {"method": method}
            if params is not None:
                request["params"] = params
            data = json.dumps(request).encode()
            connection.sendall(struct.pack(">I", len(data)) + data)
            response = receive(connection)
            if not response.get("success"):
                raise RuntimeError(f"{method}: {response.get('error')}")
            return response.get("result")

    try:
        for _ in range(100):
            if Path(address).exists():
                break
            if helper.poll() is not None:
                raise RuntimeError("Helper failed to start")
            time.sleep(0.05)
        rpc("configure", {"userDataName": "ClaudeVoidVerification", "memoryMB": 2048,
                          "cpuCount": 2, "smolBinPath": str(resources / "smol-bin.x64.img"),
                          "logDir": str(report_dir), "virtiofsdPath": "/usr/libexec/virtiofsd",
                          "firmwareCodePath": "/usr/share/OVMF/OVMF_CODE_4M.fd",
                          "firmwareVarsTemplatePath": "/usr/share/OVMF/OVMF_VARS_4M.fd"})
        print("PASS: helper configure accepted Void firmware and virtiofsd", flush=True)
        rpc("startVM", {"bundlePath": str(bundle), "memoryGB": 2, "cpuCount": 2})
        print("PASS: startVM RPC completed", flush=True)
        deadline = time.monotonic() + 120
        while time.monotonic() < deadline:
            if (rpc("isGuestConnected") or {}).get("connected"):
                break
            if helper.poll() is not None:
                raise RuntimeError("Helper exited while waiting for the guest")
            time.sleep(1)
        else:
            raise RuntimeError("Guest did not connect within 120 seconds")
        assert (rpc("isRunning") or {}).get("running"), "VM is not running"
        print("PASS: Cowork VM running with guest connected", flush=True)
        result = rpc("spawn", {"id": "void-verification", "name": "VoidVerification",
                               "command": "/bin/true", "args": [], "oneShot": True})
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            status = rpc("isProcessRunning", {"id": "void-verification"}) or {}
            if not status.get("running"):
                assert status.get("exitCode") == 0, status
                break
            time.sleep(0.5)
        else:
            raise RuntimeError("Guest process did not exit")
        print("PASS: command executed inside Cowork guest with exit code 0", flush=True)
    finally:
        if helper.poll() is None:
            try:
                rpc("stopVM")
            finally:
                helper.terminate()
                try:
                    helper.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    helper.kill()
                    helper.wait()
        log.close()
