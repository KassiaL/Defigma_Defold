## Response style

Be terse and technical. Answer first, no preamble, no recap of what you just did unless asked. No filler ("Great", "Sure", "I'll now…"), no restating my request back to me. Prefer the smallest correct change and the shortest correct answer. Don't enumerate alternatives I didn't ask for — give one recommendation with a one-line reason. Skip summaries of obvious diffs; let the code speak. Use lists/snippets over prose. Ask instead of guessing when blocked. Respond in the language I write in.
Once you have answered something, treat that answer as done. On later turns, focus your thinking on what the user is asking now, and don't go back over an earlier answer unless the user asks about it or points out a problem with it.
Keep a checklist of subtasks and mark off completed work as you go. Before finishing, check the list.

## File editing

Never overwrite user's existing changes in files. When editing a file the user has modified, always read it first and make only additive or targeted changes. Do not replace the entire file contents unless explicitly asked.

Build only when the change is large enough that it has to be checked in the running game (new screen/flow, gameplay, animations, effects, non-trivial runtime logic); skip the build for small, local edits. The `automation-bridge` skill may be used without asking.

Every build that runs the game for a check is `build_shell/test/test_instance.sh` started from the root of the checkout you work in, also outside a worktree, and the bridge attaches with `engine.connect(<ENGINE_PORT>)`. Never build or run the game through the editor (`project.build_and_run`, `project.clean_build_and_run`, `project.connect_engine`, hot reload) unless I ask for it. When this PC is short of RAM the script moves the build and the instance to a free computer of the LAN by itself and the bridge works the same; a task that checks sound runs with `TEST_SOUND=1` (Linux only, the Mac and Windows instances are muted), a task that measures performance (profiler, FPS, frame times) with `TEST_PERF=1` (this PC only). Video is `build_shell/test/record.py` wherever the game runs. Exit code 3 means no computer fits: stop and tell me, never start the build another way. See `md/shared/PARALLEL_TEST_INSTANCES.md`. Do not revert changes in git (I may be working concurrently).

Update the documentation as part of every change, without being asked: grep `md/`, `m/PROJECT_STRUCTURE.md` and `docs/` for what the change touched and fix every stale statement found there, not only the line that mentions the edited symbol.

## Code style

Avoid unnecessary defensive programming. Do not assume data is missing or constantly re-check field existence in tables. If you set a field, it exists. Similarly, do not check for standard Defold and Lua API availability (e.g., io and io.open always exist).
Use `assert` to narrow nullable Lua locals when needed to clear diagnostics.
Maximize code reuse with small, composable functions. No comments — code must be self-explanatory through names and structure.
Do not mix data types for a field or parameter. Keep types consistent end-to-end.
Do not keep legacy compatibility code unless explicitly requested. When replacing a flow or data format, remove the old code path completely and do not preserve previous save formats, globals, or fallback behavior.

## Lua diagnostics

After editing Lua files, use the `lua-check` skill; treat warnings in touched files as blockers.

## Skills

Use Codex skills for repeatable workflows:

- After editing Lua files, use `lua-check`.
- When working with Defold `.gui` files, use `defold-gui`.
- When a change needs a runtime check (see the build rule above) or the user asks to run/test/check the game, reproduce a runtime bug, automate input, inspect the runtime scene, take screenshots, read engine logs, resize/reboot the engine, or profile the running game, use the `automation-bridge` skill. The game registers `automation_bridge.command` callbacks for reaching screens and states without clicking through the UI; they are listed in `md/AUTOMATION_COMMANDS.md`. Keep that file current when adding or removing a command.
- For checking fresh Lua/resource changes in the running game, rebuild with `build_shell/test/test_instance.sh` and use `automation-bridge` to perform inputs and verify runtime state.
- When the user explicitly asks to inspect Nakama DB/storage, call an RPC, run a healthcheck, or restart the server, use `nakama-db`.
- When the user asks to check GC pressure, memory allocations per frame, or to find the source of periodic frame hitches on a screen, use `gc-profile`.

## Review by a second agent

Every visual or feel-driven task — Figma work, new or reworked screens, gameplay, animations, effects, "make it cool / juicy" requests — goes through a review loop without being asked:

- After the first pass, spawn a separate reviewer subagent: the project's specialised reviewer agent when its docs name one for this kind of change, a general agent otherwise. Give it the goal, the result (screenshots/clips from `automation-bridge`, Figma exports) and the files behind it; it reviews strictly, the way I would, and returns a concrete list of fixes. It never edits.
- My explicit requirements outrank the reviewer. Pass them to it verbatim as fixed constraints; a remark that contradicts one is rejected, not applied, unless I said the details are up to you.
- Apply the fixes, regenerate the evidence and send it back to the same reviewer (`SendMessage`). Repeat until it has no blocking remarks.
- Report the final state and any reviewer remark you deliberately rejected, with the reason.

## GUI rules

