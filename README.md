<div align="center">

# Nix

**Close the window. Quit the app.**

Nix is a lightweight macOS menu bar utility that automatically quits applications when their last window is closed — bringing Windows-style app lifecycle behavior to macOS, natively.

<br>

![macOS](https://img.shields.io/badge/macOS-14.6%2B-black?style=flat-square&logo=apple)
![Swift](https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift)
![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)
![Status](https://img.shields.io/badge/status-active%20development-green?style=flat-square)
![Architecture](https://img.shields.io/badge/architecture-event--driven-purple?style=flat-square)

<br>

</div>

---

## What is Nix?

On macOS, closing a window doesn't quit the app. It never has. Safari, Notes, Preview — close every window and the process keeps running, quietly consuming memory and CPU in the background. For users coming from Windows, this is immediately confusing. For power users who know what's happening, it's a constant source of manual cleanup.

This is a deliberate design decision by Apple: apps are expected to persist between uses, reopening instantly when called. For some apps — Music, Messages, system utilities — that makes perfect sense. For most others, it's just waste.

**Nix changes that.** When you close the last window of an app, Nix detects it and terminates the process cleanly — exactly as if you'd pressed `Cmd+Q`. The app handles its own shutdown (saving state, showing unsaved-changes dialogs), so nothing is forced or unsafe. You just get a Mac that behaves the way you expect.

Per-app rules mean Nix only does this where you want it to. Music keeps playing. Finder stays put. Discord hides like it always does. Everything else quits when you're done with it.

---

## Features

**Core behavior**
- Automatically quits apps when their last window closes
- Configurable grace period (0–30s) before terminating — reopen a window to cancel
- Four per-app behaviors: **Quit**, **Hide**, **Ignore**, or **Prompt**
- Default behavior applies globally; override per-app as needed

**Smart detection**
- Powered by macOS Accessibility API (`AXUIElement`) — event-driven, not polling
- Correctly distinguishes closed windows from minimized, hidden, or sheet windows
- Hidden apps (`Cmd+H`) are intentionally ignored — never quits what you've hidden
- Handles multi-window apps: only acts when the *last* real window closes

**Whitelist & rules**
- Built-in permanent whitelist: Finder, Dock, system processes — never touched
- User-managed whitelist: add any app you want Nix to ignore
- Per-app rule editor in Settings with search, sorted app list, and instant changes
- Rules persist across restarts via UserDefaults

**System integration**
- Launch at login via `SMAppService` (macOS 13+ native API)
- Optional system notifications when an app is quit
- Menu bar icon reflects current state: active, paused, or disabled
- Pause monitoring for 30 minutes, 2 hours, or until tomorrow

**Design**
- Native SwiftUI + AppKit hybrid — no Electron, no web views, no third-party UI frameworks
- Follows Apple's Human Interface Guidelines throughout
- Menu bar popover with live app list and one-click controls
- Tab-based Settings window: General, Apps, Whitelist

**Performance**
- Near-zero CPU usage at idle — AXObserver is event-driven
- Minimal memory footprint
- No background network requests, ever

---

## Demo

> *Screenshots and screen recordings coming in v1.0 release.*

<!-- Menu bar popover -->
<img src="docs/assets/menubar-popover.png" alt="Nix menu bar popover" width="280" />

<!-- Settings window — General tab -->
<img src="docs/assets/settings-general.png" alt="General settings tab" width="520" />

<!-- Settings window — Apps tab -->
<img src="docs/assets/settings-apps.png" alt="Per-app rules editor" width="520" />

<!-- Onboarding flow -->
<img src="docs/assets/onboarding.gif" alt="First-launch onboarding" width="480" />

---

## Why Nix?

Existing solutions in this space — RedQuits, Swift Quit — solve the basic problem. Nix is different in a few specific ways:

| | Nix | RedQuits | Swift Quit |
|---|:---:|:---:|:---:|
| Per-app behavior rules | ✅ | ❌ | ❌ |
| Grace period with cancellation | ✅ | ❌ | ❌ |
| Hide instead of quit | ✅ | ❌ | ❌ |
| Prompt mode | ✅ | ❌ | ❌ |
| User-managed whitelist UI | ✅ | ❌ | ❌ |
| Native SwiftUI settings window | ✅ | ❌ | ❌ |
| SMAppService login items | ✅ | ❌ | ❌ |
| Active development | ✅ | ⚠️ | ❌ |

The rule engine is the key differentiator. Nix is built on the premise that a single global behavior is never the right answer — your Mac has dozens of different apps with different usage patterns, and a utility worth using should reflect that.

---

## Architecture

Nix is structured as a layered service architecture. Each layer has a single, clearly defined responsibility. Nothing crosses boundaries unnecessarily.

```
┌─────────────────────────────────────────────────────────────┐
│                       NixApp  (@main)                       │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │                 AppEnvironment  (shared)              │  │
│  │                                                       │  │
│  │  ┌──────────────┐        ┌─────────────────────────┐  │  │
│  │  │  AppTracker  │        │  AccessibilityManager   │  │  │
│  │  │              │        │                         │  │  │
│  │  │  NSWorkspace │        │  AXIsProcessTrusted()   │  │  │
│  │  │  Combine     │        │  permission polling     │  │  │
│  │  └──────┬───────┘        └─────────────────────────┘  │  │
│  │         │ startMonitoring(app:)                       │  │
│  │         ▼                                             │  │
│  │  ┌──────────────────────┐                             │  │
│  │  │    WindowMonitor     │                             │  │
│  │  │                      │                             │  │
│  │  │  AXObserver (per app)│                             │  │
│  │  │  C callback bridge   │                             │  │
│  │  │  debounce + check    │                             │  │
│  │  └──────────┬───────────┘                             │  │
│  │             │ onZeroWindows(app:)                     │  │
│  │             ▼                                         │  │
│  │  ┌──────────────────────┐   ┌────────────────────┐    │  │
│  │  │     QuitEngine       │◄──│     RuleStore      │    │  │
│  │  │                      │   │                    │    │  │
│  │  │  evaluate(app:)      │   │  UserDefaults/JSON │    │  │
│  │  │  ├─ .quit            │   │  per-app rules     │    │  │
│  │  │  ├─ .hide            │   │  whitelist         │    │  │
│  │  │  ├─ .ignore          │   │  grace periods     │    │  │
│  │  │  └─ .prompt          │   └────────────────────┘    │  │
│  │  └──────────────────────┘                             │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                             │
│  ┌───────────────────┐   ┌──────────────────────────────┐   │
│  │   MenuBarView     │   │        SettingsView          │   │
│  │   (SwiftUI)       │   │  ├─ GeneralTab               │   │
│  │                   │   │  ├─ AppsTab                  │   │
│  │   @Environment    │   │  └─ WhitelistTab             │   │
│  │   Object          │   │        (SwiftUI)             │   │
│  └───────────────────┘   └──────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### Service responsibilities

| Service | Responsibility |
|---|---|
| `AppEnvironment` | Owns all services. Single dependency container. Injected as `@EnvironmentObject`. |
| `AppTracker` | Watches `NSWorkspace` for app launches and terminations. Maintains the live tracked-app list. |
| `WindowMonitor` | Creates and manages one `AXObserver` per tracked app. Fires when window count hits zero. |
| `QuitEngine` | Decision layer. Consults `RuleStore`, applies grace periods, executes quit/hide/ignore/prompt. |
| `RuleStore` | Persistence layer. Encodes per-app rules to UserDefaults as JSON. Source of truth for all behaviors. |
| `AccessibilityManager` | Checks and requests Accessibility permission. Polls for grant status since macOS provides no callback. |
| `GlobalSettings` | App-wide preferences via `@AppStorage`. Shared with engine via `didSet` sync. |

---

## How It Works

The full event flow from window close to process termination:

```
1.  User closes the last window of an app (e.g. Safari)
          │
          ▼
2.  macOS fires kAXWindowClosedNotification to Nix's AXObserver
          │
          ▼
3.  C-level callback reconstructs WindowMonitor via Unmanaged pointer
          │
          ▼
4.  150ms debounce fires on DispatchQueue.main
          │
          ▼
5.  visibleWindowCount(for: pid) queries kAXWindowsAttribute
          │   filters: minimized=false, subrole≠AXSheet/AXDialog
          ▼
6.  Count == 0 AND app.isHidden == false
          │
          ▼
7.  WindowMonitor.onZeroWindows?(app) fires
          │
          ▼
8.  QuitEngine.evaluate(app:)
          │   checks: isEnabled, isPaused, isTerminated, isHidden
          │   looks up: RuleStore.behavior(for: bundleID)
          │   applies: grace period via DispatchWorkItem (cancellable)
          ▼
9.  app.terminate()
          │   sends Cmd+Q equivalent — app handles its own shutdown
          ▼
10. NSWorkspace fires didTerminateApplicationNotification
          │
          ▼
11. AppTracker removes app from tracked list
    WindowMonitor removes AXObserver from run loop
```

The entire pipeline is event-driven. No timers poll for window state. CPU usage at idle is effectively zero.

---

## Tech Stack

| Technology | Used For |
|---|---|
| Swift 5.9+ | Primary language |
| SwiftUI | All UI: menu bar, settings, onboarding |
| AppKit | `NSRunningApplication`, `NSWorkspace`, `NSAlert` |
| ApplicationServices | `AXUIElement`, `AXObserver`, window accessibility tree |
| Combine | `NSWorkspace` notification publishers, reactive state |
| UserDefaults + Codable | Per-app rule and settings persistence |
| ServiceManagement | `SMAppService` login item registration |
| os.Logger | Structured logging, visible in Console.app |
| Foundation | `DispatchWorkItem`, timers, JSON encoding |

---

## Requirements

- **macOS 14.6 Sonoma** or later
- Xcode 15 or later (for building from source)
- Accessibility permission — required for window monitoring

### Accessibility Permission

Nix requires Accessibility access to observe window events in other applications. This is the same permission used by screen readers, window managers, and automation tools.

To grant permission:

1. Launch Nix
2. Click the menu bar icon → follow the permission prompt, **or**
3. Open **System Settings → Privacy & Security → Accessibility**
4. Enable the toggle next to **Nix**

Nix uses this permission **only** to receive `kAXWindowClosedNotification` events. It does not read window content, document text, or any application data. See [Privacy](#privacy) for full details.

---

## Installation

### Download (recommended)

> Release builds are distributed as a signed DMG.  
> Download link will appear here when v1.0 ships.

```
1. Download Nix-1.0.dmg
2. Open the DMG and drag Nix.app to /Applications
3. Launch Nix from /Applications or Spotlight
4. Follow the onboarding flow to grant Accessibility permission
```

### Homebrew Cask

> Coming after v1.0 release.

```bash
brew install --cask nix-app
```

---

## Building from Source

### Clone and open

```bash
git clone https://github.com/yourusername/nix.git
cd nix
open Nix.xcodeproj
```

### Run

1. Select the **Nix** scheme in Xcode
2. Choose **My Mac** as the run destination
3. Press **Cmd+R**

The app launches without a Dock icon. Look for the icon in your menu bar.

### First run notes

- macOS will prompt you to grant Accessibility permission the first time
- The app won't appear in the Dock — this is intentional (`.accessory` activation policy)
- To see logs, open **Console.app** and filter by subsystem: `com.sahan.Nix`

### Code signing

The project is configured for local development signing by default. For distribution builds:

1. Open project settings → **Signing & Capabilities**
2. Set your Apple Developer team
3. For direct distribution: use a **Developer ID Application** certificate
4. The app is intentionally **not sandboxed** — required for Accessibility API access

### Project structure

```
Nix/
├── App/
│   ├── NixApp.swift              # @main entry point, scene definitions
│   └── AppDelegate.swift         # NSApplicationDelegate, onboarding trigger
├── Core/
│   ├── AppTracker.swift          # NSWorkspace observers, tracked app list
│   ├── WindowMonitor.swift       # AXObserver management, zero-window detection
│   ├── QuitEngine.swift          # Decision engine: quit/hide/ignore/prompt
│   ├── AXWindowReader.swift      # Pure functions: window counting, AX queries
│   └── AccessibilityManager.swift
├── RuleEngine/
│   ├── RuleStore.swift           # UserDefaults persistence, per-app rules
│   ├── AppRule.swift             # Rule data model
│   ├── GlobalSettings.swift      # @AppStorage global preferences
│   └── AppEnvironment.swift      # Dependency container, service wiring
├── UI/
│   ├── MenuBarView.swift
│   ├── SettingsView.swift
│   ├── GeneralTab.swift
│   ├── AppsTab.swift
│   ├── WhitelistTab.swift
│   └── OnboardingView.swift
└── Services/
    ├── LoginItemService.swift    # SMAppService registration
    └── NotificationService.swift
```

---

## Roadmap

### v1.0 — MVP (current)
- [ ] AXObserver-based window monitoring
- [ ] NSWorkspace app lifecycle tracking
- [ ] QuitEngine with grace periods
- [ ] Per-app behavior rules
- [ ] UserDefaults persistence
- [ ] Settings window (General, Apps, Whitelist)
- [ ] First-launch onboarding
- [ ] SMAppService login item
- [ ] Pause mode

### v1.1 — Polish
- [ ] Sparkle auto-update integration
- [ ] Custom menu bar icon with template image support
- [ ] Grace period counter visible in menu bar popover
- [ ] "Recently quit" history in popover
- [ ] Keyboard shortcuts for common actions

### v1.2 — Intelligence
- [ ] Smart recommendations ("You always reopen X — want to ignore it?")
- [ ] Battery saver mode: more aggressive quitting on battery power
- [ ] Audio detection: skip quit if app is playing audio
- [ ] Per-app grace period overrides in Settings

### v2.0 — Advanced
- [ ] Time-based rules (e.g. "ignore VS Code after 6pm")
- [ ] iCloud sync for rules across Macs
- [ ] Automation hooks (Shortcuts app integration)
- [ ] Memory freed statistics and analytics
- [ ] Setapp distribution

---

## Privacy

Nix contacts Lemon Squeezy only to activate/validate a license key, with no telemetry, analytics, or app-usage data ever transmitted.

| Data | Collected? |
|---|---|
| App names / bundle IDs | No — only held in memory while running |
| Window contents | No |
| Document text | No |
| Screen recording | No |
| Usage analytics | No |
| Crash reports | No (manual reporting only) |
| Internet access | Yes — license activation/validation only |

**Accessibility permission** is used exclusively to receive `kAXWindowClosedNotification` events from `AXObserver`. Nix never reads the content of any window, field, document, or screen. The Accessibility API is used in read-only, structural mode — it sees that a window *exists*, not what's *inside* it.

Per-app rules are stored locally in `UserDefaults` (`~/Library/Preferences/com.sahan.Nix.plist`). Nothing leaves your machine.

---

## Known Limitations

**Apps that override window close**  
Some apps (Discord, Spark, Mimestream) intercept the close button and hide themselves rather than closing the window. Nix handles this correctly — when an app hides, its `isHidden` flag is checked before any quit decision is made. These apps are effectively self-whitelisting.

**Minimized windows are not "closed"**  
A window minimized to the Dock still exists. Nix does not treat minimize as close by default. This is intentional — it matches macOS semantics. A future setting will allow opt-in "treat minimize as close" behavior per app.

**App Store sandbox**  
Nix cannot be distributed on the Mac App Store. The Accessibility API (`AXUIElement`) requires a non-sandboxed process. This is a known, intentional constraint — all system utilities in this category share it.

**Electron app variance**  
Electron apps expose accessibility trees inconsistently. Most work correctly. Some (particularly those with non-standard window management) may not have their window close events properly observed. Add them to your whitelist if behavior is unexpected.

**Rapid window open/close**  
If an app opens and immediately closes a window during startup, the debounce timer (150ms) handles most cases. Some edge cases may trigger an incorrect zero-window evaluation that resolves on its own when the app stabilizes.

---

## Built for macOS

Nix is a native, first-class macOS application. No Catalyst. No Electron. No wrappers.

The UI is entirely SwiftUI with targeted AppKit integration where the platform requires it. The monitoring layer uses `ApplicationServices` — Apple's own framework for accessibility tooling. The login item uses `SMAppService`, the correct modern API introduced in macOS 13. Logging uses `os.Logger` for Console.app integration. Every API choice reflects how Apple themselves recommends building this category of app.

The result is an app that consumes negligible system resources, behaves predictably across macOS updates, and feels entirely at home in the environment it was built for.

---

## Systems-Level Learning Project

Nix is also a hands-on study in macOS systems engineering.

Building this app required going considerably deeper than typical app development: understanding how macOS processes communicate, how the Accessibility framework exposes other apps' UI as traversable trees, how C-level callback patterns bridge into Swift, how run loops deliver asynchronous events, and how system permissions are designed from a security model perspective.

The architecture is deliberately layered and explicit — `WindowMonitor` doesn't know about `RuleStore`, `QuitEngine` doesn't know about `AppTracker`, the UI knows nothing about AX APIs. This isn't over-engineering for a small utility; it's the practice of thinking in responsibilities, which is the skill that separates production code from prototype code.

If you're a developer learning macOS internals, the source code is meant to be readable. Every non-obvious decision has a comment explaining the *why*, not just the *what*. The roadmap document in `docs/ROADMAP.md` covers the full engineering reasoning behind the approach.

---

## Contributing

Nix is in active development. Contributions are welcome, especially:

- Edge case fixes for specific apps with unusual window behavior
- Testing on specific macOS versions
- UI feedback and design suggestions
- Documentation improvements

Please open an issue before submitting a large PR — it's worth a quick conversation first.

```bash
# Fork the repo, then:
git clone https://github.com/yourusername/nix.git
cd nix
git checkout -b feature/your-feature-name

# Make changes, then:
git commit -m "descriptive message"
git push origin feature/your-feature-name
# Open a pull request on GitHub
```

**Code style:** Swift standard formatting, `os.Logger` for all logging, no force-unwraps, `guard let` over `if let` for early exits, `[weak self]` in all stored closures.

---

## License

MIT License — see [LICENSE](LICENSE) for full text.

You're free to use, modify, and distribute this code. If you build something with it, a mention is appreciated but not required.

---

<div align="center">

<br>

Built on a Mac, for Mac.

*Nix — v0.9.0 — macOS 14.6+*

</div>
