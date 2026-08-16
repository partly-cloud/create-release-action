#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Tests ─────────────────────────────────────────────────────────────────────

run_tests() {
  # ensure_initial_tag.sh
  begin_test "Unit Test 1: ensure_initial_tag - creates 0.0.0 when no semver tags exist"
  setup_git_mock no_tags
  run_script ensure_initial_tag
  assert_eq "git tag called"  "1" "$(count_calls git_tag)"
  assert_eq "git push called" "1" "$(count_calls git_push)"
  end_test

  begin_test "Unit Test 2: ensure_initial_tag - skips when semver tag already exists"
  setup_git_mock has_tags
  run_script ensure_initial_tag
  assert_eq "git tag not called"  "0" "$(count_calls git_tag)"
  assert_eq "git push not called" "0" "$(count_calls git_push)"
  end_test

  # cleanup_rc_tags.sh
  begin_test "Unit Test 3: cleanup_rc_tags - deletes existing RC tags for the PR"
  setup_cleanup_mock $'1.2.0-rc-pr-42-abc1234\n1.1.0-rc-pr-42-def5678'
  run_script cleanup_rc_tags
  assert_nonempty "OLD_RC_TAGS written to env" "$(get_env OLD_RC_TAGS)"
  assert_eq "gh release delete called twice" "2" "$(count_calls gh_release)"
  end_test

  begin_test "Unit Test 4: cleanup_rc_tags - no-op when no RC tags exist for the PR"
  setup_cleanup_mock ""
  run_script cleanup_rc_tags
  assert_empty "OLD_RC_TAGS is empty" "$(get_env OLD_RC_TAGS)"
  assert_eq "gh release delete not called" "0" "$(count_calls gh_release)"
  end_test

  # create_tag.sh - prerelease
  begin_test "Unit Test 5: create_tag (prerelease) - creates RC tag and sets outputs"
  setup_tag_mock "1.3.0" "99" "abcdef1" "true"
  run_script create_tag
  assert_eq "RELEASE_TAG in env" "1.3.0-rc-pr-99-abcdef1" "$(get_env RELEASE_TAG)"
  assert_eq "tag output"         "1.3.0-rc-pr-99-abcdef1" "$(get_github_output tag)"
  assert_eq "git tag called"     "1"                       "$(count_calls git_tag)"
  assert_eq "git push called"    "1"                       "$(count_calls git_push)"
  end_test

  begin_test "Unit Test 6: create_tag (prerelease) - tag includes version, PR number and SHA"
  setup_tag_mock "2.0.0" "7" "0000001" "true"
  run_script create_tag
  assert_eq "tag format" "2.0.0-rc-pr-7-0000001" "$(get_github_output tag)"
  end_test

  # create_tag.sh - regular release
  begin_test "Unit Test 7: create_tag (release) - creates plain semver tag and sets outputs"
  setup_tag_mock "3.1.0" "" "abcdef1" "false"
  run_script create_tag
  assert_eq "RELEASE_TAG in env" "3.1.0" "$(get_env RELEASE_TAG)"
  assert_eq "tag output"         "3.1.0" "$(get_github_output tag)"
  assert_eq "git tag called"     "1"     "$(count_calls git_tag)"
  assert_eq "git push called"    "1"     "$(count_calls git_push)"
  end_test

  begin_test "Unit Test 8: create_tag (prerelease) - fails when PR_NUMBER is empty"
  setup_tag_mock "1.3.0" "" "abcdef1" "true"
  bash "$REPO_ROOT/scripts/create_tag.sh" >/dev/null 2>&1 && VALIDATION_EXIT=0 || VALIDATION_EXIT=$?
  assert_eq "exits non-zero" "1" "$VALIDATION_EXIT"
  end_test

  begin_test "Unit Test 9: create_tag (release) - tag does not include PR number or SHA"
  setup_tag_mock "1.0.0" "" "abcdef1" "false"
  run_script create_tag
  assert_eq    "tag is plain semver"    "1.0.0" "$(get_github_output tag)"
  assert_empty "no rc suffix in tag"           "$(grep -o '\-rc-pr-' <<< "$(get_github_output tag)" || true)"
  end_test

  # create_github_release.sh
  begin_test "Unit Test 10: create_github_release (prerelease) - calls gh with --prerelease flag"
  setup_create_release_mock "1.3.0-rc-pr-99-abcdef1" "true"
  run_script create_github_release
  assert_eq "gh called once"          "1"    "$(count_calls gh_release_create)"
  assert_eq "release tag in args"     "1"    "$(grep -c '1.3.0-rc-pr-99-abcdef1' "$gh_release_create_calls")"
  assert_eq "--prerelease flag set"   "1"    "$(grep -c -- '--prerelease' "$gh_release_create_calls")"
  assert_eq "--generate-notes set"    "1"    "$(grep -c -- '--generate-notes' "$gh_release_create_calls")"
  assert_nonempty "release_url output"       "$(get_github_output release_url)"
  end_test

  begin_test "Unit Test 11: create_github_release (release) - calls gh without --prerelease flag"
  setup_create_release_mock "2.0.0" "false"
  run_script create_github_release
  assert_eq "gh called once"           "1"   "$(count_calls gh_release_create)"
  assert_eq "release tag in args"      "1"   "$(grep -c '2.0.0' "$gh_release_create_calls")"
  assert_empty "--prerelease not set"        "$(grep -- '--prerelease' "$gh_release_create_calls" || true)"
  assert_eq "--generate-notes set"     "1"   "$(grep -c -- '--generate-notes' "$gh_release_create_calls")"
  assert_nonempty "release_url output"       "$(get_github_output release_url)"
  end_test
}

