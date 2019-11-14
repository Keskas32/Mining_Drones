local proxy_inventory = function()
  local chest = game.surfaces[1].create_entity{name = shared.proxy_chest_name, position = {1000000, 1000000}, force = "neutral"}
  return chest.get_output_inventory()
end

local taken = {}

local unique_index = function(entity)
  local index = entity.unit_number or entity.surface.index..math.floor(entity.position.x).."-"..math.floor(entity.position.y)
  return index
end

local mining_speed = 0.55
local interval = shared.mining_interval
local damage = shared.mining_damage
local ceil = math.ceil
local max = math.max
local min = math.min

local attack_proxy = function(entity)

  local size = min(ceil((max(entity.get_radius() - 0.1, 0.25)) * 2), 10)

  --Health is set so it will take just enough damage at exactly the right time

  local mining_time = entity.prototype.mineable_properties.mining_time

  local number_of_ticks = (mining_time / mining_speed) * 60
  local number_of_hits = math.ceil(number_of_ticks / interval)

  local proxy = entity.surface.create_entity{name = shared.attack_proxy_name..size, position = entity.position, force = "neutral"}
  proxy.health = number_of_hits * damage
  return proxy
end

local states =
{
  mining_entity = 1,
  return_to_depot = 2
}

local product_amount = util.product_amount

local mining_drone = {}

mining_drone.metatable = {__index = mining_drone}

mining_drone.new = function(entity)
  if entity.name ~= shared.drone_name then error("what are you playing at") end
  local new_drone = {}
  new_drone.entity = entity
  entity.ai_settings.path_resolution_modifier = 0
  new_drone.inventory = proxy_inventory()


  rendering.draw_light
  {
    sprite = "mining-drone-light",
    oriented = true,
    target = entity,
    target_offset = {0, 0},
    surface = entity.surface,
    minimum_darkness = 0.3,
    intensity = 0.6,
    scale = 2
  }

  rendering.draw_light
  {
    sprite = "utility/light_medium",
    oriented = false,
    target = entity,
    target_offset = {0, 0},
    surface = entity.surface,
    minimum_darkness = 0.3,
    intensity = 0.4,
    scale = 2.5,
  }


  setmetatable(new_drone, mining_drone.metatable)
  return new_drone
end

function mining_drone:get_desired_item()

  if self.depot then
    return self.depot:get_desired_item()
  end

end

function mining_drone:spill(stack)
  self.entity.surface.spill_item_stack(self.entity.position, stack, false, self.entity.force, false)
end

function mining_drone:process_mining()

  local target = self.mining_target
  if not (target and target.valid) then
    --cancel command or something.
    return self:return_to_depot()
  end


  local item = self:get_desired_item()
  if not item then
    self:say("I don't know what I want")
    self:return_to_depot()
    return
  end

  local mineable_properties = target.prototype.mineable_properties

  for k, product in pairs (mineable_properties.products) do
    if product.name == item then
      local amount = self.inventory.insert({name = product.name, count = product_amount(product)})
    else
      self:spill{name = product.name, count = product_amount(product)}
    end
  end

  self:update_sticker()

  if target.type == "resource" and target.amount > 1 then
    target.amount = target.amount - 1
  else
    target.destroy()
  end

  self.mining_count = self.mining_count - 1

  if not target.valid or self.mining_count <= 0 then
    self:return_to_depot()
    return
  end

  self:mine_entity(target, self.mining_count)
  return


end

function mining_drone:request_order()
  self.depot:handle_order_request(self)
end

function mining_drone:find_new_depot()
  local old_depot = self.depot
  --we should have the old depot... hopefully...

  if not old_depot then
    game.print("Oof, I am not handling this yet")
  end

  local all_depots = old_depot:get_all_depots()
  local can_go_to = {}
  for unit_number, depot in pairs (all_depots) do
    if depot:can_accept_drone() then
      can_go_to[unit_number] = depot.entity
    end
  end

  if not next(can_go_to) then
    --None to go to
    self.entity.die()
    return
  end

  local closest_entity = self.entity.surface.get_closest(self.position, can_go_to)

  local closest_depot = can_go_to[closest_entity.unit_number]

  self:set_depot(closest_depot)
  self:return_to_depot()

end

function mining_drone:process_return_to_depot()

  local depot = self.depot

  if not (depot and depot.entity.valid) then
    self:say("My depot isn't valid!")
    return self:find_new_depot()
  end

  if util.distance(self.entity.position, self.depot:get_spawn_position()) > 1 then
    self:go_to_position(self.depot:get_spawn_position())
    return
  end

  local inventory = self.inventory
  if not inventory.is_empty() then

    local destination_inventory = depot:get_output_inventory()
    for k = 1, #inventory do
      local stack = inventory[k]
      if (stack and stack.valid and stack.valid_for_read) then
        local count = stack.count
        local inserted = destination_inventory.insert(stack)
        depot.estimated_count = depot.estimated_count - inserted
        if inserted == count then
          stack.clear()
        else
          stack.count  = count - inserted
        end
      else
        break
      end
    end

    self:update_sticker()

  end

  if not self.inventory.is_empty() then
    --oof, we still holding something... oof
    self:say("oof, I am still holding something... oof")
    for name, count in pairs (self.inventory.get_contents()) do
      self:spill{name = name, count = count}
    end
  end

  self:request_order()

