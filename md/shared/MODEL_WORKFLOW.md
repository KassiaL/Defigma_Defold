# External implementation workers

MiniMax M3 through Wormsoft is the default executor. Opus handles design decisions and independent visual/motion review. The user chooses any replacement model or provider.

## Local setup

OpenCode is installed with `npm install -g opencode-ai`. Its user configuration is `~/.config/opencode/opencode.json`: provider `wormsoft`, OpenAI-compatible base URL `https://ai.wormsoft.ru/api/gpt`, model ID `minimaxai/minimax-m3`, API key reference `{env:wormsoft_api}`. Never put the key in project files, prompts, reports or logs.

`~/.local/bin/minimax-task` exports the existing Bash variable `wormsoft_api` and calls `opencode run --model wormsoft/minimaxai/minimax-m3`. When the variable is absent from the process environment it starts interactive Bash to load the user's shell configuration. A valid key does not imply available credits. On authentication, quota or provider errors, stop and report the error; do not retry indefinitely or silently change models.

## Invocation

Create a worktree using the project's `build_shell/test/agent_worktree.sh`. Start the worker from that worktree. Store its task, event log and evidence outside the repository:

```bash
minimax-task --format json "$(cat /tmp/task/prompt.txt)" > /tmp/task/events.jsonl 2> /tmp/task/stderr.log
```

The task names the goal, fixed user requirements, checkout, allowed files, relevant docs/APIs/skills, acceptance checks, evidence directory and report path. Tell the worker to read local instructions, avoid further delegation and return only a concise report. Give it a whole implementation/check/fix unit, not individual edits. The orchestrator handles integration after checking the worker's report and diff. Resume an existing worker with OpenCode's `--session <id>` rather than reconstructing its investigation.

## Checks and evidence

Use scripts for known checks and return structured failures to the worker: check name, expected/actual values, relevant error excerpt and full log path. The worker fixes failures and repeats relevant checks. Lua edits require the `lua-check` skill; runtime checks use the `automation-bridge` skill, `build_shell/test/test_instance.sh` from the worktree root and `engine.connect(ENGINE_PORT)`. No editor build or hot reload. Exit code 3 stops the runtime check. Do not build or drive a checkout another worker owns.

The report contains changed files and commit, verdict per acceptance check, diagnostics status, unresolved issues, engine port and absolute evidence paths. Keep full logs and scene dumps out of the parent's context. Record motion with `build_shell/test/record.py`; provide the original video plus timestamped contact sheets/frames for independent motion review. The worker verifies behavior, not subjective visual quality. The parent sends the user's requirements and evidence paths to the visual reviewer and returns concrete findings to the same executor.
