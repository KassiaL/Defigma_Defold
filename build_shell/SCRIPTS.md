# Build Shell Scripts

The build scripts of every Defold project that has `build_shell/project.conf`. This file and every script it describes are identical in all those projects and overwritten by `$HOME/my_shell/sync_defold_docs.py`: never edit them for one project. What a project does differently lives in the files the sync never touches, described in its own `build_shell/PROJECT.md`.

```
build_shell/
  android_wireless.sh  ios_wireless.sh   the phone builds, over Wi-Fi
  liveupdate.sh                          dev liveupdate publish
  play.sh                                desktop build to play, with sound
  adb_logs.sh                            Defold log of the connected Android phone
  dev/                                   the phone builds with a local liveupdate
  release/                               store release: release_all_platforms.sh, liveupdate.sh, bump_all_versions.sh
    helpers/                             Mac and store helpers of the release
  helpers/                               sourced or called by the scripts above, never run by hand
  git/remove_git_file.sh                 untracks a file, keeping it on disk
  test/                                  the agents' builds (md/shared/PARALLEL_TEST_INSTANCES.md)

  project files, not synced:
  project.conf                           the values of the project
  phone.conf                             the server of the phone builds
  release/release.conf                   what a release ships
  helpers/project.sh                     the hooks of the project
  helpers/build_servers.conf             where the Android engine is built
  play_project.sh                        overrides of play.sh
  test/test_instance_project.sh          overrides of test_instance.sh
  custom/                                the project's own scripts
  PROJECT.md                             what all of these do in this project
```

