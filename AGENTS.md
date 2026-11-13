## Response style

Be terse and technical. Answer first, no preamble, no recap of what you just did unless asked. No filler ("Great", "Sure", "I'll now…"), no restating my request back to me. Prefer the smallest correct change and the shortest correct answer. Don't enumerate alternatives I didn't ask for — give one recommendation with a one-line reason. Skip summaries of obvious diffs; let the code speak. Use lists/snippets over prose. Ask instead of guessing when blocked. Respond in the language I write in.
Once you have answered something, treat that answer as done. On later turns, focus your thinking on what the user is asking now, and don't go back over an earlier answer unless the user asks about it or points out a problem with it.
Keep a checklist of subtasks and mark off completed work as you go. Before finishing, check the list.

## Cloud session

When `CLAUDE_CODE_REMOTE=true` (a Claude Code cloud session), read `md/shared/CLOUD.md` first; otherwise skip it.

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
Do not keep legacy compatibility code unless explicitly requested. Backward compatibility is needed only for what players already have: the last commit named `RELEASE` on `main` (`git log main -i --grep='^release' -1`) is the released version. A mode or feature that is in that commit and playable there keeps working for that client; one missing from it, or present but still locked, has no old clients, so its protocol, storage and config change freely, with no compatibility code and no old-client handling. When replacing a flow or data format, remove the old code path completely and do not preserve previous save formats, globals, or fallback behavior.

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

## Figma

Figma is reached only through Figma Bridge (`~/figma_plugins/FigmaBridge/figma.py`, protocol in its `README.md`), never through a Figma MCP connector. Before the first Figma command read `md/FIGMA_BRIDGE.md` of the project: the file, the bridge port and what may be exported. Use it without asking whenever a task needs Figma: reading the design, editing it, exporting a `.gui` or an atlas, `figma.py shot`.

## Subagents and models

This is the only model-selection policy. The orchestrator selects models only through the settings and roles in this block; other project documents and agent definitions describe procedures, not model assignments. Edit the settings here to change the routing:

```text
CHECK_MODEL: haiku
CODE_MODEL: sonnet
DESIGN_MODEL: opus
REVIEW_MODEL: opus
HARD_MODEL: opus
```

| Setting | Use it for |
| --- | --- |
| `CHECK_MODEL` | Run existing build/export/diagnostic scripts; execute supplied automation-bridge steps and regression/smoke checks against explicit expected results; reproduce a bug using supplied steps; capture screenshots, videos, timestamped frames and contact sheets; extract specified runtime values and relevant log/error excerpts; targeted code/documentation lookups. |
| `CODE_MODEL` | Implement features, bug fixes and refactors; review code for correctness; investigate unexpected runtime/build/test failures; design or repair test scenarios and automation scripts; turn an unclear bug report into reproducible steps. |
| `DESIGN_MODEL` | Create or rework Figma screens and 3D assets, choose composition/style, design animations and gameplay feel, and implement changes whose main acceptance criterion is subjective visual or motion quality. |
| `REVIEW_MODEL` | Independent review of design, readability, animation, motion and gameplay feel, including the project's specialised visual/motion reviewers. Never substitute a functional check for this review. |
| `HARD_MODEL` | Difficult architecture and cross-system reasoning: client/server protocols, physics/network desynchronisation, rare intermittent bugs with several possible causes, wide architectural refactors, and coding investigations that remain unresolved after two distinct, evidence-based attempts by the code executor. |

- Resolve the role before starting each worker and pass the configured model explicitly in the Agent tool. This overrides model assignments elsewhere, including agent frontmatter; do not infer the worker's model from the parent session. Starting the orchestrator on a stronger model is not a reason to use that model for checks or routine implementation. An already-running session does not switch models because these settings changed: delegate to the selected model. If the selected model is unavailable, report it instead of silently choosing another.
- Split mixed tasks by responsibility: the design owner supplies the intended result and fixed constraints, the code owner implements the behavior, the check worker runs the procedure and collects evidence, and the independent reviewer judges visual/motion quality. Keep steps that share implementation files with one executor. Do not delegate work further from a check worker.
- Give a check worker the checkout, engine port (or permission to run `test_instance.sh`), exact scripts or screen/input steps, expected states/values, evidence directory and report format. Batch related build/check/capture steps into one assignment. The worker may write a short capture driver using the supplied steps, but does not change game code, invent missing acceptance criteria, weaken checks, or judge subjective quality.
- On a failed check, return its name, expected/actual values, the relevant error excerpt and the full log/evidence paths to the code owner. An incomplete check is reported as incomplete, never passed. Do not retry a failing command blindly or treat a nonzero exit as success. Build exit code 3 stops the runtime check under the existing build rules. The code owner diagnoses and fixes the failure, then returns the relevant procedure to the check worker. Escalate unresolved investigations to the hard-task owner with the attempted fixes and the concrete remaining question; use that owner from the start for the hard-task categories above.
- Keep the orchestrator's context clean. Workers retain raw logs, scene dumps, screenshots and video on disk and return only verdicts, relevant failure excerpts, changed files/commit, and absolute evidence paths. Motion evidence includes the original clip and timestamped frames/contact sheets; the reviewer can inspect the clip or request more frames when needed. Forward evidence by path rather than opening it merely to relay it. Only one worker builds or drives a checkout at a time.
- Run at most 3 executors on `opus` concurrently unless the user names another number; reviewers do not count. Give one executor one independent unit of work rather than one step. All workers follow the same worktree, skill, diagnostics, build and documentation rules. Functional checks, code review and visual review remain separate responsibilities.

