# Plan: LLM Session → X6 Diagram with Reblocks Popup

## Goal

Render the state of an LLM session (messages, tool calls, tool results) as an interactive X6 diagram in the Web UI. Each message is a node, connected in a chain. Tool calls branch off from assistant nodes. Clicking a node shows a Reblocks popup widget with the full message content.

## Data Source

The `llm-agent` actor stores messages as a list of hash-tables with keys:

- `"role"` → `"system"`, `"user"`, `"assistant"`, `"tool"`
- `"content"` → string (or `"NULL"` for assistant tool-calls)
- `"tool_calls"` → vector of tool-call hash-tables (only on assistant messages)
  - Each has `"id"`, `"function" → {"name" ..., "arguments" ...}`
- `"tool_call_id"` → string linking tool result back to the call (only on tool messages)

## Diagram Structure

```
[system] → [system] → [user] → [assistant] ──→ [asst] ──→ ...
                               ↓                ↓
                             [tool: BASH]      [tool: BASH]
                             (result)          (result)
```

### Node Types and Colors

| Role | Fill | Stroke | Label |
|------|------|--------|-------|
| `system` | `#94a3b8` (gray) | `#64748b` | truncate(content, 20), small node |
| `user` | `#3b82f6` (blue) | `#2563eb` | truncate(content, 25) |
| `assistant` (content only) | `#22c55e` (green) | `#16a34a` | truncate(content, 25) |
| `assistant` (content + tool_calls) | `#22c55e` (green) | `#16a34a` | truncate(content, 25) + branches |
| `assistant` (tool_calls only, content=NULL) | `#22c55e` (green) | `#16a34a` | "..." + branches |
| `tool` (result) | `#f59e0b` (amber) | `#d97706` | truncate(content, 25) |

### Layout

- Main chain: left → right, x += 220 per step, y = 100
- Tool branches: same x as parent assistant, y = 220 + offset * 100

### Algorithm: build-diagram-data

```
state:
  - main-chain-x = 80
  - prev-main-node-id = nil
  - tool-call-id → node-id map = {}
  - branch-y-offset map = {}

for each message at index i:
  case role == "system":
    - create node(id="m{i}", x=main-chain-x, y=100, label=truncate(content,20),
                   attrs={fill: "#94a3b8", stroke: "#64748b"})
    - edge from prev-main-node-id
    - prev-main-node-id = node-id
    - main-chain-x += 220

  case role == "user":
    - create node(id="m{i}", x=main-chain-x, y=100, label=truncate(content,25),
                   attrs={fill: "#3b82f6", stroke: "#2563eb"})
    - edge from prev-main-node-id
    - prev-main-node-id = node-id
    - main-chain-x += 220

  case role == "assistant":
    - label = content != "NULL" ? truncate(content,25) : "..."
    - create node(id="m{i}", x=main-chain-x, y=100, label=label,
                   attrs={fill: "#22c55e", stroke: "#16a34a"})
    - edge from prev-main-node-id
    - for each tool_call in tool_calls:
        - tc-node-id = "tc_{tool_call_id}"
        - branch-y = 220 + branch-y-offset * 100
        - create placeholder node(tc-node-id, x=main-chain-x, y=branch-y,
                                   label=tool_name, attrs={fill: "#f59e0b"})
        - edge from node-id → tc-node-id
        - store tool_call_id → tc-node-id in map
        - increment branch-y-offset
    - prev-main-node-id = node-id
    - main-chain-x += 220

  case role == "tool":
    - tc-node-id = lookup(tool_call_id)
    - if found: update node label and data content
```

## Node Data for Popup

Each node carries a `data` field stored server-side:

```lisp
(:role "user" :content "What files are in /tmp?")
;; or
(:role "assistant" :tool-call-id "call_00_abc" :tool-name "BASH" :content "...")
;; or
(:role "tool" :tool-call-id "call_00_abc" :tool-name "BASH" :content "lrwxr-xr-x...")
```

## Popup (Reblocks Widget)

When user clicks an X6 node:

