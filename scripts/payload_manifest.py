#!/usr/bin/env python3
"""Minimal Android OTA payload.bin manifest parser -> JSON summary.
Usage: payload_manifest.py <payload.bin> [out.json] [--debug]
"""
import sys, json, struct, collections

OPS = {
    0: 'REPLACE', 1: 'REPLACE_BZ', 2: 'MOVE', 3: 'BSDIFF', 4: 'SOURCE_COPY',
    5: 'SOURCE_BSDIFF', 6: 'ZERO', 7: 'DISCARD', 8: 'REPLACE_XZ',
    9: 'PUFFDIFF', 10: 'BROTLI_BSDIFF', 11: 'ZUCCHINI',
    12: 'LZ4DIFF_BSDIFF', 13: 'LZ4DIFF_PUFFDIFF',
}


def read_varint(b, i):
    r = 0; s = 0
    while True:
        x = b[i]; i += 1
        r |= (x & 0x7f) << s
        if not x & 0x80:
            return r, i
        s += 7


def parse_msg(b):
    i = 0; out = collections.defaultdict(list); n = len(b)
    while i < n:
        key, i = read_varint(b, i)
        f, wt = key >> 3, key & 7
        if wt == 0:
            v, i = read_varint(b, i)
        elif wt == 2:
            ln, i = read_varint(b, i)
            v = b[i:i + ln]; i += ln
        elif wt == 5:
            v = b[i:i + 4]; i += 4
        elif wt == 1:
            v = b[i:i + 8]; i += 8
        else:
            raise ValueError('wt %d at %d' % (wt, i))
        out[f].append((wt, v))
    return out


def get_var(m, f, default=0):
    v = m.get(f)
    if not v or v[0][0] != 0:
        return default
    return v[0][1]


def get_bytes(m, f):
    v = m.get(f)
    if not v or v[0][0] != 2:
        return b''
    return v[0][1]


def parse_extent(b):
    m = parse_msg(b)
    return get_var(m, 1), get_var(m, 2)


def main():
    path = sys.argv[1]
    out = None
    debug = False
    for a in sys.argv[2:]:
        if a == '--debug':
            debug = True
        else:
            out = a
    with open(path, 'rb') as f:
        assert f.read(4) == b'CrAU'
        ver = struct.unpack('>Q', f.read(8))[0]
        msize = struct.unpack('>Q', f.read(8))[0]
        sigsize = struct.unpack('>I', f.read(4))[0] if ver >= 2 else 0
        man = f.read(msize)
    m = parse_msg(man)
    info = {'version': ver, 'manifest_size': msize, 'block_size': get_var(m, 3),
            'minor_version': get_var(m, 12), 'partitions': []}
    print('payload v%d manifest=%d sig=%d block_size=%d minor=%d' % (
        ver, msize, sigsize, info['block_size'], info['minor_version']))
    for wt, pb in m.get(13, []):
        p = parse_msg(pb)
        pu = {'name': get_bytes(p, 1).decode('utf-8', 'replace')}
        ops = []
        for wt2, ob in p.get(8, []):
            o = parse_msg(ob)
            t = OPS.get(get_var(o, 1), get_var(o, 1))
            ops.append({'t': t, 'off': get_var(o, 2), 'len': get_var(o, 3),
                        'dst': [parse_extent(e) for _, e in o.get(6, [])],
                        'src': [parse_extent(e) for _, e in o.get(4, [])]})
        pu['ops'] = ops
        pu['op_counts'] = dict(collections.Counter(o['t'] for o in ops))
        pu['n_blocks'] = sum(x[1] for o in ops for x in o['dst'])
        pu['size'] = max((x[0] + x[1] for o in ops for x in o['dst']), default=0) * 4096
        if debug:
            pu['fields'] = {k: (v[0][0], str(v[0][1])[:40]) for k, v in p.items()}
        info['partitions'].append(pu)
    info['partitions'].sort(key=lambda x: x['name'])
    if debug:
        for pu in info['partitions'][:2]:
            print(pu['name'], pu['fields'])
    print('%-22s %14s %10s  %s' % ('partition', 'size', 'blocks', 'op_counts'))
    for p in info['partitions']:
        print('%-22s %14d %10d  %s' % (p['name'], p['size'], p['n_blocks'], p['op_counts']))
    if out:
        with open(out, 'w') as f:
            json.dump(info, f, indent=1)
        print('wrote', out)


if __name__ == '__main__':
    main()
