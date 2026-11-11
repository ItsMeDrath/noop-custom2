Current launch UI: see [the full-screen reference Live implementation](LIVE-REFERENCE.md). The form-style entry described below is retained for legacy callers.

# Live camera, photos and Lock Screen source

This adds local media functionality to the existing project; it is not execution or validation of the official WHOOP Live implementation. The user-supplied links describe desired behavior. Their service/hardware/version claims were not treated as verified runtime evidence.

## Camera and media

From Home choose Start Activity → Record with Live camera, or open More → Live camera & photo overlays. Start/configure a workout using the existing recorder, open the camera, then record. Camera and optional microphone permissions are requested on user action. Video frames and audio are written through AVFoundation on a serial capture queue; telemetry is composited into each recorded frame. Media clips are limited to five minutes and finish when leaving the foreground. Finishing a clip and finishing/saving the workout are separate explicit actions. Recording failures produce a recoverable error rather than a fabricated media file.

The overlay can show live heart rate, local strain estimate or recorded Sleep/Recovery stats. Heart rate expires after ten seconds without a real sample. Local strain remains labeled as an estimate. **The recorder does not supply workout calories or zones; these are unavailable.** It never relabels a day's total energy as workout energy. The photo mode can display actual recorded day calories with the explicit DAY KCAL label.

Photo mode uses the system photo picker, an explicitly selected UTC date and the measurements already stored for that date. It does not infer the correct date from the photo or manufacture readings. Example data retains its example label. Exported photos are resized to a bounded resolution and re-rendered without original metadata. A separate export produces a PNG with a transparent canvas. Share uses the iPhone share sheet; Save requests photo-library add access. There is no automatic social posting or message sending.

Implementation: [LiveCamera.swift](../App/LiveCamera.swift), [LiveView.swift](../App/Views/LiveView.swift). It reuses the existing recorder, data store and device stream. The existing recorder now updates elapsed time on received BLE samples as well as the foreground timer.

## Live Activities

[LiveActivityDriver.swift](../App/LiveActivityDriver.swift) requests and updates an ActivityKit activity for a running workout when enabled. [LiveWorkoutAttributes.swift](../Core/LiveWorkoutAttributes.swift) defines the shared typed content. The [WorkoutLive widget](../LiveActivityWidget/WorkoutLiveWidget.swift) renders Lock Screen and Dynamic Island views, hides stale measurements and stops its elapsed timer when paused/finished.

The existing Xcode project gains a **WorkoutLive** app-extension target, app dependency and PlugIns embed phase. It is not a separate project. The extension shares the local Swift package, requires no App Group, and does not use remote activity push tokens. App Info.plist declares Live Activities and camera/microphone/photo-add usage descriptions. Bluetooth-central background mode allows supported connected-sensor delivery; it does not guarantee continuous execution, app-kill recovery or exact official behavior. Camera itself does not run in the background.

Enable Live Activities in the Live screen and, if needed, iPhone app settings. Updates depend on OS scheduling and actual sensor delivery; stale dates are tied to the latest sample rather than extending an old reading indefinitely. No running timer is presented as proof of a fresh sensor connection. A stopped activity is ended; disabling the preference removes it immediately. In-flight workouts are not recovered after app termination.

The extension identifier is `$(APP_BUNDLE_IDENTIFIER).WorkoutLive`. The signed export helper now sets the parent `APP_BUNDLE_IDENTIFIER` so both identifiers remain related. Direct Xcode signing must provision the parent app and extension; the parent also retains HealthKit. An unsigned package still needs compatible signing before installation.

## Verification limits

App and widget Swift sources pass frontend syntax parsing and the project validator checks the target dependency/embed structure. No Apple SDK compilation, camera capture, audio synchronization, rendered-frame orientation, photo permission flow, video export, Lock Screen or Dynamic Island runtime test was possible here. Media and ActivityKit interoperability remain device-validation requirements. No recorded video, native app screenshot, signed IPA or official WHOOP service equivalence is claimed.
