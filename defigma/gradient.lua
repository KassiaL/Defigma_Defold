---@class defigma_gradient_stop
---@field color vector4
---@field position number

---@class defigma_linear_gradient_data: [vector3, vector3]

---@class defigma_radial_gradient_data: [vector3, vector3, number]

---@class defigma_drop_shadow_data: [number, number]

---@class defigma_text_bounds_cache
---@field text string
---@field font hash
---@field line_break boolean
---@field tracking number
---@field leading number
---@field width number
---@field height number
---@field pivot unknown
---@field bounds vector4

---@class defigma_linear_gradient
---@field type "linear"
---@field data defigma_linear_gradient_data
---@field stops defigma_gradient_stop[]
---@field is_text boolean?
---@field text_bounds_cache defigma_text_bounds_cache?

---@class defigma_radial_gradient
---@field type "radial"
---@field data defigma_radial_gradient_data
---@field stops defigma_gradient_stop[]

---@class defigma_drop_shadow
---@field type "drop_shadow"
---@field data defigma_drop_shadow_data
---@field stops defigma_gradient_stop[]

---@alias defigma_gradient defigma_linear_gradient|defigma_radial_gradient|defigma_drop_shadow

---@alias defigma_gradients table<string, defigma_gradient>

local M = {}

local NODE_TRANSFORM = hash("node_transform")
local GRADIENT_TO_LOCAL = hash("gradient_to_local")
local GRADIENT_BOUNDS = hash("gradient_bounds")
local GRAD_DATA = hash("grad_data")
local GRAD_DATA2 = hash("grad_data2")
local GRADIENT_STOP0 = hash("gradient_stop0")
local GRADIENT_STOP1 = hash("gradient_stop1")
local PROBE_SPAN = 100
local DEG_TO_RAD = math.pi / 180

---Every per-node value the shaders need is written through these three. `gui.screen_to_local` only
---reads its argument and `gui.set` copies what it is given, so one instance of each is reused
---instead of allocating a fresh vector or matrix for every node on every refresh.
local probe_point = vmath.vector3()
local screen_to_local_value = vmath.matrix4()
local node_transform_value = vmath.vector4()

---@param node node
---@return number offset_x, number offset_y
local function pivot_offset(node)
	local pivot = gui.get_pivot(node)
	local x = 0
	local y = 0
	if pivot == gui.PIVOT_CENTER or pivot == gui.PIVOT_N or pivot == gui.PIVOT_S then
		x = -gui.get(node, "size.x") * 0.5
	elseif pivot == gui.PIVOT_E or pivot == gui.PIVOT_NE or pivot == gui.PIVOT_SE then
		x = -gui.get(node, "size.x")
	end
	if pivot == gui.PIVOT_CENTER or pivot == gui.PIVOT_E or pivot == gui.PIVOT_W then
		y = -gui.get(node, "size.y") * 0.5
	elseif pivot == gui.PIVOT_N or pivot == gui.PIVOT_NE or pivot == gui.PIVOT_NW then
		y = -gui.get(node, "size.y")
	end
	return x, y
end

---A transform collapsed to zero on any axis has no inverse, and `gui.screen_to_local` answers
---with NaN. That happens on every scale-in animation, where the node is invisible anyway.
---@param value number
---@return boolean
local function is_number(value)
	return value == value
end

