local Tree = {}
Tree.__index = Tree

-- Core Tree Constructor
function Tree:new(def)
    local obj = setmetatable({}, self)
    obj.trunk_material = def.trunk_material or "mcl_core:tree"
    obj.leaf_material = def.leaf_material or "mcl_core:darkleaves"
    obj.min_radius = def.min_radius or 15
    obj.max_radius = def.max_radius or 45
    obj.name = def.name or "default_tree"
    return obj
end

-- Queue for deferred execution
function Tree:init_queue()
    self.queue = {}
end

function Tree:enqueue(fn)
    table.insert(self.queue, fn)
end

function Tree:process_queue()
    local index = 1
    local function step()
        if index <= #self.queue then
            self.queue[index]()
            index = index + 1
            minetest.after(0.01, step)
        end
    end
    step()
end

-- Draw a solid branch segment between points
function Tree:draw_branch_segment(start_pos, end_pos, radius)
    local steps = math.max(
        math.abs(end_pos.x - start_pos.x),
        math.abs(end_pos.y - start_pos.y),
        math.abs(end_pos.z - start_pos.z)
    )
    for i = 0, steps do
        local t = i / steps
        local x = math.floor(start_pos.x + (end_pos.x - start_pos.x) * t + 0.5)
        local y = math.floor(start_pos.y + (end_pos.y - start_pos.y) * t + 0.5)
        local z = math.floor(start_pos.z + (end_pos.z - start_pos.z) * t + 0.5)
        for dx = -radius, radius do
            for dy = -radius, radius do
                for dz = -radius, radius do
                    if dx * dx + dy * dy + dz * dz <= radius * radius then
                        local pos = {x = x + dx, y = y + dy, z = z + dz}
                        minetest.set_node(pos, {name = self.trunk_material})
                    end
                end
            end
        end
    end
end

-- Grow branch recursively
function Tree:branch(pos, length, thickness)
    local dir = {
        x = math.random(-2, 2),
        y = math.random(0, 2),
        z = math.random(-2, 2),
    }
    local last_node = vector.new(pos)
    for i = 1, length do
        self:enqueue(function()
            local taper = math.max(1, math.floor(thickness * (1 - i / length)))
            local next_node = {
                x = last_node.x + dir.x + math.random(-1, 1),
                y = last_node.y + dir.y,
                z = last_node.z + dir.z + math.random(-1, 1),
            }
            self:draw_branch_segment(last_node, next_node, taper)
            last_node = vector.new(next_node)
        end)
    end
    if thickness > 1 then
        local branches = math.random(2, 3)
        for i = 1, branches do
            self:enqueue(function()
                self:branch(last_node, math.floor(length * 0.6), thickness - 1)
            end)
        end
    else
        self:enqueue(function()
            self:generate_leaves(last_node, math.random(3, 5))
        end)
    end
end

-- Generate leaf blob
function Tree:generate_leaves(pos, radius)
    for dx = -radius, radius do
        for dy = -radius, radius do
            for dz = -radius, radius do
                local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
                if dist <= radius and math.random() < 0.95 then
                    local leaf_pos = {
                        x = pos.x + dx,
                        y = pos.y + dy,
                        z = pos.z + dz
                    }
                    local n = minetest.get_node(leaf_pos).name
                    if n == "air" or n == "ignore" then
                        minetest.set_node(leaf_pos, {name = self.leaf_material})
                    end
                end
            end
        end
    end
end

function Tree:root(pos, length, thickness)
    local dir = {
        x = math.random(-1, 1),
        y = -math.random(1, 2), -- forces downward growth
        z = math.random(-1, 1),
    }

    local last_node = vector.new(pos)

    for i = 1, length do
        self:enqueue(function()
            local taper = math.max(1, math.floor(thickness * (1 - i / length)))
            local next_node = {
                x = last_node.x + dir.x + math.random(-1, 1),
                y = last_node.y + dir.y,
                z = last_node.z + dir.z + math.random(-1, 1),
            }
            self:draw_branch_segment(last_node, next_node, taper)
            last_node = vector.new(next_node)
        end)
    end
end

