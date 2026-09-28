-- Pet Nexus: progresión (rebirth, rango, niveles de mascota) como funciones puras sobre los datos del jugador.
-- Igual que Economy: no tocan instancias ni remotes; devuelven (false, codigo, extra) o (true, resultado...).
local Config = require(script.Parent.Config)
local Stats = require(script.Parent.Stats)

local Progression = {}

---------------------------------------------------------------- rebirth
-- Errores: dim (mundo sin rebirth), done (ya hecho), order (falta el rebirth anterior), area (falta desbloquear el área)
function Progression.CanRebirth(data, dim)
	local def = Config.Rebirths[dim]
	if type(dim) ~= "string" or not def or not Config.Dimensions[dim] then return false, "dim" end
	if Stats.RebirthDone(data, dim) then return false, "done" end
	for other, o in pairs(Config.Rebirths) do
		if o.Number < def.Number and not Stats.RebirthDone(data, other) then return false, "order", other end
	end
	if (data.Unlocked[dim] or 0) < def.Area then return false, "area", def.Area end
	return true
end

-- Hace el rebirth de dim: marca el rebirth y, salvo con Rebirth+ (KeepOnRebirth), reinicia la moneda y las áreas
-- de ESE mundo (vuelve al área 1). No toca otros mundos. Devuelve true, { Number, Kept }.
function Progression.Rebirth(data, dim)
	local ok, err, extra = Progression.CanRebirth(data, dim)
	if not ok then return false, err, extra end
	local keep = false
	for key, def in pairs(Config.GamePasses) do
		if def.KeepOnRebirth and Stats.HasPass(data, key) then keep = true end
	end
	data.RebirthsDone[dim] = true
	if not keep then
		data.Currency[dim] = 0
		data.Unlocked[dim] = 1
	end
	return true, { Number = Config.Rebirths[dim].Number, Kept = keep }
end

---------------------------------------------------------------- rango
-- Compra el rango 'rank' con diamantes (tiene que ser el siguiente). Errores: locked, rank, owned, max, order, funds
function Progression.BuyRank(data, rank)
	if not Stats.RankUnlocked(data) then return false, "locked" end
	if type(rank) ~= "number" or rank ~= math.floor(rank) then return false, "rank" end
	local current = Stats.Rank(data)
	if rank <= current then return false, "owned" end
	if rank > #Config.Ranks.Levels then return false, "max" end
	if rank ~= current + 1 then return false, "order" end
	local cost = Config.Ranks.Levels[rank].Cost
	local have = data.Diamonds or 0
	if have < cost then return false, "funds", cost - have end
	data.Diamonds = have - cost
	data.Rank = rank
	return true
end

-- Rango comprado con Robux (producto RankSkip<rank>): da el rango si es el siguiente y está desbloqueado.
-- Si ya no aplica (se compró con diamantes mientras tanto, o el rango está bloqueado) compensa con su costo en diamantes.
-- Devuelve "rank" o "compensated", y el rango / los diamantes.
function Progression.GrantRankSkip(data, rank)
	local entry = Config.Ranks.Levels[rank]
	if Stats.RankUnlocked(data) and rank == Stats.Rank(data) + 1 then
		data.Rank = rank
		return "rank", rank
	end
	local amount = entry and entry.Cost or 0
	data.Diamonds = (data.Diamonds or 0) + amount
	return "compensated", amount
end

---------------------------------------------------------------- niveles de mascota
-- XP para pasar del nivel 'level' al siguiente (0 en el máximo)
function Progression.XPToNext(level)
	local cfg = Config.PetLevels
	if level >= cfg.MaxLevel then return 0 end
	return math.floor(cfg.XPBase * cfg.XPGrowth ^ (level - 1))
end

-- Suma XP a una mascota y sube de nivel las veces que haga falta. Devuelve los niveles subidos.
function Progression.AddPetXP(pet, amount)
	local cfg = Config.PetLevels
	pet.Level = type(pet.Level) == "number" and pet.Level or cfg.StartLevel
	pet.XP = (type(pet.XP) == "number" and pet.XP or 0) + math.max(0, amount)
	local gained = 0
	while pet.Level < cfg.MaxLevel do
		local need = Progression.XPToNext(pet.Level)
		if pet.XP < need then break end
		pet.XP -= need
		pet.Level += 1
		gained += 1
	end
	if pet.Level >= cfg.MaxLevel then
		pet.Level = cfg.MaxLevel
		pet.XP = 0
	end
	return gained
end

-- XP de un rompible para cada mascota equipada (no se divide entre ellas). Devuelve la XP dada y si alguna subió.
function Progression.GrantBreakXP(data, kindName)
	local k = Config.Breakables[kindName]
	if not k or not k.XP then return 0, false end
	local xp = math.floor(k.XP * Stats.Get(data, "XP"))
	local leveled = false
	for _, pet in ipairs(data.Pets) do
		if pet.Equipped and Progression.AddPetXP(pet, xp) > 0 then leveled = true end
	end
	return xp, leveled
end

---------------------------------------------------------------- mundo actual
-- Mundo donde está pos (área o cerca del lobby). Sin pos o fuera de todo: el mundo más avanzado desbloqueado.
function Progression.CurrentWorld(data, pos)
	if pos then
		for dim, d in pairs(Config.Dimensions) do
			if Config.ZoneFromPosition(dim, pos) then return dim end
			local flat = Vector3.new(pos.X, d.LobbyCenter.Y, pos.Z)
			if (flat - d.LobbyCenter).Magnitude < 100 then return dim end
		end
	end
	local best
	for _, dim in ipairs(Config.WorldsByOrder()) do
		if (data.Unlocked[dim] or 0) >= 1 then best = dim end
	end
	return best or Config.SpawnWorld()
end

return Progression
