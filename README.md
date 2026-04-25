# haskell-qt-qml

A desktop todo app with a Qt/QML frontend and a Haskell backend, talking over
stdin/stdout JSON. The interesting part is not the todos but the
performance discipline running through every layer. Every decision in this
codebase was made with one of three questions in mind: how often does this
run, what allocates, and what blocks.



https://github.com/user-attachments/assets/76b3838c-e89d-4a92-89f9-c0723020eb2c




I picked Haskell + Qt/QML because the combination ships cleanly to all three
desktop OSes (macOS, Windows, Linux) from a single codebase.

## What it does

- Todos with title, done state, and a project assignment
- Projects (sidebar) with add, rename, delete, and per-project filtering
- Sort and free-text search over the todo list
- Persistent state in a local SQLite database

## Layout

```
cpp/             Qt6 C++ frontend — QProcess wrapper, JSON marshalling, QML bridge
qml/             QML views — Main, TodoCard, SidebarItem
haskell/
  app/Main.hs    Entry point — wires DB, state, request loop, response writer
  src/
    State.hs     AppState, Settings, version counters
    DB.hs        SQLite schema, queries, settings serialisation
    Handler.hs   Action dispatch, input parsing
    AppState.hs  Aggregated read for the initial-state envelope
    Todo/        Todo and Projects domain modules (STM-owning)
    Types/       Pure data types (Todo, Project)
    Logger.hs    stderr logging
CMakeLists.txt   Builds Qt app + invokes cabal for the Haskell backend
```

## Build and run

You need a Qt6 install, CMake 3.20+, and a working `cabal` (GHC 9.x).

```
cmake -B build
cmake --build build
./build/cpp/haskell-qt
```

CMake builds the Haskell backend as a custom target and copies the resulting
binary next to the Qt executable. The Qt app spawns it on startup with
`QProcess`.

## Tooling decisions

These were chosen, not defaulted to. The reasoning is the part worth keeping.

**Qt6 + QML, not QtWidgets.** QML renders through the Qt Scene Graph on the
GPU. Animations, hover effects, and list scrolling cost effectively nothing on
the CPU once the scene is built. QtWidgets would have made the C++ side
slightly simpler and the UI noticeably less smooth.

**CMake, not qmake.** qmake is in maintenance. CMake is what Qt6 itself
recommends, and it is the only sane way to compose the Qt build with a
non-Qt sub-build (the Haskell binary). The Haskell build is wired in as a
custom target that runs `cabal build` and copies the resulting binary next
to the Qt executable in `POST_BUILD`.

**`cabal`, not `stack`.** No extra resolver layer; the dependency set is
small and stable. `cabal-install` is what GHC ships with.

**`sqlite-simple`, not `persistent`.** The schema is three tables. I do not
need migrations, type-class plumbing, or a query DSL. A handful of SQL
strings is more honest about what is happening on disk and compiles in a
fraction of the time.

**`aeson` with `Generic`-derived codecs.** I do not write JSON parsers by
hand. The wire format is small enough that the derived codecs are both fast
and impossible to get out of sync with the types.

**`Data.IntMap.Strict`, not `Map Int` or `[Todo]`.** All lookups in this app
are by integer id. `IntMap` gives O(min(n, W)) on big-endian Patricia trees,
which is dramatically faster than `Map Int` (with its `compare`-based
balancing) and not even comparable to a list scan. The `Strict` variant
avoids thunk buildup in the values, which matters because we mutate the same
keys repeatedly (toggle, rename).

**`STM` with `TVar` and `TQueue`, not `MVar` or `IORef`.** STM's optimistic
retry handles concurrent requests without locks. `TQueue` is the natural
single-producer-many-consumers queue for the response writer. The whole
backend has zero explicit locks.

**Newline-delimited JSON over stdin/stdout.** Smallest viable framing. Lets
QProcess use `canReadLine` to deliver complete messages without buffer
juggling on either side. I also write Compact JSON on the C++ side
(`QJsonDocument::Compact`) to keep the per-message payload as small as
possible.

**Line-buffered stdout on the Haskell side.** Without this, GHC defaults to
block buffering when stdout is not a terminal — the Qt side would see
nothing until the buffer filled. `hSetBuffering stdout LineBuffering` makes
each response visible the instant it is written.

