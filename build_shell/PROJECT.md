# Defigma_Defold build files

What the project files of `build_shell/` (see `SCRIPTS.md`) do in Defigma_Defold. Not synced.

No store release, no liveupdate, no local server and no iOS signing yet: `project.conf` keeps those keys empty (an Android phone build signs with the debug keystore of bob), `phone.conf` points the phone builds at the remote server, `release/release.conf` releases nothing, `helpers/project.sh` redefines no hook. Fill them in when the game goes to a store.