-- Main generation function
function Tree:generate(pos)
    self:init_queue()
    local base_pos = vector.round(pos)
    local radius = math.random(self.min_radius, self.max_radius)
    local height = radius * 2
    local trunk_height = math.floor(height * 0.6)

    local base_trunk_radius = math.floor(radius / 4) + 2
    local trunk_dir = {x = math.random(-1, 1), z = math.random(-1, 1)}

    local x_offset, z_offset = 0, 0

    -- ROOT GENERATION
    for i = 1, math.random(6, 10) do
        self:enqueue(function()
            local angle = math.rad(i * (360 / 8) + math.random(-20, 20))
            local r = math.random(2, 5)

            -- Start a bit up the trunk
            local start_y = base_pos.y + math.random(0, 3)

            -- Calculate starting point on side of trunk
            local root_pos = {
                x = math.floor(base_pos.x + math.cos(angle) * r),
                y = start_y,
                z = math.floor(base_pos.z + math.sin(angle) * r)
            }

            -- First segment: from trunk edge, slightly down
            local mid_pos = {
                x = root_pos.x + math.random(-1, 1),
                y = root_pos.y - 1,
                z = root_pos.z + math.random(-1, 1)
            }

            -- Second segment: farther out and deeper
            local end_pos = {
                x = root_pos.x + math.floor(math.cos(angle) * 3),
                y = root_pos.y - math.random(4, 8),
                z = root_pos.z + math.floor(math.sin(angle) * 3)
            }

            -- Draw segments with tapering thickness
            self:draw_branch_segment(root_pos, mid_pos, 3) -- thick near trunk
            self:draw_branch_segment(mid_pos, end_pos, math.random(1, 2)) -- tapering
        end)
    end

    -- TRUNK GENERATION
    for y = 0, trunk_height do
        local y_pos = y
        self:enqueue(function()
            x_offset = x_offset + trunk_dir.x * 0.1
            z_offset = z_offset + trunk_dir.z * 0.1

            local taper_x = math.max(2, math.floor((base_trunk_radius - y_pos * 0.2)))
            local taper_z = math.max(2, math.floor((base_trunk_radius - y_pos * 0.16)))

            for dx = -taper_x, taper_x do
                for dz = -taper_z, taper_z do
                    if dx * dx + dz * dz <= math.max(taper_x, taper_z)^2 then
                        local px = math.floor(base_pos.x + dx + x_offset)
                        local py = base_pos.y + y_pos
                        local pz = math.floor(base_pos.z + dz + z_offset)
                        minetest.set_node({x = px, y = py, z = pz}, {name = self.trunk_material})
                    end
                end
            end

            if y_pos > trunk_height * 0.4 and y_pos % 5 == 0 then
                self:enqueue(function()
                    self:branch({
                        x = math.floor(base_pos.x + x_offset),
                        y = base_pos.y + y_pos,
                        z = math.floor(base_pos.z + z_offset)
                    }, math.random(6, 12), math.random(2, 4))
                end)
            end
        end)
    end

    local top_pos = {
        x = math.floor(base_pos.x + x_offset),
        y = base_pos.y + trunk_height,
        z = math.floor(base_pos.z + z_offset)
    }

    local split_count = math.random(1, 3)
    for i = 1, split_count do
        self:enqueue(function()
            self:branch(top_pos, math.random(12, 20), 4)
        end)
    end

    minetest.chat_send_all("The mighty oak is taking root...")
    self:process_queue()
end

-- 🟢 OakTree definition
local OakTree = Tree:new({
    trunk_material = "mcl_core:tree",
    leaf_material = "mcl_core:darkleaves",
    min_radius = 30,
    max_radius = 45,
    name = "oak"
})

-- Node that triggers tree generation
minetest.register_node("big_tree:oak", {
    description = "Big Oak Tree Generator",
    tiles = {"big_oak_magic_sapling.png"},
    groups = {choppy = 2, oddly_breakable_by_hand = 2},
    on_rightclick = function(pos, node, clicker, itemstack, pointed_thing)
        minetest.chat_send_player(clicker:get_player_name(), "You hear the forest groan...")
        minetest.after(5, function()
            OakTree:generate(pos)
        end)
    end
})
