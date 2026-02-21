# MOO Implementation Reference

Key information from the MOO FAQ for Alchemoo implementation.

## Core Databases

Three main core databases are widely used:

1. **LambdaCore** - The original, most commonly used
2. **JHCore** - LambdaCore-based with enhancements (hypertext help, MCP support, admin groups)
3. **enCore** - Educational-focused constructivist environment

## Server Architecture

### Memory Requirements
- LambdaCore database: ~2MB on disk
- Process size: 2-3x database file size in RAM
- MOO resides entirely in resident memory when running

### Data Type Representation (C structures)

MOO values are represented by `Var` structures with:
- `type`: TYPE_NUM, TYPE_OBJ, TYPE_ERR, TYPE_STR, or TYPE_LIST
- `v`: Union of different representations

**Lists**: 
- `x.v.list[0]` always contains the list length
- Actual elements start at `x.v.list[1]`
- Example: `{17, #3}` → `list[0].v.num = 2`, `list[1].v.num = 17`, `list[2].v.obj = 3`

### Key Functions
- `new_list()` - Allocate new list values
- `var_ref()` - Create new reference to existing value
- `var_dup()` - Make top-level copy
- `free_var()` - Discard reference
- `str_dup()` - Copy strings (strings are immutable!)

## Security Model

### Threats
- **Denial of Service**: MOO can consume all memory, CPU, or disk
- **Outbound Network**: If enabled, potential for connection laundering
- **No Filesystem Access**: Server provides no OS access by default

### Compile-Time Options (options.h)
- `OUTBOUND_NETWORK` - Enable network connections (required for email)
- Must be explicitly defined to enable

## Command Parser

The built-in command parser handles verb dispatch when users type commands.
See: LambdaMOO Programmer's Manual Section 8

## Implementation Notes for Alchemoo

### Data Structures
Our Elixir structs map to MOO's C structures:
- `Alchemoo.Database.Object` ≈ MOO object
- `Alchemoo.Database.Verb` ≈ MOO verb
- `Alchemoo.Database.Property` ≈ MOO property

### Value Representation
We'll need to implement MOO's 5 types in Elixir:
- NUM → integer
- OBJ → {:obj, integer}
- ERR → {:error, atom}
- STR → binary/string
- LIST → list (with length tracking)

### Immutability
MOO values are immutable - this maps perfectly to Elixir's immutable data structures!

### Memory Model
Unlike C MOO (entirely in RAM), we can leverage:
- ETS tables for hot data
- DETS/Mnesia for persistence
- Process-based isolation
- Garbage collection

### Concurrency
BEAM's actor model is superior to MOO's task system:
- Each active task → GenServer process
- Natural timeout handling
- Built-in process monitoring
- No manual memory management

## Next Steps

1. **Value System**: Implement MOO's 5 types in Elixir
2. **Verb Execution**: Build interpreter/bytecode compiler
3. **Task System**: Map MOO tasks to OTP processes
4. **Built-in Functions**: Implement ~150 MOO builtins
5. **Command Parser**: Handle user input and verb dispatch
6. **Network Layer**: Telnet/SSH with modern protocols

## References

- [MOO FAQ](https://www.moo.mud.org/moo-faq/)
- [LambdaMOO Programmer's Manual](ftp://ftp.research.att.com/dist/eostrom/MOO/html/ProgrammersManual.html)
- [LambdaMOO SourceForge](http://sourceforge.net/projects/lambdamoo/)
