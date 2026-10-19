# Cloud Sessions

Read this only when running as a Claude Code cloud session (`CLAUDE_CODE_REMOTE=true`): an ephemeral Linux container on claude.ai with a fresh clone of the repository, no GPU, no access to my computers. Everything here replaces the matching part of `AGENTS.md` and `md/shared/PARALLEL_TEST_INSTANCES.md` for that session; the rest of `AGENTS.md` applies unchanged.

This document and `build_shell/test/cloud/` are shared by every Defold project and synced by `$HOME/my_shell/sync_defold_docs.py`: keep project-specific content out of them.

## First thing in a session

Read `/var/log/defold_cloud_setup.status`. It lists every step of the setup script with `ok` or `FAIL`; the details are in `/var/log/defold_cloud_setup.log`. When a step failed, a tool is missing or a version does not fit the project (the project pins another bob or another Blender, the exporter lacks what the export needs), see "When something is broken" before starting the task.

## What the container has

Installed by the setup script `build_shell/test/cloud/setup.sh`:

- Java 25 (default `java`); bob of every version in `DEFOLD_VERSIONS` and in `/home/user/*/build_shell/bob.sh` at `~/defold_engines/<version>/bob.jar`.
- Blender `BLENDER_VERSION` at `/opt/blender-<version>-linux-x64/blender`, the path the project scripts use; the Reforge exporter from `REFORGE_REPO` as the extension `bl_ext.user_default.reforge`.
- Xvfb with Mesa llvmpipe (software OpenGL), `x11-utils`, `xdotool`, `ffmpeg`.

Not there:

- **Figma.** There is no Figma, no Figma plugin bridge and no Defigma server. A task that needs anything in Figma (a design change, an export, `figma.py shot`, a check of a screen's look) is not done here: do the rest, then hand the Figma part to a local agent — queue it with `spawn_task` when that tool exists (I start it on my computer), otherwise write the prompt for it in the reply. The prompt stands alone: what to change in Figma, which file and frame, what to export, what to check.
- The local skills (`automation-bridge`, `lua-check`, `defold-gui`, `nakama-db`, `gc-profile`) when they are not in the session's skill list. Drive the game with the Python client in `automation-bridge-python/` directly (below). Without `lua-check`, say in the report that the Lua diagnostics were not run.
- Test hosts, the LAN, the local Extender, `~/defold_test_host`, my servers: `TEST_HOST`, `TEST_BUILD_SERVER=local` and `TEST_PERF=1` do not apply (`instance.sh` sets `TEST_BUILD_SERVER` to its proxy).
- A GPU and a sound device: the game renders on the CPU (a 3D scene runs at about 20 fps on 4 cores), so frame times and FPS mean nothing here, and clips have no sound (`TEST_SOUND=1` checks are for a local agent).

## Rules that change

- **No worktree.** The session is already its own checkout on the branch the session names; work, build and commit there. Do not run `agent_worktree.sh`, do not merge into the integration branch: commit and push to the session branch, and the merge is mine.
- **Build and run** with `build_shell/test/cloud/instance.sh` from the checkout root instead of `test_instance.sh`: the same arguments and `TEST_*` switches, the same output (`ENGINE_PORT`, `ENGINE_LOG`, `ENGINE_DISPLAY`), the same `bundle_project` of `test_instance_project.sh`. The first build compiles the native engine on build.defold.com (about 5 minutes); later builds reuse it while no native code changes.
- **Drive the game** with the Python client:

  ```sh
  PYTHONPATH=automation-bridge-python python3 - <<'EOF'
  from automation_bridge import engine
  game = engine.connect(<ENGINE_PORT>)
  shot = game.screenshot(wait=True)
  print(shot.path)
  EOF
  ```

  The project's own test scripts (`automation_scripts/` and the like) work the same way with `--port=<ENGINE_PORT>`. Video is `build_shell/test/record.py`, unchanged.
- **Show the result.** I cannot see the container: send every screenshot, clip and render that the task's check rests on with `SendUserFile`, and put the files you send in the scratchpad.
- **Blender** runs headless with the project's Blender scripts as they are; a picture of a scene is a Cycles render on the CPU from a script of your own (`blender -b <file>.blend --python <script>`), sent like a screenshot.

## How the workarounds work

The cloud network goes through an egress proxy; `instance.sh` sets up three things around `test_instance.sh`:

- `deps.py`: the GitHub proxy of the session answers 403 to archive downloads of repositories that are not attached to the session (every `dependencies#N` of `game.project`), while `git clone` of a public repository works. The script clones each dependency into `~/.cache/defold_cloud_deps`, packs it with `git archive` into the file bob would have written (`.internal/lib/<sha1 of the url>-<base64url etag>.zip`) and bob builds without `resolve` (`TEST_RESOLVE=0`, honoured by `bob_commands` of `test_instance.sh`). A new dependency needs nothing: the next run packs it.
- `extender_proxy.py`: the Extender client of bob ignores the proxy settings and cannot resolve build.defold.com in a container without DNS, so bob builds against `http://127.0.0.1:9100` (`TEST_BUILD_SERVER`) and the script forwards every request to build.defold.com through the proxy. Its log is `/tmp/extender_proxy.log`.
- `TEST_SOFTWARE_GL=1`: `run-test-env` starts the engine with `--software` (llvmpipe) instead of VirtualGL.

## Setup script

`build_shell/test/cloud/setup.sh` is the text pasted into the environment settings on claude.ai (cloud environment menu, Edit, Setup script); it runs as root in every new container before the session starts. The versions are at its top: `DEFOLD_VERSIONS`, `BLENDER_VERSION`, `REFORGE_REPO`. It never fails the container: a failed step is written to the status file and the session goes on.

## When something is broken

Anything that stops the work from starting as described here — a failed setup step, a missing package, bob or Blender of the wrong version, a host the network refuses, a cloud script that no longer works — is fixed once, for every later session and every project:

1. Fix it in this container so the task can go on (install the package, fetch the right version).
2. Make the same fix in `build_shell/test/cloud/setup.sh` (or in the cloud script that broke) and in this document, and commit it with the task.
3. Say in the reply, in a short section of its own, what changed and that the setup script has to be pasted into the environment settings again (give the whole new text when it changed), so I sync it into every project.

A host refused by the network (403 from the proxy) is not worked around: name the host, I allow it in the environment settings.
