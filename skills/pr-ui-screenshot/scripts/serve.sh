#!/usr/bin/env bash
# Starts (or reuses) a dev server on a given port and blocks until it answers HTTP.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

dir=""
port=""
command_template=""
ready_path="/"
timeout_sec=180
log_file=""
pid_file=""
stop=0

usage() {
	cat <<'USAGE'
Usage: serve.sh --dir <path> --port <n> --command <cmd> [options]
       serve.sh --stop --pid-file <path>

  --dir <path>        Working directory to run the dev server in.
  --port <n>          Port the server should listen on.
  --command <cmd>     Dev command. "{port}" is substituted when present;
                      otherwise PORT=<n> is exported.
  --ready-path <p>    Path polled until it answers (default "/").
  --timeout <sec>     How long to wait for readiness (default 180).
  --log <file>        Server output log (default <dir>/.pr-ui-screenshot-dev-<port>.log).
  --pid-file <file>   Where to record the PID (default alongside the log).
  --stop              Stop the server recorded in --pid-file.

Prints the base URL on stdout when the server is ready. If the port already
answers, the existing server is reused and no new process is started.
USAGE
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	--dir)
		dir="${2:-}"
		shift 2
		;;
	--port)
		port="${2:-}"
		shift 2
		;;
	--command)
		command_template="${2:-}"
		shift 2
		;;
	--ready-path)
		ready_path="${2:-}"
		shift 2
		;;
	--timeout)
		timeout_sec="${2:-}"
		shift 2
		;;
	--log)
		log_file="${2:-}"
		shift 2
		;;
	--pid-file)
		pid_file="${2:-}"
		shift 2
		;;
	--stop)
		stop=1
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		echo "Unknown arg: $1" >&2
		usage >&2
		exit 1
		;;
	esac
done

if [[ "$stop" -eq 1 ]]; then
	if [[ -z "$pid_file" || ! -f "$pid_file" ]]; then
		echo "Nothing to stop (no pid file at ${pid_file:-<unset>})." >&2
		exit 0
	fi
	pid="$(cat "$pid_file")"
	if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
		# Dev servers spawn children (next/webpack workers); kill the whole group, and
		# fall back to the bare pid when the group kill is not available.
		kill -TERM "-${pid}" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
		for _ in $(seq 1 20); do
			kill -0 "$pid" 2>/dev/null || break
			sleep 0.5
		done
		kill -KILL "-${pid}" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
	fi
	rm -f "$pid_file"
	echo "Stopped dev server (pid ${pid})."
	exit 0
fi

for required in dir port command_template; do
	if [[ -z "${!required}" ]]; then
		echo "--${required//_/-} is required." >&2
		usage >&2
		exit 1
	fi
done

if [[ ! -d "$dir" ]]; then
	echo "Directory not found: $dir" >&2
	exit 1
fi

base_url="http://localhost:${port}"
ready_url="${base_url}${ready_path}"

wait_for_http="${SCRIPT_DIR}/lib/wait-for-http.mjs"

if node "$wait_for_http" "$ready_url" 0 2>/dev/null; then
	echo "Reusing dev server already listening on ${base_url}." >&2
	echo "$base_url"
	exit 0
fi

log_file="${log_file:-${dir}/.pr-ui-screenshot-dev-${port}.log}"
pid_file="${pid_file:-${log_file}.pid}"

if [[ "$command_template" == *"{port}"* ]]; then
	dev_command="${command_template//\{port\}/$port}"
else
	dev_command="PORT=${port} ${command_template}"
fi

: >"$log_file"
# The server needs its own process group so --stop can take its children (next/webpack
# workers) with it. setsid does that on Linux but does not ship with macOS, so fall back
# to bash job control: with `set -m`, a background job becomes a process-group leader.
if command -v setsid >/dev/null 2>&1; then
	setsid bash -c "cd '${dir}' && exec ${dev_command}" >>"$log_file" 2>&1 &
	server_pid=$!
else
	set -m
	bash -c "cd '${dir}' && exec ${dev_command}" >>"$log_file" 2>&1 &
	server_pid=$!
	set +m
fi
echo "$server_pid" >"$pid_file"

echo "Starting dev server in ${dir} on port ${port} (pid ${server_pid}); log: ${log_file}" >&2

start_seconds=$SECONDS
set +e
node "$wait_for_http" "$ready_url" "$timeout_sec" --pid "$server_pid"
probe_status=$?
set -e

case "$probe_status" in
0)
	echo "Dev server ready at ${base_url} after $((SECONDS - start_seconds))s." >&2
	echo "$base_url"
	exit 0
	;;
3)
	echo "Dev server exited before becoming ready. Last 40 log lines:" >&2
	tail -40 "$log_file" >&2
	rm -f "$pid_file"
	exit 1
	;;
*)
	echo "Dev server did not answer ${ready_url} within ${timeout_sec}s. Last 40 log lines:" >&2
	tail -40 "$log_file" >&2
	exit 1
	;;
esac
