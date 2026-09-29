-- GLua that extract.py must translate without changing what it does, for
-- t_ci_extract.lua. Never loaded by the game.

local function lineCommentBracket()
	local a = 1 //[[ a GLua line comment, not the start of a long comment
	a = a + 1
	return a //]]
end

local function blockCommentBrackets()
	local t = { 1 } /* t[1]] is not the end ]] of this comment */
	return #t
end

local function bangWithSpace( x )
	if ! x then return "negated" end
	return "kept"
end

-- local function commentedOut() return "the commented-out copy" end
local function commentedOut() return "the real one" end
