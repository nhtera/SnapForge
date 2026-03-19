
**SnapForge — Product Requirements Document (PRD)**  
**Version:** 1.0  
**Date:** March 13, 2026  
**Author:** Tien Nguyen
**Purpose:** This PRD is written specifically for Claude (or any LLM coder) to break into tasks, create tickets, and implement step-by-step. Every section is modular with clear acceptance criteria.

### 1. Product Overview & Vision
**Product Name:** SnapForge  
**Tagline:** Forge perfect captures.  
**One-liner:** The beautiful, blazing-fast, fully native Mac app for screenshots, screen recordings, annotation, and editing — built like CleanShot X but with a fresh identity, lower price, and room for future AI polish.

**Vision**  
SnapForge is the “7-tools-in-one” successor that feels 100% native on macOS (SwiftUI + ScreenCaptureKit). Users open it once, set global hotkeys, and never think about screenshots again — everything just works instantly and looks premium.

### 2. Goals & Objectives
- Deliver a polished MVP in 8–12 weeks for solo developer.
- Beat CleanShot on price (one-time $19–29) and feel more modern.
- 4.8+ App Store rating target.
- Core success metric: 70% of users use the app daily after week 1.

### 3. Target Audience & Personas
- Primary: Developers, designers, content creators, educators, QA engineers on Mac (M1–M4 chips).
- Secondary: Anyone who hates macOS built-in screenshot workflow.
- Pain points: Messy desktop icons, poor scrolling capture, weak annotation, no floating screenshots, slow exports.

### 4. Core Features (Prioritized)

| Phase | Feature Category | Must-Have Features (with Acceptance Criteria) | Nice-to-Have (v1.1+) |
|-------|------------------|-----------------------------------------------|----------------------|
| **MVP** | Capture | • Area, Window, Fullscreen, Self-timer<br>• All-In-One mode (single shortcut + crosshair/magnifier)<br>• Pixel-perfect Retina + notch handling<br>• Freeze screen option | Scrolling capture (vertical + horizontal) |
| **MVP** | Recording | • MP4 & GIF (area/window/fullscreen)<br>• Mic + system audio + webcam overlay<br>• Show clicks & keystrokes (customizable)<br>• Recording presets (Tutorial HD, GIF Demo, Quick Share)<br>• Smart region snapping (edges, halves, thirds, resolutions)<br>• Border styles (solid/dashed/glow/none) with color picker<br>• Auto Do-Not-Disturb + hide clutter<br>• Built-in trimmer + volume adjust<br>• FPS indicator + timer display polish | Mono/stereo toggle, cloud preset sync |
| **MVP** | Annotation & Editing | • Crop, Arrow (straight + curved), Shapes, Line, Text (7 styles)<br>• Pencil (auto-smooth), Highlighter, Blur, Pixelate, Spotlight, Counter<br>• Combine multiple screenshots<br>• Dark/Light mode editor<br>• Save as editable .snapforge project file | Smart resize tool, auto-color picker |
| **MVP** | Export & Quick Access | • Quick Access Overlay after every capture (copy, save, annotate, drag-drop)<br>• Export PNG, JPG, WebP, HEIC, MP4, GIF<br>• Menu bar + global hotkeys (customizable) | — |
| **Phase 1** | Extras | • On-device OCR (Vision framework, multi-language incl. Vietnamese)<br>• Floating pinned screenshots (always-on-top, opacity, Lock mode)<br>• Background tool (10 gradients + custom + Auto Balance)<br>• Capture History (30 days, searchable) | Cloud upload (S3 or your backend), self-destruct links |
| **Future** | AI & Polish | • AI auto-blur sensitive info<br>• Auto-captions for recordings<br>• Smart annotation suggestions | Team sharing, custom domains |

### 5. User Flows (Key Scenarios)
1. **Instant Screenshot** → Global hotkey → Crosshair → Release → Quick Access Overlay appears → Annotate or copy in <3 seconds.
2. **Screen Recording** → Hotkey → Select area → Record with webcam/clicks → Stop → Auto trim + export.
3. **Scrolling Capture** → Hotkey → Scroll automatically → Stitch → Annotate.
4. **Floating Pin** → Annotate → “Pin” button → Screenshot floats above all windows forever.

### 6. Technical Requirements & Architecture
**Tech Stack (must use for native performance):**
- Language: Swift 6 + SwiftUI (primary) + AppKit where needed
- Capture: **ScreenCaptureKit** (macOS 12.3+)
- Recording: SCStream + AVAssetWriter
- Annotation: SwiftUI Canvas + PencilKit + Core Graphics / Bezier paths
- OCR: **Vision** framework (VNRecognizeTextRequest)
- Video editing: AVFoundation
- Storage: UserDefaults + FileManager (Security-Scoped Bookmarks for sandbox)
- Hotkeys: MASShortcut or new macOS 15+ API
- Project format: Custom .snapforge (JSON + images bundle)
- Distribution: Notarized direct download + Mac App Store (sandboxed)

**Architecture Overview (Claude — implement in this order):**
1. MenuBarApp + Settings window (SwiftUI)
2. CaptureEngine (ScreenCaptureKit wrapper)
3. RecordingEngine (AVAssetWriter + SCStream)
4. AnnotationView (SwiftUI Canvas + tools toolbar)
5. QuickAccessOverlay (NSWindow / SwiftUI popover)
6. HistoryManager + FloatingWindow

**Permissions (must handle gracefully):**
- Screen Recording (TCC prompt)
- Microphone & Camera
- Accessibility (for keystroke detection & scrolling in some apps)

### 7. Non-Functional Requirements
- Performance: <100ms to show overlay, 60 fps recording on M-series, <5% CPU idle
- Size: <25 MB binary
- macOS Support: macOS 13 Ventura → latest Tahoe (test on both Intel & Apple Silicon)
- Localization: English + Vietnamese (easy to add more)
- Accessibility: VoiceOver + keyboard-only navigation
- Privacy: All processing on-device (no telemetry by default)

### 8. UI/UX Guidelines
- 100% native macOS look (SF Symbols, rounded corners, Liquid Glass hints on Tahoe)
- Dark/Light auto-follow system
- Minimalist: One window + overlay + menu bar icon
- Animations: Subtle (like CleanShot)
- Icon: Simple hammer + pixel (you can generate with Grok Imagine later)

### 9. Monetization & Distribution
- One-time purchase: $24 (App Store + direct download)
- Optional Cloud add-on (future)
- Free 14-day trial (feature-limited or watermark)
- Setapp inclusion later

### 10. Success Metrics & Milestones
- MVP ready: Core capture + annotation + recording working
- Beta: 50 testers (Reddit r/macapps + Twitter)
- Launch: App Store + direct site with one-click download

### 11. Assumptions & Risks
- Assumptions: Developer is comfortable with ScreenCaptureKit (use Apple’s official sample + BetterCapture GitHub as reference)
- Risks & Mitigations:
  - Scrolling capture tricky → Start with basic capture, add later
  - Permission friction → Beautiful onboarding screen + video tutorial
  - Name conflict → Already deep-checked: SnapForge is clean (minor unrelated Android/Chrome extension only)

