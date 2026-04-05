# Handoff: Parser Stabilization & Cleanup

## Current State
- **Parser Rename**: `MOOSimple` is now `Alchemoo.MOOCode.Parser` with proper module structure.
- **Tokenizer**: `Alchemoo.Parser.Expression` uses a prioritized, iterative tokenizer that correctly handles object IDs (`#0`) and multi-char operators (`!=`).
- **Block Parsing**: `Program.ex` uses a strict, nesting-aware line processor.
- **Test Vectors**: `vectors_test.exs` contains 24 critical LambdaCore patterns — **all passing**.

## Known Issues
- **None** — all 24 parser vector tests pass. The precedence bug with `if (caller != #0)` was resolved.

## Key Files
- `lib/alchemoo/parser/expression.ex`: Recursive descent expression parser.
- `lib/alchemoo/parser/program.ex`: Line-level block parser.
- `test/alchemoo/parser/vectors_test.exs`: 24 LambdaCore parsing test vectors.

## Documentation Maintenance

**This documentation MUST be kept in sync with the codebase.** Whenever parser issues are resolved or new ones arise, update this file accordingly. Remove resolved issues and keep the known issues section current.
