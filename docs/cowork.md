# Cowork on Void Linux

Cowork runs Claude's tasks inside a small Linux virtual machine. Claude
Desktop starts it with its bundled helper (`resources/cowork-linux-helper`),
which uses QEMU with KVM, UEFI firmware (OVMF), `virtiofsd` for shared
folders, and a vsock channel to talk to the guest.

Anthropic's Debian package expects Debian file locations. The XBPS package
from this repository adapts them to Void.

## What the package does for Cowork

| Need | Debian | Void package |
|------|--------|--------------|
| QEMU | `qemu-system-x86` | Depends on `qemu-system-amd64` and `qemu-img`. |
| UEFI firmware | `/usr/share/OVMF/OVMF_CODE_4M.fd` and `OVMF_VARS_4M.fd` | Depends on `edk2-ovmf`. Adds links `/usr/share/edk2/OVMF_CODE_4M.fd` and `OVMF_VARS_4M.fd` to Void's `x64/OVMF_CODE.4m.fd` and `x64/OVMF_VARS.4m.fd`. Void's `/usr/share/OVMF` is a link to `edk2`, so Claude finds them at the Debian path. |
| `virtiofsd` | `/usr/libexec/virtiofsd` | Depends on `virtiofsd`, which installs at the same path. |
| vsock | `vhost_vsock` kernel module | Installs `/usr/lib/modules-load.d/claude-desktop.conf`, so runit loads `vhost_vsock` at boot. |

The package does not change the `edk2-ovmf` files or Void's `/usr/share/OVMF` link.

## What you must do

1. Enable hardware virtualization (Intel VT-x or AMD-V) in your firmware settings.
2. Add your user to the `kvm` group, then log out and back in:

   ```sh
   sudo usermod -aG kvm "$USER"
   ```

3. Load the vsock module now, or reboot once after installing:

   ```sh
   sudo modprobe vhost_vsock
   ```

Check the result:

```sh
ls -l /dev/kvm /dev/vhost-vsock     # both must exist
id -nG | grep -w kvm                # your user must be in kvm
```

Claude checks that it can read and write `/dev/kvm` and `/dev/vhost-vsock`.
If it cannot, Cowork shows a message that names the problem, for example
"Claude doesn't have permission to use virtualization (/dev/kvm)".

On first use, Claude downloads its VM image (about 1.3 GB) into your profile.

## Testing the VM without the app

`verify-cowork.py` boots a Cowork VM through the installed helper with a
separate socket and a temporary home folder, so it does not touch your
Claude profile. It checks four things:

1. The helper accepts Void's firmware and `virtiofsd` paths.
2. The VM starts.
3. The guest agent connects.
4. A command (`/bin/true`) runs in the guest and exits with code 0.

It then stops the VM.

```sh
python3 verify-cowork.py /path/to/bundle
```

The bundle directory must contain the uncompressed `rootfs.img`, `vmlinuz`,
and `initrd` files that match the VM manifest of your Claude Desktop
version. Logs go to `build/` in the clone.

Expected output:

```
PASS: helper configure accepted Void firmware and virtiofsd
PASS: startVM RPC completed
PASS: Cowork VM running with guest connected
PASS: command executed inside Cowork guest with exit code 0
```

This test passed on Void Linux x86_64 with Claude Desktop 2.26454.2.
