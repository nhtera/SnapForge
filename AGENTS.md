# AGENTS.md — SnapForge Codebase Guide

> **SnapForge** is a native macOS screenshot, screen recording, and annotation app built with Swift 6 + SwiftUI + AppKit.
> Bundle ID: `com.snapforge.app` · macOS 15.0+ · Menu-bar-only (`.accessory` activation policy)

---

## Tech Stack

| Layer            | Technology                                     |
| ---------------- | ---------------------------------------------- |
| Language         | **Swift 6.0** (strict concurrency enabled)     |
| UI               | **SwiftUI** (primary) + **AppKit** (windows)   |
| Capture          | **ScreenCaptureKit** (`SCKitService`)           |
| Recording        | **AVAssetWriter** + **SCStream**               |
| Annotation       | SwiftUI Canvas + Core Graphics                 |
| OCR              | Apple **Vision** framework                     |
| Storage          | `UserDefaults` + `FileManager`                 |
| Hotkeys          | `NSEvent` global/local monitors (sandbox-safe)  |
| Project Gen      | **XcodeGen** (`project.yml`)                   |
| Localization     | `en` + `vi` (`.lproj/Localizable.strings`)     |

---

## Project Structure

```
SnapForge/
├── project.yml                    # XcodeGen project definition
├── scripts/build_dmg.sh           # DMG packaging script
├── docs/                          # PRD, research, codebase review notes
│
├── SnapForge/                     # Main source target
│   ├── App/                       # App entry point & coordination
│   │   ├── SnapForgeApp.swift     # @main, MenuBarExtra, AppDelegate
│   │   ├── AppCoordinator.swift   # Singleton window manager (all NSWindow/NSPanel)
│   │   └── AppEnvironment.swift   # @Observable DI container (all services)
│   │
│   ├── Features/                  # Feature modules (each self-contained)
│   │   ├── Annotation/            # Image annotation editor
│   │   ├── Capture/               # Screenshot capture flow
│   │   ├── FloatingPin/           # Always-on-top pinned screenshots
│   │   ├── History/               # Capture history browser
│   │   ├── Onboarding/            # First-launch permission flow
│   │   ├── QuickAccess/           # Post-capture overlay
│   │   ├── Recording/             # Screen recording + GIF
│   │   ├── ScrollCapture/         # Scrolling screenshot capture
│   │   └── Settings/              # Preferences window
│   │
│   ├── Services/                  # Shared services (business logic)
│   │   ├── Capture/               # SCKitService, DesktopIconManager
│   │   ├── Recording/             # ScreenRecordingService, RecordingSession, GIFEncoder
│   │   ├── Windowing/             # (reserved)
│   │   ├── HotkeyService.swift    # Global keyboard shortcuts
│   │   ├── OCRService.swift       # On-device text recognition
│   │   ├── ExportService.swift    # PNG/JPG/WebP/HEIC export
│   │   ├── StorageService.swift   # File persistence & save locations
│   │   ├── ClipboardService.swift # Pasteboard operations
│   │   ├── PermissionService.swift# Screen recording, camera, mic permissions
│   │   ├── ColorPickerService.swift
│   │   ├── MetadataService.swift  # Image metadata (EXIF)
│   │   ├── SoundService.swift     # Audio feedback
│   │   ├── BlurEffectRenderer.swift
│   │   ├── QuickBlurService.swift
│   │   ├── QuickMockupService.swift
│   │   └── AutoRedactService.swift
│   │
│   ├── Shared/                    # Cross-cutting concerns
│   │   ├── Models/                # Data types (CaptureMode, AnnotationItem, SettingsKey, etc.)
│   │   ├── Components/            # Reusable SwiftUI views (MenuBarView, FlowLayout, etc.)
│   │   ├── Extensions/            # NSImage+Extensions
│   │   ├── Styles/                # DesignTokens (spacing, radius, animation, shadow, colors)
│   │   └── Bridging/              # (reserved for AppKit bridging)
│   │
│   ├── Resources/                 # Assets, Info.plist, localization strings
│   └── SnapForge.entitlements     # Sandbox entitlements
│
└── SnapForgeTests/                # Unit tests (Swift Testing)
```

---

## Architecture & Patterns

### 1. Coordinator Pattern — `AppCoordinator`

`AppCoordinator.shared` is the **single source of truth** for all window management. Every NSWindow and NSPanel (onboarding, capture overlay, quick access, annotation editor, history, floating pins, recording indicators) is created, shown, and dismissed through it.

**Rule:** Never create `NSWindow`/`NSPanel` outside `AppCoordinator`. Always add new window operations as methods on the coordinator.

### 2. Dependency Injection — `AppEnvironment`

`AppEnvironment.shared` is an `@Observable` container holding all global services and app-level state (e.g. `isRecording`, `menuBarIconName`). It is injected into the SwiftUI view tree via `.environment(appEnvironment)`.

**Rule:** Access services through `AppEnvironment.shared` (or the injected environment) rather than creating new service instances.

### 3. Singleton Services

Most services use the singleton pattern (`static let shared`). Key singletons:
- `AppCoordinator.shared`
- `AppEnvironment.shared`
- `CaptureSessionManager.shared`
- `ScreenRecordingService.shared`
- `ColorPickerService.shared`
- `ClickVisualizer.shared` / `KeystrokeVisualizer.shared`

### 4. Feature Module Structure

Each feature under `Features/` follows a consistent layout:
```
FeatureName/
├── FeatureView.swift          # Main SwiftUI view
├── FeatureViewModel.swift     # (if needed) @Observable view model
├── Components/                # Feature-specific subviews
├── Managers/                  # Feature-specific managers (e.g. CaptureSessionManager)
└── Services/                  # Feature-specific services (e.g. AnnotationRenderer)
```

