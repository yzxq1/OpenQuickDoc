#!/usr/bin/env bash
# 编译并运行单元测试（测试 Shared/ 下的真实代码）
set -euo pipefail
cd "$(dirname "$0")"
OUT="$(mktemp -d)/oqd-tests"
swiftc -target "$(uname -m)-apple-macos13.0" -o "$OUT" Shared/*.swift Tests/main.swift
"$OUT" "$PWD/Resources"
