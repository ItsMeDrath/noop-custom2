# Passive historical packets

`WhoopHistoryRecord.init?(frame:)` accepts CRC-validated historical frames (outer type `0x2f`) produced by `WhoopFrameDecoder`. It preserves the complete frame, payload and raw revision. It does not start transfers or acknowledge, trim or erase strap memory.

For the selected metrics revisions R9, R12, R18 and R24, the common header has these payload-relative offsets:

| Offset | Width | Interpretation |
| --- | --- | --- |
| 0 | 1 | Outer packet type `0x2f` |
| 1 | 1 | Data revision |
| 2 | 1 | Opaque, retained in raw payload |
| 3 | 4 | Unsigned little-endian packet counter |
| 7 | 4 | Unsigned little-endian Unix seconds |
| 11 | 2 | Unsigned little-endian fractional ticks, 32768 ticks per second |
| 17 (R9/R12/R24), 14 (R18) | 1 | Raw metrics inclusion flag |

The 13-byte common header must be present before any common fields are exposed; the flag has its own length check. The Android metrics batcher uses a nonzero flag to include raw packet bytes under their timestamp. This flag does not establish off-wrist state, heart-rate quality, or a physiological measurement. A short or unknown revision remains available as raw bytes. Unknown revisions have no projected common or physiological fields in this conservative implementation.

`deviceTime` uses `WhoopDeviceTime`, which mirrors Android's nearest-millisecond conversion. Raw seconds and ticks remain available when the converter rejects a noncanonical fractional component. A valid device timestamp does not itself prove that the strap clock is correct. The application can apply a date-range validation policy before importing samples.

Historical heart rate, RR intervals, temperature, respiratory metrics and other physiological offsets were not established by this bounded static pass. `heartRate` therefore returns `nil`. Received packets can be archived losslessly; they cannot yet become verified historical heart-rate samples. The realtime heart-rate layout has different offsets and must not be applied to historical packets.

The evidence is static analysis of WHOOP Android 5.444.1, not captured strap traffic. The supplied analysis APK SHA-256 is `1a00151e0a6933e075167586290d07df648e1e3eab3f2f24e1c9b561ea41f241`; its DEX set was independently matched to the complete supplied base. Protocol verification on physical GEN_4, MAVERICK and GOOSE hardware remains outstanding. Synthetic fixtures test the recovered portable layout; they do not prove device interoperability.

Analysis details and exact REA Evidence IDs are in `/workspace/whoop-analysis/phase6/HISTORY.md` and `HISTORY-EVIDENCE-INDEX.json`. Core sources: REA203 static offsets, 204 counter, 206–209 timestamp getters, 217 header guard, existing phase2/257 revision and phase2/258 flag; REA216 metrics batch, 224–227 summary/storage boundaries. Time conversion is documented in `DEVICE-TIME.md`.
