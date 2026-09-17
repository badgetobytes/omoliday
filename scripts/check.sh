#!/usr/bin/bash
# The release gate: model and packaging tests under node, the network guards
# exercised offline against a local stand-in server, QML lint, and — on an
# Omarchy desktop — the plugin validator and the shell-facing lint.
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"

server_pid=""
lint_imports=""
cleanup() {
  if [[ -n $server_pid ]]; then kill "$server_pid" 2>/dev/null || true; fi
  if [[ -n $lint_imports ]]; then unlink "$lint_imports/qs" 2>/dev/null || true; rmdir "$lint_imports" 2>/dev/null || true; fi
}
trap cleanup EXIT

node --test tests/*.test.cjs

bash -n scripts/check.sh
if command -v shellcheck >/dev/null; then shellcheck scripts/check.sh; fi

qt_tools="${QT_TOOLS_DIR:-/usr/lib/qt6/bin}"
"$qt_tools/qmllint" HolidayFetch.qml tests/fetch-harness.qml

# Every guard in HolidayFetch.qml, driven against tests/fetch-server.py.
port="${OMOLIDAY_TEST_PORT:-$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')}"
python3 tests/fetch-server.py --port "$port" &
server_pid=$!
python3 - "$port" <<'PY'
import socket, sys, time
port = int(sys.argv[1])
for _ in range(100):
    try:
        socket.create_connection(("127.0.0.1", port), timeout=0.2).close()
        sys.exit(0)
    except OSError:
        time.sleep(0.05)
sys.exit("fetch server did not start")
PY
QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen "$qt_tools/qml" tests/fetch-harness.qml -- "--port=$port"

if command -v omarchy >/dev/null; then
  omarchy plugin validate "$project_dir"
  # The running shell registers qs as its root module; reproduce that mapping
  # for the standalone linter without writing into the packaged shell.
  lint_imports="$(mktemp -d)"
  ln -s /usr/share/omarchy/shell "$lint_imports/qs"
  "$qt_tools/qmllint" -I "$lint_imports" Panel.qml BarWidget.qml
else
  printf '%s\n' 'Omarchy host checks (plugin validate, shell-facing lint) also run on an Omarchy desktop before release.'
fi
printf '%s\n' 'check.sh: all gates passed'
