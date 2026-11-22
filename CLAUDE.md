# PH:X Prop Hunt (Garry's Mod gamemode)

## Commands
- `tools/dev-setup.sh` - installs CI-pinned glualint to ~/.local/bin and GMod API defs to `.luals/` (needed by .luarc.json)
- `glualint --config glualint.json lint <path>` - same check as CI; only `[Error]` fails (~160 existing warnings are accepted)
- `.github/scripts/luatest/run.sh` - behaviour tests: runs shipped functions under a stubbed GMod in LuaJIT
- `python3 .github/scripts/check_langs.py` / `check_net_receivers.py` - translation and net.Receive sender checks

## Gotchas
- GLua syntax (`!=`, `&&`, `||`, `!`, `//`, `continue`) is valid here; don't "fix" it
- glualint and LuaLS passing ≠ working; prove gameplay changes with a luatest case
- New client files must be `AddCSLuaFile`d in `gamemodes/base_phx/gamemode/init.lua` or players never get them
- Edits under `materials/` don't reach players; clients load workshop addon 2176546751
- `derma.DefineControl` creates globals; add new ones to `diagnostics.globals` in .luarc.json
- `.claude/hooks/glualint-on-edit.sh` lints each edited .lua file and reports errors only

## CI
- Smoke test (srcds + 4 bots) runs weekly, on dispatch, or when smoke-test.yml changes
- Renovate skips glualint (curl + SHA pin in glualint.yml); bump version and SHA there by hand, then rerun tools/dev-setup.sh