```
1. JS: graph.on('node:click') fires
2. JS: initiateAction(actionCode, {args: {nodeId: "tc_call_00_abc"}})
3. Reblocks action handler receives POST request
4. Handler: (show-node-popup popup-widget "tc_call_00_abc")
5. show-node-popup:
   - (get-node-data "tc_call_00_abc") → (:role "tool" :content "...")
   - (setf (popup-node-data widget) data)
   - (show-popup widget) → sets visible=T, calls (update widget)
6. Widget re-renders with popup visible
7. User clicks ✕ or overlay → (hide-popup widget)
```

Popup layout (Tailwind):
- Overlay: `fixed inset-0 bg-black/50 flex items-center justify-center z-50`
- Card: `bg-white dark:bg-gray-800 rounded-lg shadow-xl max-w-lg w-full p-6`
- Role badge: colored span
- Content: `pre` for tool args/results, `p` for text
- Close button: ✕

## SSE Protocol

### Event: `init-diagram`

Sent on connect and when messages change. Full diagram state.

```json
{
  "nodes": [
    {"id":"m0","x":80,"y":100,"width":140,"height":30,
     "label":"You are a helpful...",
     "attrs":{"body":{"fill":"#94a3b8","stroke":"#64748b"},"label":{"fill":"#fff"}},
     "data":{"role":"system","content":"You are a helpful assistant..."}},
    {"id":"m2","x":520,"y":100,"width":180,"height":40,
     "label":"What files are in /tmp?",
     "attrs":{"body":{"fill":"#3b82f6","stroke":"#2563eb"},"label":{"fill":"#fff"}},
     "data":{"role":"user","content":"What files are in /tmp?"}}
  ],
  "edges": [
    {"source":"m0","target":"m2"}
  ]
}
```

Client handler: clears graph, re-renders all nodes and edges.

### Event: `add-node` (future)

For incremental updates. Not used in v1.

## Files

| File | Action | Description |
|------|--------|-------------|
| `src/frontend/diagram/builder.lisp` | **CREATE** | Build diagram data from messages, store node data, global actor var |
| `src/frontend/widgets/message-popup.lisp` | **CREATE** | Popup widget with role-colored content display |
| `src/frontend/widgets/x6-diagram.lisp` | **MODIFY** | Add popup child, node:click handler with Reblocks action, init-diagram with data |
| `src/frontend/routes.lisp` | **MODIFY** | Replace demo loop with session-aware SSE |
| `src/frontend/app.lisp` | No changes | |
| `src/frontend/x6/diagram.js` | No changes | |
| `codabrus.asd` | **VERIFY** | Ensure transitive deps resolve |

---

## TODO

- [x] Create `src/frontend/diagram/builder.lisp`
  - [x] `*current-session-actor*` global variable
  - [x] `*node-data*` hash-table for popup lookups
  - [x] `truncate-string` helper
  - [x] `node-attrs` helper (color scheme per role)
  - [x] `messages-of-actor` (extract messages from actor state)
  - [x] `build-diagram-data` (main algorithm)
  - [x] `get-node-data` (lookup for popup)
  - [x] Serialization to JSON (`nodes/to-json`)
- [x] Create `src/frontend/widgets/message-popup.lisp`
  - [x] `message-popup` class (inherits `ui-widget`)
  - [x] `render` method with role badge + content
  - [x] `show-node-popup` function
  - [x] `hide-popup` function
- [x] Modify `src/frontend/widgets/x6-diagram.lisp`
  - [x] Add `popup` slot with `message-popup` instance
  - [x] Create Reblocks action for node clicks in `render`
  - [x] Update `%make-init-js` in Parenscript:
    - [x] Remove hardcoded Hello→World nodes
    - [x] Add `init-diagram` event handler (clearCells + re-render)
    - [x] Add `graph.on('node:click')` handler calling `make-js-action`
  - [x] Render popup widget alongside diagram
- [x] Modify `src/frontend/routes.lisp`
  - [x] Replace demo `diagram-events-stream` with session-aware SSE
  - [x] On connect: read actor, build diagram, send `init-diagram`
  - [x] Poll loop: detect message count changes, resend `init-diagram`
- [x] Verify `codabrus.asd` transitive dependency resolution
- [x] Add tests for `builder.lisp` (4 tests passing)
- [ ] Test end-to-end: actor → diagram → popup (requires running server)
