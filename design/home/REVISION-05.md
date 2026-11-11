# WHOOP Home revision 05

The latest instruction explicitly restores WHOOP branding, superseding the earlier PULSE / free-font requirement. The membership-expiry banner remains removed as separately requested.

The existing SwiftUI iOS 17 app, local WHOOPCore package, native storage, tracker adapter, nutrition source, account code, Live camera implementation, and widget extension are retained. Internal `Pulse*` filenames identify this Home implementation; user-visible branding is WHOOP. No environment publication, backend deployment, or cloud build was performed.

## Changes

- WHOOP display and bundle names; supplied vector wordmark and monogram in Home, footer and Coach. The launcher icon is rendered at 1024 pixels from the vector monogram; the supplied raster original is retained.
- DIN Pro Bold for numbers and uppercase labels, DIN Pro Medium for secondary values, Proxima Nova for body text. All four original font files are registered and bundled again. Inter remains available to the retained nutrition implementation.
- Centered date control with a distinct center capsule, 81-point rings with 5.8-point round strokes, and the reference house/activity-line navigation icon.
- Ring fill and numeric-value transitions, date changes, a scale/fade daily menu, and shared press feedback. Reduce Motion suppresses spatial movement. Timings are implementation choices, not measured official-app timings.
- No expiry alert, expiry date, or expiry fixture was reintroduced.

## Review images

[Home top](revision-05/01-Home-top.png), [My Day](revision-05/02-Home-my-day.png), [Journal and Plan](revision-05/03-Home-journal-plan.png), [Dashboard](revision-05/04-Home-dashboard.png), [Stress and metrics](revision-05/05-Home-stress-metrics.png), [Discover More](revision-05/06-Home-discover.png), [daily menu](revision-05/07-Home-quick-menu.png), and [full gallery](revision-05/Home-review-gallery.jpg).

These are Chromium interpretations of the updated native layout using the same fixtures and fonts. They are not simulator screenshots. Browser icons approximate SF Symbols and do not establish native icon parity.

## Remaining visible and behavioral differences

The 27 references are visible in the chat, but their original image files are unavailable to the executor. Dimensions and colors remain estimated from displayed attachments; no image-byte color sampling or pixel-difference comparison was possible. The original iOS app's exact current type metrics and animation timing are unverified even though the original supplied Android fonts and logo are reused.

Discover More still uses generated UI symbol tiles rather than the photographic assets in the screenshots. System icons, current time, status-bar details, real Bluetooth connection state and battery behavior differ. The expiry banner is deliberately absent. Home values are explicitly illustrative; live tracker measurements stay separate.

Other primary screens remain at the prior Home-review boundary under the user's screen-by-screen instruction. Home destination sheets are local interaction previews, not final reproductions of those screens. Existing legacy implementations are preserved. The Linux executor has no Xcode/Apple SDK/simulator, so native compilation, native captures, physical tracker behavior, every-angle parity, and a signed IPA are not verified.

See [tokens](../tokens/home.json), [reference inventory](../reference-index.json), and [validation](../../VALIDATION.json).
