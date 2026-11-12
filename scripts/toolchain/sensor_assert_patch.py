#!/usr/bin/env python3
"""Analyze vivo libsensorservice.so: find function containing a BL to __assert2, dump context, patch it."""
import struct, sys

p = sys.argv[1] if len(sys.argv) > 1 else r'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\OriginOS_Rothko_Port\02_base\libsensorservice_vivo.so'
d = open(p, 'rb').read()

e_shoff = struct.unpack('<Q', d[0x28:0x30])[0]
es = struct.unpack('<H', d[0x3a:0x3c])[0]
n = struct.unpack('<H', d[0x3c:0x3e])[0]
secs = [struct.unpack('<IIQQQQIIQQ', d[e_shoff + i * es:e_shoff + i * es + 64]) for i in range(n)]
shstr = secs[struct.unpack('<H', d[0x3e:0x40])[0]]


def sname(off):
    end = d.index(b'\0', shstr[4] + off)
    return d[shstr[4] + off:end].decode()


by = {sname(s[0]): s for s in secs}
dynsym = by['.dynsym']
dynstr = by['.dynstr']
rela = by['.rela.plt']


def sym(i):
    o = dynsym[4] + i * 24
    st = struct.unpack('<I', d[o:o + 4])[0]
    val, size = struct.unpack('<QQ', d[o + 8:o + 24])
    end = d.index(b'\0', dynstr[4] + st)
    return d[dynstr[4] + st:end].decode(), val, size


funcs = []
for i in range(dynsym[5] // 24):
    nm, val, size = sym(i)
    if size > 0:
        funcs.append((val, size, nm))
funcs.sort()

target = 0x3895c
best = None
for val, size, nm in funcs:
    if val <= target < val + size:
        best = (val, size, nm)
print('assert BL at 0x%x inside func:' % target, best)


def insn(off):
    w = struct.unpack('<I', d[off:off + 4])[0]
    note = ''
    if (w & 0xFC000000) == 0x94000000:
        imm = w & 0x03FFFFFF
        if imm & 0x02000000:
            imm -= 0x04000000
        note = 'BL %#x' % (off + imm * 4)
    elif (w & 0xFF000010) == 0x54000000:
        imm = w & 0xFFFF
        if imm & 0x8000:
            imm -= 0x10000
        note = 'B.cond %#x' % (off + imm * 4)
    elif (w & 0x7C000000) == 0x14000000:
        imm = w & 0x03FFFFFF
        if imm & 0x02000000:
            imm -= 0x04000000
        note = 'B %#x' % (off + imm * 4)
    return w, note


print('--- instructions 0x388c0 .. 0x38990 ---')
for off in range(0x388c0, 0x38990, 4):
    w, note = insn(off)
    print('%#x %08x %s' % (off, w, note))

print('--- instructions 0x3895c .. 0x389a0 ---')
for off in range(0x3895c, 0x389a0, 4):
    w, note = insn(off)
    print('%#x %08x %s' % (off, w, note))
