# Passive WHOOP frame decoding

`Core/WhoopFrames.swift` implements corruption-checked, incremental decoding of selected WHOOP notification frames. This is a reconstruction from static Android evidence. No strap, iOS Bluetooth runtime, traffic capture, or private backend validated it. The decoder itself does not initiate hello, pair/bond, command writes, clock synchronization, historical transfer, or server upload.

## Public interface

```swift
var decoder = WhoopFrameDecoder(generation: .gen4) // or .maverick / .goose
for frame in decoder.append(notificationData) {
    let payload = frame.payload
    let heartRate = frame.realtimeHeartRate
    let components = frame.realtimeData // raw timestamp components; no epoch guess
}
```

Keep a separate decoder for every device and characteristic stream. Replace it on disconnect or when device identity changes. Choose the generation from device identity; MAVERICK and GOOSE share UUIDs. Their framing is independently confirmed below. `discardedByteCount`, `malformedFrameCount` and `bufferedByteCount` expose decoder diagnostics. Unknown packet types retain their raw payload and numeric `packetTypeCode`.

## Recovered frame structure

All multibyte integers are little endian. Start-of-frame is `aa`. The unsigned 16-bit encoded length counts payload plus four-byte CRC32 trailer. Total size is header size plus encoded length and must be divisible by four. A frame must contain at least one payload byte. Padding, if present, remains part of the payload and CRC calculation.

| Generation | Header bytes | Length offset | Header CRC storage | Header CRC coverage |
| --- | ---: | ---: | --- | --- |
| GEN_4 | 4 | 1 | byte 3, CRC8 | bytes 1–2 |
| MAVERICK | 8 | 2 | bytes 6–7, CRC16 | bytes 0–5 |
| GOOSE | 8 | 2 | bytes 6–7, CRC16 | bytes 0–5 |

CRC8 uses polynomial `07`, initial value zero, non-reflected processing, no final XOR. CRC16 uses reflected polynomial `a001`, initial value `ffff`, no final XOR. CRC32 matches Java `java.util.zip.CRC32`: reflected polynomial `edb88320`, initial/final XOR `ffffffff`. The CRC32 trailer covers only the payload, excluding header and trailer. Unknown header bytes are retained without invented semantics. CRC validity does not authenticate a device.

GEN_4 derives from `jm0.c` constructor/accessors in phase2 results202, 207–210, 223 and 227. MAVERICK derives from `jm0.e` results203, 211–213, 224 and 228–230. GOOSE derives independently from `jm0.d` constructor262, size264, validation186, and newly inspected phase5 accessors200–207. Its constructor sets length offset 2; `u()` returns 4, `w()` returns 5, `t()` returns 6 and `c()` returns 8. Its `a()` computes CRC16 over bytes 0–5 and `s()` reads the unsigned short at 6. Identical UUIDs were not used as evidence of layout equivalence.

Key complete REA Evidence identities:

| Observation | Evidence ID |
| --- | --- |
| GEN_4 constructor | `ev_a0015ecde0a67fba0c1d97fae74517610bc5d37f20894df0da6f371507384d78` |
| MAVERICK constructor | `ev_811b86dd15ccfea05c3fb9209ee78552bb8195e8903ed5b00f34229976bfc0e8` |
| GOOSE constructor | `ev_bff544ed712371fc30e3f6a05ee778cb521726548752243deb2f80714b4faae4` |
| GOOSE length-offset accessor | `ev_f14de026d8049bbc9bd2c5af02a47b61533da097d56ff6237ffa1985ec8cb3e1` |
| GOOSE CRC-offset accessor | `ev_6cf2d416c667811e45d984110436c8cdc10ef104548d95262009dc721e4b4b3c` |
| GOOSE CRC range | `ev_98683339b53679e473264d8ae13c98c09696d0583490ec92663c9a93e6197c71` |
| CRC16 update/seed | `ev_663e8d65bcfd8403f73d978ececd80da13fe6d0e2223909704763b1d2b4c9476` |
| CRC8 update/seed | `ev_91b96438501b07460f6eb79f1747732d78f2ae6e7f4a29cf3049889b721f8d84` |
| Java CRC32 use | `ev_ed43806a8c1597af35ad03cf13c13cc57fd7185666419685eee5eb3f035e0edf` |
| Complete packet integrity/alignment | `ev_7b12de18ed6fd452f58cdf06c48c800921e396c087b22231df86d7fa83416f37` |
| Little endian declaration | `ev_ec541e8eafc027690d3667f3c6e464afc59ab25c3e1bbe4d60f71ad4b4253279` |