---Screen space to the space the node is drawn in: origin at its lower left corner, unscaled.
---The basis is measured through `gui.screen_to_local`, so it carries every parent transform,
---adjust mode, anchor and safe area offset the engine actually renders with. The result is the six
---numbers of a 2d affine map instead of a matrix, so the only allocations left are the three
---vectors the engine itself returns. Rotation is read as `euler.z`: a gradient is a 2d effect and
---a node tilted out of the screen plane has no meaningful gradient axis anyway.
---@param node node
---@return number? m00, number? m01, number? m10, number? m11, number? x, number? y
local function screen_to_node(node)
	local scale_x = gui.get(node, "scale.x")
	local scale_y = gui.get(node, "scale.y")
	if scale_x == 0 or scale_y == 0 then
		return nil
	end
	local origin = gui.get_screen_position(node)
	local position_x = gui.get(node, "position.x")
	local position_y = gui.get(node, "position.y")

	probe_point.x = origin.x + PROBE_SPAN
	probe_point.y = origin.y
	probe_point.z = origin.z
	local probe = gui.screen_to_local(node, probe_point)
	local axis_x_x = (probe.x - position_x) / PROBE_SPAN
	local axis_x_y = (probe.y - position_y) / PROBE_SPAN

	probe_point.x = origin.x
	probe_point.y = origin.y + PROBE_SPAN
	probe = gui.screen_to_local(node, probe_point)
	local axis_y_x = (probe.x - position_x) / PROBE_SPAN
	local axis_y_y = (probe.y - position_y) / PROBE_SPAN

	if not (is_number(axis_x_x) and is_number(axis_x_y) and is_number(axis_y_x) and is_number(axis_y_y)) then
		return nil
	end

	local radians = gui.get(node, "euler.z") * DEG_TO_RAD
	local cos = math.cos(radians)
	local sin = math.sin(radians)
	local m00 = (cos * axis_x_x + sin * axis_x_y) / scale_x
	local m01 = (cos * axis_y_x + sin * axis_y_y) / scale_x
	local m10 = (cos * axis_x_y - sin * axis_x_x) / scale_y
	local m11 = (cos * axis_y_y - sin * axis_y_x) / scale_y
	local offset_x, offset_y = pivot_offset(node)
	return m00, m01, m10, m11,
		-(m00 * origin.x + m01 * origin.y) - offset_x,
		-(m10 * origin.x + m11 * origin.y) - offset_y
end

---@param node node
---@param gradient defigma_linear_gradient
---@return vector4
local function text_bounds(node, gradient)
	local width = gui.get(node, "size.x") --[[@as number]]
	local height = gui.get(node, "size.y") --[[@as number]]
	local pivot = gui.get_pivot(node)
	local text = gui.get_text(node)
	local font = gui.get_font(node)
	local line_break = gui.get_line_break(node)
	local tracking = gui.get_tracking(node)
	local leading = line_break and gui.get_leading(node) or 0
	local cached = gradient.text_bounds_cache
	if cached and
		cached.text == text and
		cached.font == font and
		cached.line_break == line_break and
		cached.tracking == tracking and
		cached.leading == leading and
		cached.width == width and
		cached.height == height and
		cached.pivot == pivot then
		return cached.bounds
	end

	local options = {
		line_break = line_break,
		tracking = tracking,
	}
	if line_break then
		options.width = width
		options.leading = leading
	end
	local metrics = resource.get_text_metrics(gui.get_font_resource(font), text, options)
	local x = 0
	local y = 0
	if pivot == gui.PIVOT_CENTER or pivot == gui.PIVOT_N or pivot == gui.PIVOT_S then
		x = (width - metrics.width) * 0.5
	elseif pivot == gui.PIVOT_E or pivot == gui.PIVOT_NE or pivot == gui.PIVOT_SE then
		x = width - metrics.width
	end
	if pivot == gui.PIVOT_CENTER or pivot == gui.PIVOT_E or pivot == gui.PIVOT_W then
		y = (height - metrics.height) * 0.5
	elseif pivot == gui.PIVOT_N or pivot == gui.PIVOT_NE or pivot == gui.PIVOT_NW then
		y = height - metrics.height
	end
	local bounds = vmath.vector4(x, y, metrics.width, metrics.height)
	gradient.text_bounds_cache = {
		text = text,
		font = font,
		line_break = line_break,
		tracking = tracking,
		leading = leading,
		width = width,
		height = height,
		pivot = pivot,
		bounds = bounds,
	}
	return bounds
end

