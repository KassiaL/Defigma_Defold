# Parallel Test Instances

Several agents work on the project at the same time. Every agent needs its own checkout, so builds never clobber each other; projects that keep saves or server accounts also give every checkout its own save folder and account (see `Project Settings`).

This document is shared by every Defold project and synced by `$HOME/my_shell/sync_defold_docs.py`. Everything except the last section is project independent; `Project Settings` holds the values of the current project, and the sync keeps that section of each project as it is.

The scripts are shared the same way: `build_shell/linux_test.sh`, `build_quiet.sh`, `run-test-env`, `agent_worktree.sh` and `agent_worktree_clean.sh` are identical in every project and overwritten by the sync, so never put project-specific code into them. What differs per project lives in `build_shell/linux_test_project.sh`, which the shared scripts source when it exists and the sync never touches: how the bundle is built (`bundle_project`), the bundle folder and the folder the engine starts in, extra engine arguments per instance (`project_engine_args`), the per-instance save folder (`save_root`, `save_name`) and the test output a worktree leaves behind (`worktree_output_dirs`). The header of `linux_test.sh` lists these hooks.

## Rules

- When I ask for work in your own worktree, that checkout is the only place you edit, build, run and test. The `agent/<name>` branch is the working branch until the task is merged.
- Always build with `build_shell/linux_test.sh` and always verify through the `automation-bridge` skill attached with `engine.connect(<ENGINE_PORT>)` (see `Driving the instance`). A worktree task is not finished on the diff: it is finished when the built instance shows the change working. This overrides the general "build only large changes" rule - asking for worktree work is asking for the build.
- The build always runs from the worktree root. The build scripts derive the project directory from their own location, so what they bundle is the branch checked out next to them. Never build a worktree branch from the main checkout, never build another agent's checkout, and never switch the branch of a checkout to build something else.
- Never build two branches in one directory. `bob` and the build scripts write `build/`, `.internal/` and `bundles/` (plus the files listed in `Project Settings`); two builds in one directory clobber each other and the damage shows up later as an unexplained runtime error.
- When the task is done and verified, merge it into the integration branch (see `Merging the work back`).

## Creating the checkout

```sh
build_shell/agent_worktree.sh <name>
```

Creates `<parent of the main checkout>/worktrees/<project-dir>-<name>` on branch `agent/<name>`, always next to the main checkout - calling it from inside a worktree makes a sibling, not a nested one - and copies the resolved dependency cache into it, which is the slow part of a fresh checkout. It prints `WORKTREE=<path>`. Running it again for an existing name resets that branch to the new base. Every worktree lives in that one folder next to the projects, so finished ones can be thrown away without picking them out from between the real checkouts.

## Building and running

```sh
cd <worktree>
build_shell/linux_test.sh
```

- Bundles the `x86_64-linux` debug build with the automation bridge extension (plain `bob` into `bundles/linux` unless `linux_test_project.sh` says otherwise) and starts it with `display.vsync=0` and `display.update_frequency=60`. `build_shell/build_quiet.sh` is the same with the bob noise filtered out.
- Prints `ENGINE_PORT=<port>`, `ENGINE_LOG=<path>` and `ENGINE_DISPLAY=:<n>`. The log is `<worktree>/.internal/linux_test/engine.log`.
- The engine service port is dynamic, the pid is kept in `<worktree>/.internal/linux_test/engine.pid`, so starting an instance stops the previous engine of that checkout only and never touches the engine of another agent.
- The game never appears on my desktop: the engine is started through `build_shell/run-test-env`, which gives every instance its own invisible X display - an Xvfb server named after the instance - and renders OpenGL on the GPU through VirtualGL. The game runs at full frame rate there, and bridge input and screenshots work as usual. The display closes by itself when the engine exits. `LINUX_ON_DESKTOP=1` starts the engine on my real display instead; use it only when I ask to watch the game.
- Anything else that talks to X for the instance (`xdotool`, `xwininfo`, `ffmpeg -f x11grab`, a recording tool) must run with `DISPLAY=<ENGINE_DISPLAY>`; never move an engine window to `:0`. Another process that has to run in the same environment - a second engine for a two-account test - is started as `build_shell/run-test-env --name <instance> <command>` with a name of its own; `build_shell/run-test-env --list` shows the running environments, `--stop <name>` closes one.
- The machine needs Xvfb and VirtualGL; how to install them, and why this setup, is written at the top of `build_shell/run-test-env`. When the script reports that one of them is missing, stop and tell me instead of falling back to the desktop display.
- Start the instance muted unless the task checks sound. Arguments after `linux_test.sh` go to the engine, so `build_shell/linux_test.sh --config=sound.gain=0` mutes the Defold mixer; when `Project Settings` names another way for this project, use that one instead.

