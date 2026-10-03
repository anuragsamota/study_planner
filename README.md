# Study Planner

An AI-powered study planner for students. It plans study sessions for you automatically, reminds you
when it's time to study, tracks deadlines, and shows where you're strong or weak. An optional
**Ollama**-powered coach uses an **MCP server** to understand and change your plan.

The core app works **fully offline, with no AI**. Ollama and the MCP server add extra features on top.

```
┌───────────────────────── Flutter app (Android · iOS · Web · Windows · macOS · Linux) ─────────────────────────┐
│  Offline core (always on)                          │  AI layer (optional)                                     │
│  • automatic planner      • reminders              │  • AI coach chat          • learner profile + plan tuning │
│  • tasks & deadlines      • focus timer            │  • "describe your task" quick add                         │
│  • analytics & tips       • local storage          │                                                           │
└──────────────────────────────────────┬─────────────┴───────────────┬─────────────────────────────────────────┘
                                       │ MCP (Streamable HTTP)       │ Ollama REST API
                                       ▼                             ▼
                     ┌──────────────────────────────┐   ┌──────────────────────────────────┐
                     │ Study Planner MCP server     │   │ Ollama                           │
                     │ (Python) – 14 planner tools, │   │ • this device  (localhost)       │
                     │ resources, prompts, sync     │   │ • LAN          (192.168.x.x)     │
                     └──────────────────────────────┘   │ • Ollama Cloud (ollama.com)      │
                          ▲  also usable from Claude     │ • self-hosted / custom URL       │
                          │  Desktop, IDEs, … (stdio)    └──────────────────────────────────┘
```

## Features

**Always available (no AI needed)**
- **Automatic planning.** Add your subjects, deadlines and free time, and the planner builds a 7-day schedule.
  It rebuilds the schedule whenever something changes (a new task, a finished or skipped session, a new day).
  It schedules urgent, high-priority work first and gives weak or difficult subjects and upcoming exams more
  time. It mixes subjects within a day, keeps every session inside your free time, and never goes over your
  daily cap. Every planned session shows *why* it was scheduled ("Assignment due in 2 days · high priority",
  "Weak area – extra practice"). If a task won't fit before its deadline, you get a warning.
- **Reminders.** You get a reminder before each session, one day and 3 hours before each deadline, and a
  morning summary of the day's plan. On Android, iOS, macOS and Windows these are system notifications that
  arrive even when the app is closed. On web and Linux they show while the app is open.
- **Tasks and deadlines.** Track assignments, projects, exams, reading and revision with a priority, an
  estimated time, progress and an overdue view.
- **Focus timer.** Start a session, then rate your focus when you finish. Your study time counts toward the task.
- **Analytics.** See time studied per day and per subject, your streak, and how often you met your daily goal.
  Each subject gets a **strength score** (strong / average / weak) built from your test results, your own
  rating, how many sessions you completed and your focus. The app also shows your best time of day to study,
  plus rule-based tips.
- **Personal profile.** Set your study goal, session length, breaks, preferred time of day and weekly free time.
  Each subject has a difficulty, your confidence level, a weekly target and an optional exam date.
- **Intuitive, responsive UI.** Built with Material 3 and light/dark themes. Phones get a bottom navigation
  bar, tablets get a navigation rail and desktops get an extended rail with two-column layouts. Forms open as
  bottom sheets on phones and as dialogs on large screens. A three-step onboarding creates your first plan.

**With Ollama**
- **AI coach.** Ask "what should I study today?" or "how am I doing?". With only Ollama connected the coach
  can read your data. With the MCP server connected it can also **change your plan**: add tasks, update
  deadlines, log study, re-plan and record scores.
- **Learner profile.** The AI writes a short personal profile of your strengths, weak areas and habits, and
  sets how much time the planner gives each subject.
- **Quick add.** Type "physics lab report due next Friday, about 3 hours, important" and the AI turns it into a task.

## Quick start

### 1. Run the app

