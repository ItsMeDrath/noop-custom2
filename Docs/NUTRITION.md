# Nutrition integration

## Existing project, preserved architecture

This is a native iOS 17+ SwiftUI application, not a React/Next application. `App/Views` holds screens and reusable view components, `AppStore` owns navigation and local state, and `Core` is a Foundation-only Swift package. Existing data lives in a validated JSON document with atomic/file-protected writes and complete versioned backups. The Node server in `Server` already implements browser OAuth, Keychain-bound bridge bearers, encrypted server sessions and bounded HTTP handlers. There is no browser localStorage or SQL database to replace.

Nutrition extends those exact systems. No new application/project, React router, database or authentication scheme was created. A root `package.json` supplies TypeScript tooling and the zod dependency for the existing server. Recharts, Framer Motion and lucide-react are not applicable to the native app: it uses Swift Charts, SwiftUI transitions and system symbols. Inter is bundled under its OFL license; the Nutrition section uses no WHOOP logo, name or original brand assets.

## Files and ownership

| Area | Files |
| --- | --- |
| Canonical energy calculations | [calc.ts](../lib/nutrition/calc.ts) |
| AI prompts and validated route implementation | [prompts.ts](../lib/nutrition/prompts.ts), [routes.ts](../lib/nutrition/routes.ts) |
| Existing HTTP server integration | [bridge.mjs](../Server/bridge.mjs) |
| Typed storage/response contracts | [NutritionModels.swift](../Core/NutritionModels.swift), optional nutrition field in [LocalBackup.swift](../Core/LocalBackup.swift) |
| Existing state, writes and backup integration | [AppStore.swift](../App/AppStore.swift) |
| Offline calculation runner and request state | [NutritionModel.swift](../App/NutritionModel.swift) |
| Existing authenticated transport | [AccountModel.swift](../App/AccountModel.swift) |
| Shared native components | [NutritionComponents.swift](../App/Views/NutritionComponents.swift), generic optional surfaces in [Theme.swift](../App/Views/Theme.swift) |
| Home, date strip, meals and deep dives | [NutritionViews.swift](../App/Views/NutritionViews.swift) |
| Food/photo/text/recent/favorite and exercise forms | [NutritionForms.swift](../App/Views/NutritionForms.swift) |
| Weight, profile, goal overrides, units, export/reset | [NutritionSettings.swift](../App/Views/NutritionSettings.swift) |
| Existing navigation | [RootView.swift](../App/Views/RootView.swift), [WHOOPApp.swift](../App/WHOOPApp.swift) |
| Single-source native resource build | [build-nutrition.mjs](../Scripts/build-nutrition.mjs), [validate-nutrition-resource.py](../Scripts/validate-nutrition-resource.py) |

The original Home/health/import/backup/account/workout functions remain routed. The requested primary tabs are Home, Sleep, Recovery, Strain, Nutrition and More; former primary Health/Community/Profile destinations are available through More or the existing avatar. Nutrition has its own palette and Inter typography while reusing the generic card layout and authenticated transport.

## Calculation behavior

The calorie dial displays goal minus eaten (negative when over goal), with intake-based progress and status. All calorie aggregation, goal formulas, conversions, ratios, energy-equivalent estimates and nutrition trends are implemented in `lib/nutrition/calc.ts`. The build strips only TypeScript types and packages the same code as `App/Resources/nutrition-calc.js`; JavaScriptCore runs it locally on iOS. No network is needed for manual food/exercise logging, goals, charts or weight entries. The native code handles presentation, input/storage integrity and dates, not a second set of energy formulas. Tests compare the generated runner against the canonical TypeScript response, and a Swift test decodes that response into the native DTO.

Mifflin–St Jeor uses `10 × kg + 6.25 × cm − 5 × age + 5` (male) or `−161` (female), multiplied by activity factors 1.2/1.375/1.55/1.725/1.9. Default loss/gain goal offsets are −500/+300 kcal. The default macro split is 30% protein, 40% carbohydrate, 30% fat using 4/4/9 kcal per gram; every target can be overridden. The supported auto-profile range is ages 18–100, 80–250 cm and 20–400 kg. Unsupported energy targets produce a friendly error rather than silently changing the requested goal. Blank profiles produce unavailable auto targets; a manual calorie goal still works.

Estimated burn equals maintenance plus manually logged exercise. Activity-level maintenance may already include exercise, so the screen explains avoiding duplicate estimates. No energy is silently imported from the app's unrelated cycle-energy or workout records. A positive balance means estimated deficit. Energy-equivalent mass change is `−balance / 7,700` kg; it is not a measurement or prediction of actual body-fat change.

