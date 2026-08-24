#!/usr/bin/env bash
set -u
set -o pipefail

SCRIPT_DIR=''
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIR
readonly UPDATER="$SCRIPT_DIR/veldmuis-user-defaults-update"
TEST_ROOT=''
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/veldmuis-user-defaults-test.XXXXXX")
readonly TEST_ROOT
readonly DEFAULTS_ROOT="$TEST_ROOT/defaults"
readonly CASE_HOME="$TEST_ROOT/home"
readonly STATE_BASE="$TEST_ROOT/state"
readonly OUTSIDE_FILE="$TEST_ROOT/outside.txt"
RUN_UPDATER="$UPDATER"

TEST_USER=${USER:-}
TEST_UID=${EUID:-0}
TEST_GID=$(id -g)
RUN_UNPRIVILEGED=0
CONFIG_MODE=default
CUSTOM_CONFIG_ROOT=''

FISH_OLD='old fish configuration'
FISH_ONE='fish configuration revision one'
FISH_TWO='fish configuration revision two'
FISH_CUSTOM='user fish customization'
WEZTERM_OLD='old wezterm configuration'
WEZTERM_ONE='wezterm configuration revision one'
WEZTERM_TWO='wezterm configuration revision two'

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

hash_text() {
  local temporary="$TEST_ROOT/hash-input" result
  printf '%s' "$1" > "$temporary"
  result=$(sha256sum -- "$temporary") || return 1
  printf '%s' "${result%% *}"
}

hash_file() {
  local result
  result=$(sha256sum -- "$1") || return 1
  printf '%s' "${result%% *}"
}

FISH_OLD_HASH=$(hash_text "$FISH_OLD")
FISH_ONE_HASH=$(hash_text "$FISH_ONE")
FISH_TWO_HASH=$(hash_text "$FISH_TWO")
WEZTERM_OLD_HASH=$(hash_text "$WEZTERM_OLD")
WEZTERM_ONE_HASH=$(hash_text "$WEZTERM_ONE")
WEZTERM_TWO_HASH=$(hash_text "$WEZTERM_TWO")
readonly FISH_OLD_HASH FISH_ONE_HASH FISH_TWO_HASH
readonly WEZTERM_OLD_HASH WEZTERM_ONE_HASH WEZTERM_TWO_HASH

run_as_test_user() {
  if ((RUN_UNPRIVILEGED)); then
    runuser -u "$TEST_USER" -- env "$@"
  else
    env "$@"
  fi
}

run_updater() {
  if [[ $CONFIG_MODE == custom ]]; then
    run_as_test_user \
      -u XDG_CONFIG_HOME \
      HOME="$CASE_HOME" \
      XDG_STATE_HOME="$STATE_BASE" \
      XDG_CONFIG_HOME="$CUSTOM_CONFIG_ROOT" \
      PATH=/nonexistent \
       /bin/bash -c "source \"\$1\"; veldmuis_user_defaults_test_run \"\$2\"" _ "$RUN_UPDATER" "$DEFAULTS_ROOT"
  else
    run_as_test_user \
      -u XDG_CONFIG_HOME \
      HOME="$CASE_HOME" \
      XDG_STATE_HOME="$STATE_BASE" \
      PATH=/nonexistent \
       /bin/bash -c "source \"\$1\"; veldmuis_user_defaults_test_run \"\$2\"" _ "$RUN_UPDATER" "$DEFAULTS_ROOT"
  fi
}

config_root() {
  if [[ $CONFIG_MODE == custom ]]; then
    printf '%s' "$CUSTOM_CONFIG_ROOT"
  else
    printf '%s' "$CASE_HOME/.config"
  fi
}

config_path() {
  printf '%s/%s' "$(config_root)" "$1"
}

state_path() {
  printf '%s/veldmuis/user-defaults/state.ini' "$STATE_BASE"
}

assert_eq() {
  [[ $1 == "$2" ]] || fail "$3 (expected '$2', got '$1')"
}

assert_file_content() {
  local path=$1 expected=$2 actual
  [[ -f $path && ! -L $path ]] || fail "expected regular file: $path"
  actual=$(<"$path")
  assert_eq "$actual" "$expected" "unexpected contents in $path"
}

