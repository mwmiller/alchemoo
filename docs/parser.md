# Database Parser Implementation

## Overview

`Alchemoo.Database.Parser` currently parses LambdaMOO **Format Version 4** files and builds an in-memory `%Alchemoo.Database{}` with:
- objects
- verb metadata plus verb code blocks
- local and inherited property values
- parent/child/content relationship lists

## Format 4 Structure

```text
** LambdaMOO Database, Format Version 4 **
<object_count>
<verb_count>
<dummy>
<user_count>
<user ids...>

# Object Definitions
#<N>
<name>
<handles>
<flags>
<owner>
<location>
<contents>
<next>
<parent>
<child>
<sibling>
<verb_count>
<verb_name>
<verb_owner>
<verb_perms>
<verb_prep>
...
<property_count>
<property_name>
...
<property_value_count>
<typed property values + owner/perms>

# Verb Code Section
#<objnum>:<verbnum>
<code line>
<code line>
...
.
```

## Current Parser Flow

1. Parse header and metadata (Format 4 only)
2. Parse the declared object count
3. Parse object structure, verb headers, and property names/values
4. Parse trailing `#obj:verb` code blocks
5. Build relationship lists (`children`, `contents`)
6. Resolve inherited properties into `overridden_properties` and `all_properties`

## Usage

```elixir
content = File.read!("LambdaCore.db")
{:ok, db} = Alchemoo.Database.Parser.parse(content)

system = db.objects[0]
[first_verb | _] = system.verbs
[first_prop | _] = system.properties
```

## Notes / Limitations

- `parse_file/1` is not currently exposed; use `File.read!/1` plus `parse/1`.
- Float-typed DB values are currently represented as `{:float, raw_string}`.
- Parser currently targets Format 4 only.
