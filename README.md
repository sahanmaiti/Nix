<div align="center">

# Nix

**Close the window. Quit the app.**

Nix is a lightweight macOS menu bar utility that automatically quits applications when their last window is closed — bringing Windows-style app lifecycle behavior to macOS, natively.

<br>

![macOS](https://img.shields.io/badge/macOS-14.6%2B-black?style=flat-square&logo=apple)
![Swift](https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift)
![License](https://img.shields.io/badge/license-MIT%20(source)-blue?style=flat-square)
![Pricing](https://img.shields.io/badge/pricing-%249.99%20one--time-success?style=flat-square)
![Distribution](https://img.shields.io/badge/distribution-Direct%20DMG-lightgrey?style=flat-square)

<br>

</div>

---

## What is Nix?

On macOS, closing a window doesn't quit the app. It never has. Safari, Notes, Preview — close every window and the process keeps running, quietly consuming memory and CPU in the background. For users coming from Windows, this is immediately confusing. For power users who know what's happening, it's a constant source of manual cleanup.

This is a deliberate design decision by Apple: apps are expected to persist between uses, reopening instantly when called. For some apps — Music, Messages, system utilities — that makes perfect sense. For most others, it's just waste.

**Nix changes that.** When you close the last window of an app, Nix detects it and terminates the process cleanly — exactly as if you'd pressed `Cmd+Q`. The app handles its own shutdown (saving state, showing unsaved-changes dialogs), so nothing is forced or unsafe. You just get a Mac that behaves the way you expect.

Per-app rules mean Nix only does this where you want it to. Music keeps playing. Finder stays put. Discord hides like it always does. Everything else quits when you're done with it.

---

## Get Nix

Nix is a **one-time $9.99 purchase** with a **7-day free trial** — no subscription, no account required.

- **Download:** direct signed DMG at [nix-mu.vercel.app](https://nix-mu.vercel.app)
- **Trial:** full functionality for 7 days from first launch
- **Purchase:** handled by [Lemon Squeezy](https://lemonsqueezy.com) (Merchant of Record) — license key delivered by email, or entered manually in-app
- **Updates:** automatic, via [Sparkle](https://sparkle-project.org)

> Not available on the Mac App Store — see [App Store Sandbox](#known-limitations) below for why.

---

## Features

**Core behavior**
- Automatically quits apps when their last window closes
- Configurable grace period (0–30s) before terminating — reopen a window to cancel
- Four per-app behaviors: **Quit**, **Hide**, **Ignore**, or **Prompt**
- Default behavior applies globally; override per-app as needed

**Smart detection**
- Powered by the macOS Accessibility API (`AXObserver`/`AXUIElement`) — event-driven, not polling
- Two-phase confirmation (150ms + 500ms) to correctly handle apps that hide instead of closing (Discord, Slack, Mimestream, Teams, Zoom, Skype) and apps with windows on background Spaces
- Excludes sheets, dialogs, floating windows, and zero-size phantom AX windows from the count
- Hidden apps (`Cmd+H`) are intentionally left alone — Nix never quits what you've hidden

**Whitelist & rules**
- Built-in permanent whitelist: Finder, Dock, system UI processes — never touched
- User-managed whitelist: add any app you want Nix to ignore
- Per-app rule editor in Settings with search, sorted app list, and instant changes
- Rules persist across restarts via `UserDefaults`

**System integration**
- Launch at login via `SMAppService` (native, no helper app)
- Optional system notifications when an app is quit
- Menu bar icon reflects current state: active, paused, or disabled
- Pause monitoring for 30 minutes or 2 hours
- Automatic updates via Sparkle, with EdDSA-signed appcast

**Design**
- Native SwiftUI + AppKit hybrid — no Electron, no third-party UI frameworks
- Menu bar popover with live app list and one-click controls
- Tab-based Settings window: General, Apps, Whitelist
- Guided first-launch onboarding, including Accessibility permission walkthrough

---

## Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│                        NixApp  (@main)                             │
│         AppDelegate — window management, Sparkle, license gate     │
│                                                                    │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │                 AppEnvironment  (singleton)                │    │
│  │                                                            │    │
│  │  ┌──────────────┐   ┌───────────────────┐  ┌────────────┐  │    │
│  │  │  AppTracker  │   │ AccessibilityMgr  │  │LicenseMgr  │  │    │
│  │  │  NSWorkspace │   │ AXIsProcessTrusted│  │TrialManager│  │    │
│  │  └──────┬───────┘   └───────────────────┘  └────────────┘  │    │
│  │         │ startMonitoring(app:)                            │    │
│  │         ▼                                                  │    │
│  │  ┌───────────────────────┐                                 │    │
│  │  │    WindowMonitor      │  AXObserver per app, C callback │    │
│  │  │  Phase1 (150ms debounce) → Phase2 (500ms cross-space)   │    │
│  │  └──────────┬────────────┘                                 │    │
│  │             │ onZeroWindows(app:)                          │    │
│  │             ▼                                              │    │
│  │  ┌───────────────────────┐   ┌─────────────────────┐       │    │
│  │  │     QuitEngine        │◄──│     RuleStore       │       │    │
│  │  │  quit / hide / ignore │   │  UserDefaults JSON  │       │    │
│  │  │  / prompt, grace timer│   │  per-app rules      │       │    │
│  │  └───────────────────────┘   └─────────────────────┘       │    │
│  └────────────────────────────────────────────────────────────┘    │
│                                                                    │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────────────┐   │
│  │ MenuBarView   │  │ SettingsView  │  │ Onboarding / Paywall  │   │
│  │  (SwiftUI)    │  │ General/Apps/ │  │  NSWindow-managed via │   │
│  │               │  │ Whitelist tabs│  │  AppDelegate          │   │
│  └───────────────┘  └───────────────┘  └───────────────────────┘   │
└────────────────────────────────────────────────────────────────────┘
```

### Service responsibilities

| Service | Responsibility |
|---|---|
| `AppEnvironment` | Owns all services. Single dependency container, injected as `@EnvironmentObject`. |
| `AppTracker` | Watches `NSWorkspace` for launch/terminate/hide/activate events. Maintains the tracked-app list. |
| `WindowMonitor` | One `AXObserver` per tracked app. Two-phase debounce determines true zero-window state. |
| `QuitEngine` | Decision layer. Consults `RuleStore`, applies grace periods, executes quit/hide/ignore/prompt. |
| `RuleStore` | Persistence layer. Per-app rules and whitelist, encoded to `UserDefaults` as JSON. |
| `AccessibilityManager` | Checks/requests Accessibility permission; polls since macOS gives no grant callback. |
| `GlobalSettings` | App-wide preferences via `@AppStorage`. |
| `LicenseManager` | Lemon Squeezy activation/validation, Keychain-backed license storage. |
| `TrialManager` | 7-day trial clock, stored in Keychain to resist casual reset. |
| `LoginItemService` | `SMAppService` login-item registration and system-state reconciliation. |

---

## How It Works

```
1.  User closes the last window of an app (e.g. Safari)
          │
          ▼
2.  macOS fires AXWindowClosed / AXUIElementDestroyed to Nix's AXObserver
          │
          ▼
3.  C callback bridges into WindowMonitor on the main run loop
          │
          ▼
4.  300ms debounce, then Phase 1: AX window count for that PID
          │
          ▼
5.  Count == 0 and app not hidden →
       known "hider" app or weak signal? → Phase 2 (500ms, cross-space CGWindowList check)
       otherwise                          → confirmed immediately
          │
          ▼
6.  WindowMonitor.onZeroWindows fires
          │
          ▼
7.  QuitEngine.evaluate(app:) — checks isEnabled/isPaused, looks up RuleStore
    behavior, applies grace period (cancellable via DispatchWorkItem)
          │
          ▼
8.  app.terminate() — sends Cmd+Q equivalent, app handles its own shutdown
          │
          ▼
9.  NSWorkspace fires didTerminateApplicationNotification
          │
          ▼
10. AppTracker removes the app; WindowMonitor tears down its AXObserver
```

Entirely event-driven — no polling timers for window state. CPU usage at idle is effectively zero.

---

## Tech Stack

| Technology | Used For |
|---|---|
| Swift 6 | Primary language (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`) |
| SwiftUI | Menu bar, settings, onboarding, paywall |
| AppKit | `NSRunningApplication`, `NSWorkspace`, `NSWindow` management |
| ApplicationServices | `AXUIElement`, `AXObserver`, window accessibility tree |
| Combine | `NSWorkspace` publishers, reactive state, `objectWillChange` forwarding |
| UserDefaults + Codable | Per-app rule and settings persistence |
| Keychain (Security) | License key and trial start-date storage |
| ServiceManagement | `SMAppService` login item registration |
| Sparkle 2.9.3 | EdDSA-signed automatic updates |
| os.Logger | Structured logging, subsystem `com.sahan.Nix` |

---

## Requirements

- **macOS 14.6 Sonoma** or later
- Xcode 16+ (for building from source)
- Accessibility permission — required for window monitoring

### Accessibility Permission

Nix requires Accessibility access to observe window events in other applications — the same permission class used by screen readers and window managers.

1. Launch Nix and follow the onboarding prompt, **or**
2. Open **System Settings → Privacy & Security → Accessibility**
3. Enable the toggle next to **Nix**

Nix uses this permission **only** to receive window created/closed/destroyed notifications. It does not read window content, document text, or any application data — the AX tree is queried in structural, read-only mode.

---

## Building from Source

```bash
git clone https://github.com/sahanmaiti/Nix.git
cd Nix
open Nix.xcodeproj
```

1. Select the **Nix** scheme, choose **My Mac**, press **Cmd+R**
2. The app launches without a Dock icon (`.accessory` activation policy) — look for the menu bar icon
3. macOS will prompt for Accessibility permission on first run
4. Console.app, filter by subsystem `com.sahan.Nix`, for logs

Debug builds run an internal verification suite (`Core/CoreTests.swift`) ~1.5s after launch, logging pass/fail checks for every subsystem.

### Code signing & distribution

- Team ID: `X7MF3C43X6`, bundle ID: `com.sahan.Nix`
- Not sandboxed (`ENABLE_APP_SANDBOX = NO`) — required for Accessibility API access
- Distribution build: Developer ID Application cert → `xcodebuild archive` → export → `hdiutil` DMG → `xcrun notarytool` notarize → staple

### Project structure

```
Nix/
├── App/
│   ├── NixApp.swift              # @main entry point, MenuBarExtra scene
│   └── AppDelegate.swift         # NSWindow management, Sparkle, license/paywall gating
├── Core/
│   ├── AppEnvironment.swift      # Dependency container, service wiring
│   ├── AppTracker.swift          # NSWorkspace observers, tracked app list
│   ├── WindowMonitor.swift       # AXObserver management, two-phase zero-window detection
│   ├── QuitEngine.swift          # Decision engine: quit/hide/ignore/prompt
│   ├── AccessibilityManager.swift
│   └── CoreTests.swift           # #if DEBUG verification suite
├── RuleEngine/
│   ├── RuleStore.swift           # UserDefaults persistence, per-app rules
│   ├── AppRule.swift             # Rule data model
│   └── GlobalSettings.swift      # @AppStorage global preferences
├── Services/
│   ├── LicenseManager.swift      # Lemon Squeezy activation/validation
│   ├── TrialManager.swift        # 7-day trial clock (Keychain-backed)
│   ├── KeychainHelper.swift
│   ├── LoginItemService.swift    # SMAppService registration
│   └── NotificationService.swift
└── UI/
    ├── MenuBarView.swift
    ├── SettingsView.swift / GeneralTab.swift / AppsTab.swift / WhitelistTab.swift
    ├── OnboardingView.swift
    ├── PaywallView.swift
    └── VisualEffectView.swift
```

---

## Privacy

| Data | Collected? |
|---|---|
| App names / bundle IDs | No — held in memory only while running |
| Window contents / document text | No |
| Screen recording | No |
| Usage analytics / telemetry | No |
| Crash reports | No (manual reporting only) |
| Network requests | Yes — license activation/validation against Lemon Squeezy, and Sparkle update checks against a static appcast |

Nix contacts the network only for **license activation/validation** (Lemon Squeezy) and **update checks** (Sparkle, static appcast — no telemetry payload). No app usage, window, or document data is ever transmitted.

**Accessibility permission** is used exclusively to receive AX window lifecycle notifications. Nix never reads the content of any window, field, or document — the Accessibility API is used in read-only, structural mode: it sees that a window *exists*, not what's *inside* it.

Per-app rules and settings are stored locally in `UserDefaults` (`~/Library/Preferences/com.sahan.Nix.plist`). License and trial state are stored in the Keychain. Nothing else leaves your machine.

---

## Known Limitations

**Apps that override window close**
Some apps (Discord, Slack, Mimestream, Teams, Zoom) intercept the close button and hide themselves rather than closing the window. Nix's Phase 2 check accounts for this — these apps are effectively self-whitelisting via their `isHidden` state.

**Minimized windows are not "closed"**
A window minimized to the Dock still exists and is excluded from the zero-window count. This matches macOS semantics.

**App Store sandbox**
Nix cannot be distributed on the Mac App Store. The Accessibility API (`AXUIElement`) requires a non-sandboxed process — a known, intentional constraint shared by every system utility in this category. Nix ships as a direct, notarized DMG instead.

**Electron app variance**
Electron apps expose accessibility trees inconsistently. Most work correctly; a few with non-standard window management may not report close events reliably. Add them to your whitelist if behavior is unexpected.

---

## Roadmap

### Shipped
- [x] AXObserver-based window monitoring with two-phase confirmation
- [x] NSWorkspace app lifecycle tracking
- [x] QuitEngine with grace periods
- [x] Per-app behavior rules + whitelist UI
- [x] First-launch onboarding
- [x] SMAppService login item
- [x] Pause mode
- [x] Sparkle auto-update integration
- [x] 7-day trial + Lemon Squeezy licensing (paywall, manual key entry)
- [x] Notarized DMG distribution pipeline

### Next
- [ ] Grace period countdown visible in menu bar popover
- [ ] "Recently quit" history in popover
- [ ] Per-app grace period overrides in Settings UI
- [ ] Homebrew Cask

### Later
- [ ] Smart recommendations ("You always reopen X — want to ignore it?")
- [ ] Battery-aware quitting
- [ ] Time-based rules
- [ ] iCloud sync for rules across Macs

---

## Contributing

Contributions are welcome, especially edge-case fixes for apps with unusual window behavior, macOS version testing, and documentation. Open an issue before a large PR.

**Code style:** `os.Logger` for all logging, no force-unwraps, `guard let` for early exits, `[weak self]` in stored closures, full-file diffs preferred for multi-part changes.

---

## License

Source is MIT-licensed — see [LICENSE](LICENSE). The compiled app is a paid product ($9.99, one-time); the license covers the source code, not a right to redistribute paid builds.

---

<div align="center">

<br>

Built on a Mac, for Mac.

*Nix — v1.0 — macOS 14.6+*

</div>
