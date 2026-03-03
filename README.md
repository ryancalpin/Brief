# Brief

**Voice-first AI assistant that automatically manages your lists, notes, reminders, and calendar events.**

Just speak. Brief understands natural language and instantly sends items to the right place — Apple Reminders, Notes, or Calendar — using on-device AI or your preferred cloud API.

---

## Features

| Feature | Details |
|---------|---------|
| **Push-to-talk** | Hold the mic button (or Action Button on iPhone 15 Pro+) to record |
| **AI Parsing** | Apple Intelligence (on-device, iOS 26+) or BYOK (OpenAI / Anthropic) |
| **Apple Reminders** | Auto-creates reminders with due dates, priorities, and alarms |
| **Apple Calendar** | Schedules events with locations and 15-min alerts |
| **Apple Notes** | Opens Notes pre-filled or exports via share sheet |
| **Dynamic Island** | Live Activity shows recording state and live transcript |
| **Widgets** | Recent items, Quick Record button, and Stats (all sizes) |
| **Shortcuts** | Full AppIntents integration — "Hey Siri, add a reminder in Brief" |
| **Action Button** | iPhone 15 Pro+ Action Button triggers instant recording |
| **Apple Watch** | Standalone dictation from wrist, item list, complications |
| **iCloud Sync** | SwiftData + CloudKit syncs items across all your devices |

---

## Requirements

- **iOS 18.0+** (iOS 26+ for Apple Intelligence / Foundation Models)
- **watchOS 11.0+** for Watch app
- **Xcode 16.0+**
- **Apple Developer account** (for App Groups, CloudKit, Siri entitlements)

---

## Getting Started

### 1. Install XcodeGen

```bash
brew install xcodegen
```

### 2. Generate the Xcode project

```bash
cd Brief
xcodegen generate
```

This creates `Brief.xcodeproj` with all three targets pre-configured.

### 3. Configure your Team & Bundle IDs

Open `Brief.xcodeproj` → each target → **Signing & Capabilities**:

| Target | Bundle ID to set |
|--------|-----------------|
| Brief (iOS) | `com.brief.app` → replace with your own |
| BriefWidget | `com.brief.app.widget` |
| BriefWatch | `com.brief.watchapp` |

Update the App Group identifier in `Shared/AppGroupConstants.swift`:
```swift
static let identifier = "group.YOUR_TEAM.brief.app"
```

### 4. Enable Capabilities in Xcode

For the **Brief** target:
- ✅ App Groups → add `group.YOUR_TEAM.brief.app`
- ✅ iCloud → CloudKit → container `iCloud.com.brief.app`
- ✅ Siri
- ✅ Background Modes → Audio, Background processing

For **BriefWidget** and **BriefWatch**:
- ✅ App Groups → same identifier as above

### 5. Build & Run

Select the **Brief** scheme and run on a real device (microphone, Speech framework, and Live Activities require a physical device).

---

## Architecture

```
Brief/
├── Shared/                    # Code shared across all targets
│   ├── AppGroupConstants.swift    # App Group ID, UserDefaults keys
│   └── SharedDefaults.swift       # Typed App Group wrapper
│
├── Brief/                     # iOS App target
│   ├── BriefApp.swift             # App entry point
│   ├── Models/
│   │   ├── BriefItem.swift        # SwiftData @Model
│   │   └── AIParseResult.swift    # AI response model + system prompt
│   ├── Services/
│   │   ├── VoiceRecordingService  # Speech + AVFoundation
│   │   ├── AIParsingService       # Provider orchestration
│   │   ├── AppleIntelligenceService # Foundation Models (iOS 26+)
│   │   ├── BYOKService            # OpenAI + Anthropic + rule-based
│   │   ├── EventKitService        # Reminders + Calendar
│   │   ├── NotesExportService     # Apple Notes URL scheme
│   │   └── WatchConnectivityService # iPhone ↔ Watch
│   ├── ViewModels/
│   │   ├── RecordingViewModel     # Record → parse → save flow
│   │   ├── HomeViewModel          # List filtering/sorting/grouping
│   │   └── SettingsViewModel      # Settings persistence (singleton)
│   ├── Views/
│   │   ├── HomeView               # Main list
│   │   ├── RecordingView          # Push-to-talk + waveform
│   │   ├── ItemDetailView         # Item detail + edit
│   │   ├── SettingsView           # AI keys, permissions, defaults
│   │   └── OnboardingView         # First-launch permission flow
│   ├── AppIntents/
│   │   ├── RecordBriefIntent      # Action Button / Siri
│   │   └── BriefShortcutsProvider # Siri Shortcuts app phrases
│   └── LiveActivity/
│       └── RecordingActivityAttributes # Dynamic Island
│
├── BriefWidget/               # Widget Extension
│   ├── RecentItemsWidget      # Small/Medium/Large list widget
│   └── QuickRecordWidget      # Tap-to-record + Stats widget
│
└── BriefWatch/                # watchOS App
    ├── WatchViewModel         # Record → send to iPhone flow
    ├── Views/
    │   ├── WatchRecordingView # Push-to-talk on Watch
    │   └── WatchItemListView  # Recent items list
    ├── Services/
    │   ├── WatchVoiceService  # On-Watch speech recognition
    │   └── WatchConnectivityHandler # WatchConnectivity delegate
    └── Complications/
        └── BriefComplication  # WidgetKit complications
```

