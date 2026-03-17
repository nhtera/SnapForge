# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SnapForge is a native macOS screenshot, screen recording, and annotation app. Menu-bar-only (`.accessory` activation policy), built with Swift 6 strict concurrency + SwiftUI + AppKit. Bundle ID: `com.snapforge.app`, macOS 15.0+.

## Build & Development

```bash
# Generate Xcode project (required after changing project.yml)
xcodegen generate

# Build from command line (CI-style, no code signing)
xcodebuild -project SnapForge.xcodeproj -scheme SnapForge -configuration Release \
  -derivedDataPath build/DerivedData \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  ONLY_ACTIVE_ARCH=NO build

# Run tests
xcodebuild -project SnapForge.xcodeproj -scheme SnapForgeTests -configuration Debug \
  -derivedDataPath build/DerivedData \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  test

# Build DMG for distribution
./scripts/build_dmg.sh

# Bump version (patch|minor|major) — updates project.yml
./scripts/bump-version.sh patch

# Update Sparkle appcast after a release
./scripts/update-appcast.sh

# Generate changelog from git history
./scripts/generate-changelog.sh [since-tag]
```

**Prerequisites:** Xcode 26.0+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

Project definition lives in `project.yml` (not the .xcodeproj). Always edit `project.yml` and run `xcodegen generate` — never edit the Xcode project directly.

## Architecture

### Core Singletons

- **`AppCoordinator.shared`** — Single source of truth for all window management. Every `NSWindow`/`NSPanel` is created, shown, and dismissed through it. Never create windows outside this coordinator.
- **`AppEnvironment.shared`** — `@Observable` DI container holding all services and app state (`isRecording`, `menuBarIconName`, etc.). Injected into SwiftUI via `.environment(appEnvironment)`. Access services through this, not by creating new instances.
- **`CaptureSessionManager.shared`** — Manages screenshot capture lifecycle.
- **`ScreenRecordingService.shared`** — Recording session management.
- **`RecordingCoordinator.shared`** — Orchestrates recording UI (indicators, toolbars, borders).

### SwiftUI + AppKit Bridging

The app uses AppKit `NSWindow`/`NSPanel` with `NSHostingView` wrapping SwiftUI content. Key patterns:
- `NSPanel` with `.nonactivatingPanel` for overlays that don't steal focus
- Click-through windows via `ignoresMouseEvents = true`
- Custom `FirstMouseView` (NSView subclass) for panels responding on first click
- Coordinate conversion: `cgToCocoaRect()` (CG top-left → Cocoa bottom-left)
- Activation policy toggles between `.accessory` (menu-bar) and `.regular` (Cmd+Tab visible)

### Settings

All `UserDefaults` keys are centralized in `SettingsKey` enum (static string constants). Defaults registered in `AppEnvironment.init()`. Never use raw string keys — always add to `SettingsKey`.

### Design Tokens

Use `DesignTokens` from `Shared/Styles/DesignTokens.swift` for spacing (`.xxs` through `.xxl`), radius, animation durations, and shadows. Don't hardcode these values.

## Concurrency

Swift 6 strict concurrency is enabled. All UI-bound classes are `@MainActor`. Use `@Observable` (not `ObservableObject`/`@Published`). Async work hops back to main actor via `Task { @MainActor in ... }`.

## Testing

Tests in `SnapForgeTests/` use **Swift Testing** framework (`@Test`, `#expect`) — not XCTest.

## Release Pipeline

Three GitHub Actions workflows:
1. **CI** (`ci.yml`) — builds on push/PR to `main`
2. **Release Prepare** (`release-prepare.yml`) — triggered by `release(patch|minor|major):` commit message or manual dispatch. Bumps version, generates changelog, creates release PR on `release/vX.Y.Z` branch.
3. **Release Publish** (`release-publish.yml`) — runs when release PR merges.

Auto-updates via Sparkle. Appcast XML at `appcast.xml` root.

## Key Conventions

- Feature modules under `Features/` are self-contained: `FeatureView.swift`, optional `FeatureViewModel.swift`, `Components/`, `Managers/`, `Services/`
- New capture modes: add case to `CaptureMode` enum → handle in `CaptureSessionManager` → add hotkey in `HotkeyService.Hotkey` + `AppDelegate.registerHotkeys()` → add menu item in `MenuBarView`
- New windows: add show/dismiss methods to `AppCoordinator`
- New services: `@MainActor @Observable final class` with `static let shared`, add to `AppEnvironment` if needed
- Localization: `en` + `vi` via `.lproj/Localizable.strings`
- Sandboxed app — new system capabilities require entitlement entries in `SnapForge.entitlements`
- Window levels: `.floating` for pins, `.statusBar` for recording borders, `.statusBar + 1` for toolbars

## Dependencies

- **Sparkle 2.8.1** — auto-update framework (SPM)
