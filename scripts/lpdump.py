#!/usr/bin/env python3
"""Minimal liblp (Android dynamic partition) metadata dumper + extractor.
Usage:
  lpdump.py super.img                # dump layout
  lpdump.py super.img --json out.json
  lpdump.py super.img --extract DIR  # extract logical partitions to raw images
  lpdump.py super.img --extract DIR --only system,vendor
"""
import sys, os, struct, json, hashlib

LP_METADATA_HEADER_MAGIC = 0x414C5030
LP_METADATA_GEOMETRY_MAGIC = 0x616C4467


def r32(b, o):
    return struct.unpack('<I', b[o:o + 4])[0]


def r64(b, o):
    return struct.unpack('<Q', b[o:o + 8])[0]


def parse(super_path):
    with open(super_path, 'rb') as f:
        f.seek(4096)
        geom = f.read(64)
        assert r32(geom, 0) == LP_METADATA_GEOMETRY_MAGIC, 'bad geometry magic'
        geo = {
            'struct_size': r32(geom, 4),
            'checksum': geom[8:40].hex(),
            'metadata_max_size': r32(geom, 40),
            'metadata_slot_count': r32(geom, 44),
            'logical_block_size': r32(geom, 48),
        }
        # metadata slots start at 3 pages; slot 0 is "current"
        meta_start = 4096 * 3
        f.seek(meta_start)
        hdr = f.read(geo['metadata_max_size'])
        assert r32(hdr, 0) == LP_METADATA_HEADER_MAGIC, 'bad metadata magic'
        major, minor = struct.unpack('<HH', hdr[4:8])
        header_size = r32(hdr, 8)
        tables_size = r32(hdr, 44)
        descs = []
        for i in range(5):
            o = 80 + i * 12
            descs.append({'offset': r32(hdr, o), 'num_entries': r32(hdr, o + 4), 'entry_size': r32(hdr, o + 8)})
        names = ['partitions', 'extents', 'groups', 'block_devices', 'flags']
        tables = {}
        base = meta_start + header_size
        for nm, d in zip(names, descs):
            f.seek(base + d['offset'])
            tables[nm] = {'descriptor': d, 'data': f.read(d['num_entries'] * d['entry_size'])}
    info = {'geometry': geo, 'major': major, 'minor': minor, 'header_size': header_size,
            'tables_size': tables_size, 'partitions': [], 'groups': [], 'block_devices': []}

    def cstr(b, o, ln):
        return b[o:o + ln].split(b'\0')[0].decode('utf-8', 'replace')

    # groups
    gd = tables['groups']['descriptor']
    for i in range(gd['num_entries']):
        e = tables['groups']['data'][i * gd['entry_size']:(i + 1) * gd['entry_size']]
        info['groups'].append({'name': cstr(e, 0, 36), 'flags': r32(e, 36), 'maximum_size': r64(e, 40)})
    # block devices
    bd = tables['block_devices']['descriptor']
    for i in range(bd['num_entries']):
        e = tables['block_devices']['data'][i * bd['entry_size']:(i + 1) * bd['entry_size']]
        es = bd['entry_size']
        info['block_devices'].append({'first_logical_sector': r64(e, 0), 'alignment': r64(e, 8),
                                      'alignment_offset': r32(e, 16), 'size': r64(e, 20),
                                      'partition_name': cstr(e, 28, es - 32), 'flags': r32(e, es - 4)})
    # extents
    ed = tables['extents']['descriptor']
    extents = []
    for i in range(ed['num_entries']):
        e = tables['extents']['data'][i * ed['entry_size']:(i + 1) * ed['entry_size']]
        extents.append({'num_sectors': r64(e, 0), 'target_type': r32(e, 8),
                        'target_data': r64(e, 12), 'target_source': r32(e, 20)})
    # partitions
    pd = tables['partitions']['descriptor']
    for i in range(pd['num_entries']):
        e = tables['partitions']['data'][i * pd['entry_size']:(i + 1) * pd['entry_size']]
        p = {'name': cstr(e, 0, 36), 'attributes': r32(e, 36), 'first_extent_index': r32(e, 40),
             'num_extents': r32(e, 44), 'group_index': r32(e, 48)}
        p['extents'] = extents[p['first_extent_index']:p['first_extent_index'] + p['num_extents']]
        p['size_bytes'] = sum(x['num_sectors'] for x in p['extents']) * 512
        p['group'] = info['groups'][p['group_index']]['name'] if p['group_index'] < len(info['groups']) else '?'
        info['partitions'].append(p)
    info['extents'] = extents
    return info


