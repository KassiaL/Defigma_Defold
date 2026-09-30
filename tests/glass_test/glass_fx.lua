local M = {}

local ICE = { 0.7745, 0.9843, 1.0 }
local SHEEN_ANGLE = math.rad(58)
local SHEEN_PERIOD = 5.5
local SHEEN_TIME = 2.4
local SHEEN_FROM = -0.15
local SHEEN_TO = 1.15
local SHEEN_STOPS = {
	{ 0.0, 0.0 }, { 0.36, 0.0 }, { 0.44, 0.05 }, { 0.485, 0.2 }, { 0.5, 0.45 }, { 0.512, 0.2 },
	{ 0.55, 0.04 }, { 0.6, 0.0 }, { 0.655, 0.0 }, { 0.685, 0.08 }, { 0.715, 0.0 }, { 1.0, 0.0 },
}
local RIM_STOPS = { { 0.0, 0.12 }, { 0.55, 0.2 }, { 1.0, 1.0 } }
local RIM_SWING = math.rad(35)
local RIM_PERIOD = 9.0
local RIM_FLASH = 0.9
local FLASH_WIDTH = 0.08
local GLINTS = {
	{ id = "glint_1", speed = 170, offset = 0.0, phase = 0.0 },
	{ id = "glint_2", speed = -120, offset = 0.37, phase = 2.1 },
	{ id = "glint_3", speed = 95, offset = 0.71, phase = 4.2 },
}
local GLINT_LENGTH = 220
local GLINT_CORNER_SCALE = 0.35
local GLINT_THICKNESS = 2.2
local GLINT_TOUCH_THICKNESS = 3
local GLINT_TOUCH_WIDTH = 0.07
local SPINNER_TURN = 1.4
local SPINNER_BREATH = 1.6
local SPINNER_MIN = 14
local SPINNER_MAX = 70

local function ease_in_out(t)
	return 0.5 - 0.5 * math.cos(math.pi * t)
end

local function smoothstep(edge0, edge1, x)
	local t = math.max(0, math.min(1, (x - edge0) / (edge1 - edge0)))
	return t * t * (3 - 2 * t)
end

local function stops_json(stops, alpha_scale)
	local parts = {}
	for i, s in ipairs(stops) do
		parts[i] = string.format("[%.4f,%.4f,%.4f,%.4f,%.4f]", s[1], ICE[1], ICE[2], ICE[3], math.min(s[2] * alpha_scale, 1))
	end
	return table.concat(parts, ",")
end

local function linear_json(a, b, c, d, e, f, stops, alpha_scale)
	return string.format('[{"type":"linear","transform":[%.5f,%.5f,%.5f,%.5f,%.5f,%.5f],"stops":[%s]}]',
		a, b, c, d, e, f, stops_json(stops, alpha_scale))
end

local function sheen_coordinate(self, x, y)
	local nx = (x + self.width / 2) / self.width
	local ny = (self.height / 2 - y) / self.height
	return (self.width * math.cos(SHEEN_ANGLE) * nx + self.height * math.sin(SHEEN_ANGLE) * ny) / self.sheen_span
end

local function update_sheen(self, t)
	local cycle = t % SHEEN_PERIOD
	local progress = math.min(cycle / SHEEN_TIME, 1)
	self.band = SHEEN_FROM + (SHEEN_TO - SHEEN_FROM) * ease_in_out(progress)
	if cycle > SHEEN_TIME + 0.1 and self.sheen_idle then
		return
	end
	self.sheen_idle = cycle > SHEEN_TIME
	local a = self.width * math.cos(SHEEN_ANGLE) / self.sheen_span
	local b = self.height * math.sin(SHEEN_ANGLE) / self.sheen_span
	local fills = linear_json(a, b, 0.5 - self.band, -b, a, 0.5, SHEEN_STOPS, 1)
	defigma_shape.set_paints(self.sheen, fills, "[]")
end

local function update_rim(self, t)
	local angle = math.rad(90) + RIM_SWING * math.sin(2 * math.pi * t / RIM_PERIOD)
	local cos, sin = math.cos(angle), math.sin(angle)
	local span = self.width * math.abs(cos) + self.height * math.abs(sin)
	local a = cos * self.width / span
	local b = sin * self.height / span
	local flash = math.max(math.exp(-(self.band / FLASH_WIDTH) ^ 2), math.exp(-((self.band - 1) / FLASH_WIDTH) ^ 2))
	local strokes = linear_json(a, b, 0.5 - 0.5 * (a + b), -b, a, 0.5, RIM_STOPS, 1 + RIM_FLASH * flash)
	defigma_shape.set_paints(self.rim, "[]", strokes)