assert_absent() {
  [[ ! -e $1 && ! -L $1 ]] || fail "expected path to remain absent: $1"
}

state_value() {
  local wanted_section=$1 wanted_key=$2 line section='' in_section=0
  while IFS= read -r line || [[ -n $line ]]; do
    if [[ $line == \[*\] ]]; then
      section=${line#\[}
      section=${section%\]}
      if [[ $section == "$wanted_section" ]]; then
        in_section=1
      else
        in_section=0
      fi
    elif ((in_section)) && [[ $line == "$wanted_key="* ]]; then
      printf '%s' "${line#*=}"
      return 0
    fi
  done < "$(state_path)"
  return 1
}

assert_state() {
  local actual
  actual=$(state_value "$1" "$2")
  assert_eq "$actual" "$3" "unexpected state value $1/$2"
}

write_user_file() {
  local path=$1 contents=$2
  mkdir -p -- "${path%/*}"
  printf '%s' "$contents" > "$path"
  if ((RUN_UNPRIVILEGED)); then
    chown "$TEST_UID:$TEST_GID" -- "$path"
    if [[ $path == "$CASE_HOME/"* ]]; then
      chown -R "$TEST_UID:$TEST_GID" -- "$CASE_HOME"
    fi
  fi
}

write_package() {
  local version=$1 fish_hash wez_hash fish_revision wez_revision
  local fish_template wez_template

  mkdir -p -- "$DEFAULTS_ROOT/templates/fish" "$DEFAULTS_ROOT/templates/wezterm"
  if [[ $version == 1 ]]; then
    fish_template=$FISH_ONE
    wez_template=$WEZTERM_ONE
    fish_hash=$FISH_ONE_HASH
    wez_hash=$WEZTERM_ONE_HASH
    fish_revision=2
    wez_revision=2
  else
    fish_template=$FISH_TWO
    wez_template=$WEZTERM_TWO
    fish_hash=$FISH_TWO_HASH
    wez_hash=$WEZTERM_TWO_HASH
    fish_revision=3
    wez_revision=3
  fi
  printf '%s\n' $'config_path\ttemplate_path\tcandidate_sha256\trevision' > "$DEFAULTS_ROOT/manifest.tsv"
  printf '%s\t%s\t%s\t%s\n' fish/config.fish templates/fish/config.fish "$fish_hash" "$fish_revision" >> "$DEFAULTS_ROOT/manifest.tsv"
  printf '%s\t%s\t%s\t%s\n' wezterm/wezterm.lua templates/wezterm/wezterm.lua "$wez_hash" "$wez_revision" >> "$DEFAULTS_ROOT/manifest.tsv"
  {
    printf '%s\n' $'config_path\tsha256\trevision'
    printf '%s\t%s\t%s\n' fish/config.fish "$FISH_OLD_HASH" 1
    printf '%s\t%s\t%s\n' fish/config.fish "$FISH_ONE_HASH" 2
    printf '%s\t%s\t%s\n' wezterm/wezterm.lua "$WEZTERM_OLD_HASH" 1
    printf '%s\t%s\t%s\n' wezterm/wezterm.lua "$WEZTERM_ONE_HASH" 2
  } > "$DEFAULTS_ROOT/history.tsv"
  if [[ $version != 1 ]]; then
    {
      printf '%s\t%s\t%s\n' fish/config.fish "$FISH_TWO_HASH" 3
      printf '%s\t%s\t%s\n' wezterm/wezterm.lua "$WEZTERM_TWO_HASH" 3
    } >> "$DEFAULTS_ROOT/history.tsv"
  fi
  printf '%s' "$fish_template" > "$DEFAULTS_ROOT/templates/fish/config.fish"
  printf '%s' "$wez_template" > "$DEFAULTS_ROOT/templates/wezterm/wezterm.lua"
  chmod 755 "$DEFAULTS_ROOT" "$DEFAULTS_ROOT/templates" "$DEFAULTS_ROOT/templates/fish" "$DEFAULTS_ROOT/templates/wezterm"
  chmod 644 "$DEFAULTS_ROOT/manifest.tsv" "$DEFAULTS_ROOT/history.tsv" "$DEFAULTS_ROOT/templates/fish/config.fish" "$DEFAULTS_ROOT/templates/wezterm/wezterm.lua"
}