def extract(super_path, info, outdir, only=None):
    os.makedirs(outdir, exist_ok=True)
    fd = os.open(super_path, os.O_RDONLY | getattr(os, 'O_BINARY', 0))
    try:
        for p in info['partitions']:
            if only and p['name'] not in only:
                continue
            out_path = os.path.join(outdir, p['name'] + '.img')
            with open(out_path, 'wb') as out:
                for ex in p['extents']:
                    if ex['target_type'] == 1:  # zero
                        out.write(b'\0' * ex['num_sectors'] * 512)
                        continue
                    src = info['block_devices'][ex['target_source']]
                    off = ex['target_data'] * 512
                    os.lseek(fd, off, 0)
                    remaining = ex['num_sectors'] * 512
                    while remaining:
                        chunk = os.read(fd, min(8 << 20, remaining))
                        if not chunk:
                            raise IOError('short read on %s' % p['name'])
                        out.write(chunk)
                        remaining -= len(chunk)
            with open(out_path, 'rb') as f:
                h = hashlib.sha256()
                while True:
                    b = f.read(8 << 20)
                    if not b:
                        break
                    h.update(b)
            print('%-16s %12d bytes -> %s sha256=%s' % (p['name'], p['size_bytes'], out_path, h.hexdigest()[:16]))
    finally:
        os.close(fd)


def main():
    path = sys.argv[1]
    out_json = None
    extract_dir = None
    only = None
    i = 2
    while i < len(sys.argv):
        a = sys.argv[i]
        if a == '--json':
            out_json = sys.argv[i + 1]; i += 2
        elif a == '--extract':
            extract_dir = sys.argv[i + 1]; i += 2
        elif a == '--only':
            only = set(sys.argv[i + 1].split(',')); i += 2
        else:
            raise SystemExit('bad arg ' + a)
    info = parse(path)
    g = info['geometry']
    print('geometry: max_size=%d slots=%d logical_block=%d' % (g['metadata_max_size'], g['metadata_slot_count'], g['logical_block_size']))
    print('metadata: v%d.%d header_size=%d tables_size=%d' % (info['major'], info['minor'], info['header_size'], info['tables_size']))
    print('block devices:')
    for b in info['block_devices']:
        print('  %-20s size=%d first_logical_sector=%d alignment=%d' % (b['partition_name'], b['size'], b['first_logical_sector'], b['alignment']))
    print('groups:')
    for gr in info['groups']:
        print('  %-20s max=%d flags=0x%x' % (gr['name'], gr['maximum_size'], gr['flags']))
    print('partitions:')
    print('  %-20s %14s %10s %-12s %s' % ('name', 'size', 'extents', 'group', 'attrs'))
    total = 0
    for p in sorted(info['partitions'], key=lambda x: -x['size_bytes']):
        total += p['size_bytes']
        print('  %-20s %14d %10d %-12s 0x%x' % (p['name'], p['size_bytes'], p['num_extents'], p['group'], p['attributes']))
    print('total partitions size = %d (%.2f GiB)' % (total, total / 1073741824))
    print('super file size = %d' % os.path.getsize(path))
    if out_json:
        slim = {k: v for k, v in info.items()}
        with open(out_json, 'w') as f:
            json.dump(slim, f, indent=1)
        print('json ->', out_json)
    if extract_dir:
        extract(path, info, extract_dir, only)


if __name__ == '__main__':
    main()
