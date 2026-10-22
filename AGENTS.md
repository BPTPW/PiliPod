# PiliPod agent instructions

## Project overview

- PiliPod is a SwiftUI Bilibili client with iOS 26.0 as the minimum supported
  version. The current target and verification platform is the latest iOS 27.0.
- The app target is `PiliPod` in `PiliPod.xcodeproj`. The repository also has
  `PiliPodTests` unit tests and `PiliPodUITests` UI tests.
- Swift code is organized by responsibility: `Models/` for API and domain
  types, `ViewModels/` for screen state and workflows, `Views/` for SwiftUI
  screens, `Components/` for reusable UI, and `Services/` for networking,
  playback, caching, and system integrations.
- The app uses SwiftUI with UIKit/AVFoundation integration where needed. MPVKit
  is the alternate playback engine and is pinned through Swift Package Manager.

## Working conventions

- Read the relevant view model, service, model, and view together before
  changing a user-facing flow. Keep API, playback, cache, and UI responsibilities
  in their existing layers.
- Preserve the existing SwiftUI style, localization setup, and naming patterns.
  User-visible strings belong in `PiliPod/Localizable.xcstrings` or the existing
  localization helpers; do not add hard-coded strings to new UI.
- Prefer structured Foundation APIs and existing project helpers over new
  parsing or networking abstractions. Keep changes focused and avoid unrelated
  project-file or generated-file churn.
- Do not commit credentials, cookies, personal Bilibili data, derived build
  products, or changes under `xcuserdata/`.
- Treat Bilibili API behavior and playback/CDN URLs as external inputs. Preserve
  existing fallback and error handling when modifying those paths.

## Dependencies and project files

- Swift Package Manager dependencies are recorded in
  `PiliPod.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`:
  MPVKit, Swift Protobuf, and ZIPFoundation.
- Update package dependencies through Xcode/Swift Package Manager and keep the
  resolved file in sync. Do not hand-edit generated Xcode project sections unless
  the change is specifically about project configuration.
- `PiliPod/Generated/` contains generated protobuf sources. Modify the source or
  generation process instead of editing generated output when possible.

## Build and test verification

- The Xcode MCP server (`xcode-mcp`) is configured for this project. After Swift
  or Xcode project changes, prefer its diagnostics, build, and test tools for
  verification. Use the `PiliPod` scheme and an iOS 27.0 simulator or device
  when available; iOS 26.0 remains the minimum deployment target.
- Run the focused unit tests in `PiliPodTests` for model, signing, CDN, cache,
  or service changes. The existing tests use Swift Testing (`import Testing`).
- Run `PiliPodUITests` when changing navigation, launch behavior, permissions,
  orientation, or other user flows. UI tests may require a configured simulator
  and can depend on network/login state.
- Do not treat shell `xcodebuild` as the default path unless the Xcode MCP tools
  are unavailable in the current session or the user specifically asks for shell
  output. If a shell fallback is needed, use the `PiliPod.xcodeproj` project,
  the `PiliPod` scheme, and an explicit iOS simulator destination.
- Report verification limits clearly when a build or test cannot run because the
  required Xcode version, SDK, simulator, package cache, or network is missing.

## Change checklist

Before finishing a code change:

1. Check the diff for accidental changes to generated files, `xcuserdata/`, or
   local-only settings.
2. Build or run the most relevant test target using the verification rules above.
3. For UI changes, verify both portrait and landscape behavior where the affected
   screen supports both orientations.
4. Summarize changed files, verification performed, and any remaining limitation.