## Showing the result

At the end of every task with a visible result — Figma work, a screen, an animation, gameplay, an effect — send me the evidence the check rests on without being asked: the exports or screenshots of every changed state and a clip of every changed animation or motion, with `SendUserFile` (where it is not available, list the paths). A file made by a subagent is forwarded by its path; the agent I talk to does not open it first.

## Review by a second agent

Every visual or feel-driven task — Figma work, new or reworked screens, gameplay, animations, effects, "make it cool / juicy" requests — goes through a review loop without being asked:

- After the first pass, spawn a separate reviewer subagent: the project's specialised reviewer agent when its docs name one for this kind of change, a general agent otherwise. Give it the goal, the result (screenshots/clips from `automation-bridge`, Figma exports) and the files behind it; it reviews strictly, the way I would, and returns a concrete list of fixes. It never edits.
- My explicit requirements outrank the reviewer. Pass them to it verbatim as fixed constraints; a remark that contradicts one is rejected, not applied, unless I said the details are up to you.
- Apply the fixes, regenerate the evidence and send it back to the same reviewer (`SendMessage`). Repeat until it has no blocking remarks.
- Report the final state and any reviewer remark you deliberately rejected, with the reason.

### How a design is checked

- The look of a screen — layout, sizes, colours, symmetry, every state — is checked in Figma only. The running game is for what Figma cannot show: animations and motion, runtime behaviour, layout that code moves. A change made only in Figma, with the animations already done, needs no build and no `automation-bridge` recording.
- Build every screen so each of its states can be seen in Figma: repeated elements show different states side by side, and an element (or the whole screen) with states of its own is a component set with one variant per state, placed in the screen, so switching the variant sets that state of the screen.
- Export every state that needs review as an image (`figma.py shot`) and give the images to the reviewer together with the node geometry of the screen. Full resolution is not needed: about 1000 px high is enough to judge whether it is pleasing to the eye, symmetric, aligned and consistent; crop or zoom a detail when a remark needs it.

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

`AGENTS.md`, every file in `md/shared/` and the test scripts `build_shell/test/test_instance.sh`, `build_quiet.sh`, `run-test-env`, `run-test-window.py`, `mute_macos.m`, `record.py`, `agent_worktree.sh`, `agent_worktree_clean.sh`, `defigma_twin.py`, the folder `build_shell/test/cloud/`, `build_shell/play.sh`, `build_shell/git/remove_git_file.sh` and `build_shell/helpers/build_server.sh` (the build server of every build script: the ordered servers of helpers/build_servers_auto.conf in auto mode) are shared by all Defold projects: `$HOME/my_shell/sync_defold_docs.py` copies the newest edited version into every project. The build scripts of `build_shell/` (`SCRIPTS.md` lists them) are synced the same way into every project that has `build_shell/project.conf`; what a project does differently is in its `project.conf`, `phone.conf`, `release/release.conf`, `helpers/project.sh` and `custom/`, which the sync never touches (`build_shell/PROJECT.md`). They are identical in every project: keep project-specific content out of them. The test-instance values of a project (checkout, branch, hooks, saves, servers) go to its own `md/TEST_INSTANCES.md`, project-specific script behaviour to `build_shell/test/test_instance_project.sh`; the sync never touches either.

`bridge/` (the SDK bridge) is identical in every project that has it and is synced by `$HOME/my_shell/sync_defold_bridge.py` (the edited copy wins). Nothing in it may require project code: project-specific behaviour is set from the project's bridge setup (for example `bridge.mock` `set_save_appname` / `set_save_writer`). A change of its API means updating the callers in every project that has the folder.

`defigma/` (the Defigma runtime: Lua modules, materials, the `DefigmaShape` native extension and its editor plugin) is identical in every project that has it and is synced by `$HOME/my_shell/sync_defold_defigma.py` (the edited copy wins; `--source <project>` makes every copy match one project). Nothing in it may name project code or project paths. A change of its API means updating the callers in every project that has the folder.

## Worktree

Every task that changes files is done in your own worktree, without being asked; read `md/shared/PARALLEL_TEST_INSTANCES.md` and follow it. Work directly in the main checkout only when I allowed it for that task.

- Create the checkout with `build_shell/test/agent_worktree.sh <name>` and keep every edit there, on its `agent/<name>` branch.
- Verify through a `build_shell/test/test_instance.sh` build and the `automation-bridge` skill attached with `engine.connect(<ENGINE_PORT>)` whenever the "build only large changes" rule above calls for a build: then the task is finished when the built instance shows the change working, not when the diff looks right.
- Build only from that checkout, with `build_shell/test/test_instance.sh` started from its root, so what runs is that branch. Never build a worktree branch from the main checkout or from another agent's checkout.
- When the task is done and verified, always merge it into the integration branch (`dev` in every project unless the user explicitly requests another branch): commit on `agent/<name>`, then merge that branch from the main checkout. If the merge is refused or conflicts with my uncommitted changes, stop and tell me.

## Clarifications

If you have any questions or something is not clear, you need more information - ask me about it.

## API

Before writing code, read `md/shared/API.md`.
