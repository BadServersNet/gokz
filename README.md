# GOKZ SourceMod Plugins (CS:GO)

GOKZ is a package of [SourceMod](https://www.sourcemod.net/about.php) plugins for CS:GO Kreedz (KZ) servers. The KZ game mode involves [speedrunning](https://en.wikipedia.org/wiki/Speedrun) through custom maps.

This is the [BadServers.net](https://badservers.net) version of GOKZ, maintained at [BadServersNet/gokz](https://github.com/BadServersNet/gokz). It is based on [KZGlobalTeam/gokz](https://github.com/KZGlobalTeam/gokz) and starts at version 4.0.0.

## Features

 * **Timer** - Times runs by automatically detecting the use of start and end buttons in KZ maps.
 * **Movement Modes** - Custom movement mechanics. Includes Vanilla, SimpleKZ, and KZTimer modes.
    * Mode plugins can be used alone (with only MovementAPI) to apply their mechanics at all times.
 * **Jumpstats** - Detailed statistics of your jumps and each individual air strafe.
 * **In-game Options** - Tonnes of options for players, providing them the best possible experience.
 * **Replays** - Record a replay of every run, store them in an S3-compatible bucket shared between your servers, and use bots to play them back.
 * **Anti-Cheat** - Detect and auto-ban blatant users of bhop macros and cheats (SourceBans++ supported).
 * **Database Support** - Store run times and more using either a MySQL or SQLite database. 
    * Player options are stored using the clientprefs extension.
 * **GlobalAPI Support** - Submit run times to the GlobalAPI so that players may compete across servers.
 * **Extensive Plugin API** - With forwards, natives, and modularity at its core, GOKZ is highly extensible.
 * Map bonus support, HUD, teleport menu, noclip, !goto, !measure, !race and much, much more.

For more information about what each plugin does, please see [PLUGINS.md](PLUGINS.md).

## Usage

### Server Requirements

 * 128 Tick (`-tickrate 128`)
 * [SourceMod ^1.11](https://www.sourcemod.net/downloads.php?branch=stable)
 * [DHooks Extension ^2.2.0](https://forums.alliedmods.net/showpost.php?p=2588686&postcount=589)
 * [MovementAPI Plugin ^2.4.2](https://github.com/danzayau/MovementAPI)
 * [S3 Extension ^0.2.0](https://github.com/BadServersNet/sm-s3/releases) (required for gokz-replays plugin)
 * Optional - [GlobalAPI Plugin](https://bitbucket.org/kztimerglobalteam/globalapi-smplugin) (required for gokz-globals plugin)
 * Optional - A "console cleaner" extension to prevent `Datatable warning` server console spam

### Installing

 * Ensure your server is up to date and meets the above requirements.
 * Download and extract `GOKZ-latest.zip` from the [Releases](https://github.com/KZGlobalTeam/gokz/releases) to `csgo`.
 * Add a MySQL or SQLite database called `gokz` to `csgo/addons/sourcemod/configs/databases.cfg`.
 * When the plugins first load, various configuration files will be auto-generated and can be found in `csgo/cfg/sourcemod/gokz`.
 * Use `sm_updatemappool` to populate the ranked map pool with those in `csgo/cfg/sourcemod/gokz/gokz-localranks-mappool.cfg`.

### Replay Storage

gokz-replays records a replay of every completed run, every jumpstat PB and every anti-cheat detection. Replays are kept in `csgo/addons/sourcemod/data/gokz-replays/cache` and, when the replay store is enabled, uploaded to an S3-compatible bucket so that every server sharing the same `gokz` database can play them back.

 * Create a bucket on Cloudflare R2 or any other S3-compatible service and an API token with object read and write permissions.
 * Set `gokz_replay_store_enabled 1`, `gokz_replay_store_endpoint`, `gokz_replay_store_bucket`, `gokz_replay_store_access_key` and `gokz_replay_store_secret_key` in `csgo/cfg/sourcemod/gokz/gokz-replays.cfg`. Use `gokz_replay_store_region auto` for R2 and `us-east-1` for MinIO or AWS.
 * Optionally connect a public custom domain to the bucket and set `gokz_replay_store_public_url` so downloads are served through the CDN.
 * Run `sm_replaystore_check` from the server console to verify the credentials, and `sm_replaystore_status` to see the upload queue.
 * Failed uploads are retried forever with a backoff of up to five minutes and survive map changes and restarts; `sm_replaystore_flush` retries everything immediately.
 * All servers that share a `gokz` database must share the same bucket.

Please refer to the forum for a [more detailed installation guide](https://forum.gokz.org/p/guide-gokz).

### Updating

 * Minor updates - Download and extract `GOKZ-latest-upgrade.zip` from the [Releases](https://github.com/KZGlobalTeam/gokz/releases) to `csgo`.
 * Major updates - Check the new version's release notes for specific instructions.

### Commands

Please see [COMMANDS.md](COMMANDS.md) for a list of player and admin commands.

### Mapping

Please see the [Mapping-API](https://github.com/KZGlobalTeam/gokz/wiki/Mapping-API) to see how to make maps that work with GOKZ.

## Contributing

GOKZ is an open-source, community-driven project. If you are interested in helping out, please see [CONTRIBUTING.md](CONTRIBUTING.md) for more details.

## Authors

 * **DanZay** - danzayau@gmail.com - [*Steam*](https://steamcommunity.com/id/DanZay)
 * **zealain** - zealained@gmail.com - [*Steam*](https://steamcommunity.com/id/zealain)
 * **KZTimerGlobal Team** - [*GitHub*](https://github.com/KZGlobalTeam)

## Links

[Forum](https://forum.gokz.org)

[Discord](https://www.discord.gg/csgokz)

[Steam Group](https://steamcommunity.com/groups/GOKZTimer)

[Wiki](https://github.com/KZGlobalTeam/gokz/wiki)
