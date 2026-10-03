# Study Planner – Flutter app

Cross-platform client (Android, iOS, web, Windows, macOS, Linux). See the
[project README](../README.md) for features, setup and architecture.

```bash
flutter pub get
flutter run                 # pick a device
flutter test                # unit, widget and Python-parity tests
flutter build web --release # or apk / appbundle / ios / windows / macos / linux
```

Code map:

| Path | What |
|---|---|
| `lib/models/` | Planner data (shared JSON shape with the server) and settings |
| `lib/services/planner.dart` | Offline automatic planner (mirrors `server/.../planner.py`) |
| `lib/services/analytics.dart` | Offline analytics, strengths/weaknesses, tips |
| `lib/services/reminders.dart` | Session/deadline/daily-digest notifications |
| `lib/services/ollama_client.dart` | Ollama REST client (local, LAN, cloud) |
| `lib/services/mcp_client.dart` | MCP client (Streamable HTTP, JSON-RPC) |
| `lib/services/ai_service.dart` | AI coach agent loop, learner profile, task parsing |
| `lib/state/app_state.dart` | App state: save → re-plan → reschedule reminders → sync |
| `lib/ui/` | Screens, sheets and responsive widgets |
