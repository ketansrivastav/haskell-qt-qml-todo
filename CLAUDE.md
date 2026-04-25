# CLAUDE.md

Operational guidance for working in this codebase. The README explains why
things are the way they are; this file explains how to land changes without
breaking the things that matter.

## Rule zero: performance is the primary axis

Every decision in this codebase was made with performance in mind. When you
are about to add code, ask:

- How often does this run? Per keystroke, per click, per startup, never?
- What does it allocate? Does it walk a list when it could index an `IntMap`?
- What does it block? Does it sit on a DB write inside an STM transaction?
  Does it serialise something on the GUI thread?

If a change you are about to make trades performance for convenience —
introducing a list scan where there was an indexed lookup, adding a
synchronous DB call on a hot path, sending a larger payload than needed,
collapsing hot state into the cold `QVariantMap` — **stop and flag it to the
user before writing it.** Do not silently make the trade.

Some specific things that are non-negotiable:

- Do not pretty-print JSON on the wire. Compact only — newline framing
  depends on it.
- Do not add list scans over `todos` or `projects` on the Haskell side.
  Use `IntMap` operations.
- Do not run DB writes inside an `atomically` block. STM retries; the DB
  must not.
- Do not move cold state into per-property hot signals "for symmetry". The
  cold/hot split is deliberate.
- Do not introduce a new dependency without naming what it replaces and
  what it costs at startup.

## Rule one: Haskell ↔ C++ communication is version-controlled

The wire protocol has invariants. They are easy to break by accident and the
failure mode is silent (responses dropped, UI desyncs).

**Every mutating action must bump a version counter.** `todosVer` for
todo-domain mutations, `projectsVer` for project-domain mutations. The
counter lives on `AppState`; the bump happens inside the same `atomically`
block as the state change. The new value is returned alongside the payload
and shipped back to C++ as `ver` in the `Response`.

**The C++ side gates state updates on version.** In `backend.cpp`'s
`onReadyRead`:

```cpp
if (ver > m_versions.value("todos", 0)) {
    m_versions["todos"] = ver;
    m_state["todos"] = parseTodoList(obj["result"].toArray());
    emit stateChanged();
}
```

If you add a new mutating action, you must:

1. Bump the right `*Ver` in the domain module (Todo or Projects).
2. Add the action name to the version-gated branch in `onReadyRead`.

If you skip step 1, every concurrent request that races yours will overwrite
your update. If you skip step 2, your action's response will overwrite newer
state on arrival. Both are silent.

**Read-only queries (`getTodos`, `getProjects`, `getAppState`) bypass the
gate.** They are applied unconditionally because there is nothing for them to
be stale relative to. Do not version-gate a read.

**Wire field names match Haskell field names.** Aeson-generic codecs derive
the JSON shape from the record. Renaming `todoTitle` in `Types/Todo.hs`
silently renames the wire field; the C++ `parseTodoList` will then read an
empty string. If you rename a field, update both ends in the same change.

## Build and run

```
cmake -B build
cmake --build build
./build/cpp/haskell-qt
```

`cmake --build build` triggers the `build-haskell` custom target, which runs
`cabal build exe:haskell-backend` and copies the binary to
`build/haskell-backend-bin`. The Qt build's `POST_BUILD` step then copies it
next to the Qt executable. There is no separate Haskell build step to run.

The local DB lives at `~/.local/share/haskell-qt/todos.db`. The log file is
at `~/.local/share/haskell-qt/app.log` and captures stderr from both
processes plus QML `console.log`.

To drive the backend in isolation without launching Qt:

```
echo '{"action":"getAppState"}' | ./build/haskell-backend-bin
```

## Invariants — must hold

- Every mutation bumps the relevant `*Ver` counter on `AppState`. Drop the
  bump and the C++ side will throw the response away.
- Lists leaving the backend go through `applyView` (in `Todo.Todo` and
  `Todo.Projects`). Do not hand-roll a list response — `applyView` is the
  only place filter and sort are applied, and consistency depends on it
  being the only path.
- STM lives in domain modules. `Handler.hs` is a flat dispatcher; do not
  call `atomically` or touch a `TVar` there.
- DB write ordering: insert-style operations (need the autoincrement id)
  write DB first; mutate-style and delete-style write STM first, then DB.
  The STM-first order is what makes the UI feel instant.
- stdout is JSON only. Logging goes to stderr via `Logger.hs`; the Qt
  side captures it into `app.log`.
- The single response writer thread in `Main.hs` owns stdout. Do not
  `putStrLn` from a request handler — it will interleave bytes with
  another in-flight response and corrupt the framing.

