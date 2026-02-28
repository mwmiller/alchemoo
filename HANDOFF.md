# Alchemoo Handoff - Feb 28, 2026

## Current State
- **Version**: 0.6.2
- **Stability**: High. All 155 tests passing. `mix precommit` is clean.
- **Key Fixes**:
    - **Truthiness**: Objects are now correctly truthy per MOO spec.
    - **Property Alignment**: Fixed Format 4 resolution rule (local properties before inherited).
    - **Login**: Connection metadata (`last_connect_time`, `previous_connection`) is correctly rotated upon login, ensuring `@last-connection` shows accurate history.
    - **Checkpointing**: Robustness added to prevent empty (0 object) checkpoints from being saved or loaded.
- **New Features**:
    - **SSH Readline**: Stateful line editing with ANSI support and history.
    - **SSH Key Management**: MOO built-ins `ssh_list_keys`, `ssh_add_key`, `ssh_remove_key` are operational.
    - **Enhanced Checkpointing**: Separate prime-based timers for ETF and MOO; 24h retention policy for MOO files.

## Pending Tasks / Future Work
1.  **Preposition Validation**: Command parser needs full preposition matching.
2.  **WebSocket Support**: Implement the WebSocket transport.
3.  **Performance**: Optimize interpreter hot paths and database lookups.
4.  **Network Stubs**: Complete `listen`, `unlisten`, and `open_network_connection`.

## Notes for Next Agent
- The system now correctly falls back to `test/fixtures/lambdacore.db` if no checkpoints exist.
- Always clear `~/.local/state/alchemoo/*` if you make major changes to the parser or core object structures to ensure a fresh re-parse.
- The `SSH.Readline` module handles its own echo; `client-echo` should stay at `1` for SSH connections.
