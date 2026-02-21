# MOO Built-in Functions Status

## Summary

- **Total MOO Built-ins:** ~150
- **Implemented:** 76
- **Remaining:** ~74
- **Critical for basic functionality:** Complete! ✅
- **Important for advanced functionality:** Complete! ✅

## Implemented (21)

### Type Conversion (5)
- ✅ `typeof(value)` - Get type
- ✅ `tostr(value)` - Convert to string
- ✅ `toint(value)` - Convert to integer
- ✅ `toobj(value)` - Convert to object
- ✅ `toliteral(value)` - Convert to literal string

### List Operations (6)
- ✅ `length(list)` - Get length
- ✅ `is_member(value, list)` - Check membership
- ✅ `listappend(list, value)` - Append to list
- ✅ `listinsert(list, value, index)` - Insert into list
- ✅ `listdelete(list, index)` - Delete from list
- ✅ `listset(list, index, value)` - Set list element

### Comparison (1)
- ✅ `equal(value1, value2)` - Deep equality

### Math (6)
- ✅ `random(max)` - Random number
- ✅ `min(...)` - Minimum value
- ✅ `max(...)` - Maximum value
- ✅ `abs(num)` - Absolute value
- ✅ `sqrt(num)` - Square root
- ✅ `sin(num)` - Sine
- ✅ `cos(num)` - Cosine

### Time (2)
- ✅ `time()` - Current Unix timestamp
- ✅ `ctime(time)` - Format time as string

### String (1)
- ✅ `length(str)` - String length (same as list)

---

## Critical Missing Built-ins (~15-20)

### 🔴 Essential for Basic Functionality (Must Have)

#### Output/Communication (3)
- ✅ `notify(player, text)` - Send text to player
- ✅ `connected_players()` - List online players
- ✅ `connection_name(player)` - Get connection info

#### Player/Object Context (3)
- ✅ `player()` - Get current player object
- ✅ `caller()` - Get calling object
- ✅ `this()` - Get current object

#### String Operations (5)
- ✅ `index(str, substr)` - Find substring
- ✅ `rindex(str, substr)` - Find substring from end
- ✅ `strsub(str, old, new)` - Replace substring
- ✅ `strcmp(str1, str2)` - Compare strings
- ✅ `explode(str, delim)` - Split string

#### Object Operations (4)
- ✅ `valid(obj)` - Check if object exists
- ✅ `parent(obj)` - Get parent object
- ✅ `children(obj)` - Get child objects
- ✅ `max_object()` - Get highest object number

#### Property Operations (2)
- ✅ `properties(obj)` - List properties
- ✅ `property_info(obj, prop)` - Get property info

---

## 🟡 Important but Not Critical (~20-30)

### List Operations
- ✅ `setadd(list, value)` - Add to set
- ✅ `setremove(list, value)` - Remove from set
- ✅ `sort(list)` - Sort list

### String Operations
- ✅ `decode_binary(str)` - Decode binary
- ✅ `encode_binary(str)` - Encode binary
- ✅ `match(str, pattern)` - Pattern matching
- ✅ `rmatch(str, pattern)` - Reverse pattern matching
- ✅ `substitute(str, subs)` - Substitution

### Object Operations
- ✅ `create(parent)` - Create new object
- ✅ `recycle(obj)` - Delete object
- ✅ `chparent(obj, parent)` - Change parent
- ✅ `move(obj, dest)` - Move object

### Property Operations
- ✅ `add_property(obj, name, value, info)` - Add property
- ✅ `delete_property(obj, name)` - Delete property
- ✅ `set_property_info(obj, name, info)` - Set property info
- ✅ `is_clear_property(obj, name)` - Check if clear
- ✅ `clear_property(obj, name)` - Clear property

