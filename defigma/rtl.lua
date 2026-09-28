---Mirrors nodes marked with `{"custom_parameters":"rtl"}` in Figma for right-to-left locales by
---negating their own `scale.x`. The authored scale and pivot are captured whenever the node holds
---its editor state, so switching back to a left-to-right locale restores them exactly.

local events = require("event.events")
local screen = require("defigma.screen")

---@class defigma_rtl_entry
---@field scale vector3 authored scale
---@field pivot constant? authored pivot of a text node

local PARAM = "rtl"
local RTL_LANGUAGES = { ar = true }

local MIRRORED_PIVOT = {
	[gui.PIVOT_W] = gui.PIVOT_E,
	[gui.PIVOT_E] = gui.PIVOT_W,
	[gui.PIVOT_NW] = gui.PIVOT_NE,
	[gui.PIVOT_NE] = gui.PIVOT_NW,
	[gui.PIVOT_SW] = gui.PIVOT_SE,
	[gui.PIVOT_SE] = gui.PIVOT_SW
}

local language = nil

local M = {}

---@return boolean
local function is_rtl_language()
	return RTL_LANGUAGES[language] == true
end

---Text keeps its own orientation, so its horizontal pivot has to be swapped for the node to stay
---inside the reflected box.
---@param node node
---@param entry defigma_rtl_entry
---@param is_rtl boolean
local function apply_pivot(node, entry, is_rtl)
	local pivot = entry.pivot
	if not pivot then return end
	local mirrored = MIRRORED_PIVOT[pivot]
	if not mirrored then return end
	gui.set_pivot(node, is_rtl and mirrored or pivot)
end

---@param node node
---@param entry defigma_rtl_entry
---@param is_rtl boolean
local function apply_scale(node, entry, is_rtl)
	local scale = entry.scale
	gui.set_scale(node, vmath.vector3(is_rtl and -scale.x or scale.x, scale.y, scale.z))
end

---@param node_id string|hash
---@param value any
---@param state table<string|hash, defigma_rtl_entry>
---@param capture boolean the node holds its authored state again and has to be re-read
local function apply(node_id, value, state, capture)
	if value ~= PARAM then return end
	local node = gui.get_node(node_id)
	local entry = state[node_id]
	if not entry or capture then
		entry = {
			scale = gui.get_scale(node),
			pivot = gui.get_type(node) == gui.TYPE_TEXT and gui.get_pivot(node) or nil
		}
		state[node_id] = entry
	end
	local is_rtl = is_rtl_language()
	apply_scale(node, entry, is_rtl)
	apply_pivot(node, entry, is_rtl)
end

---@type defigma_feature
local feature = {
	init = function(_, node_id, value, state)
		apply(node_id, value, state, true)
	end,
	layout_changed = function(self, node_id, value, state)
		apply(node_id, value, state, not screen.is_runtime_param(self, node_id))
	end,
	language_changed = function(_, node_id, value, state)
		apply(node_id, value, state, false)
	end,
	final = function(_, node_id, value, state)
		if value == PARAM then
			state[node_id] = nil
		end
	end
}

screen.register(feature)

---Mirrors a node that is not tagged in Figma, and keeps mirroring it on every later hook. Needed for
---nodes that stop inheriting the flip at runtime — a node detached from the mirrored root no longer
---sits under it, so the flip has to be written onto the node itself.
---@param self table
---@param node_id string
function M.track(self, node_id)
	screen.register_runtime_param(self, node_id, PARAM)
end

---@param self table
---@param node_id hash
function M.untrack(self, node_id)
	screen.unregister_runtime_param(self, node_id)
end

---@param new_language string
local function language_changed(new_language)
	language = new_language
end

---Starts tracking the current language. Call once at startup, before the first `set_language`.
---@param language_changed_event string
function M.init(language_changed_event)
	events.subscribe(language_changed_event, language_changed)
end

return M