## How to add a new action

The most common task. There are six places that touch:

1. **Domain module** (`Todo/Todo.hs` or `Todo/Projects.hs`) — add the
   function. Bump `todosVer` or `projectsVer` inside `atomically`. Return
   `(applyView newSt, newVer)`.
2. **Persistence** (`DB.hs`) — add the function if needed. Match the
   STM-first vs DB-first rule above.
3. **Dispatch** (`Handler.hs`) — add the case in `handleRequest`. Use
   `inputStr` / `inputInt` / `inputField` / `inputFieldInt` to extract
   from `req.input`.
4. **C++ method** (`backend.h` + `backend.cpp`) — add a `Q_INVOKABLE`.
   Build the input as a `QJsonObject` (single field becomes a primitive;
   multi-field becomes a nested object). Call `sendRequest`.
5. **C++ response** (`onReadyRead`) — add the action name to the
   version-gated branch for its domain.
6. **QML** — call `backend.<method>(...)`; read updated state from
   `backend.state.*`.

Skipping any of these silently breaks the loop. Most often forgotten:
step 5.

## How to add a field to AppState

- Add it on `AppState` in `State.hs`. Update `initialState`.
- If it should persist across restart, add it on `Settings` too. Update
  `defaultSettings`, `loadSettings`'s constructor, and the `Settings`
  construction sites in `Todo/Todo.hs` (each `saveSettings` call site
  builds a fresh `Settings` value).
- Use `OverloadedRecordDot` to disambiguate field access (e.g.
  `st.todoFilterText`). `AppState` and `Settings` share names by design.
- Hydrate it from disk in `Main.hs`'s startup record-update.

## Wire format conventions

- `Request.input` is `Aeson.Value`. Decode at the call site. Do not
  introduce per-action request types — adding a new action should not
  require touching the envelope.
- Multi-field input is a JSON object. C++ builds it as a nested
  `QJsonObject` (see `renameProject`, `addTodo`). Haskell reads fields
  with `inputField` / `inputFieldInt`.
- Single-field input is a JSON primitive. C++ assigns the value
  directly to `req["input"]`.

## State on the Qt side

- Canonical state lives in Haskell. The Qt side caches it in
  `m_state` (`QVariantMap`) and re-renders on `stateChanged`.
- Cold state — todos, projects, settings — goes in `m_state`.
- Hot state — anything updating at keystroke or animation speed —
  would get its own `Q_PROPERTY` and dedicated signal. None exists
  today; if you need to add one, do not collapse it into `m_state`.
- UI-only selection state (e.g. `selectedProjectId`) lives in QML.
  Do not push it to the backend.

## Naming conventions

- Record fields carry a domain prefix: `todoTitle`, `todoDone`,
  `todoProjectId`, `projectName`, `todoFilterText`,
  `projectFilterText`. This is what makes `DuplicateRecordFields` +
  `OverloadedRecordDot` work without ambiguity.
- Wire field names follow the Haskell field names directly (no Aeson
  field-label modifier). Rename one and you must update C++ parsing.

## Don'ts

- **No migration framework.** If you change column types or add NOT NULL
  columns to an existing table, either delete the local DB or write an
  `ALTER TABLE` in `initDB`.
- **No pretty-printed JSON on the wire.** Compact mode only.
- **No new modules without `other-modules` in `haskell-backend.cabal`.**
  Build succeeds; runtime fails to find them.
- **No tests yet.** Do not add speculatively. When the user asks, start
  with `applyView` and the `Settings` codec.
- **No comments that restate what the code does.** The codebase is
  intentionally sparse on inline commentary.
- **No correlation IDs on requests.** Version counters do the ordering
  work. Adding correlation IDs without a consumer is dead infrastructure.
- **No per-action request types.** `Request.input :: Maybe Value` is the
  contract.

## Pitfalls hit before

- Schema changes without DB reset cause `loadTodos` to fail because the
  SELECT references a missing column. The Haskell process exits and
  the UI shows zero items with no obvious error in the GUI — check
  `app.log`.
- Forgetting to bump a version counter: response is silently dropped
  by the C++ version gate.
- Adding a new module without listing it in `haskell-backend.cabal`:
  build succeeds, runtime says "module not found" because GHC's
  cabal build excludes anything not declared.
- Renaming a record field shared between `AppState` and `Settings`
  without `OverloadedRecordDot`: ambiguous-occurrence errors that
  look unrelated to the rename.
- Replacing all of one record-field name with `replace_all`: easy to
  double-suffix already-renamed occurrences (e.g.
  `projectFilterText` → `projectFilterTextText`). Edit deliberately.