Requires [Flutter](https://docs.flutter.dev/get-started/install) 3.47+ (Dart 3.13+).

```bash
cd app
flutter pub get
flutter run            # choose Android / iOS / Chrome / Windows / macOS / Linux
```

That's enough to use the planner, reminders and analytics.

### 2. (Optional) Connect Ollama

Install [Ollama](https://ollama.com) and pull a model that supports **tool calling**:

```bash
ollama pull llama3.2      # small and fast; qwen3, gpt-oss and llama3.1 also work well
```

In the app, open **Settings → AI (Ollama)**, choose where Ollama runs, then tap **Save & test connection**:

| Mode | URL | Notes |
|---|---|---|
| **This device** | `http://localhost:11434` | Desktop apps. On the Android emulator use `http://10.0.2.2:11434`. |
| **Local network (LAN)** | `http://192.168.1.10:11434` | Start Ollama with `OLLAMA_HOST=0.0.0.0 ollama serve` on that computer. Phones use this mode. |
| **Ollama Cloud** | `https://ollama.com` | Create an API key at ollama.com/settings/keys and pick a cloud model such as `gpt-oss:20b`. |
| **Custom / self-hosted** | any URL | For example your own Ollama behind HTTPS. Any API key is sent as `Authorization: Bearer …`. |

After a successful test, the model field lists the models that server has available.

> **Web build:** browsers block cross-origin calls unless Ollama allows them. Start it with
> `OLLAMA_ORIGINS="*"` (or your site's origin).

### 3. (Optional) Run the MCP server

The server needs Python 3.10+.

```bash
cd server
pip install -e .
python -m study_planner_mcp                  # http://0.0.0.0:8765/mcp  (+ /health)
```

In the app, open **Settings → AI → Connect the planner MCP server** and enter `http://<host>:8765/mcp`. If you
set a token on the server, enter it too. The coach then works in **agent mode** and can call the planner's tools.

| Environment variable | Default | Purpose |
|---|---|---|
| `PLANNER_API_TOKEN` | *(none)* | Bearer token the server requires. **Set this whenever the server is reachable from a network.** |
| `PLANNER_DATA_DIR` | `./data` | Where student documents are stored (one JSON file per student). |
| `PLANNER_HOST` / `PLANNER_PORT` | `0.0.0.0` / `8765` | Address the server listens on. |
| `PLANNER_CORS_ORIGINS` | `*` | Browser origins allowed to connect (for the web build). |
| `PLANNER_TRANSPORT` | `http` | Set to `stdio` for desktop MCP hosts. |

## Deployment options

| Setup | How |
|---|---|
| **Everything on one computer** | Run `ollama serve` and `python -m study_planner_mcp`. In the app, use `localhost` for both URLs. |
| **Home server on the LAN** | Run `docker compose up -d` on the server (see below). Phones and laptops connect to `http://<server-ip>:11434` and `http://<server-ip>:8765/mcp`. |
| **Cloud VM** | Run the same `docker compose` stack behind a reverse proxy with HTTPS (Caddy or nginx), and always set `PLANNER_API_TOKEN`. |
| **Ollama Cloud plus your own MCP server** | Choose "Ollama Cloud" in the app and point the MCP URL at your server. The server does not call Ollama itself, so it needs no GPU. |

```bash
cp .env.example .env            # set PLANNER_API_TOKEN
docker compose up -d
docker compose exec ollama ollama pull llama3.2
```

### Use the MCP server from Claude Desktop (or any MCP host)

```json
{
  "mcpServers": {
    "study-planner": {
      "command": "python",
      "args": ["-m", "study_planner_mcp", "--transport", "stdio", "--data-dir", "/path/to/data"],
      "cwd": "/path/to/study_planner/server"
    }
  }
}
```

stdio clients work on the `default` student. The app uses its own student ID, shown in Settings, which keeps
each student's data separate on a shared server.

## MCP server reference

**Tools:** `get_overview`, `list_subjects`, `list_tasks`, `get_schedule`, `get_analytics`, `add_subject`,
`update_subject`, `add_task`, `update_task`, `auto_plan`, `schedule_session`, `log_study_session`,
`record_score`, `update_preferences`, plus `sync_push` / `sync_pull`, which the app uses internally and
hides from the model.

**Resources:** `planner://{student_id}/document`, `planner://{student_id}/analytics`.
**Prompts:** `weekly_review`, `plan_my_day`.

### How syncing works

The app always keeps its data on the device, so it never depends on the server. When the MCP server is
connected, the app sends its document with `sync_push` and records when it last synced. If someone else
changed the server copy since then (for example Claude Desktop added a task), the server merges the two
copies by item ID. On a conflict the app's version wins, and items deleted in the app stay deleted.
After each coach turn the app downloads the server's copy with `sync_pull`, so changes made by the coach
show up right away.

## Project layout

```
app/                       Flutter app (see app/README.md for a code map)
server/
  study_planner_mcp/
    model.py               Shared document model (same JSON shape as the app)
    planner.py             Automatic planner     ┐ identical algorithms to the
    analytics.py           Analytics & tips      ┘ Dart versions in app/lib/services
    server.py              MCP tools / resources / prompts
    http_app.py            Streamable HTTP + /health + CORS + bearer auth
  tests/                   pytest suite, fake Ollama, parity-fixture generator
docker-compose.yml         Ollama + MCP server
```

## Testing

```bash
cd server && pip install -e ".[dev]" && pytest          # planner, analytics, tools, HTTP/JSON-RPC, auth
cd app && flutter analyze && flutter test               # unit, AI agent loop (mocked), widgets on 3 screen sizes
```

The planner and analytics exist in both Python (on the server) and Dart (offline in the app).
`app/test/parity_test.dart` checks that both produce **exactly** the same schedule and scores for a realistic
fixture. If you change either algorithm, regenerate the fixture with `python server/tests/make_parity_fixture.py`.

End-to-end check over real HTTP, using a scripted fake Ollama so no GPU is needed:

```bash
cd server && python -m study_planner_mcp --port 8765 --data-dir /tmp/e2e &
cd server && python tests/fake_ollama.py --port 11500 &
cd app && E2E_MCP_URL=http://127.0.0.1:8765/mcp E2E_OLLAMA_URL=http://127.0.0.1:11500 flutter test test/e2e_mcp_test.dart
```

Set `E2E_OLLAMA_URL` to a real Ollama (and `E2E_MODEL` to a model you have) to test against a real model.

## Privacy and security notes
- All data stays on the device unless you connect a remote Ollama or an MCP server.
- API keys and tokens are saved in the app's local preferences. They are not encrypted, so treat the device as trusted.
- Plain-HTTP connections are allowed so that Ollama on your LAN works. Use HTTPS for anything that goes over the internet.
