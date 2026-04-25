# Code Walkthrough

## Architecture Overview

The app is split into two processes that communicate over **stdin/stdout as newline-delimited JSON**:

- **Haskell backend** — handles all business logic, state, and SQLite persistence
- **Qt/QML frontend** — spawns the Haskell process and communicates with it via the `Backend` bridge class

---

## Haskell Backend

### `haskell/app/Main.hs` — Entry Point

The Haskell process entry point. Communication with Qt happens entirely over stdin/stdout as newline-delimited JSON.

**Startup sequence:**
1. `hSetBuffering stdout LineBuffering` — flushes each response immediately, critical for IPC
2. Opens/creates SQLite DB at the XDG platform data directory (`~/.local/share/haskell-qt/todos.db` on Linux)
3. `initDB` — creates table and seeds if empty
4. `loadTodos` — reads all rows into memory
5. `newTVarIO` — wraps in-memory state in an STM `TVar` (shared mutable state, thread-safe)
6. `newTQueueIO` — creates a thread-safe queue for outgoing responses

**Two concurrent threads:**
- **Writer thread** — sits in a `forever` loop, reads responses off `responseQ`, encodes as JSON, writes to stdout. All output goes through this single thread to avoid interleaved writes.
- **Reader loop** — main thread reads one line at a time from stdin. Each line is decoded as JSON. On success, spawns a new `forkIO` per request and pushes the response onto `responseQ`. On EOF (Qt closed the pipe), closes the DB and exits cleanly.

Each request gets its own thread so slow operations don't block others.

---

### `haskell/src/State.hs` — App State

Defines the shape of the entire in-memory state held in the `TVar`.

```haskell
data AppState = AppState
  { todos      :: IntMap Todo  -- all todos keyed by ID
  , todosVer   :: Int          -- version counter, incremented on every mutation
  , todoSort   :: SortOrder    -- Asc | Desc
  , todoFilter :: String       -- current search string
  }
```

- `IntMap Todo` — like `Map Int` but optimised for integer keys
- `todosVer` — Qt uses this to detect when re-rendering is needed
- Sort and filter state are memory-only — not persisted to DB, reset on restart

---

### `haskell/src/DB.hs` — Database Layer

Thin wrapper over `sqlite-simple`. Five focused functions:

- **`initDB`** — `CREATE TABLE IF NOT EXISTS` (idempotent), seeds 3 default todos if table is empty
- **`loadTodos`** — reads all rows into an `IntMap`, converts integer `done` column to `Bool` via `d /= 0`
- **`insertTodo`** — inserts a row, calls `lastInsertRowId` to get the auto-incremented ID SQLite assigned
- **`deleteTodoDB`** — `DELETE WHERE id = ?`
- **`updateTodoDone`** — `UPDATE SET done = ?`, booleans stored as `1`/`0` (SQLite has no native boolean)

There is no `updateTitle` — title editing is not currently supported.

---

### `haskell/src/Handler.hs` — Request Router

Defines the IPC contract between Qt and Haskell.

**`Request`** — every message from Qt has two fields:
- `action` — command name e.g. `"addTodo"`
- `input` — optional string payload e.g. todo title or ID

**`Response`** — every reply to Qt has:
- `result` — arbitrary JSON (todo list or error string)
- `action` — echoes the action name so Qt knows which request this answers
- `ver` — the `todosVer` counter so Qt knows if state changed

`handleRequest` is a pattern match on `action` that dispatches to `Todo.Todo`. Unknown actions return a JSON error string rather than crashing.

Note: `readInt` uses `read` to parse IDs from strings — fragile if Qt sends a non-numeric value.

---

### `haskell/src/Types/Todo.hs` — Todo Type

A plain data type with no logic — just the shape:

```haskell
data Todo = Todo
  { todoId :: Int
  , title  :: T.Text
  , done   :: Bool
  }
```

Separated from business logic to avoid circular imports. `deriving Generic` + `FromJSON`/`ToJSON` instances give automatic JSON serialisation with field names matching exactly what Qt expects.