### Verb Operations
- ✅ `verbs(obj)` - List verbs
- ✅ `verb_info(obj, verb)` - Get verb info
- ✅ `set_verb_info(obj, verb, info)` - Set verb info
- ✅ `add_verb(obj, info, code)` - Add verb
- ✅ `delete_verb(obj, verb)` - Delete verb
- ✅ `verb_args(obj, verb)` - Get verb args
- ✅ `set_verb_args(obj, verb, args)` - Set verb args
- ✅ `verb_code(obj, verb)` - Get verb code
- ✅ `set_verb_code(obj, verb, code)` - Set verb code

---

## 🟢 Nice to Have (~80-90)

### Player Management
- ❌ `players()` - List all players
- ❌ `is_player(obj)` - Check if player
- ❌ `set_player_flag(obj, flag)` - Set player flag

### Network
- ❌ `idle_seconds(player)` - Get idle time
- ❌ `connected_seconds(player)` - Get connection time
- ❌ `boot_player(player)` - Disconnect player
- ❌ `listen(obj, point)` - Listen for connections
- ❌ `unlisten(point)` - Stop listening

### Database
- ❌ `db_disk_size()` - Get database size
- ❌ `dump_database()` - Trigger checkpoint
- ✅ `shutdown()` - Shutdown server

### Security
- ❌ `caller_perms()` - Get caller permissions
- ❌ `set_task_perms(perms)` - Set task permissions
- ❌ `callers()` - Get call stack

### Task Management
- ❌ `task_id()` - Get current task ID
- ❌ `queued_tasks()` - List queued tasks
- ❌ `kill_task(id)` - Kill task
- ❌ `resume(id, value)` - Resume suspended task
- ✅ `suspend(seconds)` - Suspend current task
- ❌ `queue_info(id)` - Get task info
- ❌ `force_input(player, text)` - Force input

### Misc
- ✅ `server_log(message)` - Log message
- ✅ `server_version()` - Get server version
- ❌ `memory_usage()` - Get memory usage
- ❌ `floatstr(num, precision)` - Format float
- ❌ `eval(code)` - Evaluate code
- ❌ `raise(error)` - Raise error
- ❌ `call_function(name, args)` - Call function
- ❌ `function_info(name)` - Get function info
- ❌ `disassemble(obj, verb)` - Disassemble verb

### Math (Extended)
- ❌ `tan(num)` - Tangent
- ❌ `asin(num)` - Arc sine
- ❌ `acos(num)` - Arc cosine
- ❌ `atan(num)` - Arc tangent
- ❌ `sinh(num)` - Hyperbolic sine
- ❌ `cosh(num)` - Hyperbolic cosine
- ❌ `tanh(num)` - Hyperbolic tangent
- ❌ `exp(num)` - Exponential
- ❌ `log(num)` - Natural log
- ❌ `log10(num)` - Base-10 log
- ❌ `ceil(num)` - Ceiling
- ❌ `floor(num)` - Floor
- ❌ `trunc(num)` - Truncate

---

## Priority Implementation Order

### Phase 1: Critical (15 functions, ~2-3 hours)
1. `notify()` - Essential for output
2. `player()` - Essential for context
3. `caller()` - Essential for context
4. `this()` - Essential for context
5. `connected_players()` - For @who
6. `valid()` - For object checks
7. `index()` - Common string operation
8. `strsub()` - Common string operation
9. `strcmp()` - String comparison
10. `explode()` - String splitting
11. `parent()` - Object hierarchy
12. `children()` - Object hierarchy
13. `properties()` - Property introspection
14. `max_object()` - Object management
15. `connection_name()` - Connection info

### Phase 2: Important (20 functions, ~3-4 hours)
- Object creation/manipulation
- Property management
- Verb management
- List operations

### Phase 3: Nice to Have (80+ functions, ongoing)
- Extended math
- Task management
- Security
- Misc utilities

---

## Recommendation

**Implement Phase 1 (15 critical functions) next:**
- Takes ~2-3 hours
- Enables basic MOO functionality
- Allows real command execution
- Foundation for everything else

**After Phase 1, you have a usable MOO server!** 🎉