---@param node node
---@param gradient defigma_linear_gradient
local function apply_text_transform(node, gradient)
	local m00, m01, m10, m11, x, y = screen_to_node(node)
	if not (m00 and m01 and m10 and m11 and x and y) then
		return
	end
	screen_to_local_value.m00 = m00
	screen_to_local_value.m01 = m01
	screen_to_local_value.m03 = x
	screen_to_local_value.m10 = m10
	screen_to_local_value.m11 = m11
	screen_to_local_value.m13 = y
	---@diagnostic disable-next-line: param-type-mismatch
	gui.set(node, GRADIENT_TO_LOCAL, screen_to_local_value)
	gui.set(node, GRADIENT_BOUNDS, text_bounds(node, gradient))
end

---@param node node
local function apply_image_transform(node)
	local m00, m01, m10, m11, x, y = screen_to_node(node)
	if not (m00 and m01 and m10 and m11 and x and y) then
		return
	end
	local determinant = m00 * m11 - m01 * m10
	local i00 = m11 / determinant
	local i01 = -m01 / determinant
	local i10 = -m10 / determinant
	local i11 = m00 / determinant
	local width = gui.get(node, "size.x")
	local height = gui.get(node, "size.y")
	node_transform_value.x = -(i00 * x + i01 * y)
	node_transform_value.y = -(i10 * x + i11 * y)
	node_transform_value.z = i00 * width + i01 * height
	node_transform_value.w = i10 * width + i11 * height
	gui.set(node, NODE_TRANSFORM, node_transform_value)
end

---@param node node
---@param gradient defigma_linear_gradient
local function apply_linear_transform(node, gradient)
	if gradient.is_text then
		apply_text_transform(node, gradient)
	else
		apply_image_transform(node)
	end
end

---@param node node
---@param gradient defigma_linear_gradient|defigma_radial_gradient
local function apply_gradient_stops(node, gradient)
	gui.set(node, GRADIENT_STOP0, gradient.stops[1].color)
	gui.set(node, GRADIENT_STOP1, gradient.stops[2].color)
end

---@param node node
---@param gradient defigma_linear_gradient
local function apply_linear(node, gradient)
	apply_gradient_stops(node, gradient)
	local start = gradient.data[1]
	local finish = gradient.data[2]
	if gradient.is_text then
		gui.set(node, GRAD_DATA, vmath.vector4(start.x, start.y, finish.x, finish.y))
	else
		gui.set(node, GRAD_DATA, vmath.vector4(start.x, 1 - start.y, finish.x, 1 - finish.y))
	end
	apply_linear_transform(node, gradient)
end

---@param node node
---@param gradient defigma_radial_gradient
local function apply_radial(node, gradient)
	apply_gradient_stops(node, gradient)
	local center = gradient.data[1]
	local radius = gradient.data[2]
	local rotation = gradient.data[3]
	gui.set(node, GRAD_DATA, vmath.vector4(center.x, 1 - center.y, radius.x, radius.y))
	gui.set(node, GRAD_DATA2, vmath.vector4(rotation / 180 * math.pi, 0, 0, 0))
	apply_image_transform(node)
end

---@param node_name string
---@param gradients defigma_gradients
---@param node node?
function M.apply(node_name, gradients, node)
	local gradient = gradients[node_name]
	local node = node or gui.get_node(node_name)
	if gradient.type == "linear" then
		apply_linear(node, gradient)
	elseif gradient.type == "radial" then
		apply_radial(node, gradient)
	elseif gradient.type == "drop_shadow" then
		apply_image_transform(node)
	end
end

---@param node_name string
---@param gradients defigma_gradients
---@param node node?
function M.apply_transform(node_name, gradients, node)
	local gradient = gradients[node_name]
	local node = node or gui.get_node(node_name)
	if gradient.type == "linear" then
		apply_linear_transform(node, gradient)
	else
		apply_image_transform(node)
	end
end

return M