### 5. SwiftUI + AppKit Bridging

The app is menu-bar-only (`.accessory` activation policy). All windows use AppKit `NSWindow`/`NSPanel` with `NSHostingView` wrapping SwiftUI content. Key patterns:
- **`NSPanel` with `.nonactivatingPanel`** for overlays that don't steal focus
- **Click-through windows** via `ignoresMouseEvents = true`
- **First-mouse views** (custom `NSView` subclass with `acceptsFirstMouse`) for panels that respond on first click
- **Coordinate conversion** via `cgToCocoaRect()` (CG top-left origin → Cocoa bottom-left origin)

### 6. Settings via `SettingsKey`

All `UserDefaults` keys are centralized in `SettingsKey` (an enum of static string constants). Defaults are registered in `AppEnvironment.init()`.

**Rule:** Never use raw string keys for UserDefaults. Always add new keys to `SettingsKey` and register defaults in `AppEnvironment`.

---

## Concurrency Model

- **Swift 6 strict concurrency** is enabled (`SWIFT_VERSION: "6.0"`)
- All UI-bound classes are annotated `@MainActor`
- Service callbacks use `@Sendable` closures
- Async work uses `Task { @MainActor in ... }` to hop back to the main actor
- Hotkey actions are registered as `@Sendable () -> Void` and dispatch to `@MainActor` via `Task`

---

## Design System — `DesignTokens`

Use the tokens defined in `Shared/Styles/DesignTokens.swift`:

| Token               | Values                                      |
| -------------------- | ------------------------------------------- |
| `Spacing`            | `.xxs(2)` `.xs(4)` `.sm(8)` `.md(12)` `.lg(16)` `.xl(24)` `.xxl(32)` |
| `Radius`             | `.sm(4)` `.md(8)` `.lg(12)` `.xl(16)` `.full(999)` |
| `Animation`          | `.fast(0.15)` `.normal(0.25)` `.slow(0.4)` `.spring` |
| `Shadow`             | `.sm` `.md` `.lg`                           |
| `SelectionColors`    | `.primary` `.dimBackground` `.highlight`    |

**Rule:** Use `DesignTokens` values instead of hardcoded CGFloat/Color values for spacing, radius, animations, and shadows.

---

## Hotkey System

Hotkeys are defined as static constants on `HotkeyService.Hotkey` and registered in `AppDelegate.registerHotkeys()`. Current shortcuts:

| Shortcut | Action           |
| -------- | ---------------- |
| `⌘⇧4`   | Capture Area     |
| `⌘⇧3`   | Capture Fullscreen |
| `⌘⇧W`   | Capture Window   |
| `⌘⇧5`   | Start Recording  |
| `⌘⇧O`   | OCR Capture      |
| `⌘⇧C`   | Color Picker     |
| `⌘⇧S`   | Scroll Capture   |

To add a new hotkey: add a static `Hotkey` constant → register it in `AppDelegate.registerHotkeys()` → add it to `registeredHotkeys` array.

---

## Build & Run

```bash
# Generate Xcode project from project.yml (requires XcodeGen)
xcodegen generate

# Open in Xcode
open SnapForge.xcodeproj

# Build DMG for distribution
./scripts/build_dmg.sh
```

**Minimum deployment target:** macOS 15.0
**Signing:** Automatic, Team `C5K2W2P8WD`
**Sandbox:** Enabled (see `SnapForge.entitlements`)

---

## Testing

Tests live in `SnapForgeTests/` and use **Swift Testing** (`@Test`, `#expect`). Current test files:

- `AnnotationTests.swift` — annotation model & rendering
- `CaptureTests.swift` — capture flow
- `ClipboardServiceTests.swift` — clipboard operations
- `ColorPickerServiceTests.swift` — color picker
- `HotkeyServiceTests.swift` — hotkey registration
- `PermissionServiceTests.swift` — permission checks
- `Phase2Tests.swift` — phase 2 features integration
- `QuickEditTests.swift` — quick edit flows
- `RecordingTests.swift` — recording session lifecycle
- `StorageServiceTests.swift` — file storage

---

## Coding Conventions

1. **File organization:** Use `// MARK: -` sections for logical grouping
2. **Naming:** PascalCase for types, camelCase for properties/methods, descriptive names
3. **Observability:** Use `@Observable` (macOS 14+), not `ObservableObject`/`@Published`
4. **Error handling:** Print with emoji prefixes (`✅`, `❌`, `⌨️`) for console logs
5. **Window levels:** `.floating` for pins, `.statusBar` for recording borders, `.statusBar + 1` for toolbars
6. **Localization:** Support `en` and `vi` — use `Localizable.strings` for user-facing text
7. **Entitlements:** Sandboxed — any new system capability requires an entitlement entry
8. **Documentation:** Use `///` doc comments on public types and complex methods

---

## Common Workflows

### Adding a New Capture Mode
1. Add case to `CaptureMode` enum in `Shared/Models/CaptureMode.swift`
2. Add icon and shortcut strings
3. Handle the new mode in `CaptureSessionManager.startCapture(mode:)`
4. Add hotkey constant to `HotkeyService.Hotkey` and register in `AppDelegate`
5. Add menu item in `MenuBarView`

### Adding a New Service
1. Create `NewService.swift` in `Services/`
2. Use `@MainActor @Observable final class` with `static let shared`
3. Add to `AppEnvironment` if it needs to be injected into views
4. Register defaults in `AppEnvironment.init()` if it uses UserDefaults

### Adding a New Feature Module
1. Create directory under `Features/FeatureName/`
2. Add main view (`FeatureView.swift`)
3. Add components in `Components/` subdirectory
4. If it needs a window, add show/dismiss methods to `AppCoordinator`
5. Wire up from `MenuBarView` or hotkey as appropriate
