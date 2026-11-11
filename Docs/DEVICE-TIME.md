# Device timestamp conversion

`WhoopDeviceTime` converts the recovered unsigned seconds and fractional tick fields to a Foundation `Date`. The timestamp uses Unix seconds and 32768 ticks per second. It matches the Android app's rounding to whole milliseconds:

```swift
if let timestamp = WhoopDeviceTime(seconds: rawSeconds, ticks: rawTicks) {
    let instant = timestamp.date
    // Prefer this when importing records with known session/date bounds:
    let checked = timestamp.validatedDate(in: expectedStart...expectedEnd)
}
```

Use `ticks32:` for a fractional field carried in a 32-bit slot. Both initializers reject ticks of 32768 or greater before narrowing. This is a deliberate canonical-fraction guard: the Android raw two-long constructor accepts those values unchanged. A zero timestamp is mathematically the Unix epoch; no recovered evidence establishes a universal unset-clock sentinel. Date bounds belong to the caller and must come from the actual session or import context.

The conversion is `Math.round(seconds * 1000.0 + ticks * 1000.0 / 32768.0)` in the Android app. The Swift implementation preserves the double arithmetic and operation order, including a fractional-millisecond rounding effect at large unsigned seconds. It does not preserve the full 1/32768-second precision in `Date`, because Android's `toDateTime()` also uses the rounded millisecond value. A `Date` is an absolute instant; applying a local time zone changes its display, not its epoch. No firmware-specific epoch adjustment appears in the recovered conversion path.

The proof comes from static analysis of the supplied APK, SHA-256 `1a00151e0a6933e075167586290d07df648e1e3eab3f2f24e1c9b561ea41f241`:

| Observation | REA Evidence ID |
| --- | --- |
| Raw `(long,long)` constructor stores both components unchanged | `ev_8ea2fc96d0c4d1b6a7108e02629a489eba06b666ed6bef960c5879dfb486712e` |
| `j()` returns seconds, `i()` returns ticks | `ev_74bb896c56e1de341d0ee3fdf4e27b0a93eb1431d273a1c9690bc035d565a7d2`, `ev_97c55a6f263bd4eb2052bb404b819aeace579896ff7dc4ee46037c50fb2318e9` |
| `n()` performs the explicit formula above | `ev_6b974aea2d4be84d867e180a8d569cb0fb3093048db9e10dd6ff974af1cda89b` |
| `toDateTime()` returns `new org.joda.time.DateTime(n())` | `ev_1a92a645c91137253c954f31896a8124dfcddda5ffe6547f33a8590faf7df9a6` |
| Default constructor starts from Joda `DateTimeUtils.currentTimeMillis()` and `MILLIS` | `ev_099a6226c95d17910007c381967ec5c58f937d2c5fdb3cf36210b83c1d1c9d9a` |
| `l(long,mode)` splits milliseconds using 1000 and 32768 | `ev_39b71389119d982b2e539c2bfc7d623bcf52156964df426e81236fd5a5f494ff` |
| Historical record observer uses `packet.O().n()` directly | `ev_81f1f782fe0aee3748b2972708bad42500f72368d879c7048ff2448de93787f1` |
| Event processing preserves milliseconds while rebuilding Joda DateTime in UTC | `ev_f8fd197569ad3ab182896f92db26d0297ab821748c372cb490353d5213f7a353` |

The original realtime decoder (`hf0.j`, phase 2 Evidence `ev_35a5acf813cc95ce2dc95e6b0e64b20a0d7dc33b1037e964c95cecb3d112e2b6`) passes its unsigned 32-bit field and unsigned 16-bit field directly to that raw constructor. This establishes the conversion for those fields; other packet types must establish their own offsets and widths before using the converter.

The historical observer `hv1.p.b(im0.b)` consumes `packet.O().n()` with no additional epoch shift. The event branch for `if0.l` in `hv1.m.X` obtains `lm0.a.J().toDateTime().getMillis()`, constructs `new DateTime(milliseconds, DateTimeZone.UTC)`, then reads the same milliseconds. That explicit UTC step does not subtract a local-zone offset. The timestamp fields are stored eagerly; `n()` calculates milliseconds on each call rather than resolving a deferred clock base.

The millisecond constructor's splitter narrows whole seconds through a signed Java `int`. The raw packet constructor does not. Accordingly the Swift raw-field converter preserves the entire UInt32 seconds range through 2106, including values above signed Int32.max. The maximum rounded millisecond result is 4,294,967,296,000, well within Int64. It does not emulate signed-overflow behavior of the unrelated wall-clock splitter.

Static analysis establishes representation and app-side conversion. It does not establish that firmware sets its clock correctly, that a received record's date is plausible, how an unset clock is signalled, or wraparound/era recovery. No physical-device or firmware execution was performed. Synthetic tests cover the Unix epoch, a known UTC date, fractional rounding and carry, the unsigned range, invalid fractional slots, and caller-supplied date bounds.
