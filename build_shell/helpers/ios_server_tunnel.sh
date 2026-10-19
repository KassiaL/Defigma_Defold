#!/usr/bin/env bash

# Runs on the Mac: forwards <port> + 10000 (phone_port of helpers/phone.sh) on the Mac's address to <port> of the PC (the host `sergey` of
# the Mac's ssh config, or IOS_SERVER_SSH_HOST) for every port given, so the iPhone reaches the local
# server of the PC through the Mac. The tunnel is a launchd job: it outlives the ssh session of the build.
#
# usage: ios_server_tunnel.sh <mac address> <port>...

set -euo pipefail
mac_host=$1
shift
forwards=()
for port in "$@"; do
	forwards+=(-L "$mac_host:$((port + 10000)):127.0.0.1:$port")
done
label=com.defold.phone-server-tunnel
log_dir="$HOME/Library/Logs/phone-server-tunnel"
mkdir -p "$log_dir"
if launchctl list "$label" >/dev/null 2>&1; then
	launchctl remove "$label"
	sleep 1
fi
launchctl submit -l "$label" -o "$log_dir/tunnel.log" -e "$log_dir/tunnel-error.log" -- /usr/bin/ssh -N \
	-o ExitOnForwardFailure=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=3 "${forwards[@]}" "${IOS_SERVER_SSH_HOST:-sergey}"
for port in "$@"; do
	for _ in $(seq 10); do
		nc -z -w 1 "$mac_host" "$((port + 10000))" && break
		sleep 1
	done
	nc -z -w 1 "$mac_host" "$((port + 10000))" || { echo "error: the tunnel to port $port of the PC is not up, see $log_dir" >&2; exit 1; }
	printf 'Local server port %s at %s:%s\n' "$port" "$mac_host" "$((port + 10000))"
done
