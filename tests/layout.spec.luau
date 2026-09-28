-- Trazado de los mundos: áreas 1-10 en línea recta (idénticas a las de Nexus de antes), esquina en el 10 y 11-20 giradas
local H = require("./harness")
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3
local M = H.modules()
local Config = M.Config

H.describe("Trazado")

-- Implementación vieja (línea recta) para comparar
local function oldCenter(d, i) return d.Origin + Vector3.new(0, 0, (i - 1) * d.ZoneLength) end
local function oldZone(d, pos)
	if math.abs(pos.X - d.Origin.X) > 130 then return nil end
	local rel = pos.Z - d.Origin.Z + d.ZoneLength / 2
	local i = math.floor(rel / d.ZoneLength) + 1
	if i < 1 or i > d.ZoneCount then return nil end
	return i
end

local function veq(a, b, eps, msg)
	H.ok((a - b).Magnitude <= (eps or 1e-4), string.format("%s: esperado %s, obtenido %s", msg or "vector", tostring(b), tostring(a)))
end

H.test("Nexus: centros de las áreas 1-10 idénticos a los de antes", function()
	local d = Config.Dimensions.Nexus
	for i = 1, 10 do
		H.eq(Config.ZoneCenter("Nexus", i), oldCenter(d, i), "área " .. i)
		H.eq(Config.AreaCFrame("Nexus", i).Position, oldCenter(d, i), "CFrame área " .. i)
		veq(Config.AreaCFrame("Nexus", i).LookVector, Vector3.new(0, 0, 1), 1e-6, "mira hacia +Z")
	end
end)

H.test("Nexus: ZoneFromPosition igual que antes en las áreas 1-9 (puntos al azar)", function()
	local d = Config.Dimensions.Nexus
	local rng = H.rng(5)
	local zMax = d.Origin.Z + 8.5 * d.ZoneLength -- hasta el final del área 9
	for _ = 1, 5000 do
		local pos = Vector3.new(rng:NextNumber(-200, 200), rng:NextNumber(-5, 30), rng:NextNumber(-100, zMax))
		local old, new = oldZone(d, pos), Config.ZoneFromPosition("Nexus", pos)
		if old then
			H.eq(new, old, tostring(pos))
		else
			-- fuera del ancho de 1-9 solo puede aparecer el área 11: su rectángulo (ancho 260 alrededor del giro)
			-- llega por el costado derecho hasta 130 studs antes del centro del área 10, sobre el vacío
			H.ok(new == nil or new == 11, tostring(pos) .. " -> " .. tostring(new))
		end
	end
	H.eq(Config.ZoneFromPosition("Nexus", Vector3.new(-160, 0, 1376)), 11)
	H.eq(Config.ZoneFromPosition("Nexus", Vector3.new(-160, 0, 1320)), nil)
end)

H.test("Nexus: puertas, llegada y lobby en la misma posición de antes", function()
	local d = Config.Dimensions.Nexus
	for i = 2, 10 do
		local g = Config.GateCFrame("Nexus", i)
		H.eq(g.Position, oldCenter(d, i) - Vector3.new(0, 0, d.ZoneLength / 2), "puerta " .. i)
		veq(g.LookVector, Vector3.new(0, 0, -1), 1e-6, "la cara Front mira a quien llega (como WorldBuilder)")
		H.eq(Config.ZoneEntry("Nexus", i), oldCenter(d, i) - Vector3.new(0, 0, d.PlotLength / 2 + 7), "llegada " .. i)
	end
	H.eq(Config.LobbySpawn("Nexus"), d.LobbyCenter - Vector3.new(0, 0, 30))
end)

H.test("esquina: el camino gira a la derecha (-X mirando +Z) y 11-20 siguen rectas", function()
	local P = Config.ZoneCenter("Nexus", 10)
	H.eq(P, Vector3.new(0, 0, 1460))
	H.eq(Config.ZoneCenter("Nexus", 11), Vector3.new(-200, 0, 1460))
	H.eq(Config.ZoneCenter("Nexus", 20), Vector3.new(-200 - 9 * 140, 0, 1460))
	for i = 11, 20 do
		veq(Config.AreaCFrame("Nexus", i).LookVector, Vector3.new(-1, 0, 0), 1e-6, "área " .. i .. " mira a -X")
		veq(Config.ZoneEntryCFrame("Nexus", i).LookVector, Vector3.new(-1, 0, 0), 1e-6, "teleport mira a -X")
	end
	H.eq(Config.GateCFrame("Nexus", 11).Position, Vector3.new(-130, 0, 1460))
	veq(Config.GateCFrame("Nexus", 11).LookVector, Vector3.new(1, 0, 0), 1e-6, "puerta 11 mira hacia la esquina")
end)

