---@class defigma_data
---@field gradients defigma_gradients
---@field text_shadows defigma_text_shadows
---@field params table<string, any>

local M = {}

M.NODE_ID = "defigma_data"

---@param values number[]
---@return vector3
local function to_vector3(values)
	return vmath.vector3(values[1], values[2], values[3])
end

---@param values number[]
---@return vector4
local function to_vector4(values)
	return vmath.vector4(values[1], values[2], values[3], values[4])
end

---@param gradient defigma_gradient
local function decode_gradient(gradient)
	for index, value in ipairs(gradient.data) do
		if type(value) == "table" then
			gradient.data[index] = to_vector3(value)
		end
	end
	for _, stop in ipairs(gradient.stops) do
		stop.color = to_vector4(stop.color)
	end
end

---@param values table<string, number[][]>
---@return defigma_text_shadows
local function decode_text_shadows(values)
	local text_shadows = {}
	for node_id, shadows in pairs(values) do
		local decoded = {}
		for index, shadow in ipairs(shadows) do
			decoded[index] = vmath.vector4(shadow[1], shadow[2], shadow[3], 0)
		end
		text_shadows[node_id] = decoded
	end
	return text_shadows
end

---@param node node
---@return defigma_data
function M.load(node)
	local data = json.decode(gui.get_text(node))
	assert(data)
	for _, gradient in pairs(data.gradients) do
		decode_gradient(gradient)
	end
	data.text_shadows = decode_text_shadows(data.text_shadows or {})
	return data
end

return M
