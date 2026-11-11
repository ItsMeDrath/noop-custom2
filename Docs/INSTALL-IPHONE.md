# Build an IPA and install on your iPhone

This source project is an independent WHOOP-branded reconstruction. Building an IPA does not make its behavior identical to the official app. The supplied Android APK cannot be converted into an iPhone IPA: Android DEX/native libraries and iOS application binaries use different platforms.

## Windows: use Codemagic

Use the separate `WHOOP-Codemagic.zip` build upload and follow [the Windows/Codemagic guide](../README-CODEMAGIC.md). Its flat layout places `codemagic.yaml` at the repository root, so the project can be added to Codemagic and built on a cloud Mac. No local Mac is required. A successful build exposes `WHOOP-unsigned.ipa` in its artifacts; it still needs compatible signing before installation. No Codemagic build has been dispatched or passed here.

## Easiest path on your Mac

1. Extract `WHOOP-iOS-source.zip` into a short local folder, such as Downloads.
2. Install/open full **Xcode 16 or newer**, finish its first-launch setup, and install its iOS platform support. Command Line Tools alone are insufficient. In Xcode Settings → Locations, select that Xcode installation for Command Line Tools if needed.
3. Double-click **Build IPA.command** in the extracted `WHOOP-iOS` folder. If macOS asks which app to use, open Terminal and run the command below from that folder. Normal macOS approval may be required for a downloaded script; do not disable system security.
4. A successful build reveals **build/WHOOP-unsigned.ipa** in Finder. An error stops packaging and retains the Xcode log under `build/device-build.*/xcodebuild.log`; the `.xcresult` can be opened in Xcode.

```sh
bash Scripts/package-ipa-on-mac.sh
```

The script builds a Release **arm64 iPhoneOS** product, packages its actual `.app` under `Payload/`, checks its Mach-O platform and computes a SHA-256 digest. It rejects simulator products. This environment has Linux, no Xcode and no Mac executor, so the Apple build has not been run or passed here. A script that stops on a real compiler error has not produced a usable IPA.

## Install the unsigned IPA using Sideloadly

1. Install Sideloadly from [its official site](https://sideloadly.io/) on your Mac, connect your iPhone and accept the computer-trust prompt.
2. Select the connected iPhone and drag `WHOOP-unsigned.ipa` into Sideloadly.
3. Sign in through Sideloadly and start signing/installing. Enter Apple credentials only into the trusted signing tool or Xcode, never this chat or the project source. Keep the app name WHOOP; use a separate app identifier if the signing tool requires one.
4. Follow the iPhone's developer trust and Developer Mode prompts when applicable. Signing/profile validity and renewal depend on your Apple account and the generated profile.

**HealthKit must be permitted by the signing profile.** This project includes `com.apple.developer.healthkit`. Sideloadly cannot grant a capability that the provisioning profile lacks. If signing or installation reports an entitlement error, use a matching Apple development profile and Xcode's signing workflow below. Removing the entitlement while continuing to call HealthKit does not provide a working equivalent. This Sideloadly workflow has not been tested here, and an installable result is not guaranteed for every account/profile combination.

## Xcode signing or a signed development IPA

For direct installation, open `WHOOP.xcodeproj`, choose your connected iPhone, select your team under Signing & Capabilities, set your own unique bundle identifier if necessary, and press Run. The app display name remains WHOOP. Xcode must be able to provision HealthKit for that team and registered device.

To archive/export with an existing development team, sign in through Xcode, then run:

```sh
bash Scripts/export-signed-ipa-on-mac.sh ABCDE12345 com.yourname.whoop
```

Replace the example team and bundle identifiers with your actual values. The script uses Xcode's automatic provisioning and `debugging` export method, preserves the HealthKit entitlement and validates the resulting device package. It does not create an Apple membership, register arbitrary devices without your Xcode authorization, obtain missing entitlements or manufacture a signing certificate. Xcode may request permission to create/update profiles. The signed development IPA only supports devices allowed by that profile.

## Alternative: GitHub's Mac runner

The source includes `.github/workflows/ios-ipa.yml`, a manual workflow. Place the extracted project contents at a GitHub repository root, including the hidden `.github` directory. Alternatively, the project can be under `WHOOP-iOS/`, but copy its workflow into the repository-root `.github/workflows/` folder so GitHub discovers it.

In that repository open **Actions → Build iPhone IPA → Run workflow**. The workflow uses `macos-15`, tests the core and validator, builds for iPhoneOS and uploads `WHOOP-unsigned-iphone-ipa` only after a successful build. Download/extract that artifact and sign the IPA using the steps above. GitHub may charge for private-repository runner use according to your account plan. No Apple signing secrets are needed for this unsigned build.

The workflow has been prepared but not dispatched: this task has no usable GitHub login or connected Mac. No repository was changed remotely and no cloud-environment configuration was published.

## What an IPA does not complete

Account sync still needs your registered WHOOP OAuth client and configured HTTPS bridge; see [account setup](ACCOUNT-SYNC.md). Full official-app parity still requires authenticated screen/behavior comparisons, unrecovered private features and algorithms, complete device protocol work and physical-device validation. The supplied source, synthetic tests and Android static evidence cannot establish those results.
