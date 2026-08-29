#!/usr/bin/env bash
set -euo pipefail

pass_count=0
warn_count=0
fail_count=0

pass() {
  pass_count=$((pass_count + 1))
  printf 'PASS  %s\n' "$1"
}

warn() {
  warn_count=$((warn_count + 1))
  printf 'WARN  %s\n' "$1"
}

fail() {
  fail_count=$((fail_count + 1))
  printf 'FAIL  %s\n' "$1"
}

check_required() {
  local command_name=$1
  if command -v "$command_name" >/dev/null 2>&1; then
    pass "$command_name $($command_name --version 2>&1 | head -n 1)"
  else
    fail "$command_name unavailable"
  fi
}

check_required git

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  pass "docker $(docker --version)"
else
  fail "docker engine unavailable"
fi

if docker compose version >/dev/null 2>&1; then
  pass "compose $(docker compose version --short)"
else
  fail "compose unavailable"
fi

check_required make

available_kib=$(df -Pk . | awk 'NR == 2 { print $4 }')
if [ "$available_kib" -ge 10485760 ]; then
  pass "disk $((available_kib / 1024 / 1024)) GiB available"
else
  fail "disk less than 10 GiB available"
fi

if systemctl is-active --quiet bluetooth 2>/dev/null; then
  pass "bluetooth service active"
else
  warn "bluetooth service inactive or unavailable"
fi

if command -v bluetoothctl >/dev/null 2>&1 && bluetoothctl show >/dev/null 2>&1; then
  pass "bluetooth controller available"
else
  warn "bluetooth controller unavailable"
fi

if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
  pass "kvm accessible"
else
  warn "kvm unavailable; it is not required by canonical builds"
fi

if command -v lsusb >/dev/null 2>&1 && lsusb | grep -q .; then
  pass "usb devices visible"
else
  warn "usb visibility unavailable"
fi

if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then
    pass "gh authenticated"
  else
    warn "gh installed but not authenticated"
  fi
else
  warn "gh unavailable; it is optional until cloud workflows are used"
fi

if [ "$(uname -s)" = Darwin ] && command -v xcodebuild >/dev/null 2>&1; then
  pass "xcode $(xcodebuild -version | tr '\n' ' ')"
else
  printf 'INFO  xcode unavailable on Linux (expected)\n'
fi

printf 'SUMMARY pass=%d warn=%d fail=%d\n' "$pass_count" "$warn_count" "$fail_count"

if [ "$fail_count" -ne 0 ]; then
  exit 1
fi
