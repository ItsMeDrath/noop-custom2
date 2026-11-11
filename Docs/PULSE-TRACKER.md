# WHOOP Home and tracker access

The user's correction restores the screenshot's familiar labels: Sleep, Recovery, Strain, Health Monitor, Stress Monitor, My Day, Your Daily Outlook, Today's Activities, Tonight's Sleep, My Journal, My Plan, My Dashboard and Home/Health/Community/More. WHOOP branding and the supplied DIN Pro / Proxima Nova fonts are now active. This supersedes the earlier request to rewrite the Home labels. The original local screenshot files remain unavailable, so exact pixel parity is not established.

The Home tracker button previously showed a mock battery level and only opened the sample-data explanation. It now opens `PulseTrackerView`, which reuses the existing `DeviceModel` CoreBluetooth adapter. The app owns that model for the lifetime of the UI; its central manager is lazy and scanning begins only after Search. The fake 45% header battery is removed. The icon indicates an actual connected link. No battery percentage is invented when the sensor has not supplied one.

## Try it on iPhone

1. Install a real iOS device build. Enable Bluetooth and keep the tracker nearby.
2. Open the tracker icon at the top right of Home.
3. Tap **Search for Devices** and allow Bluetooth access when prompted.
4. Select the discovered tracker. If your tracker provides a heart-rate broadcast setting, enable it as needed.
5. A standard heart-rate notification begins automatically when supported. For a ready custom WHOOP service, **Start Device Heart Rate** exposes the existing explicit experimental request.
6. Confirm a fresh numerical BPM reading. A connected Bluetooth link alone does not verify live data. Disconnect is explicit; closing the panel stops any active scan but keeps an existing connection.

The tracker panel uses real radio events and received samples. A number is displayed only when a real sample is no more than ten seconds old. Unconnected, waiting, permission-denied and stale-data states use explanatory text. No connection or device reading is simulated.

## Implemented paths

- Standard Bluetooth SIG heart-rate service `180D`, measurement `2A37`.
- Recovered `61080001-8D6D-82B8-614A-1C8CB0F8DCC6` custom family.
- Recovered `FD4B0001-CCE1-4033-93CE-002D5875F58A` custom family. Shared UUIDs do not establish a specific commercial model.

The custom flow subscribes to selected notifications and exposes an explicit Hello request followed by a live-HR enable request only after a correlated acknowledgement. No arbitrary firmware, history deletion, reset or clock-write command is added. See [the request policy](DEVICE-STREAM.md).

The user asked to consider all WHOOP models. No physical WHOOP 4.0, 5.0 or MG was available, and this Linux workspace has no connected iPhone/CoreBluetooth runtime. The code supports the above service paths; it does **not** establish that every model/firmware can pair or stream. Full official initialization, history sync and private scores remain unresolved.

Home's seven-day scores remain clearly illustrative. Connection does not produce measured Recovery, Sleep Performance, daily Strain, ECG or blood-pressure results. The current work performs no login/backend integration.

## Checks

23 portable WHOOP framing, command and session tests pass, plus three standard Bluetooth HR decoding tests. These use synthetic data. Native Home/tracker source passes Swift syntax parsing and project registration checks; Apple SDK compilation, actual radio connection and device screenshots remain unverified.
