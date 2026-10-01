# Source this to run the vendored python-dateutil with local shims:
#   . tools/pyenv.sh && python3 -c 'import dateutil.parser'
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
export PYTHONPATH="$ROOT/tools/pyshim:$ROOT/.repos/dateutil/src:$ROOT/.repos/dateutil"