---

## AI Configuration

### Apple Intelligence (Default, iOS 26+)

No setup required. Uses the on-device Foundation Models framework. Requires:
- Device with Apple Intelligence support (iPhone 15 Pro and later, or any iPhone 16+)
- Apple Intelligence enabled in **Settings → Apple Intelligence & Siri**

### OpenAI (BYOK)

1. Get an API key at [platform.openai.com](https://platform.openai.com)
2. Open Brief → Settings → API Keys → Add OpenAI Key
3. Enter your `sk-...` key

Recommended model: `gpt-4o-mini` (fast, inexpensive)

### Anthropic (BYOK)

1. Get an API key at [console.anthropic.com](https://console.anthropic.com)
2. Open Brief → Settings → API Keys → Add Anthropic Key
3. Enter your `sk-ant-...` key

Default model: `claude-haiku-4-5-20251001` (fast, inexpensive)

### Offline / Rule-Based

No AI required. Brief uses pattern matching to classify basic phrases like "remind me to…", "note that…", "schedule a meeting…". Works without internet or Apple Intelligence.

---

## Voice Examples

| What you say | What Brief creates |
|-------------|-------------------|
| "Remind me to call the dentist tomorrow at 2pm" | Reminder → Apple Reminders, due tomorrow 2pm |
| "Note that the WiFi password is Brief123" | Note → Apple Notes |
| "Schedule a team standup meeting every Monday at 9am" | Calendar event → Apple Calendar |
| "Shopping list: milk, eggs, bread, coffee" | List → Apple Reminders |
| "Add dentist appointment on March 15th at 10am at the office on 5th Ave" | Calendar event with location |
| "Urgent: call the client back ASAP" | High-priority reminder |

---

## Action Button Setup (iPhone 15 Pro+)

1. Go to **Settings → Action Button**
2. Select **Shortcuts**
3. Choose the **"Record Voice Note"** shortcut (Brief installs it automatically)

The Action Button will immediately open Brief in recording mode.

---

## Widget Setup

1. Long-press your Home Screen or Lock Screen
2. Tap **+** → search for **Brief**
3. Choose a widget:
   - **Recent Items** (Small/Medium/Large) — latest captures
   - **Quick Record** (Small/Circular) — one-tap recording
   - **Brief Stats** (Small) — today's count and completions

---

## Apple Watch

The Watch app works **standalone** — no iPhone nearby required for dictation.

1. Open Brief on your Apple Watch
2. Swipe to the **Record** tab
3. Tap the purple mic button and speak
4. Brief sends the transcript to your iPhone for AI processing
5. The result appears on both Watch and iPhone

**Complications:** Add Brief to your watch face from the Watch app → Complications.

---

## Privacy

- **On-device first**: Speech recognition uses Apple's on-device engines when available
- **Foundation Models**: Apple Intelligence processing never leaves your device
- **BYOK**: Your transcript is sent to OpenAI/Anthropic only when you configure those keys
- **No telemetry**: Brief collects no analytics or usage data
- **API keys**: Stored in App Group UserDefaults on-device (production: use Keychain)

> **Security note:** The sample stores API keys in UserDefaults for simplicity.
> For production, replace `saveAPIKeys()` in `SettingsViewModel.swift` with Keychain storage.

---

## Development

### Project structure

Generated by [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`.
**Do not commit `Brief.xcodeproj`** — it is in `.gitignore` and regenerated from `project.yml`.

### Branches

- `main` — stable releases
- `claude/ios-voice-list-app-EWtHi` — active development

### Dependencies

No third-party Swift packages required. All functionality uses Apple system frameworks:
`Speech`, `AVFoundation`, `EventKit`, `WidgetKit`, `ActivityKit`, `AppIntents`, `WatchConnectivity`, `SwiftData`, `Foundation`

---

## License

MIT License — see LICENSE file.