# ── Assertions ────────────────────────────────────────────────────────────────

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  [[ "$actual" == "$expected" ]] \
    && pass "$label" \
    || fail "$label (expected '$expected', got '$actual')"
}

assert_nonempty() {
  local label="$1" actual="$2"
  [[ -n "$actual" ]] && pass "$label" || fail "$label (expected non-empty value)"
}

assert_empty() {
  local label="$1" actual="$2"
  [[ -z "$actual" ]] && pass "$label" || fail "$label (expected empty, got '$actual')"
}

# ── Test runner ───────────────────────────────────────────────────────────────

CURRENT_TEST=""
CURRENT_TEST_FAILED=0
declare -a TEST_NAMES=()
declare -a TEST_RESULTS=()

begin_test() {
  CURRENT_TEST="$1"
  CURRENT_TEST_FAILED=0
  echo "$1"
}

end_test() {
  TEST_NAMES+=("$CURRENT_TEST")
  if [[ $CURRENT_TEST_FAILED -eq 0 ]]; then
    TEST_RESULTS+=("passed")
  else
    TEST_RESULTS+=("failed")
  fi
  echo ""
}

pass() { echo "  PASS  $1"; true; }
fail() { echo "  FAIL  $1"; CURRENT_TEST_FAILED=1; }

# ── Action runner helpers ─────────────────────────────────────────────────────

run_script() {
  bash "$REPO_ROOT/scripts/${1}.sh" || true
}

# Parse GITHUB_ENV: supports both KEY=value and KEY<<EOF ... EOF heredoc syntax.
get_env() {
  local key="$1" in_block=0
  while IFS= read -r line; do
    if [[ "$line" == "${key}<<EOF" ]]; then
      in_block=1; continue
    fi
    if [[ $in_block -eq 1 ]]; then
      [[ "$line" == "EOF" ]] && break
      echo "$line"; return
    fi
    if [[ "$line" == "${key}="* ]]; then
      echo "${line#${key}=}"; return
    fi
  done < "${GITHUB_ENV:-/dev/null}"
}

get_github_output() {
  grep "^${1}=" "${GITHUB_OUTPUT:-/dev/null}" 2>/dev/null | cut -d= -f2- || true
}

# Count calls logged to a named temp file. Each mock call appends one line.
count_calls() {
  local file_var="${1}_calls"
  local file="${!file_var:-}"
  [[ -f "$file" ]] && wc -l < "$file" | tr -d ' ' || echo "0"
}

cleanup_test_files() {
  for var in GITHUB_ENV GITHUB_OUTPUT git_tag_calls git_push_calls gh_release_calls gh_release_create_calls; do
    [[ -n "${!var:-}" && -f "${!var}" ]] && rm -f "${!var}"
  done
}
trap cleanup_test_files EXIT

# ── Mock setup helpers ────────────────────────────────────────────────────────

setup_git_mock() {
  local mode="$1"
  git_tag_calls=$(mktemp "${TMPDIR:-/tmp}/git-tag-calls.XXXXXX")
  git_push_calls=$(mktemp "${TMPDIR:-/tmp}/git-push-calls.XXXXXX")
  GITHUB_ENV=$(mktemp "${TMPDIR:-/tmp}/gha-env.XXXXXX")
  GITHUB_OUTPUT=$(mktemp "${TMPDIR:-/tmp}/gha-output.XXXXXX")
  export GITHUB_ENV GITHUB_OUTPUT git_tag_calls git_push_calls GIT_MOCK_MODE="$mode"

  git() {
    case "$1" in
      tag)
        if [[ "${2:-}" == "--list" ]]; then
          [[ "$GIT_MOCK_MODE" == "has_tags" ]] && echo "1.0.0" || echo ""
        else
          echo "called" >> "$git_tag_calls"
        fi
        ;;
      rev-list) echo "abc123" ;;
      push)     echo "called" >> "$git_push_calls" ;;
    esac
  }
  export -f git
}