---

### `haskell/src/Todo/Todo.hs` — Business Logic

All mutations go through here. The key design is **DB-first vs STM-first ordering**:

- **`addTodo`** — DB first, because SQLite's `AUTOINCREMENT` generates the ID. The todo can't be inserted into the `IntMap` without knowing its key.
- **`deleteTodo`** — STM first, update UI immediately then clean up DB.
- **`toggleTodo`** — STM first, captures new `done` value inside `atomically` and passes it out to `updateTodoDone`.

**`applyView`** is a pure function called at the end of every operation that returns the todo list as Qt should see it — filtered (case-insensitive substring) and sorted. All operations return this view so the response always reflects current state.

`sortAscending`, `sortDescending`, and `setFilter` only update the `TVar` — no DB writes. All three bump `todosVer` so Qt knows to re-render even though the underlying data hasn't changed.

---

### `haskell/src/Logger.hs` — Logging

Three wrappers around `hPutStrLn stderr`. Writes to **stderr not stdout** — stdout is reserved for IPC JSON. Qt captures stderr from the Haskell process and routes it to `app.log`.

Currently defined but not imported anywhere — ready to use but not yet called.

---

### `haskell/src/Counter/Counter.hs` — Counter Feature (Dead Code)

Leftover from an earlier version of the app. References `counter` and `counterVer` fields that no longer exist on `AppState` — would cause a compile error if imported. Not imported anywhere. Can be deleted or properly wired up if a counter feature is wanted.

---

## Qt/C++ Side

### `cpp/main.cpp` — Qt Entry Point

1. Creates `QGuiApplication` (required before any Qt facilities)
2. Sets `applicationName("haskell-qt")` so `QStandardPaths` resolves to the correct XDG directory
3. Sets up `app.log` at `~/.local/share/haskell-qt/app.log` — all `qDebug`/`qWarning`/QML `console.log` output is routed here via a custom message handler
4. Finds `haskell-backend` binary next to the Qt executable — fails fast if not found
5. Creates `Backend` object and exposes it to QML as `backend` via `setContextProperty`
6. Loads `Main.qml` from disk (path set by CMake's `QML_DIR` macro)
7. Enters the Qt event loop

---

### `cpp/backend.h` / `cpp/backend.cpp` — Qt↔Haskell Bridge

The entire IPC layer. `Backend` is a `QObject` that owns the Haskell `QProcess` and exposes a reactive interface to QML.

**Key members:**
- `Q_PROPERTY(QVariantMap state ...)` — exposes `m_state` to QML as a reactive property; when `stateChanged()` is emitted QML bindings automatically re-evaluate
- `Q_INVOKABLE` methods — callable directly from QML e.g. `backend.addTodo("Buy milk")`
- `m_versions: QHash<QString, int>` — tracks last seen version per action to guard against out-of-order responses

**Constructor:** Initialises `m_state` with empty defaults, creates `QProcess`, connects three signals:
- stdout → `onReadyRead` — handles JSON responses
- stderr → forwards Haskell log output to Qt's logger (ends up in `app.log`)
- started → calls `fetchTodos()` immediately to populate the UI

**Destructor:** Graceful shutdown — closes the write channel (sends EOF to Haskell's stdin, triggering `close conn`), waits up to 3 seconds, force-kills if needed.

**`sendRequest`:** Serialises a `QJsonObject` to compact JSON, appends `\n`, writes to process stdin. The newline is the delimiter Haskell reads with `hGetLine`.

**`onReadyRead`:** Reads all available complete lines in a loop. Parses each as JSON. For mutation actions, checks `ver > m_versions["todos"]` before updating state — this is the **out-of-order guard**. Since each Haskell request runs in its own thread, responses can arrive out of order; the version number ensures a stale slow response doesn't overwrite newer state. `emit stateChanged()` triggers QML re-render.

---

## QML Frontend

### `qml/Main.qml` — UI

Contains the QML UI code. Binds to `backend.state` for reactive data and calls `backend.*` methods in response to user interactions.
