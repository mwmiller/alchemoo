# MOO Built-in Functions Status

## Summary

- **Total MOO Built-ins:** ~150
- **Implemented:** 119
- **Remaining:** ~31
- **Critical for basic functionality:** Complete! ✅
- **Important for advanced functionality:** Complete! ✅

## Implemented (119)

### Type Conversion (6)
- ✅ `typeof(value)` - Get type
- ✅ `tostr(value)` - Convert to string
- ✅ `toint(value)` - Convert to integer
- ✅ `tonum(value)` - Alias for `toint`
- ✅ `toobj(value)` - Convert to object
- ✅ `toliteral(value)` - Convert to literal string

### List Operations (9)
- ✅ `length(list)` - Get length
- ✅ `is_member(value, list)` - Check membership
- ✅ `listappend(list, value)` - Append to list
- ✅ `listinsert(list, value, index)` - Insert into list
- ✅ `listdelete(list, index)` - Delete from list
- ✅ `listset(list, index, value)` - Set list element
- ✅ `setadd(list, value)` - Add to set
- ✅ `setremove(list, value)` - Remove from set
- ✅ `sort(list)` - Sort list

### Comparison (1)
- ✅ `equal(value1, value2)` - Deep equality

### Math (23)
- ✅ `random(max)` - Random number
- ✅ `min(...)` - Minimum value
- ✅ `max(...)` - Maximum value
- ✅ `abs(num)` - Absolute value
- ✅ `sqrt(num)` - Square root
- ✅ `sin(num)` - Sine
- ✅ `cos(num)` - Cosine
- ✅ `tan(num)` - Tangent
- ✅ `asin(num)` - Arc sine
- ✅ `acos(num)` - Arc cosine
- ✅ `atan(num)` - Arc tangent
- ✅ `sinh(num)` - Hyperbolic sine
- ✅ `cosh(num)` - Hyperbolic cosine
- ✅ `tanh(num)` - Hyperbolic tangent
- ✅ `exp(num)` - Exponential
- ✅ `log(num)` - Natural log
- ✅ `log10(num)` - Base-10 log
- ✅ `ceil(num)` - Ceiling
- ✅ `floor(num)` - Floor
- ✅ `trunc(num)` - Truncate

*Note: Trignometric and other math functions return scaled integers (x1000) if fractional values are not supported.*

### Time (2)
- ✅ `time()` - Current Unix timestamp
- ✅ `ctime(time)` - Format time as string

### String Operations (15)
- ✅ `length(str)` - String length (same as list)
- ✅ `index(str, substr)` - Find substring
- ✅ `rindex(str, substr)` - Find substring from end
- ✅ `strsub(str, old, new)` - Replace substring
- ✅ `strcmp(str1, str2)` - Compare strings
- ✅ `explode(str, delim)` - Split string
- ✅ `decode_binary(str)` - Decode binary (MOO ~XX format)
- ✅ `encode_binary(str)` - Encode binary (MOO ~XX format)
- ✅ `match(str, pattern)` - Pattern matching
- ✅ `rmatch(str, pattern)` - Reverse pattern matching
- ✅ `substitute(str, subs)` - Substitution
- ✅ `crypt(str [, salt])` - One-way password hashing
- ✅ `binary_hash(str)` - SHA-1 hash of a string
- ✅ `floatstr(num, precision)` - Format scaled integer as float string

### Output/Communication (5)
- ✅ `notify(player, text)` - Send text to player
- ✅ `connected_players()` - List online players
- ✅ `connection_name(player)` - Get connection info
- ✅ `boot_player(player)` - Disconnect player
- ✅ `buffered_output_length([player])` - Get output queue size

### Player/Object Context (6)
- ✅ `player()` - Get current player object
- ✅ `caller()` - Get calling object
- ✅ `this()` - Get current object
- ✅ `is_player(obj)` - Check if player
- ✅ `players()` - List all players in database
- ✅ `set_player_flag(obj, flag)` - Set/clear USER flag

### Object Operations (8)
- ✅ `valid(obj)` - Check if object exists
- ✅ `parent(obj)` - Get parent object
- ✅ `children(obj)` - Get child objects
- ✅ `max_object()` - Get highest object number
- ✅ `create(parent)` - Create new object
- ✅ `recycle(obj)` - Delete object
- ✅ `chparent(obj, parent)` - Change parent
- ✅ `move(obj, dest)` - Move object

### Property Operations (11)
- ✅ `properties(obj)` - List properties
- ✅ `property_info(obj, prop)` - Get property info
- ✅ `set_property_info(obj, name, info)` - Set property info
- ✅ `is_clear_property(obj, name)` - Check if clear
- ✅ `clear_property(obj, name)` - Clear property
- ✅ `add_property(obj, name, value, info)` - Add property
- ✅ `delete_property(obj, name)` - Delete property
- ✅ `get_property(obj, name)` - Internal get
- ✅ `set_property(obj, name, val)` - Internal set

### Verb Operations (11)
- ✅ `verbs(obj)` - List verbs
- ✅ `verb_info(obj, verb)` - Get verb info
- ✅ `set_verb_info(obj, verb, info)` - Set verb info
- ✅ `add_verb(obj, info, code)` - Add verb
- ✅ `delete_verb(obj, verb)` - Delete verb
- ✅ `verb_args(obj, verb)` - Get verb args
- ✅ `set_verb_args(obj, verb, args)` - Set verb args
- ✅ `verb_code(obj, verb)` - Get verb code
- ✅ `set_verb_code(obj, verb, code)` - Set verb code
- ✅ `function_info(name)` - Get built-in function info
- ✅ `disassemble(obj, verb)` - Get compiled code (source)

### Task Management (8)
- ✅ `suspend(seconds)` - Suspend current task
- ✅ `task_id()` - Get current task ID
- ✅ `queued_tasks()` - List all queued/suspended tasks
- ✅ `kill_task(id)` - Terminate specific task
- ✅ `raise(error)` - Raise a MOO error
- ✅ `call_function(name, args...)` - Dynamically call a built-in function
- ✅ `eval(string)` - Synchronously evaluate MOO code
- ✅ `queue_info(id)` - Get task metadata

### Security (3)
- ✅ `caller_perms()` - Get permissions of the calling object
- ✅ `set_task_perms(obj)` - Set permissions for the current task
- ✅ `callers()` - Get current call stack

### Network (6)
- ✅ `idle_seconds(player)` - Get idle time
- ✅ `connected_seconds(player)` - Get connection time
- ✅ `listen(obj, point)` - Start listening (returns E_PERM for now)
- ✅ `unlisten(point)` - Stop listening (returns E_PERM for now)
- ✅ `open_network_connection(host, port)` - Outbound connect (returns E_PERM for now)
- ✅ `force_input(player, text)` - Inject command

### Server Management (7)
- ✅ `server_version()` - Get server version
- ✅ `server_log(message)` - Log message
- ✅ `shutdown()` - Shutdown server
- ✅ `memory_usage()` - Get memory usage
- ✅ `db_disk_size()` - Get database file size
- ✅ `dump_database()` - Trigger immediate checkpoint
- ✅ `server_started()` - Get start time

### Utilities (5)
- ✅ `read_binary(filename)` - Read file (returns E_PERM for now)
- ✅ `object_bytes(obj)` - Get object memory size
- ✅ `value_bytes(value)` - Get value memory size
- ✅ `ticks_left()` - Get remaining ticks
- ✅ `seconds_left()` - Get remaining seconds

---

**This documentation is up to date as of Feb 22, 2026.**
