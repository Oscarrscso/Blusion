#!/usr/bin/env python3
"""Give AetherEngine's prebuilt libraries a Mac Catalyst slice, made from their macOS slice, so the Catalyst app can link AetherEngine.

    scripts/aether-catalyst-slices.py <build or DerivedData folder>

FFmpegBuild, LibDovi and LibTrueHD (AetherEngine's dependencies, resolved by Xcode into SourcePackages/checkouts) ship iOS, tvOS,
visionOS and macOS slices, none for Mac Catalyst. A Catalyst app runs on macOS, so the macOS code runs there as it is; only each
binary's platform tag (LC_BUILD_VERSION) says macOS, and the linker refuses that for a Catalyst app. This copies the arm64 code of each
macOS slice into a new `ios-arm64-maccatalyst` slice, rewrites only that tag (platform macOS -> Mac Catalyst, minimum version mapped),
signs the frameworks ad hoc, and lists the slice in the xcframework. The x86_64 code is left out: its static objects carry the older
version-minimum command, which cannot be retagged in place. Nothing is downloaded and the pinned versions are unchanged.

Idempotent: an xcframework that already lists a Mac Catalyst slice is left alone. macOS only (codesign).
"""
import os
import plistlib
import shutil
import stat
import struct
import subprocess
import sys
from pathlib import Path

PACKAGES = {"ffmpegbuild", "libdovi", "libtruehd"}
SLICE = "ios-arm64-maccatalyst"
FAT_MAGICS = {0xCAFEBABE, 0xBEBAFECA}
ARM64 = 0x0100000C
LC_BUILD_VERSION = 0x32
PLATFORM_MACOS, PLATFORM_MACCATALYST = 1, 6


def fail(message):
    raise SystemExit(f"aether-catalyst-slices: {message}")


def checkouts_folder(start):
    """SourcePackages/checkouts above `start`, as prepare-aether.sh finds AetherEngine's."""
    cursor = Path(start).resolve()
    while True:
        candidate = cursor / "SourcePackages" / "checkouts"
        if candidate.is_dir():
            return candidate
        if cursor.parent == cursor:
            return None
        cursor = cursor.parent


def catalyst_version(macos):
    """The Mac Catalyst version of a macOS version, both encoded as xxxx.yy.zz. macOS 26 and later share the number; before that,
    Catalyst counts three ahead from macOS 12 (Catalyst 15), and 14.2 is the first for Apple silicon (macOS 11)."""
    major, minor = macos >> 16, (macos >> 8) & 0xFF
    if major >= 26:
        return macos
    if major >= 12:
        return ((major + 3) << 16) | (minor << 8)
    return (14 << 16) | (2 << 8)


def arm64_slice(data):
    """The arm64 part of a universal file, or the file itself when it is thin."""
    magic = struct.unpack_from(">I", data, 0)[0]
    if magic not in FAT_MAGICS:
        return data
    count = struct.unpack_from(">I", data, 4)[0]
    for index in range(count):
        cpu, _, offset, size, _ = struct.unpack_from(">IIIII", data, 8 + index * 20)
        if cpu == ARM64:
            return data[offset:offset + size]
    fail("no arm64 code in a macOS slice")


def retag_macho(data, start):
    """Rewrites the 64-bit Mach-O at `start` in place from macOS to Mac Catalyst. Returns False when it has no macOS build version."""
    if struct.unpack_from("<I", data, start)[0] != 0xFEEDFACF:
        return False
    ncmds = struct.unpack_from("<I", data, start + 16)[0]
    cursor = start + 32
    retagged = False
    for _ in range(ncmds):
        command, size = struct.unpack_from("<II", data, cursor)
        if command == LC_BUILD_VERSION:
            platform, minos = struct.unpack_from("<II", data, cursor + 8)
            if platform == PLATFORM_MACOS:
                struct.pack_into("<II", data, cursor + 8, PLATFORM_MACCATALYST, catalyst_version(minos))
                retagged = True
            elif platform != PLATFORM_MACCATALYST:
                fail(f"unexpected platform {platform}")
        cursor += size
    return retagged


def retag_archive(data):
    """Retags every object in a thin static archive. Sizes never change, so the archive's member offsets and symbol table stay valid."""
    cursor, objects = 8, 0
    while cursor < len(data):
        header = bytes(data[cursor:cursor + 60])
        name = header[:16].decode().strip()
        size = int(header[48:58].decode().strip())
        body = cursor + 60
        if name.startswith("#1/"):
            body += int(name[3:])
        if not name.startswith("__.SYMDEF") and retag_macho(data, body):
            objects += 1
        cursor += 60 + size + (size % 2)
    if objects == 0:
        fail("an archive with no macOS objects")


def make_writable(root):
    """Xcode keeps package checkouts read-only, and a copy keeps those modes: the new slice is made the user's to change."""
    paths = [root] + [Path(folder) / name for folder, folders, files in os.walk(root) for name in folders + files]
    for path in paths:
        if not path.is_symlink():
            path.chmod(path.stat().st_mode | stat.S_IWUSR)


def add_slice(xcframework):
    info_path = xcframework / "Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    libraries = info["AvailableLibraries"]
    if any(library.get("SupportedPlatformVariant") == "maccatalyst" for library in libraries):
        return False
    macos = next((library for library in libraries
                  if library.get("SupportedPlatform") == "macos" and not library.get("SupportedPlatformVariant")), None)
    if macos is None:
        fail(f"{xcframework.name} has no macOS slice")
    source, destination = xcframework / macos["LibraryIdentifier"], xcframework / SLICE
    if destination.exists():
        # Left by a run that stopped part way; it is not listed in Info.plist yet.
        make_writable(destination)
        shutil.rmtree(destination)
    shutil.copytree(source, destination, symlinks=True)
    make_writable(destination)
    library = destination / macos["LibraryPath"]
    binary = (destination / macos["BinaryPath"]) if "BinaryPath" in macos else library
    binary = binary.resolve()
    data = bytearray(arm64_slice(binary.read_bytes()))
    if data[:8] == b"!<arch>\n":
        retag_archive(data)
    elif not retag_macho(data, 0):
        fail(f"{binary.name} has no macOS build version")
    binary.write_bytes(data)
    if library.suffix == ".framework":
        subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(library)], check=True, stdout=subprocess.DEVNULL)
    entry = dict(macos)
    entry.update(LibraryIdentifier=SLICE, SupportedArchitectures=["arm64"], SupportedPlatform="ios",
                 SupportedPlatformVariant="maccatalyst")
    libraries.append(entry)
    info_path.chmod(info_path.stat().st_mode | stat.S_IWUSR)
    info_path.write_bytes(plistlib.dumps(info))
    return True


def main():
    if len(sys.argv) != 2:
        fail("usage: aether-catalyst-slices.py <build folder>")
    checkouts = checkouts_folder(sys.argv[1])
    if checkouts is None:
        # As in prepare-aether.sh: before packages resolve there is nothing to give a slice yet.
        print("aether-catalyst-slices: packages are not resolved yet; skipping", file=sys.stderr)
        return
    added = []
    for package in sorted(checkouts.iterdir()):
        if package.name.lower() not in PACKAGES:
            continue
        for xcframework in sorted(package.rglob("*.xcframework")):
            if add_slice(xcframework):
                added.append(xcframework.name)
    print(f"aether-catalyst-slices: Mac Catalyst slice added to {len(added)} xcframework(s)" + (": " + ", ".join(added) if added else ""))


if __name__ == "__main__":
    os.umask(0o022)
    main()
