#!/usr/bin/env bash
# Regression tests for sensei's static-analysis + discovery engine.
#
# Encodes real failures found by manually stress-testing sensei against
# non-standard tools/scripts (nested bash dispatch, Python argparse
# subparsers, ambiguous keyword families, dashless discovery, value
# inference, runtime-crash filtering) -- each one caught a genuine bug
# that shipped and was fixed once. This exists so none of them can
# silently come back.
#
# Run: ./test/regression.sh
# Every fixture is synthetic and self-contained (no dependency on curl,
# nmap, or any other tool actually being installed) so this is portable
# and deterministic.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SENSEI="$HERE/../sensei"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/sensei-regress.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

export PATH="$WORK/bin:$PATH"
export SENSEI_SPEC_CACHE="$WORK/cache"
mkdir -p "$WORK/bin"

pass=0 fail=0
ok()   { pass=$((pass + 1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf '  \033[31m✗\033[0m %s\n' "$1"; }
assert_contains() {  # $1=label $2=haystack $3=needle
  case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 -- expected to find: $3"; printf '%s\n' "$2" | sed 's/^/      | /' ;; esac
}
assert_not_contains() {  # $1=label $2=haystack $3=needle-that-must-be-absent
  case "$2" in *"$3"*) bad "$1 -- must NOT contain: $3"; printf '%s\n' "$2" | sed 's/^/      | /' ;; *) ok "$1" ;; esac
}

# ── fixture: nested case dispatch (scan/report), custom parsing, no --help ──
# The multi-line `pattern)\n  body\n  ;;` style; section 9 below covers the
# single-line `pattern) body ;;` style with its own fixture, and section 9b
# covers the two mixed in the same script (a nested per-flag case using
# one style, the outer dispatch using the other).
cat > "$WORK/bin/reconwrap" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  scan)
    shift
    while [ $# -gt 0 ]; do
      case "$1" in
        --target-domain)
          TARGET_DOMAIN="$2"
          shift 2
          ;;
        --disable-ssl-verification)
          NOVERIFY=1
          shift
          ;;
        --output)
          OUT="$2"
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    ;;
  report)
    shift
    while [ $# -gt 0 ]; do
      case "$1" in
        --output)
          OUT="$2"
          shift 2
          ;;
        --timeout)
          T="$2"
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    ;;
esac
EOF
chmod +x "$WORK/bin/reconwrap"

# ── fixture: getopts with a companion case body naming the variable ────────
cat > "$WORK/bin/getopttool" <<'EOF'
#!/usr/bin/env bash
while getopts "vt:" opt; do
  case "$opt" in
    v) VERBOSE=1 ;;
    t)
      TARGET="$OPTARG"
      ;;
  esac
done
EOF
chmod +x "$WORK/bin/getopttool"

# ── fixture: python argparse with subparsers + enum choices ────────────────
cat > "$WORK/bin/argparsetool.py" <<'EOF'
#!/usr/bin/env python3
import argparse

def build():
    p = argparse.ArgumentParser(prog='argparsetool')
    p.add_argument('--verbose')
    sub = p.add_subparsers(dest='command')
    scan = sub.add_parser('scan')
    scan.add_argument('--ports')
    scan.add_argument('--interface')
    config = sub.add_parser('config')
    config.add_argument('--output', choices=['json', 'csv', 'xml'])
    return p
EOF
chmod +x "$WORK/bin/argparsetool.py"

# ── fixture: ambiguous "user" family (no dependency on click) ──────────────
cat > "$WORK/bin/usertool" <<'EOF'
#!/usr/bin/env python3
import argparse
p = argparse.ArgumentParser()
p.add_argument('--user', help='run as this user')
p.add_argument('--username', help='login username')
p.add_argument('--user-agent', help='HTTP User-Agent header')
p.add_argument('--target-user', help='user account on the target')
p.add_argument('--current-user', help='show the current user')
EOF
chmod +x "$WORK/bin/usertool"

# ── fixture: a script that crashes when probed with --help ─────────────────
cat > "$WORK/bin/crashtool" <<'EOF'
#!/usr/bin/env python3
import sys
if __name__ == '__main__':
    raise RuntimeError("boom")
EOF
chmod +x "$WORK/bin/crashtool"

# ── fixture: single-line case arms ("pattern) body ;;" all on one line) ────
cat > "$WORK/bin/singlelinetool" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  --verify) echo "verifying" ;;
  --cert-path) CERT="$2"; shift 2 ;;