setup_cleanup_mock() {
  local tags="$1"
  gh_release_calls=$(mktemp "${TMPDIR:-/tmp}/gh-release-calls.XXXXXX")
  GITHUB_ENV=$(mktemp "${TMPDIR:-/tmp}/gha-env.XXXXXX")
  GITHUB_OUTPUT=$(mktemp "${TMPDIR:-/tmp}/gha-output.XXXXXX")
  export GITHUB_ENV GITHUB_OUTPUT gh_release_calls GH_TOKEN=mock PR_NUMBER=42
  export GIT_MOCK_TAG_LIST="$tags"

  git() {
    case "$1" in
      tag) echo "$GIT_MOCK_TAG_LIST" ;;
    esac
  }
  gh() {
    echo "called" >> "$gh_release_calls"
  }
  export -f git gh
}

setup_tag_mock() {
  local version="$1" pr="$2" sha="$3" prerelease="$4"
  git_tag_calls=$(mktemp "${TMPDIR:-/tmp}/git-tag-calls.XXXXXX")
  git_push_calls=$(mktemp "${TMPDIR:-/tmp}/git-push-calls.XXXXXX")
  GITHUB_ENV=$(mktemp "${TMPDIR:-/tmp}/gha-env.XXXXXX")
  GITHUB_OUTPUT=$(mktemp "${TMPDIR:-/tmp}/gha-output.XXXXXX")
  export GITHUB_ENV GITHUB_OUTPUT NEXT_VERSION="$version" PR_NUMBER="$pr" GH_TOKEN=mock
  export PRERELEASE="$prerelease" git_tag_calls git_push_calls GIT_MOCK_SHA="$sha"

  git() {
    case "$1" in
      rev-parse) echo "$GIT_MOCK_SHA" ;;
      tag)       echo "called" >> "$git_tag_calls" ;;
      push)      echo "called" >> "$git_push_calls" ;;
    esac
  }
  export -f git
}

setup_create_release_mock() {
  local tag="$1" prerelease="$2"
  gh_release_create_calls=$(mktemp "${TMPDIR:-/tmp}/gh-release-create-calls.XXXXXX")
  GITHUB_ENV=$(mktemp "${TMPDIR:-/tmp}/gha-env.XXXXXX")
  GITHUB_OUTPUT=$(mktemp "${TMPDIR:-/tmp}/gha-output.XXXXXX")
  export GITHUB_ENV GITHUB_OUTPUT RELEASE_TAG="$tag" PRERELEASE="$prerelease" GH_TOKEN=mock
  export gh_release_create_calls

  gh() {
    echo "$*" >> "$gh_release_create_calls"
    echo "https://github.com/mock/repo/releases/tag/$RELEASE_TAG"
  }
  export -f gh
}

# ── Main ──────────────────────────────────────────────────────────────────────

run_tests

total=${#TEST_NAMES[@]}
passed=0; failed=0
for r in "${TEST_RESULTS[@]}"; do
  if [[ "$r" == "passed" ]]; then passed=$((passed + 1)); else failed=$((failed + 1)); fi
done
echo "Results: $passed/$total passed"

if [[ -n "${CTRF_REPORT_PATH:-}" ]]; then
  mkdir -p "$(dirname "$CTRF_REPORT_PATH")"
  tests_json="["
  for i in "${!TEST_NAMES[@]}"; do
    [[ $i -gt 0 ]] && tests_json+=","
    tests_json+="{\"name\":\"${TEST_NAMES[$i]}\",\"status\":\"${TEST_RESULTS[$i]}\",\"duration\":0}"
  done
  tests_json+="]"
  jq -n \
    --argjson tests "$tests_json" \
    --argjson total "$total" \
    --argjson passed "$passed" \
    --argjson failed "$failed" \
    '{results:{tool:{name:"create-release-action"},summary:{tests:$total,passed:$passed,failed:$failed,pending:0,skipped:0,other:0,start:0,stop:0},tests:$tests}}' \
    > "$CTRF_REPORT_PATH"
fi

if [[ $failed -gt 0 ]]; then exit 1; fi
