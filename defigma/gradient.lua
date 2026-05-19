local M = {}

function M.apply_all(gradients)
	for k, v in pairs(gradients) do
		M.apply(k, gradients)
	end
end

function M.apply_all_transform(gradients)
	for k, v in pairs(gradients) do
		M.apply_transform(k, gradients)
	end
end

function M.apply(node_name, gradients, node)
	local g = gradients[node_name]
	if g.type == "drop_shadow" then
		M.apply_transform(node_name, gradients, node)
		return
	end

	local node = node or gui.get_node(node_name)
	gui.set(node, "gradient_stop0", g.stops[1].color)
	gui.set(node, "gradient_stop1", g.stops[2].color)
	local gradient_data = g.data

	if g.type == "radial" then
		gui.set(node, "grad_data", vmath.vector4(gradient_data[1].x, 1 - gradient_data[1].y, gradient_data[2].x, gradient_data[2].y))
		gui.set(node, "grad_data2", vmath.vector4((gradient_data[3]) / 180 * math.pi, 0, 0, 0))
	elseif g.type == "linear" then
		if not g.is_text then
			gui.set(node, "grad_data", vmath.vector4(gradient_data[1].x, 1 - gradient_data[1].y, gradient_data[2].x, 1 - gradient_data[2].y))
		else
			gui.set(node, "grad_data", vmath.vector4(gradient_data[1].x, gradient_data[1].y, gradient_data[2].x, gradient_data[2].y))
		end
	end

	M.apply_transform(node_name, gradients, node)
end

function M.apply_transform(node_name, gradients, node)
	local g = gradients[node_name]
	if g.is_text then
		return
	end

	local node = node or gui.get_node(node_name)

	local scale = gui.get_scale(node)
	local size = gui.get_size(node)

	local gui_width = gui.get_width()
	local gui_height = gui.get_height()
	local width, height = window.get_size()
	local ratio
	if gui_height > gui_width then
		local standart_ratio = gui_width / gui_height
		ratio = width / height

		if ratio > standart_ratio then
			ratio = height / gui_height
		else
			ratio = width / gui_width
		end
	else
		local standart_ratio = gui_height / gui_width
		ratio = height / width

		if ratio < standart_ratio then
			ratio = height / gui_height
		else
			ratio = width / gui_width
		end
	end

	if g.type == "drop_shadow" then
		local blur = g.data[1]
		local spread = g.data[2]
	end

	local image_atlas_size = vmath.vector3(ratio * size.x * scale.x, ratio * size.y * scale.y, 0)
	local pos_left_down = gui.get_screen_position(node)
	pos_left_down.x = pos_left_down.x - image_atlas_size.x / 2
	pos_left_down.y = pos_left_down.y - image_atlas_size.y / 2
	gui.set(node, hash("node_transform"), vmath.vector4(pos_left_down.x, pos_left_down.y, image_atlas_size.x, image_atlas_size.y))
	gui.set(node, hash("node_scale"), vmath.vector4(scale.x, scale.y, 0, 0))
end

return M
