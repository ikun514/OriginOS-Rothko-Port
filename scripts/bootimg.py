#!/usr/bin/env python3
"""Android boot image (v0-v4) / vendor_boot (v3-v4) parser + ramdisk lister.
Usage:
  bootimg.py info <img>
  bootimg.py unpack <img> <outdir>
  bootimg.py cpio-list <ramdisk-file>
  bootimg.py cpio-extract <ramdisk-file> <outdir>
"""
import sys, os, struct, hashlib, gzip, io, bz2, lzma

BOOT_MAGIC = b'ANDROID!'

FOOTER_SIZE = 4096


def lz4_legacy_decompress(data):
    """Decode legacy lz4 framing: optional 0x184C2102 magic, then [u32le size][block]...; high bit => stored."""
    out = bytearray()
    i = 0
    if len(data) >= 4 and data[:4] == b'\x02\x21\x4c\x18':
        i = 4
    while i + 4 <= len(data):
        sz = struct.unpack('<I', data[i:i + 4])[0]
        i += 4
        if sz == 0 or sz > 0x10000000:
            break
        stored = bool(sz & 0x80000000)
        sz &= 0x7fffffff
        blk = data[i:i + sz]
        i += sz
        if stored:
            out += blk
        else:
            out += lz4_block_decode(blk)
    return bytes(out)


def lz4_block_decode(src):
    """Pure-python LZ4 block decompressor."""
    out = bytearray()
    i = 0
    n = len(src)
    while i < n:
        token = src[i]; i += 1
        lit = token >> 4
        if lit == 15:
            while True:
                b = src[i]; i += 1
                lit += b
                if b != 255:
                    break
        if lit:
            out += src[i:i + lit]
            i += lit
        if i >= n:
            break
        off = src[i] | (src[i + 1] << 8); i += 2
        mlen = token & 0xf
        if mlen == 15:
            while True:
                b = src[i]; i += 1
                mlen += b
                if b != 255:
                    break
        mlen += 4
        start = len(out) - off
        if start < 0:
            raise ValueError('bad lz4 offset')
        if off >= mlen:
            out += out[start:start + mlen]
        else:
            for k in range(mlen):
                out.append(out[start + k])
    return bytes(out)


def lz4_legacy_compress(data, block_size=8 * 1024 * 1024):
    import lz4.block
    out = bytearray()
    for i in range(0, len(data), block_size):
        chunk = data[i:i + block_size]
        comp = lz4.block.compress(chunk, store_size=False, mode='high_compression')
        if len(comp) >= len(chunk):
            out += struct.pack('<I', len(chunk) | 0x80000000) + chunk
        else:
            out += struct.pack('<I', len(comp)) + comp
    return bytes(out)


def decomp(data):
    """auto-detect compression -> (name, bytes)"""
    if data[:2] == b'\x1f\x8b':
        return 'gzip', gzip.decompress(data)
    if data[:6] == b'\xfd7zXZ\x00':
        return 'xz', lzma.decompress(data)
    if data[:3] == b'BZh':
        return 'bzip2', bz2.decompress(data)
    if data[:4] == b'\x02\x21\x4c\x18':
        return 'lz4-legacy', lz4_legacy_decompress(data)
    if data[:4] == b'\x04\x22\x4d\x18':
        import lz4.frame
        return 'lz4', lz4.frame.decompress(data)
    if data[:4] == b'\x5d\x00\x00\x00':
        try:
            import zstandard
            return 'zstd', zstandard.ZstdDecompressor().decompress(data)
        except Exception:
            pass
    if data[:4] == b'\x28\xb5\x2f\xfd':
        import zstandard
        return 'zstd', zstandard.ZstdDecompressor().decompress(data)
    return 'raw', data


