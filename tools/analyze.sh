#!/usr/bin/env bash
# Static analysis of all Luau sources against the real Roblox API + the built DataModel.
# Requires: sourcemap.json (written by tools/build.luau), luau-lsp and Roblox definitions.
set -euo pipefail
cd "$(dirname "$0")/.."
LSP=${LUAU_LSP:-/opt/tools/lsp/luau-lsp}
DEFS=${ROBLOX_DEFS:-/opt/tools/lsp/globalTypes.d.luau}
# The new solver is required: with the old one luau-lsp silently drops DataModel types.
"$LSP" analyze --flag:LuauSolverV2=true --sourcemap=sourcemap.json \
	--definitions=@roblox="$DEFS" --platform=roblox \
	$(find src -name '*.luau' | sort) 2>&1 | grep -v '^\[INFO\]\|didChangeWatchedFiles' || true
