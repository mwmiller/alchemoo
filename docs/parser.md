# Database Parser Implementation

## Overview

The Alchemoo database parser successfully reads LambdaMOO Format Version 4 database files, extracting all objects, verbs, properties, and code.

## Format 4 Structure

```
** LambdaMOO Database, Format Version 4 **
<object_count>
<verb_count>
<dummy>
<user_count>
<dummy>
<clocks>
<queued>
<suspended>

# Object Definitions
#<N>
<name>
<flags (can be empty line)>
<owner>
<location>
<contents>
<next>
<parent>
<child>
<sibling>
<unknown field>
<verb_count>
<verb_name>
<verb_owner>
<verb_perms>
<verb_prep>
...
<property_count>
<property_name>
...
<property values and metadata>

# Verb Code Section
#<objnum>:<verbnum>
<code line>
<code line>
...
.
```

## Implementation Details

### Key Challenges Solved

1. **Unknown field after sibling** - Format 4 has an extra integer field after the sibling field
2. **Property values** - Properties have extensive metadata after the names that must be skipped
3. **Verb code separation** - Verb code is stored separately after all objects
4. **Distinguishing markers** - Must differentiate between `#N` (object) and `#N:N` (verb code)

### Parser Flow

1. Parse header and metadata
2. Parse N objects (structure only)
3. Skip property values/metadata
4. Parse verb code section
5. Update objects with their verb code

## Test Results

Successfully parses LambdaCore-12Apr99.db:
- 95 objects
- 1,699 verbs
- 1,697 verbs with code
- All object relationships preserved

## Usage

```elixir
{:ok, db} = Alchemoo.Database.Parser.parse_file("LambdaCore.db")

# Access objects
system = db.objects[0]

# Access verbs
[first_verb | _] = system.verbs
IO.inspect(first_verb.code)

# Access properties
[first_prop | _] = system.properties
IO.inspect(first_prop.name)
```

## Next Steps

- [ ] Parse property values (currently skipped)
- [ ] Support Format Version 1-3
- [ ] Optimize for large databases
- [ ] Add streaming parser for memory efficiency
