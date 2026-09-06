<div align="center">

# Bootsmith

**Bootable USB drives for BIOS and UEFI.** A native macOS app that writes Linux
images to USB drives — the Rufus job, without the Windows machine.

</div>

---

Bootsmith writes hybrid disk images (Ubuntu, Debian, Proxmox, Fedora, Rocky) to a USB
drive so it boots both on old BIOS machines and modern UEFI ones. It reads the
image to find out how it boots, names the volumes you are about to destroy, and
verifies the drive afterwards.

## Install

```sh
Scripts/bundle.sh          # builds dist/Bootsmith.app (universal arm64 + x86_64)
open dist/Bootsmith.app
```

In Xcode: `open Package.swift`, scheme **Bootsmith**, destination **My Mac**.

## Permissions

Grant **Full Disk Access** to Bootsmith in System Settings › Privacy & Security.
Since macOS 13 removable volumes are protected, and without that permission even
root cannot open `/dev/rdiskN`.

## Features

- **Compressed images**, written straight from `.xz`, `.gz`, `.zip` and `.bz2`
  without unpacking first — Raspberry Pi OS, Armbian and OpenWrt all ship this
  way. Decompression happens in flow, block by block; nothing intermediate
  touches the disk. `.xz` uses Apple's Compression framework, so there is no
  dependency on the `xz` binary, which macOS does not ship.
- **Checksum verification** before writing: paste a SHA-256 or the contents of a
  `SHA256SUMS` file and Bootsmith finds the line for your image. A corrupt ISO
  writes without complaint and only reveals itself in front of the server.
- **Restore the drive** — after receiving an ISO a stick is unreadable to Finder,
  which offers only to initialize it. One menu reformats it as exFAT or FAT32.
- **Drives appear and disappear on their own**, with a warning when the selected
  disk is large enough to be an external drive rather than a USB stick.

## Design notes

**No partition scheme to choose.** Rufus asks you to pick MBR/GPT and
BIOS/UEFI — picking wrong is the most common reason a stick will not boot. A
modern Linux ISO already carries both: a boot signature in the MBR for BIOS and
an EFI System Partition for UEFI. Bootsmith reads the image, reports what it found,
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

Bootsmith uses its `-stdoutpipe` mode, which hands the open descriptor back over
`SCM_RIGHTS`, rather than the simpler `-w` mode that copies stdin. Three reasons:
the pipe costs an extra copy of every block; if `authopen` dies mid-write the
parent takes a `SIGPIPE` and dies with it, which in a GUI app is a crash with no
message; and a read/write descriptor lets one authorization cover both the write
and the verification pass.

**Sector alignment.** The raw node only accepts reads and writes aligned to the
512-byte sector — an odd-sized request is rejected with `EINVAL`. Images whose
size is not a multiple of 512 are padded with zeros on the final block, and the
verification pass reads aligned and trims the excess before hashing. This is
covered by a test with a deliberately odd-sized image.

**Verification is on by default.** A drive can accept every write and still hold
garbage — worn flash, a bad cable, a cheap adapter. Finding out here costs a few
minutes; finding out in front of the server costs a trip.

## Language

English by default, Portuguese (Brazil) in Settings. Keys are the English text,
so a missing entry falls back to English instead of showing a raw identifier.

## License

MIT
