# Official WHOOP parity

The requested target is the actual WHOOP experience, with its WHOOP name and branding. Current evidence and implementation cover only part of that target. This ledger records the remaining concrete gaps rather than calling a similarly branded interface identical.

| Area | Current state | Evidence still needed |
| --- | --- | --- |
| Branding | Supplied wordmark coordinates, fonts, icon and WHOOP display name retained | iOS icon validation and rendered comparison |
| Home/navigation | Screenshot-guided compact overview, six primary tabs, full-screen score details and health tiles; see REFERENCE-UI.md | Apple SDK render, pixel/interaction comparison for a chosen WHOOP version and server-driven member payloads |
| Public account scores | OAuth/client/server source, cycle/Recovery/sleep/workout mapping and synthetic tests | Actual configured client, authorized OAuth/API test and official current specification verification |
| Apple Health/local records | Imports, journals, workouts, activities and backups implemented independently | Apple SDK build and device/runtime validation |
| Device HR | Selected frame decoder and opt-in Hello/live-HR request sequence | Real strap sessions, full connection/recovery/clock initialization and generation tests |
| Historical device data | Selected common headers, counters and timestamp conversion | Physiological fields, every revision, complete history transfer and device tests |
| Algorithms | Selected strain helper equations and table recovered; estimates explicitly labelled | Daily Recovery/sleep/private processing and native MSK internals |
| Nutrition | Offline manual logging, canonical calculations, native screens and authenticated AI route source | Apple SDK/device run and configured provider integration |
| Live media / Lock Screen | Camera, photo, transparent export and ActivityKit extension source | Real media, permissions, background delivery and widget runtime tests; workout calories/zones unavailable |
| Online services | Public-account bridge and Nutrition AI route source | Private personalized Home, Coach, teams/community, membership and other service behavior |
| iPhone distribution | Mac build/export scripts and manual CI supplied | Successful Xcode build, signing/provisioning, runtime test and actual IPA |

The separate REA analysis bundle retains `phase3/UI-NAVIGATION.md`, `RESOURCE-MAP.md`, `strings-default.xml` and `phase4/STARTUP-GATES.md`. Those reports show a hybrid Android shell and state-dependent routes. The typed Home model receives server-provided headers and pillars; no authenticated member response or signed-in screen recording was acquired. Navigation declarations and string labels alone cannot specify an exact SwiftUI replica.

The recovered `overview_gauge_day_strain` string remains the label on the large strain detail. The later user screenshots guide the compact overview's SLEEP/RECOVERY/STRAIN labels and six primary tabs, with Profile accessible through the avatar. [Screenshot revision notes](REFERENCE-UI.md) distinguish supplied visual evidence, local interaction choices and unavailable fields. No authenticated member payload or native render was captured during this revision.

The later requested navigation is Home, Sleep, Recovery, Strain, Nutrition and More. Health/Community/Profile remain reachable from More. The new Nutrition section follows the requested unbranded style; existing app branding is unchanged. A local edition preference does not grant any official paid service. See [Nutrition](NUTRITION.md) and [Live media](LIVE-MEDIA.md).
