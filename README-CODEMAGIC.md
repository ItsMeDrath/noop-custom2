# Current upload: personalized Profile, highlights and Live

Tap the Home avatar to edit age (no numeric upper limit), WHOOP Age display and day streak. More → Export Data includes profile/highlights JSON and CSV plus the existing daily/HR exports. Profile choices are user-configured; records come from saved measurements. Full-screen Live and prior features are retained. All 143 portable tests pass. Native compilation and Files/storage/camera flows remain unverified. No compiled IPA, NOOP project or user records are included.

# Build WHOOP from Windows using Codemagic

You do not need to own a Mac. Codemagic runs Xcode on its cloud Mac. This package contains iPhone source and the configuration that attempts an unsigned IPA build; it is not an already compiled app or an exact completed WHOOP replica.

1. Extract **WHOOP-Codemagic.zip** on Windows. Do not upload the ZIP itself.
2. Create a **private GitHub repository**. On its page choose **uploading an existing file** or **Add file → Upload files**. Drag all extracted files and folders into it, then commit. Upload the contents, not an extra enclosing folder. `codemagic.yaml`, `Package.swift` and `WHOOP.xcodeproj` must be visible at the repository root. This build package has fewer than 100 files, so it fits one GitHub browser upload batch. Keep `.gitattributes` and `.gitignore` too.
3. Open **https://codemagic.io/**, sign in and authorize access to that repository. Add the repository as an application and choose the **Other** project type / **codemagic.yaml** configuration if prompted. Interface wording may change.
4. Start a build on the branch containing these files. Select **WHOOP - unsigned iPhone IPA for Sideloadly** (`whoop-unsigned-ipa`). This workflow needs no Apple password, signing certificate or App Store Connect secret. Your Codemagic account must have Mac-runner access/build minutes; account-plan charges may apply.
5. If the build succeeds, open its **Artifacts** and download **WHOOP-unsigned.ipa**. On Windows, sign/install it with Sideloadly from **https://sideloadly.io/**, using a connected, trusted iPhone. The app requires iOS 17 or newer.

**Signing limitation:** the IPA is unsigned. The project uses HealthKit, so the profile Sideloadly uses must permit HealthKit; the signer cannot grant a missing capability. If signing/installing reports a HealthKit entitlement error, you need a compatible Apple development certificate/profile. Changing a file extension or removing an entitlement does not provide working HealthKit access. Signing and device compatibility have not been tested here.

**If the build fails:** open the first failing script's log. Apple compiler errors must be fixed before an IPA exists. Where the Xcode build starts, `xcodebuild.log` is retained as an artifact for diagnosis. If no workflow appears, confirm that `codemagic.yaml` is committed at the repository root and that the selected branch contains it.

This task has no connected Codemagic account and cannot dispatch the build or download its result for you yet. No Mac build or installable IPA is claimed. The workflow was prepared from Codemagic's public documentation and checked locally; the cloud build still needs to run.

The complete source archive separately includes the account bridge/backend, implementation reports, Mac signing instructions and detailed validation logs. This smaller cloud-build package contains only the complete iOS build inputs, core tests, packaging helpers and this guide. WHOOP account sync requires separate OAuth/HTTPS-bridge configuration after installation. Private WHOOP services, full device protocols and exact screen/feature parity remain incomplete.

The current package includes Nutrition, its prebuilt offline calculator, and the WorkoutLive extension. No npm install is needed for the iOS-only build; the resource verifier checks that its bundle matches calc.ts. Deploy AI from the separate complete source archive after installing root npm dependencies. The signed app and extension must use related identifiers and compatible profiles.