esac
EOF
chmod +x "$WORK/bin/singlelinetool"

# ── fixture: single-line AND multi-line arms mixed, with nested scoping ────
cat > "$WORK/bin/mixedstyletool" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  scan)
    shift
    while [ $# -gt 0 ]; do
      case "$1" in
        --target-domain) TARGET_DOMAIN="$2"; shift 2 ;;
        --verify) echo "verifying" ;;
        *) shift ;;
      esac
    done
    ;;
  report)
    shift
    while [ $# -gt 0 ]; do
      case "$1" in
        --output)
          OUT="$2"
          shift 2
          ;;
        *) shift ;;
      esac
    done
    ;;
esac
EOF
chmod +x "$WORK/bin/mixedstyletool"

# ── fixture: argparse value-taking/metadata, interpreter deliberately
# missing (python3-notreal) so --help can never run and every result below
# is forced through static analysis alone -- a real interpreter would also
# answer these correctly via its own --help text, which would test tier-2
# help parsing instead of the static analyzer this fixture exists to cover.
cat > "$WORK/bin/pyvaluetool" <<'EOF'
#!/usr/bin/env python3-notreal
import argparse
parser = argparse.ArgumentParser()
parser.add_argument("--target")
parser.add_argument("--verbose", action="store_true")
parser.add_argument(
    "--output",
    choices=["json", "csv", "xml"]
)
parser.add_argument("--retries", type=int, default=3)
parser.add_argument("--tag", metavar="TAG")
parser.add_argument("--files", nargs="+")
EOF
chmod +x "$WORK/bin/pyvaluetool"

# ── fixture: click command group, interpreter deliberately missing (same
# reasoning as pyvaluetool above -- forces every result through static
# analysis, not a real --help run) ─────────────────────────────────────────
cat > "$WORK/bin/clicktool" <<'EOF'
#!/usr/bin/env python3-notreal
import click

@click.group()
def cli():
    pass

@cli.command()
@click.option("--target")
def scan(target):
    pass

@cli.command()
@click.option(
    "--output",
    type=click.Choice(["json", "csv", "xml"])
)
def report(output):
    pass

if __name__ == "__main__":
    cli()
EOF
chmod +x "$WORK/bin/clicktool"

rm -rf "$SENSEI_SPEC_CACHE"

printf '\n1. Nested bash case scoping does not leak\n'
scan_out="$("$SENSEI" args reconwrap scan 2>&1)"
report_out="$("$SENSEI" args reconwrap report 2>&1)"
assert_contains    "scan shows --target-domain"            "$scan_out"   '--target-domain'
assert_contains    "scan shows --disable-ssl-verification" "$scan_out"   '--disable-ssl-verification'
assert_contains    "scan shows --output"                   "$scan_out"   '--output'
assert_not_contains "report does NOT show --disable-ssl-verification (the original leak)" "$report_out" '--disable-ssl-verification'
assert_not_contains "report does NOT show --target-domain" "$report_out" '--target-domain'
assert_contains     "report shows --output"                "$report_out" '--output'
assert_contains     "report shows --timeout"                "$report_out" '--timeout'
n_output_in_report="$(printf '%s\n' "$report_out" | grep -cE '^\s*--output\b')"
[ "$n_output_in_report" -le 1 ] && ok "report's --output is not duplicated" || bad "report's --output appears $n_output_in_report times (expected 1)"

printf '\n2. getopts value-taking + companion variable name\n'
got_out="$("$SENSEI" args getopttool 2>&1)"
if printf '%s\n' "$got_out" | grep -qE '^\s*-t\s+<value>'; then ok "getopts -t is detected as value-taking"; else bad "getopts -t not shown as value-taking"; printf '%s\n' "$got_out" | sed 's/^/      | /'; fi
assert_contains "getopts -t description mentions TARGET (the OPTARG variable)" "$got_out" 'TARGET'
assert_not_contains "OPTARG itself is never treated as a discovered env var" "$got_out" 'OPTARG'

