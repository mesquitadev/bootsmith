<div align="center">

# Forge

**Bootable USB drives for BIOS and UEFI.** A native macOS app that writes Linux
images to USB drives — the Rufus job, without the Windows machine.

</div>

---

Forge writes hybrid disk images (Ubuntu, Debian, Proxmox, Fedora, Rocky) to a USB
drive so it boots both on old BIOS machines and modern UEFI ones. It reads the
image to find out how it boots, names the volumes you are about to destroy, and
verifies the drive afterwards.

## Install

```sh
Scripts/bundle.sh          # builds dist/Forge.app (universal arm64 + x86_64)
open dist/Forge.app
```

In Xcode: `open Package.swift`, scheme **Forge**, destination **My Mac**.

## Permissions

Grant **Full Disk Access** to Forge in System Settings › Privacy & Security.
Since macOS 13 removable volumes are protected, and without that permission even
root cannot open `/dev/rdiskN`.

## Design notes

**No partition scheme to choose.** Rufus asks you to pick MBR/GPT and
BIOS/UEFI — picking wrong is the most common reason a stick will not boot. A
modern Linux ISO already carries both: a boot signature in the MBR for BIOS and
an EFI System Partition for UEFI. Forge reads the image, reports what it found,
and copies it byte for byte. Any "conversion" would break one of the two paths.

**Three guards before a disk is even listed** (`Core/DriveScanner.swift`):
never internal, never virtual, never a partition. Writing to an internal disk
destroys the system; writing to a partition produces a stick that will not boot.

**Privileges via `authopen`.** Writing to `/dev/rdiskN` hits two independent
barriers: Unix permissions and TCC. Elevating with `osascript … with
administrator privileges` clears the first and fails the second — the elevated
process runs in its own context and does not inherit the app's Full Disk Access.
`authopen` is a setuid helper shipped with macOS: it asks for authorization,
opens the device as root, and stays a child of the app, so TCC judges it by the
responsible app. Nothing is installed on the machine and the password never
passes through us.

**Verification is on by default.** A drive can accept every write and still hold
garbage — worn flash, a bad cable, a cheap adapter. Finding out here costs a few
minutes; finding out in front of the server costs a trip.

## Language

English by default, Portuguese (Brazil) in Settings. Keys are the English text,
so a missing entry falls back to English instead of showing a raw identifier.

## License

MIT
