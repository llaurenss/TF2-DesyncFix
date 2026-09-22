# TF2-DesyncFix

Fixes the rocket desync by simulating the rockets per each owner's usercommand (same as jumpQoL). Works on 64bit and with the TAS addon.

untested on 64bit linux.

If you're on 32bit or when jumpQoL (https://github.com/chrb22/jumpqol) supports 64bit you should use that as its the more complete fix and includes other jump related fixes/improvements.

Download compiled plugin here: https://github.com/llaurenss/TF2-DesyncFix/releases

## Convars
- `sm_desyncfix_enabled 1` - Enables or disables the fix.
- `sm_desyncfix_noncmd 1` - Whether non player spawned rockets (TAS spawned rockets for example) should also be simulated per the owner's usercommand.
- `sm_desyncfix_noncmd_offset 0` - Adds a simulation offset in ticks at spawn for non player spawned rockets. Both positive and negative values are supported.