**XDG / `QStandardPaths::AppDataLocation`.** Both processes agree on the
platform-native data directory without coordinating. The DB and the log file
live there.

## Architectural decisions

### Two processes, one pipe

The Haskell backend is a child process. Communication is newline-delimited
JSON over stdin/stdout. stderr is reserved for logs.

The alternative is FFI — link Haskell into the Qt process. I chose the
process boundary because:

- Crashes are isolated. A bad SQL query in the backend cannot take down the
  UI.
- Builds are independent. The Haskell side knows nothing about Qt; the Qt
  side knows nothing about GHC.
- Debugging becomes trivial. You can drive the backend from a terminal and
  watch the JSON flow in both directions.
- Easier to build binaries for three different OS platforms.

The cost is one JSON encode/decode per request. At human-interaction
frequencies — clicks, keystrokes — this is invisible, well under a
millisecond. If I had a use case generating thousands of requests per
second, I would revisit.

### State lives in Haskell, not in the UI

`AppState` is the single source of truth: todos, projects, sort order, filter
text, version counters. The Qt side caches a copy in a `QVariantMap` and
re-renders when it changes. QML never owns canonical state.

This matters for two reasons. First, the same data drives multiple views —
the sidebar count and the todo list both read from `backend.state.todos`,
and they cannot disagree because they are reading one array. Second, state
must survive a restart; putting it in the persistent process makes the UI a
derivation, not a peer.

### STM with version counters

Each incoming request is handled in a fresh `forkIO` thread. Shared state is
a `TVar AppState`. STM's optimistic retry resolves contention with no
explicit locking — fast path is essentially free, slow path is a transparent
re-read.

Every mutation bumps a per-domain version counter (`todosVer`,
`projectsVer`). The response carries the version. The C++ side keeps a map
of last-applied versions per domain, and drops any response whose version is
older than what it has already applied:

```cpp
if (ver > m_versions.value("todos", 0)) {
    m_versions["todos"] = ver;
    m_state["todos"] = parseTodoList(obj["result"].toArray());
    emit stateChanged();
}
```

This is the safety net that lets me fan out requests in parallel. A slow
`addTodo` finishing after a fast `deleteTodo` would otherwise resurrect the
deleted item; with version gating it just gets dropped on the floor.

Read-only queries (`getTodos`, `getProjects`) bypass the gate because there
is nothing to be stale relative to.

### A single response writer

Even though requests run in parallel, all responses go through one
`TQueue`, drained by a single writer thread that owns stdout:

```haskell
_ <- forkIO $ forever $ do
  resp <- atomically $ readTQueue responseQ
  BL.putStr (Aeson.encode resp)
  putStrLn ""
```

Without this, two concurrent `putStrLn` calls could interleave bytes in a
single line and corrupt the JSON framing on the wire. Serialising at the
boundary keeps the protocol correct without serialising the work itself.

### Hot state vs cold state on the Qt side

The Qt bridge distinguishes two update cadences:

- **Cold state** — todos, projects, settings — lives in a single
  `QVariantMap` exposed as one `Q_PROPERTY` with a single `stateChanged`
  signal. QML re-derives whatever it needs when that signal fires.
- **Hot state** — anything updating at keystroke or animation speed — would
  get its own dedicated property and signal so it does not invalidate
  bindings on the rest of the state map.

Today everything is cold. The pattern exists so that when something hot
appears (a live counter, a progress bar, a typing indicator), there is an
obvious place to put it without retrofitting the whole bridge.

The reason this matters: every `stateChanged` emit causes every QML binding
that reads `backend.state.*` to re-evaluate. That is fine at click speed.
At keystroke speed, you do not want a one-character edit to invalidate the
todo list.

### ListView for the sidebar, Repeater for the cards

`ListView` virtualises — it only instantiates delegates for visible rows.
The sidebar uses it because a project list can grow long. `Repeater` does
not virtualise; every item is a real item. The todo grid uses Repeater
because it sits inside a `Flow`, and `Flow` needs all its children present
to compute the wrap layout.

This is a deliberate trade. With hundreds of todos, the Repeater would
become a problem and I would replace `Flow + Repeater` with a custom
`GridView` or a tiled `ListView`. For the expected scale, the simpler
layout wins.

