# TF2-DesyncFix

Fixes the rocket desync by simulating the rockets per each owner's usercommand (same as jumpQoL). Works on 64bit and with the TAS addon.

If you're on 32bit or when jumpQoL (https://github.com/chrb22/jumpqol) supports 64bit you should use that as its the more complete fix and includes other jump related fixes/improvements.

## Install
1. Download [Metamod](https://www.sourcemm.net/downloads.php?branch=stable) and [Sourcemod](https://www.sourcemod.net/downloads.php?branch=stable) (stable branch). Extract them and put them in your `Team Fortress 2\tf` folder.
2. Download the compiled plugin here https://github.com/llaurenss/TF2-DesyncFix/releases extract and put it in `Team Fortress 2\tf\addons\sourcemod`.
3. Add ` -insecure` to the TF2 launch options so that the addons will be loaded.
4. And that's it. If you want to make sure that it's working, check the plugin list with the console command `sm plugins list`. 

  \
To get Sourcemod and Metamod working on the 64bit linux listen server (normal TF2 client), you need to symlink 4 files.  
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
