--Placement queue, to allow placing blocks further away and deferring their placement until we get near enough
local queue = {}

local fill_pos1 --first position for fill
local filling = nil --function determining whether to fill each node
local punching = 0 --punch cooldown
local replacing = nil --what node we're replacing, if any

--Add node to queue
local function queue_add(pos, node)
    node = node or minetest.localplayer:get_wielded_item():get_name()
    queue[pos.x] = queue[pos.x] or {}
    queue[pos.x][pos.y] = queue[pos.x][pos.y] or {}
    queue[pos.x][pos.y][pos.z] = {node, replacing}
end

--General fill function, can be supplied with functions to limit fill
local function fill(pos1, pos2, func)
    func = func or function () return true end
    local mirror_z = minetest.settings:get_bool("mirror_z")
    local a, b, c = math.abs(pos1.x-pos2.x), math.abs(pos1.y-pos2.y), math.abs(pos1.z-pos2.z)
    if a >= 64 or b >= 64 or c >= 64 or a*b*c >= 10000 then
        return "area too big ("..a.."x"..b.."x"..c..", "..(a*b*c).." nodes)"
    end
    local node = minetest.localplayer:get_wielded_item():get_name()
    for x = math.min(pos1.x, pos2.x), math.max(pos1.x, pos2.x) do
        for y = math.min(pos1.y, pos2.y), math.max(pos1.y, pos2.y) do
            for z = math.min(pos1.z, pos2.z), math.max(pos1.z, pos2.z) do
                local pos = vector.new(x, y, z)
                if func(pos, pos1, pos2) then
                    queue_add(pos, node)
                    if mirror_z then
                        queue_add(vector.new(-x, y, z), node)
                    end
                end
            end
        end
    end
end

--Fill command: fills whole area
minetest.register_chatcommand("fill", {
    params = "",
    description = "Fill indicated area",
    func = function ()
        filling = function () return true end
    end
})

--Walls command: fills vertical walls around area
minetest.register_chatcommand("walls", {
    params = "",
    description = "Fill sides of indicated area",
    func = function ()
        filling = function (pos, pos1, pos2)
            return pos.x == pos1.x or pos.x == pos2.x or pos.z == pos1.z or pos.z == pos2.z
        end
    end
})

--Replace command: sets node to replace
minetest.register_chatcommand("replace", {
    params = "<node>",
    description = "Set fill commands to only replace certain nodes",
    func = function (param)
        if not param or param == "" then replacing = nil else replacing = param end
    end
})

--Override punches to control fills
minetest.register_on_punchnode(function (pos)
    if punching > 0 then return true end
    if not filling then return end
    punching = 0.2
    if fill_pos1 then
        minetest.log("second position set")
        local error = fill(fill_pos1, pos, filling)
        filling = nil
        fill_pos1 = nil
        if error then minetest.log(error) else minetest.log("filled!") end
    else
        fill_pos1 = pos
        minetest.log("first position set")
    end
    return true
end)

--Place nodes in queue where possible
minetest.register_globalstep(function (dtime)
    if punching > 0 then punching = punching-dtime end
    if not minetest.localplayer then return end
    local player = minetest.localplayer:get_pos()
    local deletions = {}
    local node = minetest.localplayer:get_wielded_item():get_name()
    for x, l in pairs(queue) do for y, m in pairs(l) do for z, val in pairs(m) do
        local name, replace = val[1], val[2]
        if name == "" or name == node then
            local pos = vector.new(x, y, z)
            if vector.distance(player, pos) <= 20 then
                local cur_node = minetest.get_node_or_nil(pos)
                if cur_node and cur_node.name ~= name and (cur_node.name == replace or not replace) then
                    minetest.dig_node(pos)
                    if name ~= "" then minetest.place_node(pos) end
                end
                table.insert(deletions, 1, pos)
            end
        end
    end end end
    for _, pos in ipairs(deletions) do
        queue[pos.x][pos.y][pos.z] = nil
    end
end)

--Place nodes mirrored in the YZ-plane
minetest.register_on_placenode(function (pointed)
    if minetest.settings:get_bool("mirror_z") then
        pointed.under.x = -pointed.under.x
        pointed.above.x = -pointed.above.x
        queue_add(pointed.above)
    end
end)

--Dig nodes mirrored in the YZ-plane
minetest.register_on_dignode(function (pos)
    if minetest.settings:get_bool("mirror_z") then
        minetest.dig_node(pos)
        pos.x = -pos.x
        queue_add(pos, "")
    end
end)

minetest.register_cheat("Mirror (Z-axis)", "Interact", "mirror_z")