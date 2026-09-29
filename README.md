# prophunt

This prophunt gamemode was not created by me. All credit goes to Wolvindra-Vinzuerio and Kowalski. This prophunt gamemode is just an edited version.

It is Prop Hunt: X2Z ("PH:X") for Garry's Mod, with bug fixes and a test
suite on top. The license terms are in the header of
`gamemodes/prop_hunt/gamemode/sh_init.lua`.

## What is in the repository

| Path | What it is |
| --- | --- |
| `gamemodes/prop_hunt/` | The gamemode itself (`Prop Hunt: X2Z`). It derives from `base_phx`. |
| `gamemodes/base_phx/` | The modified Fretta base that `prop_hunt` derives from. |
| `lua/autorun/` | The PH:X integrity checker, which warns about conflicting addons. |
| `materials/`, `models/`, `particles/`, `sound/` | Content the server uses. Clients get their copy from the Workshop (see below). |
| `.github/` | CI workflows and the checks they run (see [Development](#development)). |

## Installing on a server

1. Copy `gamemodes/`, `lua/`, `materials/`, `models/`, `particles/` and `sound/`
   into the server's `garrysmod/` folder, merging with what is already there.
2. Start the server with `+gamemode prop_hunt` and a Prop Hunt map. No maps
   ship with this repository. The built-in map vote offers maps whose names
   start with `phx_` or `ph_` (`mv_map_prefix`).
3. Clients download the gamemode's content from Workshop item
   [2176546751](https://steamcommunity.com/sharedfiles/filedetails/?id=2176546751),
   which `gamemodes/prop_hunt/gamemode/init.lua` registers with
   `resource.AddWorkshop`. Changing a file under `materials/`, `models/` or
   `sound/` here changes nothing for players until that Workshop item is
   updated.

### Configuring

Most settings are in the in-game menu: press **F1**, then **Prop Hunt Menu**.
Server settings in that menu are only open to groups in `PHX.SVAdmins`, which
starts as `superadmin` and is edited from the same menu. Every setting is also
a console variable, so it can go in `server.cfg`. A few of the main ones:

| Cvar | Default | What it does |
| --- | --- | --- |
| `ph_round_time` | 300 | Seconds per round (map restart). |
| `ph_rounds_per_map` | 10 | Rounds played on one map (map restart). |
| `ph_hunter_blindlock_time` | 30 | Seconds hunters stay blinded at round start. |
| `ph_min_waitforplayers` | 2 | Players needed before a round starts. |
| `ph_waitforplayers` | 0 | When 1, rounds also do not count until each team has `ph_min_waitforplayers` players. |
| `ph_swap_teams_every_round`, `ph_enable_teambalance` | 1, 1 | Team rotation and balancing. |
| `ph_use_unstuck` | 0 | Built-in `!unstuck` command and key. Leave off if an addon does this. |
| `ph_enable_mapvote` | 1 | Built-in map vote. `mv_*` cvars configure it. |
| `pcr_enable` | 1 | Prop Menu (props pick a model from a list). `pcr_*` cvars configure it. |
| `lps_enable` | 1 | Last Prop Standing: the last prop alive gets a weapon. `lps_*` cvars configure it. |
| `ph_use_lang`, `ph_force_lang` | 0, en_us | Force one language on every player. |

The full list, with help text, is in `gamemodes/prop_hunt/gamemode/sh_convar.lua`
(plus `enhancedplus/sh_enhancedplus.lua` and the plugins under `plugins/`).

### Optional: ULX / ULib

ULX is not required. When it is installed, PH:X adds `ulx phforceend`,
`ulx phmenu` and `ulx ph3padjust`, the map vote and Prop Menu can use ULX
commands and ULX's map list (`mv_use_ulx_votemaps`, `pcr_use_ulx_menu`), and
who may mute whom on the scoreboard follows ULX group inheritance. Without it,
the server log shows `WARNING: ULX is not installed!` lines, which are expected.

## Development

### Checks

CI runs these (`.github/workflows/`):

| Workflow | What it checks |
| --- | --- |
| `glualint.yml` | [glualint](https://github.com/FPtje/GLuaFixer) 1.30.0 over every Lua file, with the settings in `glualint.json`. Only syntax errors fail it; warnings are annotations. |
| `static-checks.yml` | Translations against `english.lua` (keys, and format specifiers in number, order and type); a sender-validation report on server `net.Receive` handlers and a self-test of that checker; the Lua behaviour tests; and [zizmor](https://docs.zizmor.sh) over the workflows. |
| `smoke-test.yml` | Boots a real dedicated server with the gamemode and four bots, and fails on any Lua error. Several GB to download, so it runs weekly, on demand, and on pull requests that change it. |

### Running them locally

From the repository root, with `python3` and `luajit` (or `lua5.1`):

```sh
bash .github/scripts/luatest/run.sh                 # behaviour tests + parse check of every Lua file
python3 .github/scripts/check_langs.py              # translation gate
python3 .github/scripts/test_check_net_receivers.py # net checker self-test
python3 .github/scripts/check_net_receivers.py      # net.Receive sender report
glualint --config glualint.json lint .              # if glualint is installed
```

`run.sh` warns if your LuaJIT accepts GLua syntax (`!=`, `&&`, `!`) itself.
Under such a build a mistake in the GLua-to-Lua translation cannot fail
locally, so run it again with `LUA=lua5.1` before relying on the result.

### Behaviour tests

`glualint` and Codacy both pass code that errors the moment a player touches
it, so gameplay rules are tested by executing the shipped code. Each
`.github/scripts/luatest/t_*.lua` file loads `runner.lua`, pulls the real
functions out of the gamemode with `extract(path, "<regex for the first line>")`,
runs them against the stubbed Garry's Mod in `shim.lua`, and asserts with
`check(name, got, want)` and `report()`. Extract by regex rather than by line
numbers, so a test does not break when lines are added above the code. Before
trusting a new assertion, break the code it covers and make sure it fails.

### Things that are easy to get wrong

- A new client-side (`cl_` or `sh_`) file has to be sent to clients with
  `AddCSLuaFile`. See the lists at the top of
  `gamemodes/prop_hunt/gamemode/init.lua` and `sh_init.lua`, and
  `gamemodes/base_phx/gamemode/init.lua`. Files under `langs/`, `config/lib/`
  and `config/external/` are sent automatically.
- `english.lua` is the reference language. Lua's `string.format` has no
  positional arguments, so a translation has to keep english's `%s`/`%d` order
  and reword the sentence around it.
- `PHX:FTranslate` returns the key itself when english lacks the string too,
  so an `or "fallback"` after it never runs.
