---A feature reacts to the `custom_parameters` of a single node.
---Every callback is optional; implement only the moments the feature needs.
---`state` is a per-screen table owned by this feature, created on `defigma.init`.
---@class defigma_feature
---@field init fun(self: table, node_id: string|hash, value: any, state: table)?
---@field layout_changed fun(self: table, node_id: string|hash, value: any, state: table)?
---@field language_changed fun(self: table, node_id: string|hash, value: any, state: table)?
---@field final fun(self: table, node_id: string|hash, value: any, state: table)?

---@class defigma_screen_state
---@field screen hash
---@field data defigma_data
---@field runtime_params table<hash, any>
---@field state table<defigma_feature, table>
---@field gradient_nodes defigma_gradient_nodes

local data = require("defigma.data")
local gradient_nodes = require("defigma.gradient_nodes")
local text_shadow = require("defigma.text_shadow")
local events = require("event.events")

local TRANSITION_IN_STARTED = hash("monarch_screen_transition_in_started")
local LAYOUT_CHANGED = hash("layout_changed")
local TOUCH = hash("touch")
local WINDOW_EVENT = "druid.window_event"

local M = {}

---@type defigma_feature[]
M.features = {}

---@param feature defigma_feature
function M.register(feature)
	M.features[#M.features + 1] = feature
end

---@param self table
---@param hook string
local function dispatch(self, hook)
	local params = self.defigma.data.params
	local runtime_params = self.defigma.runtime_params
	for _, feature in ipairs(M.features) do
		local state = self.defigma.state[feature]
		local callback = feature[hook]
		if callback then
			for node_id, value in pairs(params) do
				callback(self, node_id, value, state)
			end
			for node_id, value in pairs(runtime_params) do
				callback(self, node_id, value, state)
			end
		end
	end
end

---@param self table
---@param screen_id string
function M.init(self, screen_id)
	local state = {}
	for _, feature in ipairs(M.features) do
		state[feature] = {}
	end
	local screen_data = data.load(gui.get_node(data.NODE_ID))
	self.defigma = {
		screen = hash(screen_id),
		data = screen_data,
		runtime_params = {},
		state = state,
		gradient_nodes = gradient_nodes.create(screen_data.gradients),
	}
	for node_name in pairs(screen_data.gradients) do
		gradient_nodes.add(self.defigma.gradient_nodes, node_name, gui.get_node(node_name))
	end
	text_shadow.apply(screen_data.text_shadows, gui.get_node)
	events.subscribe(WINDOW_EVENT, M.on_window_event, self)
	dispatch(self, "init")
end

---@param self table
function M.on_window_event(self)
	gradient_nodes.refresh(self.defigma.gradient_nodes)
end

---Keep a screen gradient node out of (or back in) the per-frame update.
---@param self table
---@param node_name string
---@param is_updating boolean
function M.set_node_updating(self, node_name, is_updating)
	gradient_nodes.set_updating(self.defigma.gradient_nodes, node_name, is_updating)
end

---@param self table
---@param is_updating boolean
function M.set_all_nodes_updating(self, is_updating)
	gradient_nodes.set_all_updating(self.defigma.gradient_nodes, is_updating)
end

---Screen nodes carried by a scroll follow its movement instead of the per-frame update.
---@param self table
---@param scroll druid.scroll
function M.bind_scroll(self, scroll)
	gradient_nodes.bind_scroll(self.defigma.gradient_nodes, scroll)
end

---@param self table
---@param node_id string
---@param value any
function M.register_runtime_param(self, node_id, value)
	local params = self.defigma.runtime_params
	if params[node_id] ~= nil then return end
	params[node_id] = value
	for _, feature in ipairs(M.features) do
		local callback = feature.init
		if callback then
			callback(self, node_id, value, self.defigma.state[feature])
		end
	end
end

---@param self table
---@param node_id hash
function M.unregister_runtime_param(self, node_id)
	local params = self.defigma.runtime_params
	local value = params[node_id]
	assert(value ~= nil)
	for _, feature in ipairs(M.features) do
		local callback = feature.final
		if callback then
			callback(self, node_id, value, self.defigma.state[feature])
		end
	end
	params[node_id] = nil
end

---@param self table
---@param node_id string|hash
---@return boolean
function M.is_runtime_param(self, node_id)
	return self.defigma.runtime_params[node_id] ~= nil
end

---@param self table
---@param dt number
function M.update(self, dt)
	gradient_nodes.update(self.defigma.gradient_nodes)
end

---@param self table
function M.release_touch_input(self)
	self.druid:on_input(TOUCH, { released = true, x = -1000, y = -1000 })
end

---@param self table
---@param message_id hash
---@param message table
---@param sender url
function M.on_message(self, message_id, message, sender)
	if message_id == TRANSITION_IN_STARTED and message.previous_screen == self.defigma.screen then
		M.release_touch_input(self)
	end
	if message_id == LAYOUT_CHANGED then
		M.on_window_event(self)
		dispatch(self, "layout_changed")
	end
end

---@param self table
---@param action_id hash
---@param action table
function M.on_input(self, action_id, action)
end

---@param self table
function M.language_changed(self)
	dispatch(self, "language_changed")
end

---@param self table
function M.final(self)
	events.unsubscribe(WINDOW_EVENT, M.on_window_event, self)
	dispatch(self, "final")
	self.defigma = nil
end

---@param self table
---@param node_id string
---@return any
function M.param(self, node_id)
	return self.defigma.data.params[node_id]
end

return M