printf '\n3. Python argparse subparsers are real subcommands\n'
is_sub_out="$(bash -c "source \"$SENSEI\" '' >/dev/null 2>&1; _spec_is_sub argparsetool.py scan && echo YES || echo NO")"
assert_contains "sensei recognizes \"scan\" as a real subcommand" "$is_sub_out" "YES"
scan_py="$("$SENSEI" args argparsetool.py scan 2>&1)"
config_py="$("$SENSEI" args argparsetool.py config 2>&1)"
config_output_detail="$("$SENSEI" args "argparsetool.py config --output" 2>&1)"
assert_contains     "argparse scan shows --ports"                "$scan_py"   '--ports'
assert_contains     "argparse scan shows --interface"             "$scan_py"   '--interface'
assert_not_contains "argparse scan does NOT show --output (config-only)" "$scan_py" '--output'
assert_contains     "argparse config shows --output"              "$config_py" '--output'
assert_contains     "argparse config --output detail shows the enum" "$config_output_detail" 'json, csv, xml'
assert_not_contains "argparse config does NOT show --ports (scan-only)"  "$config_py" '--ports'

printf '\n4. Relevance ranking is not alphabetical\n'
rank_out="$("$SENSEI" complete 1 usertool user 2>&1)"
first_hit="$(printf '%s\n' "$rank_out" | head -1 | cut -f1)"
[ "$first_hit" = "--user" ] && ok "exact whole-name match --user ranks first for query \"user\"" || bad "expected --user first, got: $first_hit"

printf '\n5. Dashless keyword discovery is selective, not the weak fallback\n'
n_hits="$(printf '%s\n' "$rank_out" | grep -c .)"
[ "$n_hits" -eq 5 ] && ok "dashless \"user\" returns exactly the 5 real user-related flags (no extra noise)" || bad "expected 5 hits, got $n_hits: $rank_out"

printf '\n6. Runtime crash never becomes the tool summary\n'
crash_out="$("$SENSEI" args crashtool 2>&1)"
assert_not_contains "crash traceback is not the summary" "$crash_out" 'Traceback'
assert_not_contains "crash traceback is not the summary" "$crash_out" 'RuntimeError'

printf '\n7. Existing exact-prefix completion is unaffected\n'
cat > "$WORK/bin/prefixtool" <<'EOF'
#!/usr/bin/env bash
cat <<HELP
Usage: prefixtool [options]
  -s, --silent    Silent mode
  -sV             Probe version
  -sC             Run default scripts
HELP
EOF
chmod +x "$WORK/bin/prefixtool"
prefix_out="$("$SENSEI" complete 1 prefixtool -s 2>&1)"
assert_contains "exact-prefix -s<Tab> still finds -sV" "$prefix_out" '-sV'
assert_contains "exact-prefix -s<Tab> still finds -sC" "$prefix_out" '-sC'

printf '\n8. sensei args, Tab-completion, and sensei discover share one matcher\n'
discover_out="$("$SENSEI" discover output "$WORK/bin/argparsetool.py" 2>&1)"
assert_contains "sensei discover finds the same --output enum sensei args does" "$discover_out" '--output'

printf '\n9. Single-line case arms ("pattern) body ;;" all on one line)\n'
sl_out="$("$SENSEI" args singlelinetool 2>&1)"
assert_contains "single-line --verify is found" "$sl_out" '--verify'
if printf '%s\n' "$sl_out" | grep -qE '^\s*--cert-path\s+<value>'; then
  ok "single-line --cert-path is detected as value-taking"
else
  bad "single-line --cert-path not shown as value-taking"; printf '%s\n' "$sl_out" | sed 's/^/      | /'
fi
assert_contains "single-line --cert-path description mentions CERT (the assigned variable)" "$sl_out" 'CERT'

printf '\n9b. Single-line and multi-line arms mixed, with nested scoping\n'
ms_scan="$("$SENSEI" args mixedstyletool scan 2>&1)"
ms_report="$("$SENSEI" args mixedstyletool report 2>&1)"
assert_contains     "mixed: scan (single-line arms) shows --target-domain" "$ms_scan"   '--target-domain'
assert_contains     "mixed: scan (single-line arms) shows --verify"        "$ms_scan"   '--verify'
assert_not_contains "mixed: scan does NOT show --output (report-only, multi-line)" "$ms_scan" '--output'
assert_contains     "mixed: report (multi-line arm) shows --output"        "$ms_report" '--output'
assert_not_contains "mixed: report does NOT show --target-domain (scan-only, single-line)" "$ms_report" '--target-domain'

printf '\n10. Python argparse value-taking + structured metadata (no --help available)\n'
pv_out="$("$SENSEI" args pyvaluetool 2>&1)"
if printf '%s\n' "$pv_out" | grep -qE '^\s*--target\s+<value>'; then
  ok "plain add_argument(\"--target\") infers value-taking"
