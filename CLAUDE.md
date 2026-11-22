# PH:X Prop Hunt (Garry's Mod gamemode)

You are maintaining PH:X, a Prop Hunt gamemode for Garry's Mod written in GLua.

## Commands

- `tools/dev-setup.sh` - installs CI-pinned glualint to ~/.local/bin and GMod API defs to `.luals/` (needed by .luarc.json)
- `glualint --config glualint.json lint <path>` - same check as CI; only `[Error]` fails (~160 existing warnings are accepted)
- `.github/scripts/luatest/run.sh` - behaviour tests: runs shipped functions under a stubbed GMod in LuaJIT
- `python3 .github/scripts/check_langs.py` / `check_net_receivers.py` - translation and net.Receive sender checks

## Gotchas

- GLua syntax (`!=`, `&&`, `||`, `!`, `//`, `continue`) is valid here; don't "fix" it
- glualint and LuaLS passing ≠ working; prove gameplay changes with a luatest case
- List each new client file with `AddCSLuaFile` in `gamemodes/base_phx/gamemode/init.lua`; unlisted files are not sent to players
- Edits under `materials/` don't reach players; clients load the workshop addon named in `resource.AddWorkshop` (prop_hunt `init.lua`)
- `derma.DefineControl` creates globals; add new ones to `diagnostics.globals` in .luarc.json
- `.claude/hooks/glualint-on-edit.sh` lints each edited .lua file and reports errors only

## CI

- Smoke test (srcds + 4 bots) runs weekly, on dispatch, or when smoke-test.yml changes
- Renovate skips glualint (it is pinned by version and SHA-256 checksum in glualint.yml); bump both there by hand, then rerun tools/dev-setup.sh