### Flat schema with foreign keys, not nested data

A todo carries a `projectId`. Projects do not contain todos. I considered
the nested model — a project owns a list of todos — and rejected it on
performance grounds:

- Filtering and counting across all todos is one linear pass over one
  array, not a flat-map across N project arrays.
- Moving a todo between projects is a single field write, not a remove and
  re-insert across two collections.
- The wire payload is flat, which keeps JSON small and C++ parsing
  trivial. Nested would mean redundant project data inside every todo
  group.

The downside is that project counts are computed at render time on the QML
side. For a single-user desktop app at this scale, that is the right call.
At service scale I would denormalise.

### Settings persisted as a JSON blob

Sort order and filter text live on `AppState` directly. They are also
serialised into a single-row `settings` table as an Aeson-encoded JSON
string. Adding a new setting is a one-line change to the `Settings` record;
the schema does not move.

`AppState` is the runtime form. `Settings` is the persistence form. They
have overlapping fields and live as separate types so either can evolve
without touching the other.

### Domain modules own their STM

`Todo/Todo.hs` and `Todo/Projects.hs` each own the STM transactions for
their slice of state. `Handler.hs` is a flat dispatcher — it never calls
`atomically` or touches a `TVar`. This is partly hygiene, partly speed of
iteration: when something about todos changes, there is exactly one file to
read.

The split between `Types/Todo.hs` (data only) and `Todo/Todo.hs`
(operations) exists to break a circular dependency: `State.hs` needs the
`Todo` type, and `Todo/Todo.hs` needs `AppState` from `State.hs`. The
pure-data module sits beneath both.

### `Value`-typed input on the wire

The request envelope is `{ action: String, input: Value }`. Input is an
Aeson `Value`, not a fixed type — a string action gets a JSON string, an
int-id action gets a number, a multi-field action like `renameProject` or
`addTodo` gets an object. Decoding happens at the call site in `Handler.hs`
via small helpers (`inputStr`, `inputInt`, `inputField`, `inputFieldInt`).

This trades a little type-level rigour for the ability to add a new action
without writing a new request type. For a project of this size, the trade
is worth it. I would revisit at scale.

### DB write ordering

`addTodo` writes to SQLite first because we need the auto-increment id
before we can construct the in-memory record. Everything else
(`deleteTodo`, `toggleTodo`, `deleteProject`, `renameProject`) writes to
STM first so the UI feels instant, then to the DB. If the process dies
between the STM commit and the DB write, the DB wins on next startup —
the user sees the pre-crash state, not a phantom edit. This is the right
default: DB is durable, STM is recoverable.

### `applyView` as the only path to a wire payload

Every list of todos that leaves the backend goes through `Todo.applyView`.
Same for projects. The function applies filter, then sort, in a single
pass over `IntMap.elems`, returning `[Todo]`. There is no other way to
build the payload.

This guarantees that filtering and sorting are consistent across
`addTodo`, `deleteTodo`, `getTodos`, every code path. It also makes any
future optimisation (memoising the sorted list, switching to a sorted
container) one-place-only.

### Logging routes through one file

Haskell logs to stderr via `Logger.hs`. The Qt process captures Haskell's
stderr via `readyReadStandardError` and forwards it through `qDebug()`. A
custom `QtMessageHandler` installed in `main.cpp` routes everything
(`qDebug`, `qWarning`, QML `console.log`, the forwarded Haskell stderr)
into a single timestamped `app.log`. From a packaged build the user sees
nothing; everything is on disk if you need it.

## What is intentionally not here

- **No migrations framework.** The schema is small. `CREATE TABLE IF NOT
  EXISTS` plus the occasional manual `ALTER TABLE` is enough today.
- **No request/response correlation IDs.** Version counters do the
  ordering work I need.
- **No tests on the Haskell side.** When I add them, the pure functions
  (`applyView`, the Settings codec) are the obvious first targets. The
  STM operations are not far behind.
- **No QML model proxies.** Filtering and project lookups happen in JS
  inside Main.qml today. If the lists grow large, a `QSortFilterProxyModel`
  is the next step — but it is more code, and not worth it yet.

