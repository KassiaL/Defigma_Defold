---@alias defigma_text_shadows table<string, vector4[]>

local M = {}

local CONSTANTS = { hash("text_shadow"), hash("text_shadow2") }

---@param text_shadows defigma_text_shadows
---@param get_node fun(node_id: string): node
function M.apply(text_shadows, get_node)
	for node_id, shadows in pairs(text_shadows) do
		local node = get_node(node_id)
		for index, shadow in ipairs(shadows) do
			gui.set(node, CONSTANTS[index], shadow)
		end
	end
end

return M
