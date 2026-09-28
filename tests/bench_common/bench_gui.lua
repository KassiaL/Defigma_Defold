local defigma = require("defigma.screen")
local gradient_nodes = require("defigma.gradient_nodes")

local M = {}

local SET_LOAD = hash("set_load")
local ROOT = hash("root")
local LAYER_OFFSET = 6
local MOVE_AMPLITUDE = 40

---@param self table
---@param screen_id string
function M.init(self, screen_id)
	defigma.init(self, screen_id)
	self.roots = { gui.get_node(ROOT) }
	self.base_positions = { gui.get_position(self.roots[1]) }
	self.moving = false
	self.time = 0
end

---@param self table
local function add_layer(self)
	local index = #self.roots
	local clones = gui.clone_tree(self.roots[1])
	local root = clones[ROOT]
	local position = self.base_positions[1] + vmath.vector3(index * LAYER_OFFSET, -index * LAYER_OFFSET, 0)
	gui.set_position(root, position)
	for name in pairs(self.defigma.data.gradients) do
		gradient_nodes.add(self.defigma.gradient_nodes, name, clones[hash(name)])
	end
	self.roots[index + 1] = root
	self.base_positions[index + 1] = position
end

---@param self table
---@param dt number
function M.update(self, dt)
	if self.moving then
		self.time = self.time + dt
		local offset = vmath.vector3(math.sin(self.time * 2) * MOVE_AMPLITUDE, math.cos(self.time * 1.3) * MOVE_AMPLITUDE, 0)
		for i = 1, #self.roots do
			gui.set_position(self.roots[i], self.base_positions[i] + offset)
		end
	end
	defigma.update(self, dt)
end

---@param self table
---@param message_id hash
---@param message table
---@param sender url
function M.on_message(self, message_id, message, sender)
	if message_id == SET_LOAD then
		while #self.roots < message.layers do
			add_layer(self)
		end
		self.moving = message.moving
		msg.post(sender, "load_set")
	end
	defigma.on_message(self, message_id, message, sender)
end

---@param self table
function M.final(self)
	defigma.final(self)
end

return M
