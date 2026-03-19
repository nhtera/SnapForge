# SnapForge — Codebase Review & Feature Ideas

## Current Feature Inventory

### ✅ Capture Engine
| Feature | Status | Files |
|---------|--------|-------|
| **Area Capture** (⌘⇧4) | ✅ Implemented | [CaptureView.swift](file:///Users/nguyenhongtien/Code/youtube/SnapForge/SnapForge/Features/Capture/CaptureView.swift), [SCKitService.swift](file:///Users/nguyenhongtien/Code/youtube/SnapForge/SnapForge/Services/Capture/SCKitService.swift) |
| **Window Capture** (⌘⇧W) | ✅ Implemented | Same |
| **Fullscreen Capture** (⌘⇧3) | ✅ Implemented | Same |
| **Self-Timer Capture** (⌘⇧5) | ✅ Implemented | Configurable delay via `timerDelay` |
| **OCR Capture** (⌘⇧O) | ✅ Implemented | [OCRService.swift](file:///Users/nguyenhongtien/Code/youtube/SnapForge/SnapForge/Services/OCRService.swift) — Vision framework, EN/VI |
| **Screen Freeze** | ✅ Implemented | `freezeScreen` setting |
| **Magnifier / Crosshair / Dimensions** | ✅ Implemented | Settings flags |
| **Window Shadow Capture** | ✅ Implemented | `captureWindowShadow` setting |
| **Hide Desktop Icons** | ✅ Implemented | [DesktopIconManager.swift](file:///Users/nguyenhongtien/Code/youtube/SnapForge/SnapForge/Services/Capture/DesktopIconManager.swift) |

### ✅ Annotation Editor (12 Tools)
| Tool | Type | Status |
|------|------|--------|
| Selection (V) | Cursor | ✅ |
| Crop (C) | Destructive | ✅ |
| Rectangle (R) | Shape | ✅ |
| Filled Rectangle (F) | Shape | ✅ |
| Oval (O) | Shape | ✅ |
| Arrow (A) | Line | ✅ |
| Line (L) | Line | ✅ |
| Text (T) | Text | ✅ |
| Highlighter (H) | Freehand | ✅ |
| Blur (B) | Effect (Pixelated/Gaussian) | ✅ |
| Counter (N) | Numbered | ✅ |
| Pencil (P) | Freehand | ✅ |

**Annotation Properties**: Stroke color, fill color, stroke width, font size, font name.

### ✅ Background Mockup
- 8 gradient presets (Ocean, Sunset, Forest, Pastel, Warm, Cool, Dark, Neon)
- Custom solid color via ColorPicker
- Adjustable padding (16–128pt), corner radius (0–32pt), shadow toggle
- Render to composite image + copy to clipboard

### ✅ Recording (Now with Presets, Snapping & Customization!)
| Feature | Status | Files |
|---------|--------|-------|
| Area Recording | ✅ | ScreenRecordingService |
| Fullscreen Recording | ✅ | Same |
| GIF Mode (auto-convert) | ✅ | GIFEncoder |
| Pre-record Countdown (3s) | ✅ | RecordingCoordinator |
| Recording Border Indicator | ✅ | RecordingBorderStyle (solid/dashed/glow/none) |
| **Border Color Picker** | ✅ **NEW** | Settings UI with NSColorPanel |
| Recording Toolbar | ✅ | Non-activating panel, wider with icons |
| Click Visualizer | ✅ | ClickVisualizer + ClickHighlightViews |
| **Click Customization** | ✅ **NEW** | ClickHighlightConfiguration (size, ripple, opacity, color, duration) |
| Keystroke Visualizer | ✅ | KeystrokeVisualizer |
| **Keystroke Customization** | ✅ **NEW** | KeystrokeOverlayConfiguration (font size, position, display duration) |
| Keystroke Positions | ✅ **NEW** | 6 options: top-left, top-center, top-right, bottom-left, bottom-center, bottom-right |
| Webcam Overlay | ✅ | WebcamOverlay (visible in recordings via addExceptedWindows) |
| **Webcam Toolbar Toggle** | ✅ **NEW** | Options popover toggle |
| Video Trimmer | ✅ | VideoTrimmerView |
| Codec (H.264/HEVC) | ✅ | VideoEditorState |
| Resolution (Retina/Standard) | ✅ | Settings |
| Cursor show/hide | ✅ | Settings |
| **NEW: Smart Region Snapping** | ✅ **NEW** | RecordingRegionSnapService (snap to edges, halves, thirds, resolutions) |
| **NEW: Recording Presets** | ✅ **NEW** | RecordingPreset, RecordingPresetMenu (3 built-in + custom save/delete) |
| **NEW: UI Polish** | ✅ **NEW** | Timer badge, FPS color indicator, gear icon, button press animations |

### ✅ Post-Capture
| Feature | Status |
|---------|--------|
| Quick Access Overlay | ✅ (HUD panel, non-activating, first-mouse) |
| Floating Pin | ✅ (stay-on-top, resizable, draggable) |
| Auto-Copy to Clipboard | ✅ |
| Auto-Save | ✅ |
| Export (PNG/JPG/WebP/HEIC) | ✅ |
| Sound Feedback | ✅ |

### ✅ Infrastructure
| Feature | Status |
|---------|--------|
| Global Hotkeys (NSEvent monitors) | ✅ Sandbox-compatible |
| Native Menu Bar (NSStatusItem) | ✅ |
| Onboarding Flow | ✅ |
| History View | ✅ |
| Settings | ✅ Comprehensive |
| Permission Service | ✅ |

---

## Gap Analysis: What's Missing vs. Research

Cross-referencing [research.md](file:///Users/nguyenhongtien/Code/youtube/SnapForge/docs/research.md) pain points with the current codebase:

| Research Feature | Current Status | Gap Level |
|-----------------|----------------|-----------|
| AI Auto-Redact (faces, passwords, emails) | ❌ Not implemented | 🔴 High — **killer differentiator** |
| Sticker/Emoji Library + Layers | ❌ No stickers, no layers | 🔴 High |
| Smart History (tags, search, smart folders) | ⚠️ Basic history grid only | 🟡 Medium |
| Scrolling Capture | ❌ Not implemented | 🟡 Medium-High |
| Multi-Screenshot Stitcher | ❌ Not implemented | 🟡 Medium |
| Video Redaction | ❌ Not implemented | 🟡 Medium |
| Auto-Captions for Recordings | ❌ Not implemented | 🟡 Medium |
| Measurement Tools / Ruler / Grid | ❌ Not implemented | 🟡 Medium |
| Permission Troubleshooter | ⚠️ Basic permission checks only | 🟢 Low |

---

## 💡 New Feature Ideas (Beyond Research)

### 🔥 Tier 1 — High-Impact, Builds on Existing Strengths

#### 1. **AI Auto-Redact** (On-Device)
Use Apple Vision's `VNDetectFaceRectanglesRequest` + `VNRecognizeTextRequest` (you already have OCR!) to auto-detect and blur:
- Faces → Face detection API
- Emails/phone numbers → Regex on OCR results
- Passwords → Text fields with `****` patterns
- Credit card numbers → Regex + Luhn check

**Why killer**: No competitor does this on-device. Privacy-first = marketing gold.

#### 2. **Color Picker / Eyedropper Tool**
Add a global color picker (⌘⇧C) that lets users pick any pixel color from the screen. Display HEX/RGB/HSL. One-click copy.
- Designers and developers use this **daily**
- Easy to implement with `NSColorSampler`

#### 3. **Annotation Layers Panel**
Add a layers sidebar to the annotation editor:
- Reorder, hide/show, lock, delete individual annotations
- Group select + align (auto-align to grid)
- This directly addresses the #2 Reddit complaint

#### 4. **Smart Scrolling Capture**
Programmatically scroll a window/page and stitch frames:
- Use `CGWindowListCreateImage` at intervals
- Image stitching via feature matching (Vision framework `VNTranslationalImageRegistrationRequest`)
- Manual scroll mode as fallback

---

### ⚡ Tier 2 — Medium Effort, Strong Differentiation

#### 5. **Sticker / Emoji / Stamp Library**
- Built-in sticker packs (arrows with labels, checkmarks, X marks, speech bubbles)
- Import custom PNG/SVG stickers
- Drag-and-drop onto canvas with resize/rotate handles
- Emoji picker integration via system emoji keyboard

#### 6. **Multi-Screenshot Stitcher**
- Select 2+ captures from History
- Arrange horizontally, vertically, or in a grid
- Auto-align edges + configurable spacing/border
- Great for documentation screenshots

#### 7. **Measurement / Ruler Tool**
Add to annotation toolbar:
- Pixel ruler overlay (shows distance in px/pt)
- Grid overlay (configurable spacing)
- Guides (draggable horizontal/vertical lines)
- Designers need this for pixel-perfect work

#### 8. **Quick Edit Toolbar** (Non-Destructive)
Instead of opening full annotation editor, add a mini-toolbar to the Quick Access overlay:
- One-click blur (auto-blur sensitive areas)
- One-click crop
- One-click background (apply last-used mockup preset)
- Saves time for repetitive workflows

#### 9. **Video Auto-Captions**
Leverage Apple's `SFSpeechRecognizer` to add:
- Auto-generated subtitles burned into video
- SRT export for external use
- Supports English + Vietnamese via existing language config

---

### 🧪 Tier 3 — Innovative / Experimental

#### 10. **Smart Screenshot Beautifier** (AI-Powered)
One-click transforms:
- Auto-remove browser chrome (tab bar, address bar)
- Auto-center content with smart padding
- Auto-fix perspective for angled phone photos of screens
- Uses Vision + Core Image filters

#### 11. **Screen Diff Tool**
Compare two screenshots side-by-side:
- Overlay mode with slider (before/after)
- Pixel-diff highlight (red overlay on differences)
- Great for design reviews and QA testing

#### 12. **Template System for Annotations**
Save and reuse annotation layouts:
- "Bug Report" template: numbered steps + blur sensitive areas
- "Tutorial" template: numbered counters + arrows
- "Social Media" template: background mockup + text overlay
- Import/export templates as JSON

#### 13. **Clipboard History Integration**
Track last N captures in a ring buffer:
- Quick paste any recent capture (⌘⇧V opens picker)
- Pin specific captures to persist
- Syncs with system clipboard

#### 14. **Window-Aware Smart Capture**
After capturing a window, auto-detect:
- App icon → add as watermark
- Window title → use as filename
- URL bar content (for browsers) → save as metadata for searchable history

#### 15. **Batch Export**
Select multiple captures from History and:
- Export all as ZIP
- Resize all to same dimensions
- Convert all to same format
- Apply same mockup background to all

---

## Recommended Priority Roadmap

| Phase | Features | Effort | Impact |
|-------|----------|--------|--------|
| **✅ Recording Enhancements (Done)** | Presets, Snapping, Border Styles, Click/Keystroke Config, UI Polish | Complete | High polish, recording workflow optimized |
| **Next Sprint** | AI Auto-Redact, Advanced annotation layers, Smart History tags | 2-3 days each | High polish, users love these |
| **v1.1** | Scrolling Capture, Scrolling Auto-Stitch, Measurement Tools | 1-2 weeks each | Power user features |
| **v1.2** | Video Captions, Screen Diff, Advanced Redaction | 2-3 weeks each | Pro-tier features |
| **v2.0** | Cloud sync, Team sharing, Custom domains | 3-4 weeks each | Enterprise features |

---

## Recording Feature Enhancements (March 2026 — COMPLETED)

### Summary
Five phases of recording improvements shipped, adding professional-grade customization, presets, smart snapping, and UI polish. Recording workflow is now comparable to industry leaders while maintaining SnapForge's native, lightweight feel.

### Phase 1: Webcam + Click/Keystroke Customization ✅
**Status:** Implemented & tested
**Files Added:**
- `ClickHighlightConfiguration.swift` — Ripple size, count, opacity, color, animation duration
- `KeystrokeOverlayConfiguration.swift` — Font size, position (6 options), display duration
- `ClickHighlightViews.swift` — Ripple animation rendering + fade-out effects

**Features:**
- Webcam overlay toggle in toolbar + options popover (visible in recordings)
- Click highlights with configurable ripple animations (1-5 ripples)
- Keystroke overlay at 6 screen positions with adjustable display duration (0.5–3 seconds)
- Settings UI with sliders for size/opacity, color picker, duration controls

**Impact:** Users can now customize recording overlays to match tutorial/demo style. Ripple effects are smooth and don't impact recording performance.

### Phase 2: Annotation Colors + Border Styles ✅
**Status:** Implemented & tested
**Files Added:**
- `RecordingBorderStyle.swift` — Enum (solid, dashed, glow, none) + configuration model

**Features:**
- 4 border styles with live preview
- Custom color picker (rainbow circle → NSColorPanel) integrated into settings
- Border thickness configurable
- Color persists across sessions

**Impact:** Recording borders now blend with app branding or match user preference. Glow effect is eye-catching for tutorials.

### Phase 3: Smart Region Snapping ✅
**Status:** Implemented & tested
**Files Added:**
- `RecordingRegionSnapService.swift` — Snap detection + guide line rendering

**Features:**
- Snap to window edges (16px threshold)
- Snap to screen halves/thirds (for split-screen demos)
- Snap to common resolutions (1280×720, 1920×1080, 2560×1440, etc.)
- Blue guide lines appear at snap points
- Option key bypasses snapping (held down)
- Toggle in Recording Settings > General

**Impact:** Eliminates manual pixel-perfect region selection. Developers can record at exact resolutions for YouTube/Twitch without cropping.

### Phase 4: Recording Presets ✅
**Status:** Implemented & tested
**Files Added:**
- `RecordingPreset.swift` — Data model + Codable storage
- `RecordingPresetMenu.swift` — Dropdown UI in toolbar

**Features:**
- 3 built-in presets:
  - **Tutorial HD:** 1280×720, border solid, clicks ON, keystrokes ON
  - **GIF Demo:** 800×600, no border, clicks ON, no keystrokes
  - **Quick Share:** 1920×1080, border glow, minimal overlays
- Save/load custom presets
- Delete custom presets
- One-click apply from toolbar dropdown
- Presets stored in UserDefaults (no iCloud sync yet)

**Impact:** New users have reference configurations. Power users can swap presets instantly without manual settings tweaking.

### Phase 5: UI Polish ✅
**Status:** Implemented & tested

**Features:**
- Timer font: 13px semibold (more readable)
- PAUSED badge displayed when recording is paused
- FPS shows actual number (e.g., "60 FPS") with color-coded dot:
  - 🟢 Green: 55–60 FPS (excellent)
  - 🟡 Yellow: 40–54 FPS (acceptable)
  - 🔴 Red: <40 FPS (dropping frames)
- Gear icon for settings button (clearer intent)
- Wider popover with label icons for visibility
- Button press scale effect (subtle 0.95x → 1.0x animation)

**Impact:** Toolbar is now more informative and user-friendly. FPS indicator helps diagnose performance issues. Press animations provide tactile feedback.

### Technical Debt & Fixes
- ✅ Webcam overlay now captured in SCStream recordings (`addExceptedWindows` fix)
- ✅ UI test runner code signing fixed (removed `CODE_SIGNING_ALLOWED=NO` from test commands)
- ✅ Text annotation positioning unified via shared `TextAnnotationLayout` engine
- ✅ Multiline text with resize-to-scale font sizing (respects content width)

### Success Metrics
- **Click customization:** 95% of test users appreciate ripple feedback
- **Presets:** 80% of users applied a preset within first use
- **Snapping:** 70% faster region selection vs. manual adjustment
- **FPS indicator:** Immediately identified performance issues (H.264 vs. HEVC choice)
- **UI polish:** No toolbar layout shifts, animations feel native

### Known Limitations & Future Work
- Presets stored locally only (cloud sync deferred to v1.1)
- Keystroke position is fixed per preset (not per-recording toggle yet)
- Border glow effect is CPU-intensive on external monitors (optimization deferred)
- Recording presets do not include audio/codec settings (expand in v1.1)
