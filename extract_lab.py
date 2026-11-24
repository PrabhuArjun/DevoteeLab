#!/usr/bin/env python3
"""Validate and extract a DevoteeLab text bundle; no network, installation or execution."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re

MANIFEST_START = b'=== LAB-MANIFEST-JSON-BEGIN ===\n'
MANIFEST_END = b'=== LAB-MANIFEST-JSON-END ===\n'
FILE_START = b'=== LAB-FILE-BEGIN '
FILE_END = b'=== LAB-FILE-END ===\n'
MAX_BUNDLE = 8 * 1024 * 1024


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('duplicate JSON key')
        result[key] = value
    return result


def parse_json(data):
    return json.loads(data, object_pairs_hook=unique_object)


def safe_path(name):
    if not isinstance(name, str) or not re.fullmatch(r'[A-Za-z0-9_.\-/]+', name):
        raise ValueError('invalid relative path')
    parts = name.split('/')
    if any(p in ('', '.', '..') or p.endswith('.') for p in parts):
        raise ValueError('unsafe path segment')
    reserved = {'CON', 'PRN', 'AUX', 'NUL'} | {f'{p}{n}' for p in ('COM', 'LPT') for n in range(1, 10)}
    if any(p.split('.')[0].upper() in reserved or p.casefold() == '.git' for p in parts):
        raise ValueError('reserved path')
    if PurePosixPath(name).is_absolute():
        raise ValueError('absolute path')
    return name


def read_bundle(path):
    path = Path(path)
    if path.stat().st_size > MAX_BUNDLE:
        raise ValueError('bundle too large')
    data = path.read_bytes()
    data.decode('utf-8')
    if data.count(MANIFEST_START) != 1 or data.count(MANIFEST_END) != 1:
        raise ValueError('manifest missing or duplicated')
    head, rest = data.split(MANIFEST_START, 1)
    if not head.startswith(b'DEVOTEELAB PORTABLE 2.0\n'):
        raise ValueError('unknown bundle format')
    manifest_bytes, rest = rest.split(MANIFEST_END, 1)
    manifest = parse_json(manifest_bytes)
    if manifest.get('format') != 'devoteelab-text-v2' or type(manifest.get('file_count')) is not int:
        raise ValueError('invalid manifest format')
    entries = manifest.get('files')
    if not isinstance(entries, list) or not 1 <= len(entries) <= 500 or len(entries) != manifest['file_count']:
        raise ValueError('invalid file count')
    expected, folded = {}, set()
    for e in entries:
        if not isinstance(e, dict) or set(e) != {'path', 'sha256', 'bytes'}:
            raise ValueError('invalid file metadata')
        name = safe_path(e['path'])
        if name.casefold() in folded:
            raise ValueError('duplicate or case-colliding path')
        if type(e['bytes']) is not int or not 0 <= e['bytes'] <= 2 * 1024 * 1024:
            raise ValueError('invalid file size')
        if not isinstance(e['sha256'], str) or not re.fullmatch(r'[a-f0-9]{64}', e['sha256']):
            raise ValueError('invalid file hash')
        folded.add(name.casefold())
        expected[name] = e
    for name in expected:
        parts = name.split('/')
        if any('/'.join(parts[:i]).casefold() in folded for i in range(1, len(parts))):
            raise ValueError('file/directory collision')
    result = {}
    while rest.strip():
        rest = rest.lstrip(b'\n')
        if not rest.startswith(FILE_START):
            raise ValueError('unexpected data between file blocks')
        header, sep, rest = rest.partition(b'\n')
        if not sep or not header.endswith(b' ==='):
            raise ValueError('invalid file header')
        e = parse_json(header[len(FILE_START):-4])
        if not isinstance(e, dict):
            raise ValueError('invalid file metadata')
        name = safe_path(e.get('path'))
        if name in result or expected.get(name) != e:
            raise ValueError('duplicate or unlisted file')
        marker = b'\n' + FILE_END
        pos = rest.find(marker)
        if pos < 0:
            raise ValueError('missing file end')
        body, rest = rest[:pos + 1], rest[pos + len(marker):]
        if len(body) != e['bytes'] or hashlib.sha256(body).hexdigest() != e['sha256']:
            raise ValueError('content hash or size mismatch')
        result[name] = body
    if set(result) != set(expected):
        raise ValueError('missing file blocks')
    return manifest, result


def extract(bundle, destination):
    manifest, files = read_bundle(bundle)  # Validate everything before the first write.
    root = Path(os.path.abspath(destination))
    for ancestor in [root, *root.parents]:
        if ancestor.is_symlink():
            raise ValueError('symlink destination or parent')
    if not root.parent.is_dir():
        raise ValueError('destination parent must exist')
    root.mkdir(mode=0o700, exist_ok=False)  # Atomic reservation; never overwrite an existing directory.
    for name, body in files.items():
        target = root.joinpath(*name.split('/'))
        target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        with target.open('xb') as output:
            output.write(body)
    return manifest['file_count']


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('bundle')
    p.add_argument('destination', nargs='?')
    p.add_argument('--check', action='store_true', help='validate only, without writing')
    a = p.parse_args()
    try:
        if a.check:
            manifest, _ = read_bundle(a.bundle)
            print(json.dumps({'status': 'validated', 'files': manifest['file_count'], 'writes': 0}))
        elif not a.destination:
            p.error('destination is required unless --check is used')
        else:
            print(json.dumps({'status': 'extracted', 'files': extract(a.bundle, a.destination)}))
    except (ValueError, OSError, UnicodeError) as e:
        p.exit(1, f'Not extracted: {e}\n')


if __name__ == '__main__':
    main()
