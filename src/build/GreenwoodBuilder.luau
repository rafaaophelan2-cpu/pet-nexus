-- Pet Nexus: constructor del mundo 1 "Greenwood" (solo edición). Uso desde execute_luau (Edit):
--   require(game.ServerStorage.PetNexusBuild.GreenwoodBuilder:Clone()).BuildWorld()
-- Mundo "en tierra" y cotidiano (nada llamativo): pasto continuo, veredas, casas, edificios, bosques y parques.
-- Todo se coloca en coordenadas locales de cada área (Config.AreaCFrame): x = derecha, z = adelante (hacia donde se
-- camina), así las áreas 11-20 (después de la curva a la derecha del área 10) usan el mismo código.
-- Los props salen de ServerStorage.PetNexusBuild.Props (modelos generados, pivote en el centro de la base, frente a +Z).
-- Si falta un prop, se omite sin romper nada.
local CollectionService = game:GetService("CollectionService")
local Config = require(game.ReplicatedStorage.PetNexus.Config:Clone())
local WB = require(game.ServerStorage.PetNexusBuild.WorldBuilder:Clone())
local Props = game.ServerStorage.PetNexusBuild.Props

local GB = {}
local DIM = "Greenwood"
local part = WB.Part

local function C(r, g, b) return Color3.fromRGB(r, g, b) end
local GRASS = C(126, 196, 98)
local GRASS_SIDE = C(138, 206, 106)
local SIDEWALK = C(196, 188, 174)
local CURB = C(160, 150, 140)
local STONE = C(186, 180, 170)
local PLAZA = C(196, 176, 140)
local GOLD = C(246, 202, 84)
local WOOD = C(150, 104, 70)
local WATER = C(96, 176, 230)
local HEDGE = C(70, 140, 70)

local HW = 118 -- borde de las zonas laterales (barrera un poco más afuera)
local BARRIER = 121

---------------------------------------------------------------- helpers
local function localCF(A, x, y, z) return A * CFrame.new(x, y, -z) end

local function prop(parent, name, cf, scale, collide)
	local src = Props:FindFirstChild(name)
	if not src then return nil end
	local m = src:Clone()
	if scale and scale ~= 1 then m:ScaleTo(scale) end
	m:PivotTo(cf)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true; d.CanCollide = collide or false; d.CanQuery = collide or false; d.CanTouch = false
		end
	end
	m.Parent = parent
	return m
end

-- prop en coordenadas del área mirando hacia (fx, fz) (por defecto, hacia el centro del camino a su misma altura z)
local function place(parent, A, name, x, z, scale, fx, fz, collide, y, extraYaw)
	local pos = localCF(A, x, y or 0, z).Position
	local tgt = localCF(A, fx or 0, y or 0, fz or z).Position
	local dir = (tgt - pos) * Vector3.new(1, 0, 1)
	local cf = dir.Magnitude > 0.01 and CFrame.lookAt(pos, pos - dir) or CFrame.new(pos) -- el frente (+Z) mira al objetivo
	if extraYaw then cf = cf * CFrame.Angles(0, math.rad(extraYaw), 0) end
	return prop(parent, name, cf, scale, collide)
end

