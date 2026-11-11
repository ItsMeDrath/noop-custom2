# Home revision 03 — latest screenshot batch

## Scope and reference

The 27 supplied images are indexed in [the reference catalog](../reference-index.json). The chosen screen is Home, including its top, four lower scroll positions, mini-ring header and quick-action popover. The earlier user process requires Home review before the next screen. Health, Profile, More, Community, Stress Monitor detail and the new Live layouts are **not rebuilt or approved** in this revision. Home context sheets are local interactions, not final versions of those pending screens.

The actual screenshots are visible in the conversation. Their raw image files are not mounted in this workspace. Dimensions below were read approximately from the displayed 945 × 2048 images and normalized to 393 × 852 points. Color values are visually estimated; no pixel sampling, image subtraction or simulator capture was possible. The browser images are not native app screenshots.

## Implemented from this batch

The avatar/streak/date/tracker header, black membership banner, compact 33% Sleep / 38% Recovery / 15.8 Strain rings, yellow Recovery status, insight card, taller paired monitor cards, inline My Day plus menu, gradient Day In Review row, Tonight's Sleep with Set Alarm, four activity rows, seven-day journal and Behavior Insights, plan illustration, metric customization, weekly dual-scale Strain/Recovery chart, stress graph, lower metric rows, Weight, four Discover More cards and footer now follow the supplied composition. Navigation floats in a rounded four-item pill with a separate Coach button. A scrolled header replaces the large hero with mini-rings.

All Home values come from `App/Resources/pulse-home-mock.json`. The fixture includes the screenshot's weekly scores, activity durations/times and dashboard values. The stress curve is an illustrative reconstruction, not sampled graph points or a real stress computation. No screenshot pixels are used as a screen background.

PULSE remains the original brand. Inter remains the free font, with SF Symbols replacing the original custom icons. Original product/people imagery is represented by independent symbol illustrations. That is an intentional visual difference under the original-branding requirement.

## Layout review

Approximate reference positions in points, followed by the browser's measured bounds:

| Element | Approximate reference x/y/w/h | Browser x/y/w/h |
| --- | --- | --- |
| Membership banner | 14.6 / 112.7 / 363.9 / 62.8 | 14.5 / 112 / 364 / 63 |
| First ring | 34 / 236.6 / 81 / 81 | 34 / 235 / 81 / 81 |
| Insight card | 14.6 / 376.4 / 363.9 / 110.6 | 14.5 / 375 / 364 / 114 |
| Monitor pair | 14.6 / 516 / 363.9 / 85 | 14.5 / 517 / 364 / 85 |
| Day In Review row | 14.6 / 678.2 / 363.9 / 43.6 | 14.5 / 679 / 364 / 44 |
| Main navigation pill | 10.8 / 767.2 / 302 / 58.2 | 11 / 768 / 302 / 58 |
| Coach button | 324.4 / 768.5 / 57.8 / 57.8 | 324 / 768 / 58 / 58 |

These reference values are estimates. Small deltas are not evidence of pixel equality, and browser bounds do not establish SwiftUI bounds.

The review pass corrected the earlier oversized rings, percentage glyph size, header position, banner line height, insight paragraph spacing, monitor type scale, dashboard row padding, chart height and explicit vertical card layout. The browser capture now preserves the status/header area in each scroll-state image.

## Visible remaining differences

- PULSE wordmark and Coach monogram replace WHOOP branding.
- Inter has different numeral shapes, widths and wrapping from the original custom fonts.
- Native SF Symbols, and simple SVG equivalents in the browser, differ from the original icons.
- Discover More thumbnails and plan art are original symbol-based illustrations, not the original product/people images.
- The stress trace is a fixture approximation; exact graph vertices, gradient interpolation and activity marker locations are unverified.
- Blur, material opacity, gradient colors, native text baselines, safe-area positioning and animation timing require an iPhone render.
- The header's 65% is explicitly reference sample data when disconnected. The status dot and tracker panel reflect actual native connection state; no physical connection is fabricated.
- Other bottom-tab destinations remain disabled in this Home-first review. Their supplied screens await approval.

## Behavior and validation

Nine browser checks cover restored labels/values, four activity rows/eight metrics, sticky mini-rings, the five-action menu, per-metric customization, date changes, tracker boundary, explicit sample Coach conversation and no errors/external requests. The canonical Swift DTO decodes the actual fixture, including all seven dates, unique record identities and bounded stress values. All 32 app Swift sources plus the widget pass syntax parsing; project references pass structural validation. Existing Core, server and Bluetooth adapter source are unchanged in this Home pass.

No Apple SDK typecheck/build, simulator screenshot, exact image comparison, signed IPA, paid membership activation, real Coach backend or physical tracker test is claimed. Alarm and save controls inside Home context sheets are explicitly local previews. The tracker route still uses the existing real CoreBluetooth adapter and shows real received HR separately from the mock scores.