Environment switches:

| Variable | Effect |
| --- | --- |
| `LINUX_INSTANCE=<id>` | Overrides the instance id (default: the checkout folder name); it names the X display and, where the project has them, the save folder and the server account |
| `LINUX_RESET=1` | Deletes the save folder of that instance before building (projects with per-instance saves) |
| `LINUX_CLEAN=1` | Forces a clean bob build |
| `LINUX_BUILD_ONLY=1` | Bundles without launching |
| `LINUX_LAUNCH_ONLY=1` | Launches the existing bundle without building |
| `LINUX_ON_DESKTOP=1` | Starts the engine on my real display (only when I ask to watch) |

## Saves and accounts

How an instance stores its progress is described in `Project Settings`. When it has an instance id, the id defaults to the checkout folder name and each checkout gets its own save folder (and its own server account, if the game has one). When every instance shares one save or one account, never run two instances that write it at the same time: the server keeps one live session per account, so two clients signed in as the same account kick each other out.

## Driving the instance

The `automation-bridge` skill talks to the engine over the bridge port, not through the editor - the editor is bound to the main checkout and would build the wrong branch:

```python
from automation_bridge import engine

game = engine.connect(<ENGINE_PORT>)
```

In a worktree never call `editor.open_project`, `project.build_and_run`, `project.clean_build_and_run` or `project.connect_engine`: the editor either builds the main checkout or starts a second editor on the worktree, and neither runs the `linux_test.sh` bundle.

Stop an instance through the bridge, never with `kill`: `game.close_engine()` posts `@system/exit` to the engine, so it shuts itself down.

Rebuild with `build_shell/linux_test.sh` after every Lua or resource change: the script stops the previous engine of that checkout itself and starts the new bundle. Hot reload through the editor is not an option here, and it invalidates registered bridge commands anyway.

Registered commands and published states are listed in `md/AUTOMATION_COMMANDS.md`; use them to reach a screen or a state instead of clicking through the whole UI.

## Merging the work back

The branch is not the deliverable, the integration branch is. When the task is finished and verified in the instance:

1. Commit everything on `agent/<name>` inside the worktree.
2. Merge from the main checkout, the one that keeps the integration branch checked out: `git -C <main checkout> merge agent/<name>`.
3. The main checkout usually carries my own uncommitted changes. Git aborts the merge instead of overwriting them; if that happens, or the merge conflicts, stop and tell me - do not stash, reset or revert my files.

A merged worktree is disposable - nothing ever returns to it, a later task creates its own - so it can be thrown away as soon as the branch is merged:

```sh
build_shell/agent_worktree_clean.sh            # every worktree of this project
build_shell/agent_worktree_clean.sh <name>     # only that agent
build_shell/agent_worktree_clean.sh -n         # list what would go, remove nothing
```

It stops the engine a worktree still runs, then removes the worktrees git knows about, the branch of each one, their instance save folders and their test output (both from `linux_test_project.sh`). What it never touches without being told: a worktree with uncommitted changes (`-f` overrides), a branch that is not merged (it says so and keeps it), the worktree it is called from - run it from the main checkout to remove that one - and the save folder of the plain build (`--include-main-save`). Skip the question with `-y`, dry run with `-n`.

## Project Settings

The values of this project. The sync never overwrites this section; rewrite it by hand for each project.

- Main checkout: `$HOME/defold_projects/Defigma_Defold`, integration branch `main`.
- No `build_shell/linux_test_project.sh` yet: the shared scripts build a plain bob bundle into `bundles/linux` with no extra engine arguments and no per-instance saves. Add the hook file when the project needs more (an instance config, its own save folder).
