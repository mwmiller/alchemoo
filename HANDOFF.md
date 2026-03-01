# Handoff: Parser Stabilization & Cleanup

## Current State
- **Parser Rename**: `MOOSimple` is now `Alchemoo.Parser.Program`. All references updated.
- **Tokenizer**: `Alchemoo.Parser.Expression` now uses a prioritized, iterative tokenizer that correctly handles object IDs (`#0`) and multi-char operators (`!=`).
- **Block Parsing**: `Program.ex` uses a strict, nesting-aware line processor that resolved most block-level errors.
- **Test Vectors**: `vectors_test.exs` contains 24 critical LambdaCore patterns.

## Known Issues
- **Precedence Bug**: `if (caller != #0)` fails with `:expected_closing_paren`. The `Expression` parser's recursive descent logic (specifically `parse_comparison` or `parse_additive`) is likely "greedy" and consuming the closing parenthesis as part of the expression instead of stopping.
- **Remaining Failures**: 4 parser tests failing (Vectors #12, Nested Structure, Backtick Catch, Comment Stripping).

## Next Steps
1.  **Fix Precedence Consumption**: Modify `Expression.parse_comparison` (and other levels) to explicitly *peek* at the next token and stop if it's not a valid operator for that level. Currently, it seems to be recursing unconditionally.
2.  **Verify Vectors**: Ensure all 24 vectors in `vectors_test.exs` pass.
3.  **Clean Cleanup**: Verify `lib/alchemoo/parser/moo_simple.ex` is truly gone from git index.

## Key Files
- `lib/alchemoo/parser/expression.ex`: The recursive descent logic needing the fix.
- `lib/alchemoo/parser/program.ex`: The line-level block parser (mostly stable).
- `test/alchemoo/parser/vectors_test.exs`: The "bible" of failing cases.