Prefer `gui.set_enabled` for visibility control. Use `gui.set_visible` only for the renderable node whose own visual content is being swapped or explicitly hidden/shown, such as an image node after `set_texture` or a text/image-bearing node whose drawable must stay enabled but not rendered. Do not use `gui.set_visible` for containers, parents, layout/grouping nodes, or as a general replacement for `gui.set_enabled`. To turn an `on_input` action into node coordinates use `mylib.screen_to_node_local(node, mylib.input_screen_point(action))`, and `gui.pick_node(node, action.x, action.y)` for a plain box hit test. Never rebuild a node's transform by walking parents with `gui.get_position` / `gui.get_scale`: those return authored values and omit the per-node adjust mode, so the result silently breaks as soon as anything in the chain is scaled through `PLATFORM_SCALER_CONFIG`.
For GUI render ordering, avoid `gui.move_above(node, nil)` and `gui.move_below(node, nil)` on nodes that must preserve their local position, especially during drag/reparent flows. Use an explicit sibling reference in the same parent instead; `nil` can produce unexpected visual bugs.
Do not modify any `*.gui_script` files.
`.gui` files are exported from Figma and any edit in them is overwritten by the next export: never fix a design problem there, report what has to be changed in Figma instead.

`on_change_layout` restores static GUI nodes to their layout/editor visual state.

## Defigma shapes and text gradients

Every Figma rectangle, ellipse, vector and frame fill outside an atlas section exports as a `DefigmaShape` custom node (native extension in `defigma/`): gradients, strokes, shadows, blur and arcs live in its custom properties and need no Lua, no `defigma_data` entry and no refresh. A progress ring is a Figma arc ellipse; change it with `defigma_shape.set_sweep(node, percent)` (or `set_arc` / `get_arc`). A shape node cannot be a round stencil clipper (its geometry is a rectangle): round masks stay `TYPE_PIE`. Before moving an element from an atlas to a shape, read "Risks and measured numbers" in `defigma/DEFIGMA.md`: on a weak GPU a big shape costs its area once per fill.

The only materials left are for text: a text node whose material is `linear_text` is drawn by a gradient shader and renders as nothing without an applied gradient. Every template that declares text gradients or text shadows in its `defigma_data` needs `gradient_nodes` applied to its nodes.

`defigma.gradient` reads the node transform from the engine (`gui.get_screen_position` plus two `gui.screen_to_local` probes), so there is no pass to merge and no batching: the cost is the number of refreshed nodes. Keep that number down instead — `gradient_nodes.bind_scroll` keeps one `on_scroll` subscription per scroll and refreshes every registry bound to it on real movement, and `gradient_nodes.refresh_all` covers a loop that touches many widgets.

Call `gradient_nodes.create_for_widget` from the widget that owns the nodes, but drive the per-frame work from the owner: leave entries out of the per-frame update (the default), bind the scroll that moves them, and call `refresh` only after the content or the transform of that widget changed. Do not add a per-widget `update` that refreshes gradients every frame when many instances exist.

## Project structure

Project structure note: see `m/PROJECT_STRUCTURE.md`.

`AGENTS.md`, every file in `md/shared/` and the test scripts `build_shell/test/test_instance.sh`, `build_quiet.sh`, `run-test-env`, `run-test-window.py`, `mute_macos.m`, `play.sh`, `record.py`, `agent_worktree.sh`, `agent_worktree_clean.sh` are shared by all Defold projects: `$HOME/my_shell/sync_defold_docs.py` copies the newest edited version into every project. Keep project-specific content out of them, except a trailing `## Project Settings` section, which the sync keeps per project; project-specific script behaviour goes to `build_shell/test/test_instance_project.sh`, which the sync never touches.

`bridge/` (the SDK bridge) is identical in every project that has it and is synced by `$HOME/my_shell/sync_defold_bridge.py` (the edited copy wins). Nothing in it may require project code: project-specific behaviour is set from the project's bridge setup (for example `bridge.mock` `set_save_appname` / `set_save_writer`). A change of its API means updating the callers in every project that has the folder.

## Worktree

Every task that changes files is done in your own worktree, without being asked; read `md/shared/PARALLEL_TEST_INSTANCES.md` and follow it. Work directly in the main checkout only when I allowed it for that task.

- Create the checkout with `build_shell/test/agent_worktree.sh <name>` and keep every edit there, on its `agent/<name>` branch.
- Verify through a `build_shell/test/test_instance.sh` build and the `automation-bridge` skill attached with `engine.connect(<ENGINE_PORT>)` whenever the "build only large changes" rule above calls for a build: then the task is finished when the built instance shows the change working, not when the diff looks right.
- Build only from that checkout, with `build_shell/test/test_instance.sh` started from its root, so what runs is that branch. Never build a worktree branch from the main checkout or from another agent's checkout.
- When the task is done and verified, always merge it into the integration branch: commit on `agent/<name>`, then merge that branch from the main checkout. If the merge is refused or conflicts with my uncommitted changes, stop and tell me.

## Clarifications

If you have any questions or something is not clear, you need more information - ask me about it.

## API

Before writing code, read `md/shared/API.md`.
