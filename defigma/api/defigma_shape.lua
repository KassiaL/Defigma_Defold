---@meta

---@class defigma_shape
defigma_shape = {}

---@param node node
---@param start number
---@param sweep number
---@param ratio number
function defigma_shape.set_arc(node, start, sweep, ratio) end

---@param node node
---@param sweep number
function defigma_shape.set_sweep(node, sweep) end

---@param node node
---@return number start
---@return number sweep
---@return number ratio
function defigma_shape.get_arc(node) end

---@param node node
---@param fills string
---@param strokes string
function defigma_shape.set_paints(node, fills, strokes) end

---@param node node
---@return string fills
---@return string strokes
function defigma_shape.get_paints(node) end