end


function mining_drone:process_failed_command()
  if self.state == states.mining_entity then
    self:say("I can't mine that entity!")

    self:clear_attack_proxy()


    self:return_to_depot()
    return
  end

  if self.state == states.return_to_depot then
    self:say("I can't return to my depot!")
    self:return_to_depot()
  end

end

function mining_drone:update(event)
  if not self.entity.valid then return end

  if event.result ~= defines.behavior_result.success then
    --self:say("FAIL BLOG.ORG")
    self:process_failed_command()
    return
  end

  if self.state == states.mining_entity then
    self:process_mining()
    return
  end

  if self.state == states.return_to_depot then
    self:process_return_to_depot()
    return
  end
end

function mining_drone:say(text)
  self.entity.surface.create_entity{name = "flying-text", position = self.entity.position, text = text}
end

function mining_drone:mine_entity(entity, count)
  self.mining_count = count or 1
  self.mining_target = entity
  self.state = states.mining_entity
  local attack_proxy = attack_proxy(entity)
  self.attack_proxy = attack_proxy
  local command = {}

  local commands =
  {
    {
      type = defines.command.go_to_location,
      destination_entity = attack_proxy,
      distraction = defines.distraction.by_damage,
      pathfind_flags = {prefer_straight_paths = false, use_cache = false}
    },
    {
      type = defines.command.attack,
      target = attack_proxy,
      distraction = defines.distraction.by_damage
    }
  }
  self.entity.set_command
  {
    type = defines.command.compound,
    structure_type = defines.compound_command.return_last,
    commands = commands,
    distraction = defines.distraction.by_damage
  }
end

function mining_drone:set_depot(depot)
  self.depot = depot
end

function mining_drone:return_to_depot()
  self.state = states.return_to_depot
  local depot = self.depot

  if not (depot and depot.entity.valid) then
    self:find_new_depot()
    return
  end

  if self.mining_count then
    depot.estimated_count = depot.estimated_count - self.mining_count
    self.mining_count = nil
  end

  local position = depot:get_spawn_position()
  if position then
    self:go_to_position(position, 0.3)
    return
  end
end

function mining_drone:go_to_position(position, radius)
  self.entity.set_command
  {
    type = defines.command.go_to_location,
    destination = position,
    radius = radius or 1
  }
end

function mining_drone:go_to_entity(entity, radius)
  self.entity.set_command
  {
    type = defines.command.go_to_location,
    destination_entity = entity,
    radius = radius or 5
  }
end

function mining_drone:clear_attack_proxy()
  local destroyed = self.attack_proxy and self.attack_proxy.valid and self.attack_proxy.destroy()
  self.attack_proxy = nil
end


function mining_drone:clear_mining_target()
  if self.mining_target and self.mining_target.valid then
    if self.depot then
      self.depot:add_mining_target(self.mining_target)
    end
  end
  self.mining_target = nil
end

function mining_drone:clear_depot(unit_number)
  if not self.depot then return end
  self.depot.drones[unit_number] = nil
  if self.mining_count then
    self.depot.estimated_count = self.depot.estimated_count - self.mining_count
    self.mining_count = nil
  end
  self.depot = nil
end

function mining_drone:handle_drone_deletion(unit_number)
  self:clear_attack_proxy()
  self:clear_mining_target()
  self:clear_depot(unit_number)
end

local insert = table.insert
function mining_drone:update_sticker()

  local renderings = self.renderings
  if renderings then
    for k, v in pairs (renderings) do
      rendering.destroy(v)
    end
    self.renderings = nil
  end

  local inventory = self.inventory

  local contents = inventory.get_contents()

  if not next(contents) then return end

  local number = table_size(contents)

  local drone = self.entity
  local surface = drone.surface
  local forces = {drone.force}

  local renderings = {}
  self.renderings = renderings

  insert(renderings, rendering.draw_sprite
  {
    sprite = "utility/entity_info_dark_background",
    target = drone,
    surface = surface,
    forces = forces,
    only_in_alt_mode = true,
    target_offset = {0, -0.5},
    x_scale = 0.5,
    y_scale = 0.5,
  })

  insert(renderings, rendering.draw_sprite
  {
    sprite = "item/"..next(contents),
    target = drone,
    surface = surface,
    forces = forces,
    only_in_alt_mode = true,
    target_offset = {0, -0.5},
    x_scale = 0.5,
    y_scale = 0.5,
  })


end

return mining_drone