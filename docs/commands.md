# Command System

Alchemoo implements the full MOO command execution pipeline, parsing player input and executing verbs from the database.

## Architecture

```
Player Input → Parser → Executor → Database → Task → Output
```

### Command.Parser

Parses raw command strings into structured verb calls.

**Syntax:**
```
verb [dobj] [prep] [iobj]
```

**Examples:**
```
look                    → {verb: "look", dobj: nil, prep: nil, iobj: nil}
look me                 → {verb: "look", dobj: "me", prep: nil, iobj: nil}
get ball                → {verb: "get", dobj: "ball", prep: nil, iobj: nil}
put ball in box         → {verb: "put", dobj: "ball", prep: "in", iobj: "box"}
give ball to wizard     → {verb: "give", dobj: "ball", prep: "to", iobj: "wizard"}
```

### Command.Executor

Executes parsed commands by finding and running verbs.

**Verb Search Order:**
1. Player's verbs
2. Player's location verbs
3. Direct object verbs
4. Indirect object verbs

**Environment Variables:**

The executor builds a complete MOO environment for verb execution:

| Variable | Type | Description |
|----------|------|-------------|
| `player` | OBJ | Current player object |
| `this` | OBJ | Object the verb is defined on |
| `caller` | OBJ | Calling object (same as player for commands) |
| `verb` | STR | Verb name as typed |
| `argstr` | STR | Full argument string |
| `args` | LIST | List of argument strings |
| `dobj` | STR | Direct object string |
| `dobjstr` | STR | Direct object string (alias) |
| `prepstr` | STR | Preposition string |
| `iobj` | STR | Indirect object string |
| `iobjstr` | STR | Indirect object string (alias) |

**Example:**

Command: `put ball in box`

Environment:
```moo
player = #2
this = #2
caller = #2
verb = "put"
argstr = "ball in box"
args = {"ball", "in", "box"}
dobj = "ball"
dobjstr = "ball"
prepstr = "in"
iobj = "box"
iobjstr = "box"
```

## Execution Flow

1. **Connection.Handler** receives input from player
2. **Command.Parser** parses command into structure
3. **Command.Executor** finds verb target
4. **Database.Server** looks up verb code
5. **TaskSupervisor** spawns task with environment
6. **Task** executes verb code
7. **Built-in notify()** sends output to player

## Built-in Commands

Alchemoo provides several built-in commands that bypass verb lookup:

- `quit` - Disconnect from server
- `@who` - List connected players
- `@stats` - Show database statistics

## Error Handling

**Verb Not Found:**
```
> asdf
I don't understand that.
```

**Empty Command:**
```
> 
> 
```

**Execution Error:**
```
> broken_verb
Error executing command: ...
```

## Integration with Task System

Commands spawn tasks with proper context:

```elixir
task_opts = [
  player: player_id,
  this: obj_id,
  caller: player_id,
  handler_pid: handler_pid,
  args: []
]
```

Tasks are:
- Limited to 10 per player (configurable)
- Killed on disconnect
- Tracked in Registry
- Subject to tick quotas

## Future Enhancements

### Object Matching

Currently, the executor only searches the player object. Full implementation should:

1. Parse object references (`me`, `here`, `#123`)
2. Search player's inventory
3. Search location contents
4. Match by name/alias

### Preposition Matching

Alchemoo implements full multi-word preposition matching aligned with LambdaMOO's `prep_list`. Verbs can specify valid prepositions:

```moo
@verb me:put this in/on/under that
```

The parser correctly identifies these and populates `prepstr` and the corresponding index.

### Wildcard Verbs

Support wildcard verb names:

```moo
@verb me:*smile
```

Matches: `smile`, `grin`, `beam`, etc.

### Direct/Indirect Object Types

Verbs specify object types:

```moo
@verb me:look this none none    // No objects
@verb me:get this none none     // Direct object only
@verb me:put this in that       // Both objects
```

The executor should validate object presence.

## Configuration

```elixir
# CONFIG: Maximum tasks per player
config :alchemoo, :max_tasks_per_player, 10

# CONFIG: Default tick quota per task
config :alchemoo, :default_tick_quota, 10_000
```

## Testing

See `test/alchemoo/command/parser_test.exs` and `test/alchemoo/command/executor_test.exs`.

## See Also

- [Task System](tasks.md)
- [Built-in Functions](builtins-status.md)
- [Database](database.md)
