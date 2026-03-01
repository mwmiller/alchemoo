# Alchemoo Handoff - March 1, 2026

## Current State
- **Version**: 0.6.3
- **Stability**: High. All 161 tests passing. `mix precommit` is clean.
- **Key Fixes**:
    - **Permissions**: Implemented full MOO-compatible permission checks for objects, properties, and verbs.
    - **Verb Execution**: Enforced `VF_EXEC` (x) bit and implemented `setuid` logic (verbs run as owner if `x` is set).
    - **Command Parsing**: Implemented full multi-word preposition matching aligned with LambdaMOO `prep_list`.
    - **Synchronous Commands**: Refactored `#0:do_command` to be synchronous with proper fallback to internal parser.
    - **Security Defaults**: Changed default task permissions to `-1` (NOTHING) for safety.
- **New Features**:
    - **Preposition Support**: Robust multi-word preposition matching in the command parser.
    - **Permission System**: A dedicated `Permissions` module for centralized security logic.
    - **Synchronous Tasks**: Support for synchronous task execution in `Alchemoo.Task.run/3`.

## Pending Tasks / Future Work
1.  **WebSocket Support**: Implement the WebSocket transport.
2.  **Performance**: Optimize interpreter hot paths and database lookups.
3.  **Network Stubs**: Complete `listen`, `unlisten`, and `open_network_connection`.

## Notes for Next Agent
- The system now correctly falls back to `test/fixtures/lambdacore.db` if no checkpoints exist.
- Always clear `~/.local/state/alchemoo/*` if you make major changes to the parser or core object structures to ensure a fresh re-parse.
- The `SSH.Readline` module handles its own echo; `client-echo` should stay at `1` for SSH connections.
- Top-level `Runtime.call_verb` calls now automatically establish a default wizard context (#2) if none exists, primarily for testing and external Elixir calls.
