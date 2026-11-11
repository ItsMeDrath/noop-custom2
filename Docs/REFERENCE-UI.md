# Screenshot-guided interface revision

The user supplied four visual references after rejecting the earlier layout. These are now the primary visual inputs alongside the recovered wordmark and fonts. They show multiple WHOOP app versions, so they cannot all define one identical screen at once.

## Reference choices and changes

- The third image supplies the current overview: compact avatar/date/device header, three small rings, an HRV context card, Health/Stress monitor shortcuts, My Day/Daily Outlook, compact activities, tonight's sleep, journal and customizable dashboard rows.
- The first image supplies full-screen Sleep, Recovery and Day Strain details: large circular gauge, subdued wordmark, prominent number, back/Today/info header, a statistic card with a top pointer, and a purple-to-blue outlined insight card.
- The flat Home/Health/Community/More navigation and floating white plus button follow the smaller app screenshots. Profile remains reachable through the avatar. The previous five-item floating pill and large header logo were replaced.
- The fourth image supplies the steel-blue Sleep, bright-green Recovery and blue Strain palette, compact Health monitor tiles and visual shape of the WHOOP Age card.
- The second image's stress monitor layout informs a missing-data screen. A colored scale with no needle/value and an explicit unavailable state does not claim that a WHOOP stress calculation has been recovered.

[Theme.swift](../App/Views/Theme.swift), [RootView.swift](../App/Views/RootView.swift), [DashboardViews.swift](../App/Views/DashboardViews.swift), [DetailViews.swift](../App/Views/DetailViews.swift) and [ReferenceComponents.swift](../App/Views/ReferenceComponents.swift) implement the revision. Account, import, backup, device and core scoring code are unchanged.

## Data and actions

The existing example week is retained and identified as example data. Reference-image scores such as 14.2, 85% and 74% were not inserted into saved user measurements. The original brand assets remain the source assets; no screenshot is used as a noninteractive screen background.

The rings open full-screen details; back dismisses; info explains the displayed score; monitor shortcuts navigate to Health or stress; the floating plus offers activity/workout/journal actions; View All opens the activity library; dashboard customization persists row visibility. Date navigation and imported/local measurements remain connected. Comparisons use the previous UTC day of the same data provenance, and arrow direction denotes a numeric change rather than a clinical status. Whole-number display uses the existing formatter.

Unprovided fields remain unavailable: historical heart-rate zone durations, VO₂ max, sleep consistency/efficiency/stress, blood oxygen, skin temperature, stress scores and WHOOP Age. Strength time only sums actual logged activities named as strength training. Average heart rate is the arithmetic average of supplied samples, not an inferred continuous recording. Sleep labels use actual duration/need, not fabricated bedtime or alarm recommendations. HRV text describes a measured difference rather than diagnosing recovery readiness.

The Coach-shaped action is retained for visual fidelity and explicitly reports that Coach is unavailable; it never fabricates a generated reply. No new private API or authenticated WHOOP service was implemented in this UI pass.

## Validation boundary

All 16 app Swift files pass frontend syntax parsing. Generated Xcode source/resource references pass the structural validator. The previously tested portable Core/Tests/Package and backend sources are byte-for-byte unchanged. Screenshot previews are browser approximations of the revised source, with their own navigation checks; they are not iPhone simulator output or proof that the SwiftUI target compiles. No Apple executor or connected Codemagic account is available here, so native rendering, device interaction, pixel comparison and IPA production remain unverified.

This revision follows the supplied visual references much more directly. It does not establish an exact replica across WHOOP versions or complete functional parity.

## Subsequent integration

The screenshot revision above is historical. The later user request changes primary navigation to Home, Sleep, Recovery, Strain, Nutrition and More, retaining Health/Community/Profile routes through More. Nutrition uses its own unbranded Inter palette. Live media and ActivityKit are now source additions; native rendering and device behavior remain unverified. See [Nutrition](NUTRITION.md) and [Live media](LIVE-MEDIA.md).
