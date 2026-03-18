# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Reclamo is a Ruby gem that exposes Ruby objects (modules, classes, instances, namespaces) through JSON-RPC. It is network-agnostic — the gem handles JSON-RPC message parsing, method dispatch, and response serialization, while transport (HTTP, WebSocket, stdio, TCP, etc.) is the caller's responsibility.

Ruby >= 3.2 required.

## Commands

```bash
bin/setup              # Install dependencies
rake test              # Run all tests
rake rubocop           # Run linter
rake                   # Run tests + rubocop (default)
ruby -Ilib:test test/test_reclamo.rb                    # Run a single test file
ruby -Ilib:test test/test_reclamo.rb -n test_method     # Run a single test method
bin/console            # Interactive console with gem loaded
```

## Code Style

- Double quotes for all strings (enforced by RuboCop)
- `frozen_string_literal: true` at the top of every Ruby file
- Target Ruby version: 3.2

## Structure

- `lib/reclamo.rb` — main entry point
- `lib/reclamo/version.rb` — version constant
- `test/` — Minitest tests
- `sig/` — RBS type signatures
- `exe/` — CLI executables (if any)
