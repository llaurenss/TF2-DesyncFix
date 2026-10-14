# TF2-DesyncFix

Fixes the rocket desync by simulating the rockets per each owner's usercommand (same as jumpQoL). Works on 64-bit and with the TAS addon.

If you're on 32-bit or when jumpQoL (https://github.com/chrb22/jumpqol) supports 64bit you should use that as its the more complete fix and includes other jump related fixes/improvements.

## Install
1. Download [Metamod](https://www.sourcemm.net/downloads.php?branch=stable) and [Sourcemod](https://www.sourcemod.net/downloads.php?branch=stable) (stable branch). Extract both archives and copy their contents in your `Team Fortress 2\tf` folder.
2. Download the compiled plugin here https://github.com/llaurenss/TF2-DesyncFix/releases. Extract the archive and copy its contents into `Team Fortress 2\tf\addons\sourcemod`.
3. Add ` -insecure` to your TF2 launch options to allow the addons to load.
4. And that's it! To verify that the plugin is loaded you can use the console command `sm plugins list`. 

### Linux (64-bit listen server)
To get Metamod and Sourcemod working on the 64-bit Linux TF2 client (listen server), you need to create four symlinks.
Open the terminal in the `Team Fortress 2` folder and run these 4 commands to create the symlinks:
```
ln -sv libtier0.so   bin/linux64/libtier0_srv.so
ln -sv libvstdlib.so bin/linux64/libvstdlib_srv.so
ln -sv engine.so     bin/linux64/engine_srv.so
ln -sv server.so     tf/bin/linux64/server_srv.so
```

## Convars
- `sm_desyncfix_enabled 1` - Enables or disables the fix.
- `sm_desyncfix_noncmd 1` - Whether non player spawned rockets (TAS spawned rockets for example) should also be simulated per the owner's usercommand.
- `sm_desyncfix_noncmd_offset 0` - Adds a simulation offset in ticks at spawn for non player spawned rockets. Both positive and negative values are supported.

<br>