reset_case() {
  rm -rf -- "$CASE_HOME" "$STATE_BASE"
  if [[ -n $CUSTOM_CONFIG_ROOT ]]; then
    rm -rf -- "$CUSTOM_CONFIG_ROOT"
  fi
  mkdir -p -- "$CASE_HOME" "$STATE_BASE"
  CUSTOM_CONFIG_ROOT="$CASE_HOME/custom-config"
  CONFIG_MODE=default
  write_package 1
  if ((RUN_UNPRIVILEGED)); then
    chown -R "$TEST_UID:$TEST_GID" -- "$CASE_HOME" "$STATE_BASE"
  fi
}

expect_failure() {
  if run_updater >/dev/null 2>&1; then
    fail 'updater unexpectedly succeeded'
  fi
}

write_managed_state() {
  # Canonical seed fixture accepted by the updater: schema=1; [fish] and
  # [wezterm]; mode, origin, applied_hash, candidate_hash, observation.
  local origin=$1 fish_hash=$2 fish_candidate=$3 wez_hash=$4 wez_candidate=$5 path
  path=$(state_path)
  mkdir -p -- "${path%/*}"
  printf '%s\n' \
    'schema=1' \
    '[fish]' \
    'mode=managed' \
    "origin=$origin" \
    "applied_hash=$fish_hash" \
    "candidate_hash=$fish_candidate" \
    'observation=seeded' \
    '[wezterm]' \
    'mode=managed' \
    "origin=$origin" \
    "applied_hash=$wez_hash" \
    "candidate_hash=$wez_candidate" \
    'observation=seeded' > "$path"
  chmod 600 -- "$path"
  if ((RUN_UNPRIVILEGED)); then
    chown "$TEST_UID:$TEST_GID" -- "$path"
    chown -R "$TEST_UID:$TEST_GID" -- "$STATE_BASE"
  fi
}