else
  bad "plain --target not shown as value-taking"; printf '%s\n' "$pv_out" | sed 's/^/      | /'
fi
if printf '%s\n' "$pv_out" | grep -qE '^\s*--verbose\s+<'; then
  bad "action=\"store_true\" --verbose wrongly shown as value-taking"; printf '%s\n' "$pv_out" | sed 's/^/      | /'
else
  ok "action=\"store_true\" --verbose is boolean, not value-taking"
fi
assert_contains "--retries shows its type=int as structured <int>" "$pv_out" '--retries'
if printf '%s\n' "$pv_out" | grep -qE '^\s*--retries\s+<int>'; then
  ok "--retries value is the structured <int>, not a bare <value>"
else
  bad "--retries missing structured <int>"; printf '%s\n' "$pv_out" | sed 's/^/      | /'
fi
assert_contains "--retries description mentions its default" "$pv_out" 'default: 3'
if printf '%s\n' "$pv_out" | grep -qE '^\s*--tag\s+<TAG>'; then
  ok "--tag uses its metavar=TAG as the structured value"
else
  bad "--tag missing structured <TAG> metavar"; printf '%s\n' "$pv_out" | sed 's/^/      | /'
fi
if printf '%s\n' "$pv_out" | grep -qE '^\s*--files\s+<value>\.\.\.'; then
  ok "--files nargs=\"+\" shows the repeatable ... suffix"
else
  bad "--files missing nargs repeatable suffix"; printf '%s\n' "$pv_out" | sed 's/^/      | /'
fi
pv_output_detail="$("$SENSEI" args pyvaluetool --output 2>&1)"
assert_contains "--output choices=[...] surfaces as a real enum, not just in the description" "$pv_output_detail" 'json, csv, xml'
pv_complete="$("$SENSEI" complete 2 pyvaluetool --output "" 2>&1)"
assert_contains "Tab-completion after --output offers json from the structured enum" "$pv_complete" 'json'
assert_contains "Tab-completion after --output offers csv from the structured enum" "$pv_complete" 'csv'
assert_contains "Tab-completion after --output offers xml from the structured enum" "$pv_complete" 'xml'

printf '\n11. Click command groups: real, scoped subcommands (not a Click-specific path)\n'
click_scan="$("$SENSEI" args clicktool scan 2>&1)"
click_report="$("$SENSEI" args clicktool report 2>&1)"
assert_contains     "click scan shows --target"                       "$click_scan"   '--target'
assert_not_contains "click scan does NOT show --output (report-only)" "$click_scan"   '--output'
assert_contains     "click report shows --output"                     "$click_report" '--output'
assert_not_contains "click report does NOT show --target (scan-only)" "$click_report" '--target'
assert_contains     "click report --output enum uses type=click.Choice(...)" \
  "$("$SENSEI" args clicktool report --output 2>&1)" 'json, csv, xml'
click_scan_complete="$("$SENSEI" complete 2 clicktool scan "" 2>&1)"
click_report_complete="$("$SENSEI" complete 2 clicktool report "" 2>&1)"
assert_contains     "Tab-completion: clicktool scan offers --target"  "$click_scan_complete"   '--target'
assert_not_contains "Tab-completion: clicktool scan does NOT offer --output" "$click_scan_complete" '--output'
assert_contains     "Tab-completion: clicktool report offers --output" "$click_report_complete" '--output'
assert_not_contains "Tab-completion: clicktool report does NOT offer --target" "$click_report_complete" '--target'

printf '\n12. Function/alias names never masquerade as flags or subcommand tokens\n'
assert_not_contains "clicktool scan does NOT list its own handler function as a candidate" "$click_scan_complete" 'func'
assert_not_contains "clicktool report does NOT list its own handler function as a candidate" "$click_report_complete" 'func'
discover_func="$("$SENSEI" discover scan "$WORK/bin/clicktool" 2>&1)"
assert_contains "sensei discover (structural search) still finds the scan() function" "$discover_func" 'func'

echo
if [ "$fail" -eq 0 ]; then
  printf '\033[32mAll %d checks passed.\033[0m\n' "$pass"
  exit 0
else
  printf '\033[31m%d passed, %d FAILED.\033[0m\n' "$pass" "$fail"
  exit 1
fi
