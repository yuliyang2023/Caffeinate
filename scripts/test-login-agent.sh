#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -sdk "$(xcrun --show-sdk-path)" \
    Caffeinate/Settings/ConfigData.swift \
    Caffeinate/Settings/ConfigHandler.swift \
    tests/login-agent/main.swift \
    -o .build/test-login-agent
.build/test-login-agent
