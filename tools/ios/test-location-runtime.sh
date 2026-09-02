#!/usr/bin/env bash
set -euo pipefail
{
  cat tools/ios/location-runtime-shim.swift
  sed '/^import CoreLocation$/d; /^import BlueBandMapCore$/d' apps/ios/Adapters/Location/ForegroundLocationClient.swift
  cat tools/ios/location-runtime-tests.swift
} | docker compose run --rm -T swift swift -