Every build script stops with an error when `$bob` (the `bob.jar` of the project's Defold version) is not in the environment.

Everything under `release/` builds or publishes what reaches a store or the production liveupdate: it requires `release_branch` and a clean working tree. `liveupdate.sh` requires `dev_branch`. The phone builds and `test/test_instance.sh` publish nothing and run on any branch, which keeps the agent worktrees buildable.

## Project files

`project.conf` holds values only, every key present (an empty value where the project has none): `release_branch`, `dev_branch`; the Android vendors (`android_release_vendor` of the store build, `android_dev_vendor` of the dev and phone builds), their settings files (`android_release_settings`, `android_dev_settings`, `ios_settings`, relative to the project root) and architectures; the keystore (`keystore`, `keystore_alias`, `keystore_password_file`, `key_password_file`; an empty `keystore` builds with the debug keystore of bob); `store_api_dir` (`google_play.json`, `appstore/appstore.p8`, `appstore/other.json` and the `asc` module of the App Store Connect API); the Mac values of the iOS builds (`mac_checkout`, the development and distribution certificates with their password files, identities and profile names); the liveupdate values (`game_version_file` and `game_version_pattern`: the file and the regular expression whose first group is the game version, which names the liveupdate folder and which `bump_all_versions.sh` raises; `liveupdate_bundle_resource_dirs`: the bundle resource folders the archives are mirrored into); the Telegram chat and bot of the notifications.

`helpers/project.sh` redefines the hooks the project needs; the list and the defaults (nothing, or an error for the liveupdate ones) are in the header of `helpers/build_helpers.sh`. A project without liveupdate leaves out the liveupdate hooks, sets `release_liveupdate=no` and an empty `game_version_file`.

`custom/` holds the scripts only one project has (desktop and html5 builds, scene exports, deploys); the sync never touches it.

## Phone builds

`android_wireless.sh [--address <ip:port>]` and `ios_wireless.sh` put the phone build of the working tree (uncommitted and untracked files included) on the phone over Wi-Fi: `export_android_phone` / `export_ios_phone`, the automation bridge kept (`KEEP_AUTOMATION_BRIDGE=1`), no liveupdate, every resource inside the package, the installed app replaced without clearing its data.

`phone.conf` says which server they talk to: `phone_server=local` is the server of this PC (`phone_server_ports`), `remote` the production one. `phone_settings <address>` prints the bob settings of the build; `phone_port <port>` (`helpers/phone.sh`) is `<port> + 10000`, the port the phone reaches port `<port>` of the local server at, since neither Android (`adb reverse`) nor the Mac (ssh tunnel) may listen below 1024. `android_phone_setup` / `android_phone_restore` run in the project root around the Android build. All three default to nothing (`helpers/phone.sh`), so a project on the remote server only sets `phone_server=remote`.

- Android (`helpers/phone.sh`): without `ANDROID_SERIAL` the script runs again through `helpers/adb_wifi.sh`, which connects the phone of Wireless debugging (Android 11+; pair once with `helpers/adb_wifi.sh pair <ip:port> <code>` from the pairing dialog, the connection port is the one of the main Wireless debugging screen) and refuses an ambiguous choice; `--address` picks one, an `ANDROID_SERIAL` set beforehand (a USB phone) skips the lookup. The build reaches the local server at `127.0.0.1` through `adb reverse`, which works over Wi-Fi as well. Before installing it removes `files/liveupdate.mounts` and `files/liveupdate_archives` of the installed app, then installs, starts it and shows `adb logcat -s defold` (Ctrl+C stops the log). Different signing keys still require uninstalling by hand; a MIUI phone asks to confirm the installation on its screen.
- iOS (`helpers/mac.sh`, `helpers/ios_phone_build.sh`): the working tree becomes a commit that no branch points at (`working_tree_commit`), pushed into `~/<mac_checkout>` on the home Mac (`ssh macbookair`, `md/shared/TEST_HOSTS.md`) with `bob.jar`; the Mac builds it there and installs it with `xcrun devicectl` (`helpers/ios_wifi_install.sh`, Wi-Fi or USB; `ios-deploy` cannot reach an iOS 17+ device over Wi-Fi) on `IOS_DEVICE_UDID` or the first available iPhone. The Mac login keychain is locked in an ssh session and `~/Documents` is closed to it, so signing uses the development certificate of `project.conf` in a throwaway keychain (`release/helpers/setup_ios_signing.sh`) and the development profile downloaded through the App Store Connect API. A new test device must be registered in App Store Connect and the profile regenerated with it. With the local server the Mac opens an ssh tunnel to this PC (`helpers/ios_server_tunnel.sh`, launchd job `com.defold.phone-server-tunnel`, the host `sergey` of the Mac's ssh config or `IOS_SERVER_SSH_HOST`, logs in `~/Library/Logs/phone-server-tunnel/`): the iPhone reaches the local server at `<port> + 10000` of the Mac's `en0` address.

`dev/android_wireless_local_liveupdate.sh` and `dev/ios_wireless_local_liveupdate.sh` are the same builds with liveupdate, all of it local, to watch the liveupdate flow: the first pass of the Android phone build produces `liveupdate.zip`, `pack_liveupdate` packs it where the local server serves the dev liveupdate (`project_liveupdate_target`), and the package leaves the archives out, so the phone downloads and mounts them from this PC. They need `phone_server=local`. The iOS package is built from the archives of the Android pass, as in a release.

`adb_logs.sh` tails the Defold log of the connected Android phone.

`play.sh` builds a desktop debug bundle into `bundles/play` (`build/play`) and launches it with sound; it is the person's build, never the agents'. `play_project.sh`, when present, may set `engine_cwd`, prepend engine arguments and replace `bundle_project`. The script launches the bundle's `game.projectc`, keeping the editor's `build/default` resources out of this run. `PLAY_CLEAN=1` forces a clean build, `PLAY_BUILD_SERVER` picks the build server; arguments are forwarded to the engine.

## Shared shell

`helpers/bob_env.sh` reads `project.conf` and `release/release.conf` and defines the `export_*` functions: `export_android_release` (the store AAB, `liveupdate` from `release_liveupdate`), `export_android_dev` (the dev APK with liveupdate), `export_android_phone` (`export_android_dev` without liveupdate, with `KEEP_AUTOMATION_BRIDGE=1`), `export_ios_release` and `export_ios_phone`. Each sets `vendor`, which the hooks read. `project_title` is `project.title` as written; `dir_build_after_bob_jar` is the same title with its spaces stripped, which is how the Android bundler names the package folder and the executable; the iOS bundler keeps the spaces, so `ipa_path` is built from `project_title`. `helpers/game_project.py get <section.key>` reads `game.project`, `bump` raises `android.version_code`, `ios.bundle_version` and the last number of `project.version`.

`helpers/build_helpers.sh` holds the functions of every build. `run_bob` wraps every bob run in `project_build_start` / `project_build_finish`, and copies `game.project` before and writes the copy back after, from an EXIT trap of the subshell it runs in, so the file comes back byte for byte after a finished, failed or interrupted (Ctrl-C) build; the trap belongs to that subshell, so the EXIT traps of the calling scripts still run. `build_android_liveupdate_bundle` is the two-pass liveupdate build: it empties the bundle resource folders, runs `run_android_bundle`, packs the resulting `liveupdate.zip` (which refills those folders), and `run_android_rebundle` repackages with the build folder untouched so the package carries the archives. `pack_liveupdate` packs into `project_liveupdate_target` at most once per build session (`liveupdate_packed` is exported, so the nested `release/liveupdate.sh --skip-build` of a release publishes without repacking). `publish_liveupdate <title>` packs, runs `project_publish_liveupdate` and sends the Telegram message with the game version, the manifest version, the changed and total archives and the download size for existing clients.

`helpers/pack_liveupdate.py` unpacks the `liveupdate.zip` produced by bob, splits it into content-versioned archives (`<archive>_<hash>.arcd0` + `manifest.json` + `archive_sizes.json`) through `helpers/liveupdate_pack.py`, and copies the result into `<target>/<game version>`, so every client generation publishes into its own folder and a release never moves the content older clients download. Archives whose content did not change keep their name, so they are neither re-uploaded nor re-downloaded by clients; previously published archives are never deleted, so clients that already fetched an older manifest keep working. It mirrors the archives into the `liveupdate_bundle_resource_dirs` as `<archive>_<hash>.zip` (the extension the Android bundler stores uncompressed), so the next bundling pass ships them as bundle resources; `--clear-bundle-resources` empties those folders and exits. It prints `LIVEUPDATE_GAME_VERSION`, `MANIFEST_VERSION`, `ARCHIVES_TOTAL`, `ARCHIVES_CHANGED`, `ARCHIVES_BUNDLED`, `TOTAL_MB` and `CHANGED_MB`. `helpers/liveupdate_pack.py` reads the bob manifest through `helpers/liveupdate_ddf_pb2.py` (generated from `helpers/liveupdate_ddf.proto`, needs the Python `protobuf` module) and refuses resources with identical content, listing them. `send_telegram_message` posts HTML to the chat of `project.conf`. The guards are `require_release_build` (`release_branch`, clean tree) and `require_dev_build` (`dev_branch`). `send_telegram_message` sends nothing when `telegram_chat_id` is empty.

`helpers/build_servers.conf` is the switch for where the Android engine is built: `debug_build_server` and `release_build_server` take a choice of `helpers/build_server.sh` (`build_server_url`): `auto` takes the local Extender at `http://localhost:9000` when its `/actuator/health` answers within 2 s and otherwise builds on `build.defold.com` with a line on stderr; `local` fails the build when the Extender does not answer; `cloud` is `build.defold.com`; a url is that server. A `beta_*` bob always builds on `build-stage.defold.com`. The release export reads `release`, the dev and phone exports `debug`; iOS always builds on the cloud, the local Extender builds no iOS. `require_clean_working_tree` ignores that file, so switching it does not block a release.

## Release

`release/release.conf` says what `release/release_all_platforms.sh` releases: `release_platforms` (`android` for Google Play, `ios` for the App Store, or both) and `release_liveupdate` (`yes`: the liveupdate content is published and the packages ship the archives as bundle resources; `no`: every resource ships inside the packages and nothing is published).

`release/release_all_platforms.sh` must run on a clean `release_branch`. It runs `project_release_checks`, bumps the versions (`release/bump_all_versions.sh`), asks the stores that they do not hold the bumped versions (`release/helpers/check_store_version.py`), runs `project_before_release_commit`, commits `RELEASE` and pushes it to GitHub over ssh with `~/.ssh/github`. With liveupdate it builds the AAB with symbols here as the two-pass liveupdate build (the build the archives are packed from, also for an iOS-only release) and publishes liveupdate (`release/liveupdate.sh --skip-build`); without it, it builds the AAB in one pass, only when Android is released. Then it builds and uploads the iOS package on the home Mac (`release/helpers/build_on_mac.sh`) while it uploads the AAB to Google Play (`release/helpers/play_upload.py`), and notifies Telegram. Arguments: `--platforms "android ios"|android|ios` (overrides `release_platforms` for one run), `--skip-store-upload`, `--play-track production|beta|alpha|internal`, `--play-status draft|completed`.

`release/bump_all_versions.sh` requires a clean `release_branch`, bumps `game.project` (`game_project.py bump`), the game version of `game_version_file` when the project has one (`game_project.py bump-game-version`) and runs `project_bump_versions`.

`release/liveupdate.sh [--skip-build]` publishes the production liveupdate content and refuses to run when `release_liveupdate` is not `yes`. Without arguments it requires a clean `release_branch`, runs `project_validate_liveupdate`, builds the store vendor (so the archives are the ones the store packages ship) and publishes. With `--skip-build` it only publishes what the caller already packed, and checks the branch but not the tree: the build it continues has already left the files of `project_build_start` rewritten.

`liveupdate.sh` is the dev counterpart: `dev_branch`, the `android_dev_vendor` build, no clean tree, no `project_validate_liveupdate` (on the dev branch everything has changed since the last RELEASE commit by definition).

`release/helpers/build_on_mac.sh <commit> [--upload]` builds the iOS store package of one commit on the home Mac over ssh (`helpers/mac.sh`): it pushes the commit into `~/<mac_checkout>` with `bob.jar`, with liveupdate also `res/ios/liveupdate` (rsync), downloads the App Store profile through the App Store Connect API, and runs `release/helpers/setup_ios_signing.sh`, `release/helpers/build_ios_release.sh` and, with `--upload`, `release/helpers/appstore_upload.sh` on the Mac, with the distribution certificate in a throwaway keychain that is deleted when the build ends. It checks no branch.

`release/helpers/build_ios_release.sh` runs on the Mac: it bundles the ipa (`export_ios_release`, `run_ios_bundle`, which runs `project_before_ios_bundle`), checks its `CFBundleVersion` against `game.project`, runs `project_verify_ipa` and prints `IPA=<path>`. `release/helpers/setup_ios_signing.sh` runs on the Mac before any iOS build: it decodes the certificate and the profile the script of `helpers/mac.sh` carries into `$IOS_SIGNING_DIR`, puts the certificate into a throwaway keychain and verifies it with `security import` / `security find-identity` and the profile with `security cms`.

`release/helpers/check_store_version.py` asks Google Play for its uploaded version codes and App Store Connect for its builds before anything is signed or built, and fails the release when the store already holds this release's `android.version_code` or `ios.bundle_version` — both stores only reject a duplicate at the upload, which is a whole build too late. App Store Connect also wants a build strictly higher than its highest, so that is checked too.

`release/helpers/play_upload.py` uploads the AAB and its native symbols to Google Play through the Android Publisher API and creates the track release; it aborts before committing the edit if the bundle's `versionCode` does not match `game.project`. It is safe to run again for a release that is already up: a bundle Play already holds under that version code is reused when its sha256 matches the file and refused when it does not, and the track release replaces the draft that is there rather than adding a second one, inheriting its release notes and leaving the live release and any staged rollout alone. A dropped connection or a 429/5xx is retried with backoff: four times for an upload, five for an API call.

`release/helpers/appstore_upload.sh` runs on the Mac and uploads the IPA with `xcrun altool` and the App Store Connect API key.

## Other

`git/remove_git_file.sh` asks for paths relative to the git root in a loop and untracks each one (`git rm --cached`), keeping the file on disk.

`test/` holds the agents' builds: `test_instance.sh`, `build_quiet.sh`, `run-test-env`, `run-test-window.py`, `record.py`, `agent_worktree.sh`, `agent_worktree_clean.sh`, `defigma_twin.py`, `mute_macos.m` and `cloud/`, described in `md/shared/PARALLEL_TEST_INSTANCES.md`. `test_instance.sh` builds outside the project build stage of the scripts above (no `run_bob`, no hooks); what a project changes in it is in `test/test_instance_project.sh`.
