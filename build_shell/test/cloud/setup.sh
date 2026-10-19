#!/usr/bin/env bash
# Setup script of the Claude Code cloud environment (environment settings -> Setup script): prepares a fresh
# container for every Defold project before the session starts. The text pasted into the settings is a copy
# of this file; after changing it here, paste it there again (md/shared/CLOUD.md, "Setup script").
# Never fails the container: every step logs to /var/log/defold_cloud_setup.log, and the steps that failed
# are listed in /var/log/defold_cloud_setup.status, which the session reads first.
# Shared by every Defold project and synced by sync_defold_docs.py.

DEFOLD_VERSIONS="1.14.0"
BLENDER_VERSION="5.2.1"
REFORGE_REPO="https://github.com/KassiaL/reforge.git"

log=/var/log/defold_cloud_setup.log
status=/var/log/defold_cloud_setup.status
: >"$log"
: >"$status"

step() {
	local name=$1
	shift
	echo "== $name" >>"$log"
	if "$@" >>"$log" 2>&1; then
		echo "ok   $name" >>"$status"
	else
		echo "FAIL $name (exit $?)" >>"$status"
	fi
}

apt_packages() {
	export DEBIAN_FRONTEND=noninteractive
	apt-get update -qq
	apt-get install -y -qq openjdk-25-jdk-headless xvfb libgl1-mesa-dri libglu1-mesa libopenal1 \
		x11-utils xdotool ffmpeg pulseaudio-utils \
		libxi6 libxkbcommon0 libsm6 libxrender1 libxxf86vm1 libxfixes3 libegl1
	update-alternatives --set java /usr/lib/jvm/java-25-openjdk-amd64/bin/java
}

project_defold_versions() {
	cat /home/user/*/build_shell/bob.sh 2>/dev/null | sed -n 's/^defold_version=//p'
}

bob_jars() {
	local version
	for version in $(printf '%s\n' $DEFOLD_VERSIONS $(project_defold_versions) | sort -uV); do
		mkdir -p "$HOME/defold_engines/$version"
		[ -s "$HOME/defold_engines/$version/bob.jar" ] ||
			curl -fsSL -o "$HOME/defold_engines/$version/bob.jar" \
				"https://github.com/defold/defold/releases/download/$version/bob.jar"
	done
}

blender() {
	local dir="/opt/blender-$BLENDER_VERSION-linux-x64"
	[ -x "$dir/blender" ] ||
		curl -fsSL "https://download.blender.org/release/Blender${BLENDER_VERSION%.*}/blender-$BLENDER_VERSION-linux-x64.tar.xz" |
		tar xJ -C /opt
	"$dir/blender" -b --version | head -n1
}

reforge() {
	local extensions="$HOME/.config/blender/${BLENDER_VERSION%.*}/extensions/user_default"
	rm -rf /tmp/reforge "$extensions/reforge"
	git clone -q --depth 1 "$REFORGE_REPO" /tmp/reforge
	mkdir -p "$extensions"
	cp -r /tmp/reforge/reforge "$extensions/reforge"
	rm -f "$extensions"/reforge/*.zip
}

step "apt packages, java 25" apt_packages
step "bob.jar" bob_jars
step "blender $BLENDER_VERSION" blender
step "reforge" reforge
cat "$status"
exit 0
