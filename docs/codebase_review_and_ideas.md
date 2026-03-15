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

### ✅ Recording
| Feature | Status |
|---------|--------|
| Area Recording | ✅ |
| Fullscreen Recording | ✅ |
| GIF Mode (auto-convert) | ✅ via [GIFEncoder.swift](file:///Users/nguyenhongtien/Code/youtube/SnapForge/SnapForge/Services/Recording/GIFEncoder.swift) |
| Pre-record Countdown (3s) | ✅ |
| Recording Border Indicator | ✅ |
| Recording Toolbar | ✅ (non-activating panel) |
| Click Visualizer | ✅ [ClickVisualizer.swift](file:///Users/nguyenhongtien/Code/youtube/SnapForge/SnapForge/Features/Recording/Components/ClickVisualizer.swift) |
| Keystroke Visualizer | ✅ [KeystrokeVisualizer.swift](file:///Users/nguyenhongtien/Code/youtube/SnapForge/SnapForge/Features/Recording/Components/KeystrokeVisualizer.swift) |
| Webcam Overlay | ✅ [WebcamOverlay.swift](file:///Users/nguyenhongtien/Code/youtube/SnapForge/SnapForge/Features/Recording/Components/WebcamOverlay.swift) |
| Video Trimmer | ✅ [VideoTrimmerView.swift](file:///Users/nguyenhongtien/Code/youtube/SnapForge/SnapForge/Features/Recording/Components/VideoTrimmerView.swift) |
| Codec (H.264/HEVC) | ✅ |
| Resolution (Retina/Standard) | ✅ |
| Cursor show/hide | ✅ |

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
| **Next Sprint** | Color Picker, Quick Edit Toolbar, Annotation Layers Panel | 2-3 days each | High polish, users love these |
| **v1.1** | AI Auto-Redact, Sticker Library, Smart History (tags + search) | 1-2 weeks each | **Killer differentiators** |
| **v1.2** | Scrolling Capture, Multi-Stitcher, Measurement Tools | 1-2 weeks each | Power user features |
| **v2.0** | Video Captions, Screen Diff, Template System, Batch Export | 2-3 weeks each | Pro-tier features |
