# Partition footprint budget (super = 9 GiB / 9663676416 bytes)

### Table A -- vivo PD2339 (OriginOS 16.2.13.1) dynamic partitions

| partition | bytes | GiB | GB |
|---|---:|---:|---:|
| system | 7934083072 | 7.389 | 7.93 |
| vendor | 3135754240 | 2.920 | 3.14 |
| product | 393981952 | 0.367 | 0.39 |
| system_ext | 411910144 | 0.384 | 0.41 |
| odm | 4780032 | 0.004 | 0.00 |
| odm_dlkm | 348160 | 0.000 | 0.00 |
| vendor_dlkm | 45801472 | 0.043 | 0.05 |
| system_dlkm | 14913536 | 0.014 | 0.01 |
| **total** | **11941572608** | **11.121** | **11.94** |

### Table B -- rothko (Redmi K70 Ultra) current logical partitions

| partition | bytes | GiB | GB |
|---|---:|---:|---:|
| system | 879894528 | 0.819 | 0.88 |
| vendor | 1644707840 | 1.532 | 1.64 |
| product | 4478963712 | 4.171 | 4.48 |
| system_ext | 936296448 | 0.872 | 0.94 |
| odm | 881057792 | 0.821 | 0.88 |
| odm_dlkm | 348160 | 0.000 | 0.00 |
| vendor_dlkm | 21970944 | 0.020 | 0.02 |
| mi_ext | 126640128 | 0.118 | 0.13 |
| **total** | **8969879552** | **8.354** | **8.97** |

## Capacity constraint

| item | bytes | GiB |
|---|---:|---:|
| super physical size | 9663676416 | 9.000 |
| rothko logical partitions now | 8969879552 | 8.354 |
| reserve (lp metadata / alignment) | 62914560 | 0.059 |
| **usable headroom** | **630882304** | **0.588** |
| vivo all dynamic partitions | 11941572608 | 11.121 |

## Question 1: replace ONLY system, keep every other rothko partition

- rothko total 8.354 GiB - rothko system 0.819 GiB + vivo system 7.389 GiB = **14.924 GiB**
- over the 9 GiB hard cap by **5.924 GiB**; net growth is 6.570 GiB while the free headroom is only 0.588 GiB

Even dropping rothko `product` (4.171 GiB) as well does not save the naive swap:
  10.752 GiB -> still over by 1.752 GiB.

## Question 2: three candidate combinations

rothko kept set (vendor family, hardware-bound, cannot be dropped): vendor + odm + odm_dlkm + vendor_dlkm = 2.373 GiB

| combo | content | total GiB | margin vs 9 GiB | must shrink vivo system by |
|---|---|---:|---:|---:|
| Combo 1 | full port: vivo system+product+system_ext + rothko vendor/odm/dlkm + mi_ext | 10.631 | -1730 MiB | 1.689 GiB |
| Combo 2 | full port but no mi_ext | 10.513 | -1609 MiB | 1.571 GiB |
| Combo 3 | minimal: only vivo system + rothko vendor/odm/dlkm, product/system_ext as 64 MiB placeholders | 9.825 | -905 MiB | 0.883 GiB |

- **Combo 1** (10.631 GiB, margin -1730 MiB): most complete: keeps the whole OriginOS app/service set, and mi_ext for rothko HyperOS vendor services
- **Combo 2** (10.513 GiB, margin -1609 MiB): saves 0.118 GiB; only safe if rothko vendor init/fstab never mounts /mi_ext
- **Combo 3** (9.825 GiB, margin -905 MiB): drops vivo product/system_ext (HyperOS-side apps lost); highest boot risk

## Max allowed vivo system size per combo

| combo | fixed non-system part GiB | max vivo system GiB | shrink needed vs 7.389 GiB |
|---|---:|---:|---:|
| Combo 1 | 3.242 | 5.700 | 1.689 GiB (22.9%) |
| Combo 2 | 3.124 | 5.818 | 1.571 GiB (21.3%) |
| Combo 3 | 2.436 | 6.506 | 0.883 GiB (12.0%) |

## Conclusions

1. The naive swap (only system) is impossible: over by 5.9 GiB.
2. Even the most aggressive combo 3 requires vivo system <= 6.506 GiB (currently 7.389 GiB).
3. The one lever that does not require deleting files: rebuild system.erofs with
   zstd/lz4hc compression + dedupe when repacking. If the vivo image is uncompressed
   or only lz4-level, zstd-19 typically saves 15-30%: 7.389 x 0.80 = 5.91 GiB, which
   makes combo 3 fit outright and combo 2/1 close enough for targeted pruning.
4. Whether mi_ext can be dropped depends on rothko's vendor init/fstab forcing a mount;
   confirm against the vendor image in 02_base before deciding.
