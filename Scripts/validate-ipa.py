#!/usr/bin/env python3
"""Check IPA structure and its main Mach-O platform; does not verify signing."""
import argparse
import json
import plistlib
import struct
import zipfile
from pathlib import PurePosixPath

ARM64 = 0x0100000C
IOS = 2

def macho_platforms(data):
    if len(data) < 32 or data[:4] != b'\xcf\xfa\xed\xfe':
        raise ValueError('Expected a thin little-endian 64-bit Mach-O device executable.')
    _, cpu, _, filetype, ncmds, sizecmds, _, _ = struct.unpack_from('<8I', data)
    if cpu != ARM64 or filetype != 2:
        raise ValueError('The main executable must be an arm64 Mach-O executable.')
    end = 32 + sizecmds
    if end > len(data) or ncmds > sizecmds // 8:
        raise ValueError('Truncated Mach-O command table.')
    offset = 32
    platforms = []
    for _ in range(ncmds):
        if offset + 8 > end:
            raise ValueError('Truncated Mach-O load command.')
        cmd, length = struct.unpack_from('<II', data, offset)
        if length < 8 or length % 4 or offset + length > end:
            raise ValueError('Invalid Mach-O load command length.')
        if cmd == 0x32:  # LC_BUILD_VERSION: iOS=2, iOSSimulator=7
            if length < 24:
                raise ValueError('Truncated LC_BUILD_VERSION.')
            platform, _, _, ntools = struct.unpack_from('<4I', data, offset + 8)
            if 24 + ntools * 8 > length:
                raise ValueError('Truncated build tools table.')
            platforms.append(platform)
        elif cmd == 0x25:  # LC_VERSION_MIN_IPHONEOS, older device binaries
            if length < 16:
                raise ValueError('Truncated LC_VERSION_MIN_IPHONEOS.')
            platforms.append(IOS)
        elif cmd in (0x24, 0x2F, 0x30):
            raise ValueError('macOS, tvOS or watchOS executable is not an iPhone app.')
        offset += length
    if offset != end or not platforms or any(p != IOS for p in platforms):
        raise ValueError('Executable is not confirmed as iOS device platform; simulator products are rejected.')
    return platforms

def validate(path):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        if len(set(names)) != len(names):
            raise ValueError('Duplicate ZIP entry.')
        for name in names:
            parts = PurePosixPath(name).parts
            if name.startswith('/') or '\\' in name or '..' in parts:
                raise ValueError('Unsafe ZIP path.')
        apps = sorted({n.split('/')[1] for n in names if n.startswith('Payload/')
                       and len(n.split('/')) > 2 and n.split('/')[1].endswith('.app')})
        if len(apps) != 1:
            raise ValueError('Expected exactly one main Payload/*.app.')
        prefix = f'Payload/{apps[0]}/'
        info = plistlib.loads(archive.read(prefix + 'Info.plist'))
        executable = info.get('CFBundleExecutable')
        if not isinstance(executable, str) or not executable or '/' in executable or '\\' in executable or executable in ('.', '..'):
            raise ValueError('Invalid CFBundleExecutable.')
        if info.get('CFBundlePackageType') != 'APPL' or info.get('CFBundleSupportedPlatforms') != ['iPhoneOS']:
            raise ValueError('Info.plist must identify an iPhoneOS application.')
        if info.get('CFBundleDisplayName') not in {'PULSE', 'WHOOP'} or not info.get('CFBundleIdentifier'):
            raise ValueError('App display name or bundle identifier is missing.')
        entry = archive.getinfo(prefix + executable)
        if not (entry.external_attr >> 16) & 0o111:
            raise ValueError('The main executable has no executable permission in the IPA.')
        platforms = macho_platforms(archive.read(entry))
        extensions = sorted({n[len(prefix + 'PlugIns/'):].split('/')[0] for n in names
                             if n.startswith(prefix + 'PlugIns/') and '.appex/' in n})
        if info.get('NSSupportsLiveActivities') and not extensions:
            raise ValueError('Live Activities are declared but the widget extension is missing.')
        for extension in extensions:
            base = prefix + 'PlugIns/' + extension + '/'
            child = plistlib.loads(archive.read(base + 'Info.plist'))
            child_id, child_executable = child.get('CFBundleIdentifier'), child.get('CFBundleExecutable')
            if child.get('CFBundlePackageType') != 'XPC!' or child.get('CFBundleSupportedPlatforms') != ['iPhoneOS']:
                raise ValueError('The embedded extension must target iPhoneOS.')
            if not isinstance(child_id, str) or not child_id.startswith(info['CFBundleIdentifier'] + '.'):
                raise ValueError('Extension identifier must extend the main application identifier.')
            if not isinstance(child_executable, str) or '/' in child_executable or '\\' in child_executable or child_executable in ('', '.', '..'):
                raise ValueError('Invalid extension executable.')
            child_entry = archive.getinfo(base + child_executable)
            if not (child_entry.external_attr >> 16) & 0o111:
                raise ValueError('The extension executable has no executable permission.')
            macho_platforms(archive.read(child_entry))
        if archive.testzip() is not None:
            raise ValueError('IPA checksum validation failed.')
        return {'app': apps[0], 'bundle_identifier': info['CFBundleIdentifier'],
                'architecture': 'arm64', 'platform': 'iOS device',
                'platform_load_commands': platforms, 'embedded_extensions': extensions, 'signing': 'not checked',
                'warning': 'Structure validation does not establish that this app builds, runs, or can be installed.'}

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ipa')
    args = parser.parse_args()
    try:
        print(json.dumps(validate(args.ipa), indent=2))
    except (ValueError, KeyError, OSError, zipfile.BadZipFile, plistlib.InvalidFileException, struct.error) as error:
        parser.exit(1, f'IPA validation failed: {error}\n')
