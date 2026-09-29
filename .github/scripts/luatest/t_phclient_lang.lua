dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

-- Client translations: runs the shipped cl_lang.lua against every shipped main
-- and LPS language file, registered through the real Initialize hook.

CLIENT, SERVER = true, false

-- list.Get hands back a copy of what list.Set stored, as GMod does.
local lists = {}
list = {
  Set = function(n, k, v) lists[n] = lists[n] or {}; lists[n][k] = v end,
  Get = function(n) local r = {} for k, v in pairs(lists[n] or {}) do r[k] = v end return r end,
}
function PHX:GetCLCVar(n) return PHX:GetCVar(n) end

-- Language files are plain Lua data, so load their shipped bytes as they are
-- (extract.py would also warn about the word "continue" inside a string).
local repo = (debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "../../../"
local function loadLang(rel)
  local f = assert(io.open(repo .. rel, "r"))
  local src = f:read("*a")
  f:close()
  loadchunk(src, rel)()
end
local function ls(dir)
  local r = {}
  local h = io.popen("ls '" .. repo .. dir .. "'")
  for name in h:lines() do if name:match("%.lua$") then r[#r + 1] = dir .. "/" .. name end end
  h:close()
  if #r == 0 then error("EMPTY language directory: " .. dir) end
  return r
end

S.boolCVar("ph_use_lang", "0"); CreateConVar("ph_force_lang", "en_us"); CreateConVar("ph_cl_language", "en_us")
loadblocks("cl_lang.lua", extract("gamemodes/prop_hunt/gamemode/cl_lang.lua", "1-999999"))

local function boot()
  PHX.LANGUAGES = {}
  for _, f in ipairs(ls("gamemodes/prop_hunt/gamemode/langs")) do loadLang(f) end
  for _, f in ipairs(ls("gamemodes/prop_hunt/gamemode/plugins/lps/lang")) do loadLang(f) end
  return attempt(S.fire, "Initialize")
end
check("Initialize with every shipped language", boot(), "ok")
check("12 languages loaded", table.Count(PHX.LANGUAGES), 12)

local function as(lang, fn, ...)
  S.cvars["ph_cl_language"].v = lang
  local r = fn(PHX, ...)
  S.cvars["ph_cl_language"].v = "en_us"
  return r
end

print("\n== [#38/#78] PHX:Translate falls back to English ==")
local EN_LPS = PHX.LANGUAGES.en_us.LASTPROP_ANNOUNCE_ALL
check("LPS phrase reached English", EN_LPS, "The Last Prop is Resisting!")
check("en_us, LPS phrase", as("en_us", PHX.Translate, "LASTPROP_ANNOUNCE_ALL"), EN_LPS)
check("de, LPS phrase is still German's own", as("de", PHX.Translate, "LASTPROP_ANNOUNCE_ALL"),
      PHX.LANGUAGES.de.LASTPROP_ANNOUNCE_ALL)
check("tr, own phrase is still Turkish", as("tr", PHX.Translate, "HUD_ROTLOCK"), "Nesne Döndürme: Kitli")
check("tr, LPS phrase (no Turkish LPS file) -> English", as("tr", PHX.Translate, "LASTPROP_ANNOUNCE_ALL"), EN_LPS)
check("unloaded code xx -> English", as("xx", PHX.Translate, "LASTPROP_ANNOUNCE_ALL"), EN_LPS)
S.cvars["ph_use_lang"].v = "1"; S.cvars["ph_force_lang"].v = "tr"
check("server forces tr, LPS phrase -> English", PHX:Translate("LASTPROP_ANNOUNCE_ALL"), EN_LPS)
S.cvars["ph_force_lang"].v = "xx"
check("server forces unloaded xx -> English", PHX:Translate("HUD_ROTLOCK"), "Prop Rotation: Locked")
S.cvars["ph_use_lang"].v = "0"; S.cvars["ph_force_lang"].v = "en_us"
check("tr, formatted own phrase", as("tr", PHX.Translate, "HUD_AUTOTAUNT", 5), "Otomatik Alaya 5 saniye")
check("tr, formatted LPS phrase -> English formatted",
      as("tr", PHX.Translate, "LPS_WEPLIST", "smg") == PHX.LANGUAGES.en_us.LPS_WEPLIST:format("smg"), true)
check("undefined key still reports it", as("tr", PHX.Translate, "PHCLIENT_NO_SUCH_KEY"),
      "Error: Translation PHCLIENT_NO_SUCH_KEY not found")
check("undefined key with args still reports it", as("tr", PHX.Translate, "PHCLIENT_NO_SUCH_KEY", 1),
      "Error: Cannot translate, PHCLIENT_NO_SUCH_KEY not found")
check("FTranslate unchanged: tr LPS phrase", as("tr", PHX.FTranslate, "LASTPROP_ANNOUNCE_ALL"), EN_LPS)
check("FTranslate unchanged: undefined key echoed", PHX:FTranslate("PHCLIENT_NO_SUCH_KEY"), "PHCLIENT_NO_SUCH_KEY")

print("\n== [#38] GetRandomTranslated falls back to English ==")
local function inTable(v, t) for _, x in ipairs(t) do if x == v then return true end end return false end
check("en_us suicide message", inTable(as("en_us", PHX.GetRandomTranslated, "SUICIDEMSG"), PHX.LANGUAGES.en_us.SUICIDEMSG), true)
check("tr suicide message is Turkish", inTable(as("tr", PHX.GetRandomTranslated, "SUICIDEMSG"), PHX.LANGUAGES.tr.SUICIDEMSG), true)
check("unloaded xx -> English table", inTable(as("xx", PHX.GetRandomTranslated, "SUICIDEMSG"), PHX.LANGUAGES.en_us.SUICIDEMSG), true)
PHX.LANGUAGES.en_us.PHCLIENT_ENONLY_TBL = { "only english" }
check("table missing from tr -> English table", as("tr", PHX.GetRandomTranslated, "PHCLIENT_ENONLY_TBL"), "only english")
check("undefined table still reported", as("tr", PHX.GetRandomTranslated, "PHCLIENT_NO_TBL"), "cannot find PHCLIENT_NO_TBL table.")

print("\n== [#165] a language table without Name does not abort the setup ==")
list.Set("PHX.CustomExternalLanguage", "vi", { code = "vi", HUD_HP = "MAU" })
check("Initialize with a nameless external language", boot(), "ok")
check("nameless language is added", PHX.LANGUAGES.vi ~= nil, true)
check("LPS insertion still ran after it", PHX.LANGUAGES.de.LASTPROP_ANNOUNCE_ALL ~= nil, true)
list.Set("PHX.CustomExternalLanguage", "vi2", { code = "de" })
check("nameless duplicate of a loaded code", boot(), "ok")

print("\n== [#256] language preview copes with a partial external language ==")
local texts = {}
local function Panel()
  local p = { __valid = true }
  return setmetatable(p, { __index = function(_, k)
    if k == "Add" then return function() return Panel() end end
    if k == "SetText" then return function(_, t) texts[#texts + 1] = t end end
    if k == "IsValid" then return function(self) return self.__valid end end
    if k == "Remove" then return function(self) self.__valid = false end end
    return function() end
  end })
end
vgui = { Create = function() return Panel() end }
function ScrW() return 1920 end
function ScrH() return 1080 end
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a } end
loadblocks("cl_init.lua@showLangPreview",
  "local lgWind = {}\n" .. extract("gamemodes/prop_hunt/gamemode/cl_init.lua", [[^function PHX:showLangPreview]]))
local function has(want) for _, t in ipairs(texts) do if t == want then return true end end return false end
check("preview opens", attempt(PHX.showLangPreview, PHX), "ok")
check("German entry unchanged: title", has("Deutsch (German)"), true)
check("German entry unchanged: example", has('Example: "Das Spiel wird nach diser runde enden", "Gesundheit"'), true)
check("German entry unchanged: author", has("Author(s): Major Nick"), true)
check("partial pack: title from its code", has("vi (vi)"), true)
check("partial pack: example falls back to English", has('Example: "Game will end after this round", "MAU"'), true)
check("partial pack: unknown author", has("Author(s): ?"), true)

report()
