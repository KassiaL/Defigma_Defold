# Parallel Test Instances

Several agents work on the project at the same time. Every agent needs its own checkout, so builds never clobber each other; projects that keep saves or server accounts also give every checkout its own save folder and account (see `Project Settings`).

`build_shell/test/test_instance.sh` is the only way an agent builds and runs the game for a check - in a worktree and in the main checkout alike. `build_shell/test/play.sh` is the person's build, never the agents': it bundles the debug build of the platform it runs on into `bundles/play` (bob output `build/play`; `build_shell/test/play_project.sh`, when present, overrides `bundle_project` and `engine_cwd`) and starts it on the desktop with sound, in place of the editor's Build. The editor builds (`project.build_and_run`, `project.clean_build_and_run`, `project.connect_engine`, hot reload) are used only when I ask for them.

This document is shared by every Defold project and synced by `$HOME/my_shell/sync_defold_docs.py`. Everything except the last section is project independent; `Project Settings` holds the values of the current project, and the sync keeps that section of each project as it is.

The scripts are shared the same way: `build_shell/test/test_instance.sh`, `build_quiet.sh`, `run-test-env`, `run-test-window.py`, `mute_macos.m`, `play.sh`, `record.py`, `agent_worktree.sh`, `agent_worktree_clean.sh` and `defigma_twin.py` are identical in every project and overwritten by the sync, so never put project-specific code into them. What differs per project lives in `build_shell/test/test_instance_project.sh`, which the shared scripts source when it exists and the sync never touches: how the bundle is built for `$test_platform` (`bundle_project`), the bundle folder and the folder the engine starts in, extra engine arguments per instance (`project_engine_args`), the per-instance save folder (`save_root`, `save_name`), the ports of this PC the game needs when it runs on a test host (`main_host_ports`) and the test output a worktree leaves behind (`worktree_output_dirs`). The header of `test_instance.sh` lists these hooks.

## Rules

- Every task that changes files works in a worktree of its own by default, without being asked; the main checkout is edited directly only when I allowed it for that task. The worktree is the only place you edit, build, run and test. The `agent/<name>` branch is the working branch until the task is merged.
- Always build with `build_shell/test/test_instance.sh` and always verify through the `automation-bridge` skill attached with `engine.connect(<ENGINE_PORT>)` (see `Driving the instance`). When the change needs a build (the "build only large changes" rule of `AGENTS.md`), the task is not finished on the diff: it is finished when the built instance shows the change working.
- The build always runs from the worktree root. The build scripts derive the project directory from their own location, so what they bundle is the branch checked out next to them. Never build a worktree branch from the main checkout, never build another agent's checkout, and never switch the branch of a checkout to build something else.
- Never build two branches in one directory. `bob` and the build scripts write `build/`, `.internal/` and `bundles/` (plus the files listed in `Project Settings`); two builds in one directory clobber each other and the damage shows up later as an unexplained runtime error.
- When the task is done and verified, merge it into the integration branch (see `Merging the work back`).

## Creating the checkout

```sh
build_shell/test/agent_worktree.sh <name>
```

Creates `<parent of the main checkout>/worktrees/<project-dir>-<name>` on branch `agent/<name>`, always next to the main checkout - calling it from inside a worktree makes a sibling, not a nested one - and copies the resolved dependency cache into it, which is the slow part of a fresh checkout. It prints `WORKTREE=<path>`. Running it again for an existing name resets that branch to the new base. Every worktree lives in that one folder next to the projects, so finished ones can be thrown away without picking them out from between the real checkouts.

A project whose main checkout runs a Defigma web server under pm2 (the server the Figma plugins upload exports to) gets a twin of it for the worktree: `build_shell/test/defigma_twin.py`, called by the script, starts the same server under the pm2 name of the worktree folder, writing into the worktree, on a free port from 16900, prints `DEFIGMA_PORT=<port>` and writes the port to `<worktree>/.internal/defigma_port`; an export sent with that port (Figma Bridge: `defigma.export(nodes, { upload_port })`) lands in the worktree. `agent_worktree_clean.sh` deletes the twin with the worktree.

