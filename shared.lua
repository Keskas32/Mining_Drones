--Shared data interface between data and script, notably prototype names.

local data = {}

data.drone_name = "mining-drone"
data.proxy_chest_name = "mining-drone-proxy-chest"
data.mining_damage = 5
data.mining_interval = math.floor(26 * 1.5) --dictated by character mining animation
data.attack_proxy_name = "mining-drone-attack-proxy-new"
data.mining_depot = "mining-depot"
data.mining_depot_chest_h = "mining-depot-chest-h"
data.mining_depot_chest_v = "mining-depot-chest-v"
data.variation_count = 20

data.mining_speed_technology = "mining-drone-mining-speed"
data.mining_productivity_technology = "mining-drone-productivity"

data.depots =
{
  ["mining-depot"] =
  {
    radius = 25 + 0.5,
    capacity = 50,
    drop_offset = {0, -5.5},
    shifts =
    {
      north = {0,0},
      south = {0, 1},
      east = {0, 0.5},
      west = {0, 0.5},
    }
  }
}

return data
