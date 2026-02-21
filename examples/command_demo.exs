#!/usr/bin/env elixir

# Demo: Command Execution
#
# This demo shows the complete command execution pipeline:
# 1. Parse command
# 2. Find verb
# 3. Execute verb code
# 4. Send output to player

Mix.install([])

# Add lib to path
Code.prepend_path("_build/dev/lib/alchemoo/ebin")

alias Alchemoo.Command.{Parser, Executor}

IO.puts("\n=== Alchemoo Command Execution Demo ===\n")

# Test command parsing
IO.puts("1. Command Parsing")
IO.puts("-------------------")

commands = [
  "look",
  "look me",
  "get ball",
  "put ball in box",
  "give ball to wizard"
]

for cmd <- commands do
  {:ok, parsed} = Parser.parse(cmd)
  IO.puts("  #{inspect(cmd)}")
  IO.puts("    → verb: #{inspect(parsed.verb)}")
  IO.puts("    → dobj: #{inspect(parsed.dobj)}")
  IO.puts("    → prep: #{inspect(parsed.prep)}")
  IO.puts("    → iobj: #{inspect(parsed.iobj)}")
end

IO.puts("\n2. Command Execution Flow")
IO.puts("-------------------------")
IO.puts("""
  Player types: "look"
    ↓
  Connection.Handler receives input
    ↓
  Command.Parser parses command
    ↓
  Command.Executor finds verb
    ↓
  Database.Server looks up verb code
    ↓
  TaskSupervisor spawns task
    ↓
  Task executes verb code
    ↓
  notify() sends output to player
    ↓
  Player sees result
""")

IO.puts("3. MOO Environment Variables")
IO.puts("----------------------------")
IO.puts("""
  For command: "put ball in box"
  
  player   = #2              (current player)
  this     = #2              (object verb is on)
  caller   = #2              (calling object)
  verb     = "put"           (verb name)
  argstr   = "ball in box"   (full arguments)
  args     = {"ball", "in", "box"}
  dobj     = "ball"          (direct object)
  dobjstr  = "ball"          (alias)
  prepstr  = "in"            (preposition)
  iobj     = "box"           (indirect object)
  iobjstr  = "box"           (alias)
""")

IO.puts("4. Built-in Commands")
IO.puts("-------------------")
IO.puts("""
  quit     - Disconnect from server
  @who     - List connected players
  @stats   - Show database statistics
""")

IO.puts("\n=== Demo Complete ===\n")
IO.puts("To try it yourself:")
IO.puts("  1. Start server: mix run --no-halt")
IO.puts("  2. Connect: telnet localhost 7777")
IO.puts("  3. Type commands!")