## Building and running

```sh
cd <worktree>
build_shell/test/test_instance.sh
```

- Bundles the debug build of the platform it runs on (`x86_64-linux` here) with the automation bridge extension (plain `bob` into `bundles/test_instance` unless `test_instance_project.sh` says otherwise) and starts it with `display.vsync=0` and `display.update_frequency=60`. `build_shell/test/build_quiet.sh` is the same with the bob noise filtered out.
- Prints `ENGINE_PORT=<port>`, `ENGINE_LOG=<path>` and `ENGINE_DISPLAY=:<n>`, or `ENGINE_HOST=<host>` instead of `ENGINE_DISPLAY` when the instance runs on a test host (see `Test hosts`). The log is `<worktree>/.internal/test_instance/engine.log`.
- The engine service port is dynamic, the pid is kept in `<worktree>/.internal/test_instance/engine.pid`, so starting an instance stops the previous engine of that checkout only and never touches the engine of another agent.
- The game never appears on my desktop: the engine is started through `build_shell/test/run-test-env`, which gives every instance its own invisible X display - an Xvfb server named after the instance - and renders OpenGL on the GPU through VirtualGL. The game runs at full frame rate there, and bridge input and screenshots work as usual. The display closes by itself when the engine exits. `TEST_ON_DESKTOP=1` starts the engine on my real display instead; use it only when I ask to watch the game.
- Never move an engine window to the desktop display `:0`; a tool that talks to X for a local instance runs with `DISPLAY=<ENGINE_DISPLAY>` (video does not need it: `record.py`). Another process that has to run in the same environment - a second engine for a two-account test - is started as `build_shell/test/run-test-env --name <instance> <command>` with a name of its own; `build_shell/test/run-test-env --list` shows the running environments, `--stop <name>` closes one.
- The machine needs Xvfb and VirtualGL; how to install them, and why this setup, is written at the top of `build_shell/test/run-test-env`. When the script reports that one of them is missing, stop and tell me instead of falling back to the desktop display.
- The sound of an instance never reaches the speakers, and nothing has to be passed for it. On Linux `run-test-env` gives every environment a PulseAudio/PipeWire null sink `test-<name>` next to its display and plays the game into it; `test_instance.sh` prints its monitor source as `ENGINE_AUDIO=test-<instance>.monitor`, and `record.py` (below) records it next to the picture. On macOS `test_instance.sh` re-signs the bundle ad hoc without the hardened runtime and injects `build_shell/test/mute_macos.m` (compiled there with `cc`, `DYLD_INSERT_LIBRARIES`), which sets the volume of every `AVAudioPlayerNode` of the engine to 0 before it plays; on Windows `run-test-window.py` mutes the audio sessions of the engine (`ISimpleAudioVolume`, as the Volume Mixer does). Neither touches the volume of the game (its `master` group), which the game may set itself, so the clips recorded there have no sound: a task that checks sound runs with `TEST_SOUND=1`, which picks a Linux computer. `TEST_ON_DESKTOP=1` plays on the speakers.

- Video is always `build_shell/test/record.py`, wherever the instance runs - it finds the engine of this checkout and picks the way to record by itself:

  ```sh
  build_shell/test/record.py start <clip>.mp4     # returns at once; drive the game meanwhile
  build_shell/test/record.py stop                 # prints CLIP=<path here> and CLIP_SOUND=yes|no
  build_shell/test/record.py <clip>.mp4 --seconds 5
  ```

  60 fps of the game window only. With `CLIP_SOUND=no` and a task that needs the sound, start the instance again with `TEST_SOUND=1`.
  The ffmpeg recording (Linux) encodes with libx264, which needs even sides: a window with an odd width or height (`game.resize(490, 1043)`) is not refused, the clip gets one black column or row added (490x1044) and `record.py` prints a warning; resize the engine to even sides when that edge matters. The game window is never resized by the script, since that would change the layout being recorded.

Environment switches:

| Variable | Effect |
| --- | --- |
| `TEST_INSTANCE=<id>` | Overrides the instance id (default: the checkout folder name); it names the X display and, where the project has them, the save folder and the server account |
| `TEST_RESET=1` | Deletes the save folder of that instance before building (projects with per-instance saves) |
| `TEST_CLEAN=1` | Forces a clean bob build |
| `TEST_BUILD_ONLY=1` | Bundles without launching |
| `TEST_LAUNCH_ONLY=1` | Launches the existing bundle without building |
| `TEST_ON_DESKTOP=1` | Starts the engine on my real display (only when I ask to watch); always local |
| `TEST_SOUND=1` | The task checks sound: only a Linux computer is picked, where the sound reaches the recording (see `Test hosts`) |
| `TEST_PERF=1` | The task measures performance (profiler, `gc-profile`, FPS, frame times): only this PC, where the numbers are compared (see `Test hosts`) |
| `TEST_HOST=local` / `<host>` | For the scripts, not for a task: forces this PC (no RAM check) or that test host. `ab_checkout.py` and a remote run use it |

## Test hosts

Before building, `test_instance.sh` chooses the computer through `~/defold_test_host/test_host.py pick` (one copy per computer, installed by `md/shared/TEST_HOSTS.md`; without it `test_instance.sh` cannot start). A computer fits with at least 6144 MB free (`MemAvailable`, `MIN_FREE_MB`: a clean bob build peaks at about 6 GB, an incremental one at about 4.6 GB, the engine itself takes about 400 MB; the peak is bob's native resource processing, not its Java heap, so `-Xmx` does not lower it); a UDP broadcast finds the other computers of the test network with their free RAM (no addresses to configure; any computer of the network can be the one an agent works on).

- This PC when it fits, as described above; else the other computer with the most free RAM - a Linux, Mac or Windows one, the instance muted on the last two.
- A task tells what it needs, never which computer: `TEST_SOUND=1` when it checks sound (only Linux fits, this PC first: only there the sound reaches the recording), `TEST_PERF=1` when it measures performance (only this PC fits: the Remotery profiler reaches only a local engine, and frame times of another computer do not compare). Both may be given together.

`python3 ~/defold_test_host/test_host.py hosts` prints what the broadcast finds. When no computer fits, the script prints why and exits with code 3: stop and tell me - never start the build another way (editor, `TEST_HOST`).

A remote run changes nothing for the agent:

- The test host gets the checkout as it is, uncommitted and untracked files included (a snapshot commit sent as an incremental git bundle), builds it with its own `build_shell/test/test_instance.sh` and starts the instance there. The build output streams into the local terminal.
- `ENGINE_PORT` is a local port: `engine.connect(<ENGINE_PORT>)`, commands, input, scene queries, `game.logs` and `log_stream` work as with a local engine, and a screenshot path points to a local copy in `<checkout>/.internal/test_instance/remote_files/`. `ENGINE_LOG` is a local mirror of the remote engine log.
- The run writes `<checkout>/.internal/test_instance/engine.port` (the local port) and `remote.json` (`alias` for `ssh`, `os`, the remote `display`, the remote `pid_file`) and prints `ENGINE_SSH=<alias>`: anything that has to work on the computer of the engine runs there over `ssh <alias>` with `DISPLAY=<display>`. A local run deletes `remote.json`.
- `engine.pid` holds the pid of the local forwarder (`test_host.py forward`); stopping it stops the remote engine, so the next `test_instance.sh` run and `agent_worktree_clean.sh` handle a remote instance like a local one. `game.close_engine()` works as usual.
- The game reaches the ports of this PC that `main_host_ports` names (local server, CDN) through relays on the LAN address of this PC; `project_engine_args` passes `TEST_MAIN_HOST` and `TEST_MAIN_PORT_<port>` to the client.
- What is the same and what is not, at a glance:

  | | This PC | Another computer (`ENGINE_HOST` printed) |
  | --- | --- | --- |
  | Bridge commands, input, scene, screenshots, logs | work | work the same; a screenshot path points to a local copy |
  | Video | `record.py` | `record.py`; the clip is copied here, without sound from a Mac or Windows |
  | Profiler, FPS, frame times | work | never there: `TEST_PERF=1` keeps the instance here |

- Video under the hood (`record.py` reads `remote.json`): on Linux ffmpeg `x11grab` of the engine window on its invisible display, over ssh on a test host, with the sound of `test-<instance>.monitor` of that computer; on a Mac (macOS 15+, needs the Screen Recording permission there) and on Windows the native recorder of the automation bridge (`/recording/start`), the clip coming back through the test host agent.
- On a Mac the game window opens on that machine's desktop; on Linux hosts it uses `run-test-env` as here, and on Windows `run-test-window.py` keeps the window on the user's desktop but invisible (layered alpha 1, click-through, no taskbar button, never focused, bottom of the Z order) at 60 FPS.

Adding a computer to the network and checking it is `md/shared/TEST_HOSTS.md`; every computer of the network reaches every other one by `ssh <alias>` too. The agent (`test_host.py agent`) answers only LAN addresses, keeps its checkouts, bob.jar copies and job logs in `~/defold_test_host` and starts by itself after every login. The header of `~/defold_test_host/test_host.py` describes the protocol.

## Saves and accounts

How an instance stores its progress is described in `Project Settings`. When it has an instance id, the id defaults to the checkout folder name and each checkout gets its own save folder (and its own server account, if the game has one). When every instance shares one save or one account, never run two instances that write it at the same time: the server keeps one live session per account, so two clients signed in as the same account kick each other out.

## Driving the instance

The `automation-bridge` skill talks to the engine over the bridge port, not through the editor - the editor is bound to the main checkout and would build the wrong branch:

```python
from automation_bridge import engine

game = engine.connect(<ENGINE_PORT>)
```

Never call `editor.open_project`, `project.build_and_run`, `project.clean_build_and_run` or `project.connect_engine` unless I ask for an editor build: in a worktree the editor either builds the main checkout or starts a second editor on the worktree, it never runs the `test_instance.sh` bundle, and it cannot move the build to a test host.

Stop an instance through the bridge, never with `kill`: `game.close_engine()` posts `@system/exit` to the engine, so it shuts itself down.

Rebuild with `build_shell/test/test_instance.sh` after every Lua or resource change: the script stops the previous engine of that checkout itself and starts the new bundle. Hot reload through the editor is not an option here, and it invalidates registered bridge commands anyway.

Registered commands and published states are listed in `md/AUTOMATION_COMMANDS.md`; use them to reach a screen or a state instead of clicking through the whole UI.

## Merging the work back

The branch is not the deliverable, the integration branch is. When the task is finished and verified in the instance:

1. Commit everything on `agent/<name>` inside the worktree.
2. Merge from the main checkout, the one that keeps the integration branch checked out: `git -C <main checkout> merge agent/<name>`.
3. The main checkout usually carries my own uncommitted changes. Git aborts the merge instead of overwriting them; if that happens, or the merge conflicts, stop and tell me - do not stash, reset or revert my files.

A merged worktree is disposable - nothing ever returns to it, a later task creates its own - so it can be thrown away as soon as the branch is merged:

```sh
build_shell/test/agent_worktree_clean.sh            # every worktree of this project
build_shell/test/agent_worktree_clean.sh <name>     # only that agent
build_shell/test/agent_worktree_clean.sh -n         # list what would go, remove nothing
```

It stops the engine a worktree still runs, then removes the worktrees git knows about, the branch of each one, their instance save folders and their test output (both from `test_instance_project.sh`). What it never touches without being told: a worktree with uncommitted changes (`-f` overrides), a branch that is not merged (it says so and keeps it), the worktree it is called from - run it from the main checkout to remove that one - and the save folder of the plain build (`--include-main-save`). Skip the question with `-y`, dry run with `-n`.

## Project Settings

The values of this project. The sync never overwrites this section; rewrite it by hand for each project.

- Main checkout: `$HOME/defold_projects/Defigma_Defold`, integration branch `main`.
- No `build_shell/test/test_instance_project.sh` yet: the shared scripts build a plain bob bundle into `bundles/linux` with no extra engine arguments and no per-instance saves. Add the hook file when the project needs more (an instance config, its own save folder).