def parse_boot(data):
    assert data[:8] == BOOT_MAGIC, 'not a boot image: %r' % data[:8]
    hdr = {}
    (kernel_size, kernel_addr, ramdisk_size, ramdisk_addr, second_size, second_addr,
     tags_addr, page_size, hdr_version, os_version) = struct.unpack('<10I', data[8:48])
    hdr.update(kernel_size=kernel_size, kernel_addr=kernel_addr, ramdisk_size=ramdisk_size,
               second_size=second_size, tags_addr=tags_addr, page_size=page_size,
               header_version=hdr_version, os_version=os_version)
    hdr['name'] = data[48:64].rstrip(b'\0').decode('utf-8', 'replace')
    hdr['cmdline'] = data[64:64 + 512].rstrip(b'\0').decode('utf-8', 'replace')
    hdr['id'] = data[576:576 + 32].hex()
    hdr['extra_cmdline'] = data[608:608 + 1024].rstrip(b'\0').decode('utf-8', 'replace')
    if hdr_version >= 3:
        hdr['header_size'] = struct.unpack('<I', data[20:24])[0]  # wrong slot; fixed below
    return hdr


def parse_boot_v3plus(data):
    assert data[:8] == BOOT_MAGIC
    hdr = {}
    (hdr['kernel_size'], hdr['ramdisk_size'], hdr['os_version'], hdr['header_size'],
     hdr['reserved0']) = struct.unpack('<5I', data[8:28])
    hdr['header_version'] = struct.unpack('<I', data[40:44])[0]
    hdr['cmdline'] = data[44:44 + 1536].rstrip(b'\0').decode('utf-8', 'replace')
    hdr['page_size'] = 4096
    if hdr['header_version'] >= 4:
        (hdr['signature_size'],) = struct.unpack('<I', data[1580:1584])
    else:
        hdr['signature_size'] = 0
    off = 4096
    hdr['kernel_off'] = off; off += hdr['kernel_size']
    hdr['ramdisk_off'] = off; off += hdr['ramdisk_size']
    return hdr