-- árbol/decoración con giro aleatorio
local function scatter(parent, A, name, x, z, scale, rng, collide)
	local cf = localCF(A, x, 0, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	return prop(parent, name, cf, scale, collide)
end

-- caja en coordenadas del área: tamaño (ancho x, alto, largo z)
local function box(parent, A, name, cx, cy, cz, sx, sy, sz, color, extra)
	local t = { Name = name, Size = Vector3.new(sx, sy, sz), CFrame = localCF(A, cx, cy, cz), Color = color }
	if extra then for k, v in pairs(extra) do t[k] = v end end
	return part(parent, t)
end
local DECO = { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }

local function cyl(parent, A, name, cx, cy, cz, diameter, height, color, extra)
	local t = { Name = name, Shape = Enum.PartType.Cylinder, Size = Vector3.new(height, diameter, diameter),
		CFrame = localCF(A, cx, cy, cz) * CFrame.Angles(0, 0, math.rad(90)), Color = color }
	if extra then for k, v in pairs(extra) do t[k] = v end end
	return part(parent, t)
end

local function barrier(parent, cf, size)
	local b = part(parent, { Name = "Barrier", Size = size, CFrame = cf, Transparency = 1, CanQuery = false, CanTouch = false, CastShadow = false })
	return b
end

-- borde discontinuo blanco alrededor de un rectángulo (en coordenadas del área)
local function dashed(parent, A, w, l, y)
	local dash, gap = 3.2, 2.6
	local function run(x0, z0, x1, z1)
		local len = math.max(math.abs(x1 - x0), math.abs(z1 - z0))
		local alongX = math.abs(x1 - x0) > math.abs(z1 - z0)
		local d = 0
		while d + dash <= len do
			local t = (d + dash / 2) / len
			local x, z = x0 + (x1 - x0) * t, z0 + (z1 - z0) * t
			box(parent, A, "Dash", x, y, z, alongX and dash or 0.7, 0.12, alongX and 0.7 or dash, C(255, 255, 255), DECO)
			d += dash + gap
		end
	end
	local hx, hz = w / 2 - 3, l / 2 - 3
	run(-hx, -hz, hx, -hz); run(-hx, hz, hx, hz); run(-hx, -hz, -hx, hz); run(hx, -hz, hx, hz)
end

-- pared de bosque (colinas + pinos) a lo largo de un segmento local (x fijo, de z0 a z1) o (z fijo, de x0 a x1)
local function forestLine(parent, A, x0, z0, x1, z1, rng, outward)
	local len = ((x1 - x0) ^ 2 + (z1 - z0) ^ 2) ^ 0.5
	local d = 0
	while d <= len do
		local t = len > 0 and d / len or 0
		local x, z = x0 + (x1 - x0) * t, z0 + (z1 - z0) * t
		local ox, oz = outward.X, outward.Y
		scatter(parent, A, "RockHill", x + ox * rng:NextNumber(26, 34), z + oz * rng:NextNumber(26, 34), rng:NextNumber(1.5, 1.9), rng)
		scatter(parent, A, "PineCluster", x + ox * rng:NextNumber(4, 10), z + oz * rng:NextNumber(4, 10), rng:NextNumber(1.0, 1.3), rng)
		d += rng:NextNumber(38, 46)
	end
end

---------------------------------------------------------------- puerta de área (estilo pueblo: postes de piedra + muro de luz verde)
local function gate(parent, i)
	local g = Instance.new("Model"); g.Name = "Gate"; g.Parent = parent
	local gcf = Config.GateCFrame(DIM, i)
	local half = 24
	for _, sx in ipairs({ -1, 1 }) do
		local base = gcf * CFrame.new(sx * (half + 3), 0, 0)
		part(g, { Name = "Post", Size = Vector3.new(5, 24, 5), CFrame = base * CFrame.new(0, 12, 0), Color = STONE })
		part(g, { Name = "PostCap", Size = Vector3.new(6.5, 2, 6.5), CFrame = base * CFrame.new(0, 25, 0), Color = CURB })
		part(g, { Name = "Lamp", Shape = Enum.PartType.Ball, Size = Vector3.new(3, 3, 3), CFrame = base * CFrame.new(0, 27.5, 0), Color = C(255, 236, 170), Material = Enum.Material.Neon, CanCollide = false })
	end
	local wall = part(g, { Name = "AreaGate", Size = Vector3.new(half * 2 + 1, 26, 1), CFrame = gcf * CFrame.new(0, 13, 0),
		Color = C(150, 230, 150), Material = Enum.Material.Neon, Transparency = 0.4, CastShadow = false })
	wall:SetAttribute("Dimension", DIM)
	wall:SetAttribute("Zone", i)
	CollectionService:AddTag(wall, "AreaGate")
	local pp = Instance.new("ProximityPrompt")
	pp.Style = Enum.ProximityPromptStyle.Custom
	pp.ActionText = "Comprar"
	pp.ObjectText = "Area " .. i .. " · " .. Config.AreaName(DIM, i)
	pp.MaxActivationDistance = 16
	pp.RequiresLineOfSight = false
	pp.Parent = wall
	WB.TextSurface(wall, Enum.NormalId.Front, {
		{ Name = "AreaNum", Text = "Area " .. i, Size = UDim2.fromScale(0.8, 0.16), Pos = UDim2.fromScale(0.1, 0.06) },
		{ Name = "AreaName", Text = Config.AreaName(DIM, i), Size = UDim2.fromScale(0.94, 0.22), Pos = UDim2.fromScale(0.03, 0.22), Color = C(255, 240, 160) },
		{ Name = "Price", Text = Config.FormatNumber(Config.ZonePrice(DIM, i)), Size = UDim2.fromScale(0.5, 0.17), Pos = UDim2.fromScale(0.4, 0.46) },
	})
	local sg = wall:FindFirstChildOfClass("SurfaceGui")
	sg.Price.TextXAlignment = Enum.TextXAlignment.Left
	sg.Price.TextColor3 = Config.CurrencyOf(DIM).Color
	-- sello invisible de todo el ancho (el cliente le quita la colisión si el área está pagada)
	local seal = part(g, { Name = "GateSeal", Size = Vector3.new(252, 160, 2), CFrame = gcf * CFrame.new(0, 70, 0), Transparency = 1, CanQuery = false, CanTouch = false, CastShadow = false })
	seal:SetAttribute("Dimension", DIM)
	seal:SetAttribute("Zone", i)
	CollectionService:AddTag(seal, "AreaGateSeal")
	return wall
end

---------------------------------------------------------------- temas (zonas laterales: x en [63, 118] y [-118, -63], z en [-60, 60])
local THEMES = {}
local SIDES = { -1, 1 }

local function lamps(m, A)
	for _, sx in ipairs(SIDES) do
		for _, z in ipairs({ -35, 35 }) do place(m, A, "StreetLamp", sx * 58, z, 1, 0, z, true) end
	end
end
local function trees(m, A, name, rng, count, scaleMin, scaleMax, xs)
	for _, sx in ipairs(xs or SIDES) do
		for k = 1, count do
			scatter(m, A, name, sx * rng:NextNumber(70, 112), -60 + (k - 0.5) * (120 / count) + rng:NextNumber(-5, 5), rng:NextNumber(scaleMin, scaleMax), rng, true)
		end
	end
end
local function bushes(m, A, rng, n)
	for _ = 1, n do
		local sx = rng:NextNumber() < 0.5 and -1 or 1
		scatter(m, A, "Bush", sx * rng:NextNumber(66, 115), rng:NextNumber(-62, 62), rng:NextNumber(0.8, 1.2), rng)
	end
end

THEMES["Maple Street"] = function(m, A, rng)
	for _, sx in ipairs(SIDES) do
		for _, z in ipairs({ -36, 36 }) do place(m, A, "House", sx * 92, z, 1.1, 0, z, true) end
		scatter(m, A, "Oak", sx * 100, 0, 0.9, rng, true)
	end
	bushes(m, A, rng, 6); lamps(m, A)
end
THEMES["Oak Park"] = function(m, A, rng)
	place(m, A, "Fountain", -90, 0, 1.2, 0, 0, true)
	for _, z in ipairs({ -22, 22 }) do place(m, A, "Bench", -90, z, 1, -90, 0, true) end
	cyl(m, A, "StatueBase", 90, 1, 0, 14, 2, STONE)
	place(m, A, "DogStatue", 90, 0, 1.1, 0, 0, true, 2)
	for _, z in ipairs({ -22, 22 }) do place(m, A, "Bench", 90, z, 1, 90, 0, true) end
	for _, sx in ipairs(SIDES) do for _, z in ipairs({ -50, 50 }) do scatter(m, A, "Oak", sx * 104, z, rng:NextNumber(0.9, 1.1), rng, true) end end
	bushes(m, A, rng, 6); lamps(m, A)
end
THEMES["Pine Woods"] = function(m, A, rng)
	trees(m, A, "Pine", rng, 5, 0.8, 1.1); trees(m, A, "Pine", rng, 3, 0.7, 0.9); bushes(m, A, rng, 8)
end
THEMES["Market Row"] = function(m, A, rng)
	for _, sx in ipairs(SIDES) do for _, z in ipairs({ -40, 0, 40 }) do place(m, A, "MarketStall", sx * 84, z, 1, 0, z, true) end end
	bushes(m, A, rng, 4); lamps(m, A)
end
THEMES["Willow Pond"] = function(m, A, rng)
	cyl(m, A, "Pond", -90, 0.25, 0, 44, 0.5, WATER, { Material = Enum.Material.Glass, Transparency = 0.15, CanCollide = false })
	cyl(m, A, "PondRim", -90, 0.1, 0, 48, 0.4, C(190, 180, 160))
	box(m, A, "Dock", -70, 0.6, 0, 16, 0.6, 6, WOOD)
	for k = 1, 10 do
		local a = k / 10 * math.pi * 2
		cyl(m, A, "Reed", -90 + math.cos(a) * 23, 2, math.sin(a) * 23, 0.6, 4, C(90, 150, 70), DECO)
	end
	for _, z in ipairs({ -50, 50 }) do scatter(m, A, "Oak", -100, z, 1, rng, true) end
	trees(m, A, "Birch", rng, 3, 0.9, 1.1, { 1 })
	for _, z in ipairs({ -20, 20 }) do place(m, A, "Bench", 72, z, 1, 0, z, true) end
	bushes(m, A, rng, 5); lamps(m, A)
end
THEMES["Brick Lane"] = function(m, A, rng)
	for _, sx in ipairs(SIDES) do for _, z in ipairs({ -36, 36 }) do place(m, A, "BrickBuilding", sx * 92, z, 1.05, 0, z, true) end end
	bushes(m, A, rng, 4); lamps(m, A)
end
THEMES["Birch Forest"] = function(m, A, rng)
	trees(m, A, "Birch", rng, 6, 0.9, 1.2); trees(m, A, "Birch", rng, 3, 0.8, 1.0); bushes(m, A, rng, 6)
end
THEMES["Garden Homes"] = function(m, A, rng)
	place(m, A, "House", -92, -36, 1.1, 0, -36, true); place(m, A, "House", 92, 36, 1.1, 0, 36, true)
	for _, spot in ipairs({ { -92, 30 }, { 92, -30 } }) do
		for r = -1, 1 do
			box(m, A, "GardenBed", spot[1], 0.6, spot[2] + r * 9, 28, 1.2, 5, C(120, 84, 60))
			for k = -1, 1 do scatter(m, A, "Bush", spot[1] + k * 9, spot[2] + r * 9, 0.45, rng) end
		end
	end
	lamps(m, A)
end
THEMES["Old Mill"] = function(m, A, rng)
	place(m, A, "Windmill", -92, 0, 1.1, 0, 0, true)
	for r = -4, 4 do box(m, A, "Wheat", 90, 1, r * 12, 44, 2, 7, C(236, 206, 110), { CastShadow = false, CanCollide = false }) end
	for _, z in ipairs({ -30, 30 }) do cyl(m, A, "Hay", 110, 3, z, 7, 6, C(226, 190, 100)) end
	bushes(m, A, rng, 4)
end
THEMES["Downtown"] = function(m, A, rng)
	for _, sx in ipairs(SIDES) do for _, z in ipairs({ -36, 36 }) do place(m, A, "OfficeBuilding", sx * 92, z, 1.05, 0, z, true) end end
	lamps(m, A)
end
THEMES["Deep Woods"] = function(m, A, rng)
	trees(m, A, "Pine", rng, 6, 0.9, 1.2); trees(m, A, "Oak", rng, 3, 0.8, 1.0); bushes(m, A, rng, 10)
end
THEMES["Campground"] = function(m, A, rng)
	place(m, A, "Tent", -90, -30, 1, 0, -30, true); place(m, A, "Tent", -92, 28, 1, 0, 28, true); place(m, A, "Tent", 90, 0, 1, 0, 0, true)
	for _, sx in ipairs(SIDES) do
		for k = 1, 2 do
			part(m, { Name = "Log", Shape = Enum.PartType.Cylinder, Size = Vector3.new(10, 2.4, 2.4), Color = WOOD,
				CFrame = localCF(A, sx * 76, 1.2, -45 + k * 30) * CFrame.Angles(0, math.rad(90), 0) })
		end
	end
	trees(m, A, "Pine", rng, 3, 0.8, 1.0); bushes(m, A, rng, 4)
end
THEMES["School Yard"] = function(m, A, rng)
	place(m, A, "School", -92, 0, 1.1, 0, 0, true)
	box(m, A, "Court", 90, 0.35, 0, 44, 0.3, 80, C(210, 120, 90))
	box(m, A, "CourtLine", 90, 0.52, 0, 44, 0.06, 1, C(255, 255, 255), DECO)
	box(m, A, "CourtLineL", 70, 0.52, 0, 1, 0.06, 80, C(255, 255, 255), DECO)
	box(m, A, "CourtLineR", 110, 0.52, 0, 1, 0.06, 80, C(255, 255, 255), DECO)
	cyl(m, A, "CourtCircle", 90, 0.5, 0, 14, 0.06, C(255, 255, 255), DECO)
	lamps(m, A)
end
THEMES["Riverside"] = function(m, A, rng)
	for _, sx in ipairs(SIDES) do
		box(m, A, "River", sx * 91, 0.25, 0, 56, 0.5, 26, WATER, { Material = Enum.Material.Glass, Transparency = 0.15, CanCollide = false })
		box(m, A, "Bridge", sx * 91, 1, 0, 8, 1, 30, WOOD)
		for _, z in ipairs({ -40, 40 }) do scatter(m, A, (sx < 0) and "Oak" or "Birch", sx * 96, z, rng:NextNumber(0.9, 1.1), rng, true) end
	end
	bushes(m, A, rng, 6); lamps(m, A)
end
THEMES["Station Street"] = function(m, A, rng)
	place(m, A, "TrainStation", -92, 0, 1.1, 0, 0, true)
	for _, dx in ipairs({ -3, 3 }) do box(m, A, "Rail", 90 + dx, 0.6, 0, 0.8, 0.5, 124, C(150, 150, 160)) end
	for k = -6, 6 do box(m, A, "Sleeper", 90, 0.3, k * 9.5, 10, 0.4, 2, WOOD) end
	lamps(m, A)
end
THEMES["Autumn Grove"] = function(m, A, rng)
	trees(m, A, "AutumnTree", rng, 5, 0.9, 1.2); trees(m, A, "AutumnTree", rng, 2, 0.8, 1.0)
	for _ = 1, 10 do
		local sx = rng:NextNumber() < 0.5 and -1 or 1
		part(m, { Name = "Leaves", Shape = Enum.PartType.Ball, Size = Vector3.new(6, 2, 6), Color = C(230, 130, 60), CanCollide = false,
			CFrame = localCF(A, sx * rng:NextNumber(66, 115), 0.3, rng:NextNumber(-60, 60)) })
	end
end
THEMES["Lakeside Cabins"] = function(m, A, rng)
	place(m, A, "Cabin", -92, -32, 1, 0, -32, true); place(m, A, "Cabin", -92, 32, 1, 0, 32, true)
	cyl(m, A, "Lake", 96, 0.25, 36, 40, 0.5, WATER, { Material = Enum.Material.Glass, Transparency = 0.15, CanCollide = false })
	-- santuario de pociones gratis (tag PotionShrine)
	place(m, A, "PotionHut", 92, -22, 1, 0, -22, true)
	local shrine = box(m, A, "PotionShrine", 72, 3, -22, 6, 6, 6, C(200, 150, 255), { Transparency = 1, CanCollide = false, CanQuery = false })
	CollectionService:AddTag(shrine, "PotionShrine")
	local pp = Instance.new("ProximityPrompt"); pp.Style = Enum.ProximityPromptStyle.Custom; pp.ActionText = "Reclamar"; pp.ObjectText = "Pociones gratis"
	pp.MaxActivationDistance = 14; pp.RequiresLineOfSight = false; pp.Parent = shrine
	trees(m, A, "Pine", rng, 2, 0.8, 1.0)
end
THEMES["Hilltop"] = function(m, A, rng)
	for _ = 1, 5 do
		local sx = rng:NextNumber() < 0.5 and -1 or 1
		part(m, { Name = "Hill", Shape = Enum.PartType.Ball, Size = Vector3.new(34, 18, 34) * rng:NextNumber(0.8, 1.2), Color = GRASS_SIDE,
			CFrame = localCF(A, sx * rng:NextNumber(80, 110), -3, rng:NextNumber(-50, 50)), CanCollide = false })
	end
	place(m, A, "LookoutTower", 92, 0, 1.1, 0, 0, true)
	trees(m, A, "Oak", rng, 2, 0.8, 1.0, { -1 }); bushes(m, A, rng, 6)
end
THEMES["Balloon Field"] = function(m, A, rng)
	-- globo aerostático hacia Nexus (el viaje con Esencia se conecta después)
	local balloon = place(m, A, "HotAirBalloon", -90, 0, 1.2, 0, 0, true)
	local stop = box(m, A, "BalloonStop", -70, 3, 0, 8, 6, 8, C(255, 255, 255), { Transparency = 1, CanCollide = false })
	stop:SetAttribute("From", DIM); stop:SetAttribute("To", "Nexus")
	CollectionService:AddTag(stop, "WorldVehicle")
	local vp = Instance.new("ProximityPrompt"); vp.Style = Enum.ProximityPromptStyle.Custom; vp.ActionText = "Viajar"; vp.ObjectText = "Hot Air Balloon → Nexus"
	vp.MaxActivationDistance = 14; vp.RequiresLineOfSight = false; vp.Parent = stop
	-- ALTAR DE MEDITACIÓN elevado y muy visible (Zona de Meditación del mundo 1)
	local ax, az, h = 88, 0, 10
	cyl(m, A, "AltarBase", ax, h / 2, az, 34, h, STONE)
	cyl(m, A, "AltarTrim", ax, h + 0.3, az, 36, 0.6, GOLD)
	for k = 0, 4 do box(m, A, "AltarStep", ax - 19 - k * 3, h - 1 - k * 2, az, 6, 2, 16, STONE) end
	box(m, A, "AltarStepFill", ax - 25, (h - 9) / 2, az, 14, h - 9, 16, STONE)
	place(m, A, "MeditationAltar", ax, az, 1, 0, 0, false, h + 0.6)
	local zone = box(m, A, "MeditationZone", ax, h + 6.6, az, 30, 12, 30, C(215, 175, 255), { Transparency = 1, CanCollide = false, CanTouch = false, CanQuery = false, CastShadow = false })
	zone:SetAttribute("Dimension", DIM)
	zone:SetAttribute("Zone", 20)
	CollectionService:AddTag(zone, "MeditationZone")
	local beam = cyl(m, A, "AltarBeam", ax, h + 40, az, 6, 80, C(215, 175, 255), { Material = Enum.Material.Neon, Transparency = 0.75, CanCollide = false, CanQuery = false, CastShadow = false })
	local sign = box(m, A, "AltarSign", ax, h + 22, az - 16, 30, 5, 0.4, C(255, 255, 255), { Transparency = 1, CanCollide = false, CanQuery = false })
	sign.CFrame = CFrame.lookAt(sign.Position, localCF(A, 0, h + 22, 0).Position)
	local asg = WB.TextSurface(sign, Enum.NormalId.Front, { { Text = "ALTAR DE MEDITACIÓN", Size = UDim2.fromScale(0.96, 0.8), Pos = UDim2.fromScale(0.02, 0.1), Color = C(230, 205, 255) } })
	asg.PixelsPerStud = 8
	bushes(m, A, rng, 4)
end

---------------------------------------------------------------- área
local function areaBase(m, A, d, a, rng)
	box(m, A, "Path", 0, -0.5, 0, d.ZoneWidth, 1.2, d.ZoneLength, SIDEWALK)
	for _, sx in ipairs(SIDES) do
		box(m, A, "Curb", sx * (d.ZoneWidth / 2 - 1.2), 0.3, 0, 2.4, 1, d.ZoneLength, CURB)
		box(m, A, "SideGrass", sx * ((d.ZoneWidth / 2 + HW) / 2), -0.3, 0, HW - d.ZoneWidth / 2, 1.2, d.ZoneLength, GRASS_SIDE)
	end
	box(m, A, "PlotRim", 0, 0.35, 0, d.PlotWidth + 5, 0.7, d.PlotLength + 5, CURB)
	box(m, A, "Plot", 0, 0.45, 0, d.PlotWidth, 0.9, d.PlotLength, a.Plot)
	dashed(m, A, d.PlotWidth, d.PlotLength, 0.95)
end

local function straightArea(m, A, d, i, a, rng)
	areaBase(m, A, d, a, rng)
	local theme = THEMES[a.Name]
	if theme then theme(m, A, rng) end
	-- barreras laterales y bosque de borde
	for _, sx in ipairs(SIDES) do
		barrier(m, localCF(A, sx * BARRIER, 80, 0), Vector3.new(4, 160, d.ZoneLength))
		forestLine(m, A, sx * 132, -d.ZoneLength / 2 + 10, sx * 132, d.ZoneLength / 2, rng, Vector2.new(sx, 0))
	end
end

-- Área de la curva (Golden Square): el camino gira a la derecha; adelante y a la izquierda queda la plaza del REBIRTH
local function cornerArea(m, A, d, i, a, rng)
	local front, left = Config.Layout.CornerFront, Config.Layout.CornerLeft
	local L = d.ZoneLength
	-- camino hasta la salida derecha (x = HalfWidth) y parcela
	box(m, A, "Path", (130 - 63) / 2, -0.5, 0, 130 + 63, 1.2, L, SIDEWALK)
	box(m, A, "Curb", -63 + 1.2, 0.3, 0, 2.4, 1, L, CURB)
	box(m, A, "PlotRim", 0, 0.35, 0, d.PlotWidth + 5, 0.7, d.PlotLength + 5, CURB)
	box(m, A, "Plot", 0, 0.45, 0, d.PlotWidth, 0.9, d.PlotLength, a.Plot)
	dashed(m, A, d.PlotWidth, d.PlotLength, 0.95)
	-- plaza en L: franja de adelante y franja de la izquierda
	box(m, A, "PlazaFront", (130 - left) / 2, -0.3, (L / 2 + front) / 2, 130 + left, 1.2, front - L / 2, PLAZA)
	box(m, A, "PlazaLeft", (-63 - left) / 2, -0.3, 0, left - 63, 1.2, L, PLAZA)
	-- estatua de REBIRTH: perro ángel dorado gigante en la esquina de la plaza, mirando al camino
	local sx, sz = -118, 118
	cyl(m, A, "PedestalBase", sx, 1.5, sz, 44, 3, STONE)
	cyl(m, A, "PedestalTrim", sx, 3.2, sz, 46, 0.5, GOLD, { Material = Enum.Material.SmoothPlastic })
	cyl(m, A, "Pedestal", sx, 6, sz, 34, 6, C(250, 244, 230))
	place(m, A, "GoldenDogStatue", sx, sz, 1, 0, 0, true, 9)
	-- punto de interacción (tag RebirthStatue + Dimension): delante del pedestal, hacia el camino
	local dirX, dirZ = -sx, -sz
	local mag = (dirX ^ 2 + dirZ ^ 2) ^ 0.5
	local px, pz = sx + dirX / mag * 26, sz + dirZ / mag * 26
	local rb = box(m, A, "RebirthStatue", px, 3, pz, 8, 6, 8, GOLD, { Transparency = 1, CanCollide = false, CanQuery = false })
	rb:SetAttribute("Dimension", DIM)
	CollectionService:AddTag(rb, "RebirthStatue")
	local rp = Instance.new("ProximityPrompt"); rp.Style = Enum.ProximityPromptStyle.Custom; rp.ActionText = "Rebirth"; rp.ObjectText = "Rebirth 1"
	rp.MaxActivationDistance = 16; rp.RequiresLineOfSight = false; rp.Parent = rb
	-- alfombra dorada desde el camino hasta la estatua
	local c0 = localCF(A, -58, 0.35, 58).Position
	local c1 = localCF(A, px, 0.35, pz).Position
	part(m, { Name = "Carpet", Size = Vector3.new(10, 0.2, (c1 - c0).Magnitude), CFrame = CFrame.lookAt((c0 + c1) / 2, c1), Color = C(200, 50, 60), CanCollide = false, CastShadow = false })
	-- columnas doradas alrededor, setos, flores y rayos de luz
	for k = 0, 9 do
		local ang = math.rad(-20 + k * 26)
		local cx, cz = sx + math.cos(ang) * 40, sz - math.sin(ang) * 40
		if not (cx > sx and cz < sz and math.abs(math.atan2(cz - sz, cx - sx) + math.pi / 4) < 0.35) then -- deja libre el acceso de la alfombra
			cyl(m, A, "GoldColumn", cx, 9, cz, 3.2, 18, GOLD)
			part(m, { Name = "ColumnOrb", Shape = Enum.PartType.Ball, Size = Vector3.new(3.6, 3.6, 3.6), CFrame = localCF(A, cx, 19.6, cz), Color = C(255, 240, 180), Material = Enum.Material.Neon, CanCollide = false })
		end
	end
	for _, off in ipairs({ { -60, 0 }, { 0, 60 } }) do
		for k = -2, 2 do
			part(m, { Name = "Hedge", Shape = Enum.PartType.Ball, Size = Vector3.new(9, 6, 9), Color = HEDGE,
				CFrame = localCF(A, sx + off[1] + (off[1] == 0 and k * 11 or 0), 2.5, sz + off[2] + (off[2] == 0 and k * 11 or 0)) })
		end
	end
	for k = 1, 4 do
		local bx, bz = sx + rng:NextNumber(-10, 10), sz + rng:NextNumber(-10, 10)
		cyl(m, A, "LightBeam", bx, 55, bz, 3, 110, C(255, 230, 150), { Material = Enum.Material.Neon, Transparency = 0.82, CanCollide = false, CanQuery = false, CastShadow = false })
	end
	local title = box(m, A, "RebirthTitle", sx, 66, sz, 90, 18, 0.4, C(255, 255, 255), { Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false })
	title.CFrame = CFrame.lookAt(title.Position, localCF(A, 0, 66, 0).Position)
	local tsg = WB.TextSurface(title, Enum.NormalId.Front, { { Text = "REBIRTH", Size = UDim2.fromScale(0.96, 0.9), Pos = UDim2.fromScale(0.02, 0.05), Color = GOLD, StrokeColor = C(120, 70, 0) } })
	tsg.PixelsPerStud = 4 -- el texto escalado tiene un tope de tamaño: menos píxeles por stud = letras más grandes en el mundo
	-- piso de honor: anillo dorado y círculo claro bajo las columnas
	cyl(m, A, "HonorRing", sx, 0.35, sz, 100, 0.2, GOLD, DECO)
	cyl(m, A, "HonorFloor", sx, 0.4, sz, 94, 0.2, C(238, 226, 196), DECO)
	-- macetas con flores alrededor del anillo
	for k = 0, 7 do
		local ang = math.rad(10 + k * 30)
		local fx, fz = sx + math.cos(ang) * 58, sz - math.sin(ang) * 58
		if not (fx > sx + 20 and fz < sz - 20) then
			box(m, A, "Planter", fx, 1.2, fz, 8, 2.4, 8, C(170, 120, 80))
			scatter(m, A, "Bush", fx, fz, 0.9, rng)
		end
	end
	-- obeliscos dorados a los lados de la entrada de la alfombra
	for _, o in ipairs({ { -76, 50 }, { -50, 76 } }) do
		box(m, A, "ObeliskBase", o[1], 1.5, o[2], 7, 3, 7, STONE)
		box(m, A, "Obelisk", o[1], 13, o[2], 4, 20, 4, GOLD, { Material = Enum.Material.Metal, Reflectance = 0.1 })
		part(m, { Name = "ObeliskOrb", Shape = Enum.PartType.Ball, Size = Vector3.new(4, 4, 4), CFrame = localCF(A, o[1], 25, o[2]), Color = C(255, 240, 180), Material = Enum.Material.Neon, CanCollide = false })
	end
	-- bancos y faroles en la plaza
	for _, spot in ipairs({ { -80, 150 }, { -150, 60 }, { 40, 150 }, { -150, -20 } }) do place(m, A, "Bench", spot[1], spot[2], 1, sx, sz, true) end
	for _, spot in ipairs({ { -64, 72 }, { 80, 76 }, { -70, -60 } }) do place(m, A, "StreetLamp", spot[1], spot[2], 1.1, 0, 0, true) end
	-- barreras (izquierda, adelante y el tramo derecho de adelante que no pertenece al área 11)
	barrier(m, localCF(A, -left - 2, 80, (front - L / 2) / 2), Vector3.new(4, 160, front + L / 2))
	barrier(m, localCF(A, (130 - left) / 2, 80, front + 2), Vector3.new(130 + left, 160, 4))
	barrier(m, localCF(A, 132, 80, (128 + front) / 2), Vector3.new(4, 160, front - 128))
	-- bosque exterior
	forestLine(m, A, -left - 10, -L / 2 + 10, -left - 10, front, rng, Vector2.new(-1, 0))
	forestLine(m, A, -left, front + 10, 140, front + 10, rng, Vector2.new(0, 1))
end

function GB.BuildArea(i)
	local d = Config.Dimensions[DIM]
	local a = d.Areas[i]
	local root = workspace:WaitForChild("World")
	local wf = root:FindFirstChild(DIM) or Instance.new("Folder"); wf.Name = DIM; wf.Parent = root
	local af = wf:FindFirstChild("Areas") or Instance.new("Folder"); af.Name = "Areas"; af.Parent = wf
	local old = af:FindFirstChild("Area_" .. i)
	if old then old:Destroy() end
	local m = Instance.new("Model"); m.Name = "Area_" .. i; m.Parent = af
	m:SetAttribute("AreaName", a.Name)
	local rng = Random.new(i * 4231 + 17)
	local A = Config.AreaCFrame(DIM, i)
	if i == Config.Layout.TurnArea then cornerArea(m, A, d, i, a, rng) else straightArea(m, A, d, i, a, rng) end
	if i > 1 then gate(m, i) end
	return m
end

---------------------------------------------------------------- lobby Maple Square (+ zona VIP a la izquierda)
function GB.BuildLobby()
	local d = Config.Dimensions[DIM]
	local root = workspace:WaitForChild("World")
	local wf = root:FindFirstChild(DIM) or Instance.new("Folder"); wf.Name = DIM; wf.Parent = root
	local old = wf:FindFirstChild("Lobby"); if old then old:Destroy() end
	local m = Instance.new("Model"); m.Name = "Lobby"; m.Parent = wf
	local rng = Random.new(77)
	local f = d.Forward or Vector3.new(0, 0, 1)
	local A = CFrame.lookAt(d.LobbyCenter, d.LobbyCenter + f) -- mismo marco que las áreas: x derecha, z adelante
	local frontZ = (Config.ZoneCenter(DIM, 1) - d.LobbyCenter):Dot(f) - d.ZoneLength / 2 -- borde del área 1
	local backZ = -110
	-- piso: vereda amplia + plaza circular de piedra
	box(m, A, "LobbyFloor", 0, -0.5, (frontZ + backZ) / 2, 2 * HW, 1.2, frontZ - backZ, GRASS_SIDE)
	cyl(m, A, "Plaza", 0, -0.1, 0, 132, 1.2, PLAZA)
	cyl(m, A, "PlazaRing", 0, 0.05, 0, 136, 0.6, CURB)
	cyl(m, A, "PlazaInner", 0, 0.12, 0, 60, 1, STONE)
	box(m, A, "ToArea1", 0, -0.1, (66 + frontZ) / 2 + 2, 44, 1.2, frontZ - 66 + 4, SIDEWALK)
	-- centro: torre del reloj
	place(m, A, "ClockTower", 0, 0, 1.2, 0, 60, true, 0.6)
	-- árboles de maple (otoño suave) y faroles alrededor
	for k = 0, 7 do
		local ang = math.rad(22.5 + k * 45)
		local x, z = math.cos(ang) * 76, math.sin(ang) * 76
		if not (z < -40 and math.abs(x) < 70) and not (z > 40 and math.abs(x) < 30) and not (x > 50 and z > 0 and z < 60) then -- libre: máquina de mejoras
			scatter(m, A, "AutumnTree", x, z, rng:NextNumber(0.85, 1.0), rng, true)
		end
		local lx, lz = math.cos(ang + math.rad(22.5)) * 62, math.sin(ang + math.rad(22.5)) * 62
		place(m, A, "StreetLamp", lx, lz, 1, 0, 0, true)
	end
	for _, spot in ipairs({ { -40, 20 }, { 40, 20 }, { -40, -20 }, { 40, -20 } }) do place(m, A, "Bench", spot[1], spot[2], 1, 0, 0, true) end
	-- tiendas: Shop y PREMIUM SHOP atrás a los costados, mirando al centro
	local shopFolder = Instance.new("Model"); shopFolder.Name = "Shops"; shopFolder.Parent = m
	WB.BuildShop(shopFolder, "Shop", localCF(A, 50, 0, -50).Position, d.LobbyCenter)
	WB.BuildShop(shopFolder, "Premium", localCF(A, -50, 0, -50).Position, d.LobbyCenter)
	-- MÁQUINA DE MEJORAS (pestañas Mejoras / Rango) a la derecha de la plaza, mirando al centro
	local ux, uz = 100, 16
	cyl(m, A, "UpgradePad", ux, 0.15, uz, 36, 1, STONE)
	cyl(m, A, "UpgradePadTrim", ux, 0.4, uz, 37, 0.4, C(120, 215, 140), { Material = Enum.Material.SmoothPlastic })
	place(m, A, "UpgradeMachine", ux, uz, 1.3, 0, uz, true, 0.6)
	local um = box(m, A, "UpgradeMachine", ux - 14, 3, uz, 8, 6, 8, C(255, 255, 255), { Transparency = 1, CanCollide = false, CanQuery = false })
	um:SetAttribute("Dimension", DIM)
	CollectionService:AddTag(um, "UpgradeMachine")
	local upp = Instance.new("ProximityPrompt"); upp.Style = Enum.ProximityPromptStyle.Custom; upp.ActionText = "Abrir"; upp.ObjectText = "Mejoras y Rango"
	upp.MaxActivationDistance = 16; upp.RequiresLineOfSight = false; upp.Parent = um
	local usign = box(m, A, "UpgradeSign", ux, 31, uz, 26, 5, 0.4, C(255, 255, 255), { Transparency = 1, CanCollide = false, CanQuery = false })
	usign.CFrame = CFrame.lookAt(usign.Position, localCF(A, 0, 31, uz).Position)
	local usg = WB.TextSurface(usign, Enum.NormalId.Front, { { Text = "MEJORAS", Size = UDim2.fromScale(0.96, 0.8), Pos = UDim2.fromScale(0.02, 0.1), Color = C(170, 255, 170) } })
	usg.PixelsPerStud = 8
	-- ZONA VIP (espacio 4 = a la izquierda): cerco dorado, barrera VIP en la entrada y región VipZone
	local vx0, vx1, vz0, vz1 = -HW + 2, -78, -14, 86 -- izquierda = x negativo en el marco local
	local vcx, vcz = (vx0 + vx1) / 2, (vz0 + vz1) / 2
	box(m, A, "VipFloor", vcx, -0.05, vcz, vx1 - vx0, 1.2, vz1 - vz0, C(60, 40, 70))
	box(m, A, "VipCarpet", vcx, 0.6, vcz, 12, 0.2, vz1 - vz0 - 10, C(200, 50, 60), DECO)
	place(m, A, "VipLounge", vcx - 6, vcz, 1, 0, vcz, true)
	local entZ0, entZ1 = vcz - 12, vcz + 12
	for z = vz0, vz1, 10 do
		if z < entZ0 or z > entZ1 then
			cyl(m, A, "VipPost", vx1, 3, z, 1.6, 6, GOLD)
			part(m, { Name = "VipPostTop", Shape = Enum.PartType.Ball, Size = Vector3.new(2.2, 2.2, 2.2), CFrame = localCF(A, vx1, 6.4, z), Color = GOLD })
		end
	end
	box(m, A, "VipRope", vx1, 4.6, (vz0 + entZ0) / 2, 0.5, 0.5, entZ0 - vz0, C(170, 30, 40), DECO)
	box(m, A, "VipRope", vx1, 4.6, (entZ1 + vz1) / 2, 0.5, 0.5, vz1 - entZ1, C(170, 30, 40), DECO)
	for _, zz in ipairs({ vz0, vz1 }) do box(m, A, "VipFence", vcx, 3, zz, vx1 - vx0, 6, 1, GOLD, { Transparency = 0.2 }) end
	local vb = box(m, A, "VipBarrier", vx1, 7, vcz, 2, 14, entZ1 - entZ0, C(255, 215, 90), { Material = Enum.Material.ForceField, Transparency = 0.35 })
	CollectionService:AddTag(vb, "VipBarrier")
	local vz = box(m, A, "VipZone", vcx, 15, vcz, vx1 - vx0 - 2, 30, vz1 - vz0 - 2, C(255, 215, 90), { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
	vz:SetAttribute("Dimension", DIM)
	CollectionService:AddTag(vz, "VipZone")
	local vsign = box(m, A, "VipSign", vx1 + 1, 16, vcz, 0.4, 7, 24, C(255, 255, 255), { Transparency = 1, CanCollide = false, CanQuery = false })
	vsign.CFrame = CFrame.lookAt(vsign.Position, localCF(A, 0, 16, vcz).Position)
	WB.TextSurface(vsign, Enum.NormalId.Front, { { Text = "VIP", Size = UDim2.fromScale(0.9, 0.9), Pos = UDim2.fromScale(0.05, 0.05), Color = GOLD, StrokeColor = C(90, 50, 0) } })
	-- barreras del lobby y bosque alrededor
	barrier(m, localCF(A, -BARRIER, 80, (frontZ + backZ) / 2), Vector3.new(4, 160, frontZ - backZ))
	barrier(m, localCF(A, BARRIER, 80, (frontZ + backZ) / 2), Vector3.new(4, 160, frontZ - backZ))
	barrier(m, localCF(A, 0, 80, backZ - 2), Vector3.new(2 * BARRIER + 4, 160, 4))
	forestLine(m, A, -132, backZ, -132, frontZ, rng, Vector2.new(-1, 0))
	forestLine(m, A, 132, backZ, 132, frontZ, rng, Vector2.new(1, 0))
	forestLine(m, A, -132, backZ - 12, 132, backZ - 12, rng, Vector2.new(0, -1))
	return m
end

---------------------------------------------------------------- mundo completo
function GB.BuildWorld()
	local d = Config.Dimensions[DIM]
	local root = workspace:WaitForChild("World")
	local wf = root:FindFirstChild(DIM)
	if wf then wf:Destroy() end
	wf = Instance.new("Folder"); wf.Name = DIM; wf.Parent = root
	-- suelo de pasto continuo bajo todo el mundo (mundo en tierra, sin vacío)
	local lo, hi = Vector3.new(math.huge, 0, math.huge), Vector3.new(-math.huge, 0, -math.huge)
	local function grow(p) lo = Vector3.new(math.min(lo.X, p.X), 0, math.min(lo.Z, p.Z)); hi = Vector3.new(math.max(hi.X, p.X), 0, math.max(hi.Z, p.Z)) end
	grow(d.LobbyCenter + Vector3.new(-260, 0, -260)); grow(d.LobbyCenter + Vector3.new(260, 0, 260))
	for i = 1, d.ZoneCount do
		local c = Config.ZoneCenter(DIM, i)
		grow(c + Vector3.new(-320, 0, -320)); grow(c + Vector3.new(320, 0, 320))
	end
	-- en baldosas (una pieza no puede medir más de 2048 studs)
	local ground = Instance.new("Model"); ground.Name = "Ground"; ground.Parent = wf
	local TILE = 1000
	local x = lo.X
	while x < hi.X do
		local z = lo.Z
		local w = math.min(TILE, hi.X - x)
		while z < hi.Z do
			local l = math.min(TILE, hi.Z - z)
			part(ground, { Name = "GroundTile", Size = Vector3.new(w, 2, l), Position = Vector3.new(x + w / 2, -1.1, z + l / 2), Color = GRASS, CastShadow = false })
			z += TILE
		end
		x += TILE
	end
	GB.BuildLobby()
	for i = 1, d.AreasBuilt do GB.BuildArea(i) end
	-- huevos (PROVISIONALES): lobby a la derecha del camino y costado del área 2
	local eggs = Instance.new("Model"); eggs.Name = "Eggs"; eggs.Parent = wf
	local LA = CFrame.lookAt(d.LobbyCenter, d.LobbyCenter + (d.Forward or Vector3.new(0, 0, 1)))
	WB.BuildEgg(eggs, "MapleEgg", localCF(LA, 40, 0, 40).Position)
	WB.BuildEgg(eggs, "OakEgg", localCF(Config.AreaCFrame(DIM, 2), 56, 0, -55).Position)
	-- cierre al final del área 20
	if d.AreasBuilt >= d.ZoneCount then
		local A = Config.AreaCFrame(DIM, d.ZoneCount)
		local endM = Instance.new("Model"); endM.Name = "WorldEnd"; endM.Parent = wf
		barrier(endM, localCF(A, 0, 80, d.ZoneLength / 2 + 2), Vector3.new(2 * BARRIER + 4, 160, 4))
		forestLine(endM, A, -132, d.ZoneLength / 2 + 12, 132, d.ZoneLength / 2 + 12, Random.new(99), Vector2.new(0, 1))
	end
end

return GB