The original complete records are retained under `/workspace/whoop-analysis/phase2/results` and `phase5/results`; `phase5/PROTOCOL-EVIDENCE-INDEX.json` indexes the selected bodies. Analysis APK SHA-256 is `1a00151e0a6933e075167586290d07df648e1e3eab3f2f24e1c9b561ea41f241`. The full-package comparison previously established byte-identical DEX inputs. Extracted CRC tables in `phase2/CRC-TABLES.json` are supplemental static DEX extraction, not REA Evidence or runtime observations; all 256 entries match the stated polynomials.

The separately recovered aligned outgoing envelope uses the same lengths and CRCs. Its MAVERICK/GOOSE header constants are byte1=`01`, byte4=`00`, byte5=`01`, independently recovered through each generation's setters and role constructors. Builder Evidence `ev_1e0e9698643ea54f7faf79dd246c2fda40c64f0204a10e472f7755e282317351` supports the aligned payload branch. Its unaligned branch contains a self-copy operation also confirmed by direct DEX disassembly; a portable encoder must reject unaligned input rather than invent a repair. Full analysis and setter Evidence are in `phase5/PROTOCOL-OUTGOING.md`. These envelope facts alone do not recover arbitrary command payloads or establish a full handshake.

## Recovered realtime payload fields

Payload byte 0 selects the outer packet type. The enum preserves command `23`, response `24`, puffin command/response `25`/`26`, realtime `28`, raw realtime `2b`, history `2f`, event `30`, metadata `31`, console `32`, realtime/history IMU `33`/`34`, relative puffin events `35`, puffin strap events `36`, relative battery console `37`, puffin metadata `38`. These type bytes differ from data revision bytes.

For type `28`, at least nine payload bytes are required before constructing `WhoopRealtimeData`:

| Payload offset | Field |
| --- | --- |
| 1 | Raw unsigned revision byte |
| 2–5 | Raw unsigned 32-bit timestamp component |
| 6–7 | Raw unsigned 16-bit timestamp component |
| 8 | Raw unsigned heart-rate byte |
| 18 | Revision2 only, when payload has 20 bytes: `isOffWrist = (byte == 0)` |
| 19 | Revision2 only, when payload has 20 bytes: raw body-location code |

Constructor Evidence `ev_35a5acf813cc95ce2dc95e6b0e64b20a0d7dc33b1037e964c95cecb3d112e2b6`, model Evidence `ev_6f0624cca243163c3baa09356cd327e55dcbb56dcad391fdc87aa2df3d827ea0`, and description Evidence `ev_6a9c2f9b86d76412baa7f9990ffec4295defa739b54e72f0244bb2903f6911cf` establish these selected offsets. Android reads bytes 18/19 unconditionally, but describes their meanings for revision 2. The port guards lengths and restricts those two interpretations to revision 2. Basic fields for other revisions are a constructor-based interpretation and do not establish every firmware revision's compatibility. No timestamp epoch/units, RR intervals, body-location mapping or HRV formula is invented. `realtimeHeartRate` suppresses zero and explicitly off-wrist readings as a local presentation policy; `realtimeData.heartRate` preserves the raw byte.

## Reassembly and limits

The decoder accepts fragmented and concatenated notifications, validates headers before using their lengths, then checks alignment, nonempty payload and CRC32. Invalid candidates advance one byte, allowing the next valid `aa` prefix to be found; corrupt payloads are never returned. Notifications with a nonzero `Data.startIndex` work. Retained input is bounded to 65,544 bytes, derived from the 16-bit length plus the largest header rounded up; this is a parser bound, not a measured device maximum. Large input is processed in bounded slices.

A valid header whose length has not yet arrived stays pending. The decoder does not scan that pending payload for frame-like bytes, because legitimate payloads can contain `aa` and even complete frame-shaped byte sequences. A CRC-valid corrupted length can consequently delay recovery until its declared length arrives. Disconnecting replaces that pending stream state. This policy is an explicit local stream-parser design, not a claim of exact Android malformed-input parity.

## Validation and remaining scope

`WhoopFrameTests` uses fixed synthetic fixtures generated by `phase5/protocol-fixtures.py`: extracted DEX table lookups provide header checksums; Python `zlib.crc32` provides trailer checksums. Swift implements bitwise recurrences, so fixture checks do not call the implementation under test. `123456789` independently anchors CRC8=`f4`, CRC16=`4b37`, CRC32=`cbf43926`. The GEN_4 fixture has header CRC=`ff`, MAVERICK/GOOSE header CRC=`dad6`, payload CRC=`a7a2ca65`. These fixtures are not recorded packets.

Tests cover all two-fragment boundaries, one-byte fragments, concatenated frames, corrupt header/payload recovery, noise, alignment/length rejection, maximum length, bounded buffering, nonzero Data indices, unknown packet types, truncated payloads, guarded revision fields and off-wrist/zero presentation policy. Physical packet timing, firmware negotiation, all command/history/event schemas, timestamp conversion, automatic GOOSE identification, full custom handshake and private server calculations remain unverified. Passive decoding alone does not make a strap start streaming.