write_pending_state() {
  local fish_hash=$1 candidate_hash=$2 target temp dev ino mode path
  target=$(config_path fish/config.fish)
  temp=${target%/*}/.veldmuis-fish.ABC123
  dev=$(stat -c '%d' -- "$target")
  ino=$(stat -c '%i' -- "$target")
  mode=$(stat -c '%a' -- "$target")
  path=$(state_path)
  mkdir -p -- "${path%/*}"
  printf '%s\n' \
    'schema=1' \
    '[fish]' \
    'mode=managed' \
    'origin=seeded' \
    "applied_hash=$fish_hash" \
    "candidate_hash=$candidate_hash" \
    'observation=pending' \
    '[pending_fish]' \
    "target=$target" \
    "old_hash=$fish_hash" \
    "new_hash=$candidate_hash" \
    "temp_path=$temp" \
    "old_dev=$dev" \
    "old_inode=$ino" \
    "old_mode=$mode" \
    '[wezterm]' \
    'mode=managed' \
    'origin=seeded' \
    "applied_hash=$WEZTERM_ONE_HASH" \
    "candidate_hash=$WEZTERM_ONE_HASH" \
    'observation=seeded' > "$path"
  chmod 600 -- "$path"
  if ((RUN_UNPRIVILEGED)); then
    chown "$TEST_UID:$TEST_GID" -- "$path"
    chown -R "$TEST_UID:$TEST_GID" -- "$STATE_BASE"
  fi
  printf '%s' "$temp"
}

make_pending_temp() {
  local temp=$1
  printf '%s' "$FISH_ONE" > "$temp"
  chmod 644 -- "$temp"
  if ((RUN_UNPRIVILEGED)); then
    chown "$TEST_UID:$TEST_GID" -- "$temp"
  fi
}

test_current_hash_adoption() {
  local path inode_before inode_after
  reset_case
  path=$(config_path fish/config.fish)
  write_user_file "$path" "$FISH_ONE"
  inode_before=$(stat -c '%i' -- "$path")
  run_updater || fail 'current-hash adoption failed'
  inode_after=$(stat -c '%i' -- "$path")
  assert_file_content "$path" "$FISH_ONE"
  assert_eq "$inode_after" "$inode_before" 'current-hash adoption rewrote the file'
  assert_state fish mode managed
  assert_state fish origin adopted
  assert_state fish applied_hash "$FISH_ONE_HASH"
  assert_state fish candidate_hash "$FISH_ONE_HASH"
}

test_custom_xdg_config() {
  local path
  reset_case
  CONFIG_MODE=custom
  path=$(config_path fish/config.fish)
  write_user_file "$path" "$FISH_ONE"
  run_updater || fail 'custom XDG config case failed'
  assert_file_content "$path" "$FISH_ONE"
  assert_absent "$CASE_HOME/.config/fish/config.fish"
  assert_state fish mode managed
  assert_state fish applied_hash "$FISH_ONE_HASH"
}

test_historical_update() {
  local path
  reset_case
  path=$(config_path fish/config.fish)
  write_user_file "$path" "$FISH_OLD"
  run_updater || fail 'historical update failed'
  assert_file_content "$path" "$FISH_ONE"
  assert_state fish applied_hash "$FISH_ONE_HASH"
  assert_state fish observation updated
}

test_seeded_state() {
  local fish_path wez_path fish_inode wez_inode
  reset_case
  fish_path=$(config_path fish/config.fish)
  wez_path=$(config_path wezterm/wezterm.lua)
  write_user_file "$fish_path" "$FISH_ONE"
  write_user_file "$wez_path" "$WEZTERM_ONE"
  write_managed_state seeded "$FISH_ONE_HASH" "$FISH_ONE_HASH" "$WEZTERM_ONE_HASH" "$WEZTERM_ONE_HASH"
  fish_inode=$(stat -c '%i' -- "$fish_path")
  wez_inode=$(stat -c '%i' -- "$wez_path")
  run_updater || fail 'seeded-state case failed'
  assert_eq "$(stat -c '%i' -- "$fish_path")" "$fish_inode" 'seeded fish file was rewritten'
  assert_eq "$(stat -c '%i' -- "$wez_path")" "$wez_inode" 'seeded WezTerm file was rewritten'
  assert_state fish origin seeded
  assert_state fish applied_hash "$FISH_ONE_HASH"
  assert_state fish observation current
  assert_state wezterm origin seeded
}

test_changed_managed_file_and_independent_update() {
  local fish_path wez_path
  reset_case
  fish_path=$(config_path fish/config.fish)
  wez_path=$(config_path wezterm/wezterm.lua)
  write_user_file "$fish_path" "$FISH_OLD"
  write_user_file "$wez_path" "$WEZTERM_OLD"
  run_updater || fail 'initial independent update failed'
  write_package 2
  write_user_file "$fish_path" "$FISH_CUSTOM"
  write_user_file "$wez_path" "$WEZTERM_ONE"
  run_updater || fail 'managed independent update failed'
  assert_file_content "$fish_path" "$FISH_CUSTOM"
  assert_file_content "$wez_path" "$WEZTERM_TWO"
  assert_state fish applied_hash "$FISH_ONE_HASH"
  assert_state fish candidate_hash "$FISH_TWO_HASH"
  assert_state fish observation modified
  assert_state wezterm applied_hash "$WEZTERM_TWO_HASH"
  assert_state wezterm observation updated
}

test_managed_missing() {
  local fish_path
  reset_case
  fish_path=$(config_path fish/config.fish)
  write_user_file "$fish_path" "$FISH_ONE"
  write_user_file "$(config_path wezterm/wezterm.lua)" "$WEZTERM_ONE"
  write_managed_state seeded "$FISH_ONE_HASH" "$FISH_ONE_HASH" "$WEZTERM_ONE_HASH" "$WEZTERM_ONE_HASH"
  rm -- "$fish_path"
  run_updater || fail 'managed-missing case failed'
  assert_absent "$fish_path"
  assert_state fish mode managed
  assert_state fish applied_hash "$FISH_ONE_HASH"
  assert_state fish observation missing
}

test_unrecognized_and_symlink_target() {
  local path
  reset_case
  path=$(config_path fish/config.fish)
  write_user_file "$path" "$FISH_CUSTOM"
  run_updater || fail 'unrecognized-file case failed'
  assert_file_content "$path" "$FISH_CUSTOM"
  assert_state fish observation unrecognized

  reset_case
  path=$(config_path fish/config.fish)
  write_user_file "$OUTSIDE_FILE" "$FISH_CUSTOM"
  mkdir -p -- "${path%/*}"
  if ((RUN_UNPRIVILEGED)); then
    chown -R "$TEST_UID:$TEST_GID" -- "$CASE_HOME"
  fi
  ln -s -- "$OUTSIDE_FILE" "$path"
  run_updater || fail 'symlink-target case failed'
  [[ -L $path ]] || fail 'symlink target was replaced'
  assert_file_content "$OUTSIDE_FILE" "$FISH_CUSTOM"
  assert_state fish observation unsafe
}

test_pending_before_replacement() {
  local path temp
  reset_case
  path=$(config_path fish/config.fish)
  write_user_file "$path" "$FISH_OLD"
  write_user_file "$(config_path wezterm/wezterm.lua)" "$WEZTERM_ONE"
  temp=$(write_pending_state "$FISH_OLD_HASH" "$FISH_ONE_HASH")
  make_pending_temp "$temp"
  run_updater || fail 'pending-before-replacement recovery failed'
  assert_file_content "$path" "$FISH_ONE"
  assert_state fish applied_hash "$FISH_ONE_HASH"
  assert_state fish observation current
}

test_pending_after_replacement() {
  local path temp
  reset_case
  path=$(config_path fish/config.fish)
  write_user_file "$path" "$FISH_ONE"
  write_user_file "$(config_path wezterm/wezterm.lua)" "$WEZTERM_ONE"
  temp=$(write_pending_state "$FISH_OLD_HASH" "$FISH_ONE_HASH")
  rm -f -- "$temp"
  run_updater || fail 'pending-after-replacement recovery failed'
  assert_file_content "$path" "$FISH_ONE"
  assert_state fish applied_hash "$FISH_ONE_HASH"
  assert_state fish observation current
}

test_corrupted_pending_temp() {
  local path temp
  reset_case
  path=$(config_path fish/config.fish)
  write_user_file "$path" "$FISH_OLD"
  write_user_file "$(config_path wezterm/wezterm.lua)" "$WEZTERM_ONE"
  temp=$(write_pending_state "$FISH_OLD_HASH" "$FISH_ONE_HASH")
  make_pending_temp "$temp"
  printf '%s' 'corrupted pending content' > "$temp"
  run_updater || fail 'corrupted pending-temp recovery failed'
  assert_file_content "$path" "$FISH_OLD"
  assert_absent "$temp"
  assert_state fish mode managed
  assert_state fish applied_hash "$FISH_OLD_HASH"
  assert_state fish observation modified
  assert_state wezterm observation current
}

test_nested_parent_symlink() {
  local path real_parent
  reset_case
  path=$(config_path fish/config.fish)
  real_parent="$CASE_HOME/real-fish"
  write_user_file "$real_parent/config.fish" "$FISH_OLD"
  mkdir -p -- "$CASE_HOME/.config"
  if ((RUN_UNPRIVILEGED)); then
    chown -R "$TEST_UID:$TEST_GID" -- "$CASE_HOME"
  fi
  ln -s -- "$real_parent" "${path%/*}"
  run_updater || fail 'nested-parent symlink case failed'
  [[ -L ${path%/*} ]] || fail 'nested parent symlink was replaced'
  assert_file_content "$real_parent/config.fish" "$FISH_OLD"
  assert_state fish mode unmanaged
  assert_state fish observation unsafe
}

test_unsafe_state_directory() {
  local path
  reset_case
  path=$(config_path fish/config.fish)
  write_user_file "$path" "$FISH_OLD"
  chmod 777 -- "$STATE_BASE"
  expect_failure
  assert_file_content "$path" "$FISH_OLD"
  assert_absent "$(state_path)"
}

test_production_root_validation() {
  local path
  reset_case
  path=$(config_path fish/config.fish)
  write_user_file "$path" "$FISH_OLD"
  chmod 775 -- "$DEFAULTS_ROOT"
  expect_failure
  assert_file_content "$path" "$FISH_OLD"
  assert_absent "$(state_path)"
}

test_untrusted_or_unsafe_state() {
  local path state outside
  reset_case
  path=$(config_path fish/config.fish)
  write_user_file "$path" "$FISH_OLD"
  write_user_file "$(config_path wezterm/wezterm.lua)" "$WEZTERM_OLD"
  write_managed_state seeded "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" "$FISH_ONE_HASH" "$WEZTERM_OLD_HASH" "$WEZTERM_ONE_HASH"
  state=$(<"$(state_path)")
  expect_failure
  assert_file_content "$path" "$FISH_OLD"
  assert_eq "$(<"$(state_path)")" "$state" 'untrusted state was modified'

  reset_case
  path=$(config_path fish/config.fish)
  write_user_file "$path" "$FISH_OLD"
  outside="$TEST_ROOT/unsafe-state"
  write_user_file "$outside" 'state'
  mkdir -p -- "$(dirname -- "$(state_path)")"
  ln -s -- "$outside" "$(state_path)"
  expect_failure
  assert_file_content "$path" "$FISH_OLD"
}

test_malformed_package() {
  local path
  reset_case
  path=$(config_path fish/config.fish)
  write_user_file "$path" "$FISH_OLD"
  printf '%s\n' 'not-a-manifest' > "$DEFAULTS_ROOT/manifest.tsv"
  chmod 644 -- "$DEFAULTS_ROOT/manifest.tsv"
  expect_failure
  assert_file_content "$path" "$FISH_OLD"
  assert_absent "$(state_path)"
}

test_lock() {
  local lock_path holder
  reset_case
  lock_path="$(state_path).lock"
  mkdir -p -- "${lock_path%/*}"
  : > "$lock_path"
  chmod 600 -- "$lock_path"
  if ((RUN_UNPRIVILEGED)); then
    chown "$TEST_UID:$TEST_GID" -- "$lock_path"
  fi
  (run_as_test_user bash -c "exec {fd}<> \"\$1\"; flock -n \"\$fd\"; sleep 1" _ "$lock_path") &
  holder=$!
  sleep 0.1
  expect_failure
  wait "$holder" || true
}

if [[ ! -x $UPDATER ]]; then
  fail "updater is not executable: $UPDATER"
fi

if ((EUID == 0)); then
  if command -v runuser >/dev/null 2>&1 && id nobody >/dev/null 2>&1; then
    TEST_USER=nobody
    TEST_UID=$(id -u nobody)
    TEST_GID=$(id -g nobody)
    RUN_UNPRIVILEGED=1
    chmod 755 -- "$TEST_ROOT"
    if "$UPDATER" >/dev/null 2>&1; then
      fail 'production updater did not reject root invocation'
    fi
    RUN_UPDATER="$TEST_ROOT/veldmuis-user-defaults-update"
    cp -- "$UPDATER" "$RUN_UPDATER"
    chmod 755 -- "$RUN_UPDATER"
  else
    printf 'SKIP: root guard was checked, but no unprivileged runner is available\n'
    exit 0
  fi
else
  printf 'SKIP: root invocation requires a root runner\n'
fi

test_current_hash_adoption
test_custom_xdg_config
test_historical_update
test_seeded_state
test_changed_managed_file_and_independent_update
test_managed_missing
test_unrecognized_and_symlink_target
test_pending_before_replacement
test_pending_after_replacement
test_corrupted_pending_temp
test_nested_parent_symlink
test_unsafe_state_directory
test_production_root_validation
test_untrusted_or_unsafe_state
test_malformed_package
test_lock

printf 'PASS: veldmuis-user-defaults-update harness\n'