def parse_vendor_boot(data):
    assert data[:8] == b'VNDRBOOT', 'not vendor_boot: %r' % data[:8]
    hdr = {}
    off = 8
    hdr['header_version'], hdr['page_size'], hdr['kernel_addr'], hdr['ramdisk_addr'], \
        hdr['vendor_ramdisk_size'] = struct.unpack('<5I', data[off:off + 20])
    off += 20
    hdr['cmdline'] = data[off:off + 2048].rstrip(b'\0').decode('utf-8', 'replace')
    off += 2048
    hdr['tags_addr'] = struct.unpack('<I', data[off:off + 4])[0]
    off += 4
    hdr['name'] = data[off:off + 16].rstrip(b'\0').decode('utf-8', 'replace')
    off += 16
    hdr['header_size'] = struct.unpack('<I', data[off:off + 4])[0]
    off += 4
    hdr['dtb_size'] = struct.unpack('<I', data[off:off + 4])[0]
    off += 4
    hdr['dtb_addr'] = struct.unpack('<Q', data[off:off + 8])[0]
    off += 8
    entries = []
    ps0 = hdr['page_size'] or 4096
    if hdr['header_version'] >= 4:
        hdr['table_size'], hdr['table_entry_num'], hdr['table_entry_size'], hdr['bootconfig_size'] = \
            struct.unpack('<4I', data[off:off + 16])
        off += 16
        dtb_off_tmp = ((hdr['header_size'] + ps0 - 1) // ps0) * ps0 + hdr['vendor_ramdisk_size']
        dtb_off_tmp = ((dtb_off_tmp + ps0 - 1) // ps0) * ps0
        table_off = ((dtb_off_tmp + hdr['dtb_size'] + ps0 - 1) // ps0) * ps0
        for i in range(hdr['table_entry_num']):
            eo = table_off + i * hdr['table_entry_size']
            size, eoffset, typ = struct.unpack('<3I', data[eo:eo + 12])
            nm = data[eo + 12:eo + 12 + 32].rstrip(b'\0').decode('utf-8', 'replace')
            board = data[eo + 44:eo + 44 + 64].rstrip(b'\0').decode('utf-8', 'replace')
            entries.append({'size': size, 'offset': eoffset, 'type': typ, 'name': nm, 'board_id': board})
        hdr['table_off'] = table_off
    hdr['entries'] = entries
    ps = hdr['page_size'] or 4096
    hdr['vendor_ramdisk_off'] = ((hdr['header_size'] + ps - 1) // ps) * ps
    hdr['dtb_off'] = ((hdr['vendor_ramdisk_off'] + hdr['vendor_ramdisk_size'] + ps - 1) // ps) * ps
    return hdr


def cpio_entries(data):
    """iterate newc cpio entries -> (name, mode, uid, gid, data)"""
    i = 0
    out = []
    while True:
        if data[i:i + 6] not in (b'070701', b'070702'):
            if data[i:i + 4] == b'\0\0\0\0':
                break
            raise ValueError('bad cpio magic at %d: %r' % (i, data[i:i + 16]))
        hdr = data[i:i + 110]
        fields = [int(hdr[6 + j * 8:6 + (j + 1) * 8], 16) for j in range(13)]
        ino, mode, uid, gid, nlink, mtime, filesize = fields[0], fields[1], fields[2], fields[3], fields[4], fields[5], fields[6]
        namesize, chksum = fields[11], fields[12]
        name = data[i + 110:i + 110 + namesize - 1].decode('utf-8', 'replace')
        pos = i + 110 + namesize
        pos = (pos + 3) & ~3
        body = data[pos:pos + filesize]
        pos = (pos + filesize + 3) & ~3
        out.append({'name': name, 'mode': mode, 'uid': uid, 'gid': gid, 'size': filesize, 'data': body})
        i = pos
        if name == 'TRAILER!!!':
            break
    return out


def cmd_info(path):
    data = open(path, 'rb').read()
    if data[:8] != BOOT_MAGIC:
        print('not a boot image, first bytes:', data[:16].hex())
        return
    version = struct.unpack('<I', data[40:44])[0]
    print('file', path, 'size', len(data))
    print('header_version', version)
    if version in (0, 1, 2):
        h = parse_boot(data)
        for k, v in h.items():
            if k != 'cmdline':
                print(' ', k, '=', v)
        print('  cmdline =', h['cmdline'][:200])
        ps = h['page_size']
        off = ps
        ker = data[off:off + h['kernel_size']]
        off += (h['kernel_size'] + ps - 1) // ps * ps
        rd = data[off:off + h['ramdisk_size']]
        print('  kernel magic', ker[:8].hex(), 'ramdisk bytes', len(rd), 'compress?', decomp(rd)[0] if rd else 'none')
    else:
        h = parse_boot_v3plus(data)
        for k, v in h.items():
            if k != 'cmdline':
                print(' ', k, '=', v)
        print('  cmdline =', h['cmdline'][:200])
        ker = data[h['kernel_off']:h['kernel_off'] + h['kernel_size']]
        rd = data[h['ramdisk_off']:h['ramdisk_off'] + h['ramdisk_size']]
        print('  kernel magic', ker[:16].hex(), 'ramdisk', len(rd))
        if rd:
            n, d = decomp(rd)
            print('  ramdisk compression', n, 'decompressed', len(d))
            try:
                ents = cpio_entries(d)
                print('  cpio entries', len(ents))
                for e in ents[:40]:
                    print('   %s %o %d' % (e['name'], e['mode'], e['size']))
            except Exception as ex:
                print('  cpio parse err', ex)


def cmd_unpack(path, outdir):
    data = open(path, 'rb').read()
    os.makedirs(outdir, exist_ok=True)
    version = struct.unpack('<I', data[40:44])[0]
    if version in (0, 1, 2):
        h = parse_boot(data); ps = h['page_size']
        off = ps
        open(os.path.join(outdir, 'kernel'), 'wb').write(data[off:off + h['kernel_size']])
        off += (h['kernel_size'] + ps - 1) // ps * ps
        rd = data[off:off + h['ramdisk_size']]
        off += (h['ramdisk_size'] + ps - 1) // ps * ps
        sec = data[off:off + h['second_size']]
        if rd:
            n, d = decomp(rd)
            open(os.path.join(outdir, 'ramdisk.cpio'), 'wb').write(d)
        if sec:
            open(os.path.join(outdir, 'second'), 'wb').write(sec)
        print('unpacked boot v%d' % version)
        return
    if version in (3, 4):
        h = parse_boot_v3plus(data)
        open(os.path.join(outdir, 'kernel'), 'wb').write(data[h['kernel_off']:h['kernel_off'] + h['kernel_size']])
        rd = data[h['ramdisk_off']:h['ramdisk_off'] + h['ramdisk_size']]
        if rd:
            n, d = decomp(rd)
            open(os.path.join(outdir, 'ramdisk.cpio'), 'wb').write(d)
            print('ramdisk compression', n)
        print('unpacked boot v%d' % version)
        return
    raise SystemExit('unsupported header version %d' % version)


def cmd_vendor_boot(path, outdir):
    data = open(path, 'rb').read()
    h = parse_vendor_boot(data)
    os.makedirs(outdir, exist_ok=True)
    for k, v in h.items():
        if k != 'cmdline':
            print(' ', k, '=', v)
    print('  cmdline =', h['cmdline'][:300])
    ps = h['page_size']
    total = h['vendor_ramdisk_size']
    for i, e in enumerate(h['entries']):
        off = h['vendor_ramdisk_off'] + e['offset']
        chunk = data[off:off + e['size']]
        fn = 'ramdisk_%d_%s.bin' % (i, (e['name'] or 'frag').replace('/', '_'))
        open(os.path.join(outdir, fn), 'wb').write(chunk)
        try:
            n, d = decomp(chunk)
            open(os.path.join(outdir, fn + '.cpio'), 'wb').write(d)
            print('  fragment %d %s type=%d size=%d comp=%s entries=%d' % (
                i, e['name'], e['type'], e['size'], n, len(cpio_entries(d))))
        except Exception as ex:
            print('  fragment %d %s type=%d size=%d decomp/parse err %s' % (i, e['name'], e['type'], e['size'], ex))
    dtb = data[h['dtb_off']:h['dtb_off'] + h['dtb_size']]
    if dtb:
        open(os.path.join(outdir, 'dtb.bin'), 'wb').write(dtb)
        print('  dtb size', len(dtb), 'magic', dtb[:8].hex())
    print('  header_size', h['header_size'], 'vendor_ramdisk_off', h['vendor_ramdisk_off'], 'dtb_off', h['dtb_off'])


def cmd_cpio_list(path):
    data = open(path, 'rb').read()
    n, d = decomp(data)
    ents = cpio_entries(d)
    print('compression', n, 'entries', len(ents))
    for e in ents:
        print('%o %5d %s' % (e['mode'], e['size'], e['name']))


def cmd_cpio_extract(path, outdir):
    data = open(path, 'rb').read()
    n, d = decomp(data)
    ents = cpio_entries(d)
    for e in ents:
        rel = e['name'].lstrip('/')
        if rel in ('', '.', 'TRAILER!!!'):
            continue
        p = os.path.join(outdir, rel)
        if e['mode'] & 0o170000 == 0o040000:
            os.makedirs(p, exist_ok=True)
        elif e['mode'] & 0o170000 == 0o120000:
            os.makedirs(os.path.dirname(p) or outdir, exist_ok=True)
            try:
                os.symlink(e['data'].decode(), p)
            except OSError:
                pass
        else:
            os.makedirs(os.path.dirname(p) or outdir, exist_ok=True)
            with open(p, 'wb') as f:
                f.write(e['data'])
            os.chmod(p, (e['mode'] & 0o7777) | 0o600)
    print('extracted', len(ents), 'entries to', outdir)


if __name__ == '__main__':
    cmd = sys.argv[1]
    if cmd == 'info':
        cmd_info(sys.argv[2])
    elif cmd == 'unpack':
        cmd_unpack(sys.argv[2], sys.argv[3])
    elif cmd == 'vendor-boot':
        cmd_vendor_boot(sys.argv[2], sys.argv[3])
    elif cmd == 'cpio-list':
        cmd_cpio_list(sys.argv[2])
    elif cmd == 'cpio-extract':
        cmd_cpio_extract(sys.argv[2], sys.argv[3])
    else:
        raise SystemExit(__doc__)