Missing calendar days do not become zero-intake deficits. Intake/protein averages include logged days. Only days explicitly marked fully logged contribute to historical/weekly balance. The chart can show partial intake while omitting that day's balance. Weight trend uses actual recorded values in a rolling seven-calendar-day window; units are normalized centrally. Current profile settings apply when recalculating history, with the latest weight logged on/before each date; the goal line is labeled as the current goal.

## Storage, concurrency and backup

`AppStore.nutrition` contains typed foods, exercises, weights, favorites, settings and complete-day flags. Saves first calculate/validate the edited snapshot, reject a concurrent nutrition edit rather than overwrite it, then call the existing atomic writer with rollback on failure. Nutrition adds an optional field to the existing backup format; older backups decode with no nutrition records. Restoring an older complete backup is an explicit full replacement. Reset Nutrition deletes only Nutrition; the existing global delete confirmation now includes nutrition. Loading an example health week does not erase nutrition.

Nutrition accepts up to 10,000 combined records, and all records also count toward the existing 100,000-row/20 MiB full-backup limits. Food names, units, dates, numeric ranges and duplicate identities are validated. Photos and API keys are not stored in the nutrition model or backup. Exports are versioned `NUTRITION_EXPORT` JSON; use the existing full backup for complete app restoration.

## Server setup and API key

From the complete source project root:

```sh
npm ci
npm test
cp Server/.env.example Server/.env
chmod 600 Server/.env
# Edit Server/.env locally on your server.
npm start --prefix Server
```

Keep the existing OAuth/encryption configuration. Add `AI_API_KEY`, `AI_API_URL` (the full HTTPS OpenAI-compatible chat-completions endpoint), and optional `AI_MODEL` in **Server/.env**, then restart the server. The example selects `gpt-4o-mini`; choose a model supported by your provider. No key goes in Xcode, the app bundle, browser code, Git, a backup or this chat. Provider usage follows your provider account.

AI routes reuse the existing bridge bearer, session validation, private-origin binding and rate limits. Connect the existing account through More before AI use. Manual nutrition works without that connection. The server still needs its existing WHOOP OAuth setup to issue sessions; this task did not create a separate nutrition password/login.

| POST route | Input JSON | Output JSON |
| --- | --- | --- |
| `/api/nutrition/analyze-meal` | `{image: "data:image/jpeg;base64,..."}` (or PNG) | `{items:[{name,grams,kcal,protein,carbs,fat,confidence}]}` |
| `/api/nutrition/parse-food` | `{text:"2 eggs and toast"}` | Same items envelope |
| `/api/nutrition/estimate-exercise` | `{text:"30 min jogging",weightKg:80}` | `{kcal:...}` |
| `/api/nutrition/day-review` | `{day,eaten,protein,carbs,fat,exercise,goal,estimatedBurned,balance,complete}`; nullable goal/burn/balance | `{summary:"..."}` |

All use `Authorization: Bearer <existing bridge bearer>` and JSON content type. zod validates inputs and outputs. Invalid provider JSON/schema receives exactly one retry; network errors, provider errors and rate limits do not automatically retry. Provider response/body size, time, row and input limits are enforced. Generic error codes/messages never include the provider body or key. Requests use the server-selected HTTPS endpoint, no redirects, inherited proxy/CA trust, six AI requests per session per minute, a 20-second per-provider deadline and the existing overall request deadline.

The native photo picker creates a maximum 1280-pixel thumbnail and re-encodes JPEG before upload, removing source metadata. Compressed images must be below 1 MB. Images and meal descriptions are sent only after the user's analysis action. Estimates return as editable rows and are never saved automatically. Day review sends day totals only after Generate Review, and stale responses cannot replace a newer day's review. Every nutrition screen includes: “Estimates may be inaccurate. Not medical advice.”

## Validation boundary

`npm test` builds/typechecks the TypeScript source, runs calculator/API tests, then the existing Node bridge tests. Swift tests cover the existing core and nutrition backup/DTO integrity. Native source syntax, generated resources, fonts, project references and the updated cloud-upload archive are checked locally. This Linux environment cannot typecheck SwiftUI/JavaScriptCore against Apple's SDK, run an iPhone, authorize Photos/camera, or produce/sign an IPA. Actual Apple SDK and live configured-provider testing remain necessary; no such success is claimed.
