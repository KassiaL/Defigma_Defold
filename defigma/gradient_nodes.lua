---Registry of gradient nodes owned by one screen or widget.
---Every entry is applied once when added; after that a node is refreshed either every frame
---(`is_updating`) or only on demand: window events, data changes, scroll movement.
---@class defigma_gradient_entry
---@field id string
---@field node node
---@field is_updating boolean

---@class defigma_gradient_nodes
---@field gradients defigma_gradients
---@field entries defigma_gradient_entry[]
---@field updating_count number
---@field scrolls defigma_scroll_binding[]

---One subscription per scroll refreshes every registry bound to it, so the nodes it carries are
---re-applied on real movement instead of every frame.
---The binding never stores the scroll itself: a weak key that its own value references stays
---alive forever in Lua 5.1, and then the screen nodes behind it are never collected either.
---@class defigma_scroll_binding
---@field content_node node
---@field on_scroll event
---@field registries defigma_gradient_nodes[]
---@field x number?
---@field y number?

local data = require("defigma.data")
local gradient = require("defigma.gradient")
local text_shadow = require("defigma.text_shadow")

local M = {}

---@param gradients defigma_gradients
---@return defigma_gradient_nodes
function M.create(gradients)
	return {
		gradients = gradients,
		entries = {},
		updating_count = 0,
		scrolls = {},
	}
end

---@param self defigma_gradient_nodes
---@param id string
---@param node node
function M.add(self, id, node)
	self.entries[#self.entries + 1] = { id = id, node = node, is_updating = true }
	self.updating_count = self.updating_count + 1
	gradient.apply(id, self.gradients, node)
end

---@param entry defigma_gradient_entry
---@param self defigma_gradient_nodes
---@param is_updating boolean
local function set_entry_updating(self, entry, is_updating)
	if entry.is_updating == is_updating then
		return
	end
	entry.is_updating = is_updating
	self.updating_count = self.updating_count + (is_updating and 1 or -1)
end

---@param self defigma_gradient_nodes
---@param id string
---@param is_updating boolean
function M.set_updating(self, id, is_updating)
	for i = 1, #self.entries do
		local entry = self.entries[i]
		if entry.id == id then
			set_entry_updating(self, entry, is_updating)
		end
	end
end

---@param self defigma_gradient_nodes
---@param is_updating boolean
function M.set_all_updating(self, is_updating)
	for i = 1, #self.entries do
		set_entry_updating(self, self.entries[i], is_updating)
	end
end

---Re-apply the transform of every entry, no matter whether it is in the per-frame update.
---@param self defigma_gradient_nodes
function M.refresh(self)
	for i = 1, #self.entries do
		local entry = self.entries[i]
		gradient.apply_transform(entry.id, self.gradients, entry.node)
	end
end

---Re-apply only the entries kept in the per-frame update.
---@param self defigma_gradient_nodes
function M.update(self)
	if self.updating_count == 0 then
		return
	end
	for i = 1, #self.entries do
		local entry = self.entries[i]
		if entry.is_updating then
			gradient.apply_transform(entry.id, self.gradients, entry.node)
		end
	end
end

---@type table<druid.scroll, defigma_scroll_binding>
local bindings_by_scroll = setmetatable({}, { __mode = "k" })

---Scrolls keep triggering `on_scroll` while they settle, so refresh on real movement only.
---@param binding defigma_scroll_binding
---@return boolean
local function has_moved(binding)
	local content = binding.content_node
	local x = gui.get(content, "position.x")
	local y = gui.get(content, "position.y")
	if binding.x == x and binding.y == y then
		return false
	end
	binding.x = x
	binding.y = y
	return true
end

---@param binding defigma_scroll_binding
local function on_scroll(binding)
	if not has_moved(binding) then
		return
	end
	for i = 1, #binding.registries do
		M.refresh(binding.registries[i])
	end
end

---Nodes moved by a scroll are refreshed from its movement instead of every frame.
---@param self defigma_gradient_nodes
---@param scroll druid.scroll
function M.bind_scroll(self, scroll)
	local binding = bindings_by_scroll[scroll]
	if not binding then
		binding = { content_node = scroll.content_node, on_scroll = scroll.on_scroll, registries = {} }
		bindings_by_scroll[scroll] = binding
	end
	if #binding.registries == 0 then
		binding.on_scroll:subscribe(on_scroll, binding)
	end
	binding.registries[#binding.registries + 1] = self
	self.scrolls[#self.scrolls + 1] = binding
end

---@param self defigma_gradient_nodes
function M.unbind_scroll(self)
	for i = 1, #self.scrolls do
		local binding = self.scrolls[i]
		for index = #binding.registries, 1, -1 do
			if binding.registries[index] == self then
				table.remove(binding.registries, index)
			end
		end
		if #binding.registries == 0 then
			binding.on_scroll:unsubscribe(on_scroll, binding)
		end
	end
	self.scrolls = {}
end

---Refresh several registries. Use it wherever a loop touches many widgets.
---@param registries defigma_gradient_nodes[]
function M.refresh_all(registries)
	for i = 1, #registries do
		M.refresh(registries[i])
	end
end

---Load the widget defigma data, register every gradient node it declares and apply its text shadows.
---Widget nodes stay out of the per-frame update until `set_updating` or `bind_scroll` is used.
---@param widget druid.widget
---@return defigma_gradient_nodes
function M.create_for_widget(widget)
	local widget_data = data.load(widget:get_node(data.NODE_ID))
	local self = M.create(widget_data.gradients)
	for node_name in pairs(widget_data.gradients) do
		M.add(self, node_name, widget:get_node(node_name))
	end
	M.set_all_updating(self, false)
	text_shadow.apply(widget_data.text_shadows, function(node_id)
		return widget:get_node(node_id)
	end)
	return self
end

return M