H.test("esquina: la plaza (adelante e izquierda) es del área 10", function()
	local P = Config.ZoneCenter("Nexus", 10)
	H.eq(Config.ZoneFromPosition("Nexus", P + Vector3.new(150, 0, 150)), 10, "plaza adelante-izquierda")
	H.eq(Config.ZoneFromPosition("Nexus", P + Vector3.new(185, 0, 0)), 10, "izquierda")
	H.eq(Config.ZoneFromPosition("Nexus", P + Vector3.new(0, 0, 185)), 10, "adelante")
	H.eq(Config.ZoneFromPosition("Nexus", P + Vector3.new(195, 0, 0)), nil, "fuera por la izquierda")
	H.eq(Config.ZoneFromPosition("Nexus", P + Vector3.new(0, 0, 195)), nil, "fuera por adelante")
	H.eq(Config.ZoneFromPosition("Nexus", P + Vector3.new(-129, 0, 0)), 10, "justo antes de la puerta 11")
	H.eq(Config.ZoneFromPosition("Nexus", P + Vector3.new(-131, 0, 0)), 11, "justo después de la puerta 11")
	H.eq(Config.ZoneFromPosition("Nexus", P + Vector3.new(-200, 0, 125)), 11, "isla lateral izquierda del área 11")
	H.eq(Config.ZoneFromPosition("Nexus", P + Vector3.new(-200, 0, -125)), 11, "isla lateral derecha del área 11")
	H.eq(Config.ZoneFromPosition("Nexus", P + Vector3.new(-200, 0, -135)), nil, "fuera del ancho del área 11")
	local rect = Config.AreaRect("Nexus", 10)
	H.eq(rect.Width, 130 + 190)
	H.eq(rect.Length, 190 + 70)
end)

H.test("cada puerta separa el área anterior de la suya", function()
	for _, dim in ipairs({ "Nexus", "Greenwood" }) do
		for i = 2, 20 do
			local g = Config.GateCFrame(dim, i)
			local ahead = -g.LookVector -- hacia donde se avanza
			H.eq(Config.ZoneFromPosition(dim, g.Position - ahead * 1), i - 1, dim .. " antes de la puerta " .. i)
			H.eq(Config.ZoneFromPosition(dim, g.Position + ahead * 1), i, dim .. " después de la puerta " .. i)
			H.eq(Config.ZoneFromPosition(dim, Config.ZoneEntry(dim, i)), i, dim .. " llegada " .. i)
		end
	end
end)

H.test("las áreas de un mundo no se pisan", function()
	local rng = H.rng(77)
	for _, dim in ipairs({ "Nexus", "Greenwood" }) do
		local o = Config.Dimensions[dim].Origin
		for _ = 1, 6000 do
			local pos = o + Vector3.new(rng:NextNumber(-1700, 400) + 0.37, 0, rng:NextNumber(-200, 1800) + 0.37)
			local hits = 0
			for i = 1, 20 do
				if Config.PointInArea(dim, i, pos) then hits += 1 end
			end
			H.ok(hits <= 1, dim .. ": " .. tostring(pos) .. " está en " .. hits .. " áreas")
		end
	end
end)

H.test("Greenwood y Nexus no se superponen (el anticheat de un mundo no toca al otro)", function()
	local rng = H.rng(3)
	for _, pair in ipairs({ { "Greenwood", "Nexus" }, { "Nexus", "Greenwood" } }) do
		local a, b = pair[1], pair[2]
		for i = 1, 20 do
			local rect = Config.AreaRect(a, i)
			for _ = 1, 150 do
				local p = rect.CFrame.Position + rect.CFrame.RightVector * rng:NextNumber(-rect.Width / 2, rect.Width / 2)
					+ rect.CFrame.LookVector * rng:NextNumber(-rect.Length / 2, rect.Length / 2)
				H.eq(Config.ZoneFromPosition(b, p), nil, a .. " área " .. i .. " cae en " .. b)
			end
		end
		H.eq(Config.ZoneFromPosition(b, Config.Dimensions[a].LobbyCenter), nil, "lobby de " .. a)
	end
end)

H.test("mundo inicial: Nexus mientras Greenwood no tenga mapa", function()
	H.eq(Config.StartWorld, "Greenwood")
	H.eq(Config.SpawnWorld(), "Nexus")
	local M2 = H.modules()
	M2.Config.Dimensions.Greenwood.AreasBuilt = 3
	H.eq(M2.Config.SpawnWorld(), "Greenwood")
	H.eq(M2.Config.WorldsByOrder()[1], "Greenwood")
	H.eq(M2.Config.WorldsByOrder()[2], "Nexus")
end)

H.test("economía de Nexus igual que hoy (precios y multiplicadores)", function()
	for i = 1, 20 do
		local g = i -- antes Nexus era el mundo 1: índice global = área
		H.eq(Config.GlobalIndex("Nexus", i), g)
		H.eq(Config.ZonePrice("Nexus", i), g <= 1 and 0 or math.floor(150 * (1.9 ^ (g - 2))))
		H.eq(Config.ZoneMultiplier("Nexus", i), 1.65 ^ (g - 1))
	end
	local M2 = H.modules()
	M2.Config.Dimensions.Nexus.EconomyOrder = nil -- usaría Order = 2
	H.eq(M2.Config.GlobalIndex("Nexus", 1), 21)
end)

return H