end

local function perimeter_point(self, s)
	local w, h, r = self.width / 2 - 1.5, self.height / 2 - 1.5, self.radius
	local straight_x, straight_y = 2 * (w - r), 2 * (h - r)
	local quarter = math.pi * r / 2
	s = s % self.perimeter
	local segments = {
		{ straight_x, function(d) return -w + r + d, h, 0 end },
		{ quarter, function(d) local a = math.pi / 2 - d / r return w - r + r * math.cos(a), h - r + r * math.sin(a), math.deg(a - math.pi / 2) end },
		{ straight_y, function(d) return w, h - r - d, -90 end },
		{ quarter, function(d) local a = -d / r return w - r + r * math.cos(a), -h + r + r * math.sin(a), math.deg(a - math.pi / 2) end },
		{ straight_x, function(d) return w - r - d, -h, 180 end },
		{ quarter, function(d) local a = -math.pi / 2 - d / r return -w + r + r * math.cos(a), -h + r + r * math.sin(a), math.deg(a - math.pi / 2) end },
		{ straight_y, function(d) return -w, -h + r + d, 90 end },
		{ quarter, function(d) local a = math.pi - d / r return -w + r + r * math.cos(a), h - r + r * math.sin(a), math.deg(a - math.pi / 2) end },
	}
	for i, segment in ipairs(segments) do
		if s <= segment[1] or i == #segments then
			local x, y, angle = segment[2](math.min(s, segment[1]))
			local corner_distance = i % 2 == 0 and 0 or math.min(s, segment[1] - s)
			return x, y, angle, corner_distance
		end
		s = s - segment[1]
	end
end

local function update_glints(self, t)
	for _, glint in ipairs(self.glints) do
		local s = glint.offset * self.perimeter + glint.speed * t
		local x, y, angle, corner_distance = perimeter_point(self, s)
		local touch = math.exp(-((sheen_coordinate(self, x, y) - self.band) / GLINT_TOUCH_WIDTH) ^ 2)
		local breath = 0.55 + 0.45 * math.sin(t * 1.7 + glint.phase)
		local stretch = GLINT_CORNER_SCALE + (1 - GLINT_CORNER_SCALE) * smoothstep(0, GLINT_LENGTH * 0.55, corner_distance)
		glint.position.x, glint.position.y = x, y
		gui.set_position(glint.node, glint.position)
		gui.set_euler(glint.node, vmath.vector3(0, 0, angle))
		glint.scale.x = stretch * (1 + 0.4 * touch)
		glint.scale.y = GLINT_THICKNESS + GLINT_TOUCH_THICKNESS * touch
		gui.set_scale(glint.node, glint.scale)
		glint.color.w = math.min(0.35 + 0.65 * breath + touch, 1)
		gui.set_color(glint.node, glint.color)
	end
end

local function update_spinner(self, t)
	gui.set_euler(self.spinner, vmath.vector3(0, 0, -360 * (t / SPINNER_TURN % 1)))
	local breath = 0.5 - 0.5 * math.cos(2 * math.pi * t / SPINNER_BREATH)
	defigma_shape.set_sweep(self.spinner, SPINNER_MIN + (SPINNER_MAX - SPINNER_MIN) * breath)
end

function M.init(self)
	local glass = gui.get_node("tile_glass")
	local size = gui.get_size(glass)
	self.width, self.height, self.radius = size.x, size.y, 40
	self.sheen_span = self.width * math.cos(SHEEN_ANGLE) + self.height * math.sin(SHEEN_ANGLE)
	self.perimeter = 2 * (self.width - 2 * self.radius) + 2 * (self.height - 2 * self.radius) + 2 * math.pi * self.radius
	self.sheen = gui.get_node("glass_sheen")
	gui.set_color(self.sheen, vmath.vector4(1, 1, 1, 1))
	self.rim = gui.get_node("tile_rim")
	self.spinner = gui.get_node("spinner")
	self.glints = {}
	for i, glint in ipairs(GLINTS) do
		local node = gui.get_node(glint.id)
		gui.set_blend_mode(node, gui.BLEND_ADD)
		self.glints[i] = { node = node, speed = glint.speed, offset = glint.offset, phase = glint.phase, position = gui.get_position(node), scale = vmath.vector3(1), color = gui.get_color(node) }
	end
	self.time = 0
	self.band = SHEEN_FROM
end

function M.update(self, dt)
	self.time = self.time + dt
	update_sheen(self, self.time)
	update_rim(self, self.time)
	update_glints(self, self.time)
	update_spinner(self, self.time)
end

return M
