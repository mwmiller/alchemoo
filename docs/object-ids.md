# Object ID Management

Alchemoo follows LambdaMOO's object ID allocation strategy to ensure compatibility.

## Object ID Allocation

### max_object()

The `max_object()` built-in returns the highest object ID that has ever been created, **not** the number of objects currently in the database.

```moo
max_object()  => #95  (even if only 50 objects exist)
```

This value **never decreases**, even when objects are recycled.

### Player Objects

**Player object IDs are never reused.** Once an object ID is assigned to a player, it remains permanently allocated, even if the player is deleted.

This ensures:
- Player references in logs remain valid
- Historical data integrity
- No confusion from ID reuse

### Non-Player Objects

**Non-player object IDs can be recycled.** When an object is recycled with `recycle()`, its ID is added to a pool of available IDs.

The next call to `create()` will:
1. Check if there are any recycled IDs available
2. If yes, reuse the lowest recycled ID
3. If no, increment `max_object()` and use the new ID

## Implementation

### State Tracking

The Database.Server maintains:

```elixir
%{
  max_object: 95,              # Highest ID ever created
  recycled_objects: [23, 45],  # Available for reuse (sorted)
  object_count: 93             # Current number of objects
}
```

### create() Algorithm

```moo
function create(parent)
  if (length(recycled_objects) > 0)
    // Reuse recycled ID
    new_id = recycled_objects[1]
    recycled_objects = recycled_objects[2..$]
  else
    // Allocate new ID
    max_object = max_object + 1
    new_id = max_object
  endif
  
  // Create object with new_id
  ...
endfunction
```

### recycle() Algorithm

```moo
function recycle(obj)
  object = get_object(obj)
  
  // Check if it's a player
  if (is_player(object))
    // Players cannot be recycled
    return E_PERM
  endif
  
  // Add to recycled pool
  recycled_objects = setadd(recycled_objects, obj)
  
  // Remove object
  delete_object(obj)
endfunction
```

## Examples

### Creating Objects

```moo
> max_object()
#95

> create($thing)
#96

> max_object()
#96

> create($thing)
#97
```

### Recycling and Reusing

```moo
> max_object()
#97

> recycle(#50)
// #50 is now available for reuse

> create($thing)
#50  // Reused recycled ID

> max_object()
#97  // Unchanged!

> create($thing)
#98  // No more recycled IDs, so increment
```

### Player Protection

```moo
> recycle(#2)  // Wizard player
E_PERM  // Cannot recycle players

> max_object()
#98  // Unchanged
```

## Database Statistics

The `@stats` command shows:

```
Database: 93 objects (max: #98, recycled: 2)
```

Where:
- **93 objects** - Current number of objects
- **max: #98** - Highest ID ever created
- **recycled: 2** - Number of IDs available for reuse

## Checkpoint Persistence

### Current Implementation

Checkpoints currently store:
- ✅ All objects
- ✅ max_object value
- ❌ recycled_objects list (TODO)

### Future Enhancement

Checkpoints should persist the recycled_objects list to maintain ID allocation consistency across restarts.

Without this, recycled IDs are lost on restart, and new objects will always get incrementing IDs until the next recycle.

## Configuration

No configuration needed - this behavior is part of MOO compatibility.

## See Also

- [Built-in Functions](builtins-status.md) - create(), recycle(), max_object()
- [Database](database.md) - Database structure
- [Checkpoint System](checkpoint.md) - Persistence
