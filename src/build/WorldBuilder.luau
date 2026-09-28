-- Pet Nexus: constructor de mundo (solo edición). Uso desde execute_luau (Edit):
--   local WB = require(game.ServerStorage.PetNexusBuild.WorldBuilder)
--   WB.BuildLobby("Nexus"); WB.BuildArea("Nexus", 1); WB.BuildEnvironment()
-- Reconstruir un área borra y rehace World.<Dim>.Area_<i>. Estilo: PS99 (pastel, pilares blancos escalonados con orbes,
-- parcelas con borde blanco discontinuo, islas flotantes). Temas por nombre de área en THEMES.
local CollectionService = game:GetService("CollectionService")
-- (en Edit, require() de Config puede devolver una versión cacheada: se usa un clon para leer siempre la actual)
local Config = require(game.ReplicatedStorage.PetNexus.Config:Clone())

local WB = {}

local WHITE = Color3.fromRGB(250, 250, 255)
local PATH = Color3.fromRGB(214, 210, 250)
local PATH_EDGE = Color3.fromRGB(170, 158, 240)
local UNDER1 = Color3.fromRGB(190, 176, 245)
local UNDER2 = Color3.fromRGB(160, 140, 230)
local TRUNK = Color3.fromRGB(176, 128, 118)

local function part(parent, props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.CastShadow = true
	for k, v in pairs(props) do p[k] = v end
	p.Parent = parent
	return p
end
WB.Part = part

local function shade(c, f) return Color3.new(math.clamp(c.R * f, 0, 1), math.clamp(c.G * f, 0, 1), math.clamp(c.B * f, 0, 1)) end
local function lighten(c, f) return c:Lerp(Color3.new(1, 1, 1), f) end

local function folder(parent, name)
	local f = parent:FindFirstChild(name)
	if not f then f = Instance.new("Model"); f.Name = name; f.Parent = parent end
	return f
end

local function disc(parent, center, diameter, thickness, color, props)
	local p = part(parent, {
		Shape = Enum.PartType.Cylinder, Size = Vector3.new(thickness, diameter, diameter),
		CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)), Color = color,
	})
	if props then for k, v in pairs(props) do p[k] = v end end
	return p
end

local function ball(parent, pos, size, color, props)
	local p = part(parent, { Shape = Enum.PartType.Ball, Size = Vector3.new(size, size, size), Position = pos, Color = color, CanCollide = false })
	if props then for k, v in pairs(props) do p[k] = v end end
	return p
end

local function textSurface(p, face, lines, bg)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 20
	sg.LightInfluence = 0
	sg.Parent = p
	if bg then
		local f = Instance.new("Frame"); f.Size = UDim2.fromScale(1, 1); f.BackgroundColor3 = bg; f.BorderSizePixel = 0; f.Parent = sg
	end
	for _, l in ipairs(lines) do
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Font = Enum.Font.FredokaOne
		t.TextScaled = true
		t.Text = l.Text
		t.TextColor3 = l.Color or Color3.new(1, 1, 1)
		t.Size = l.Size
		t.Position = l.Pos
		t.Name = l.Name or "Label"
		local s = Instance.new("UIStroke"); s.Thickness = l.Stroke or 6; s.Color = l.StrokeColor or Color3.new(0, 0, 0); s.Parent = t
		t.Parent = sg
	end
	return sg
end
WB.TextSurface = textSurface
WB.TextSurface = textSurface

---------------------------------------------------------------- props
-- Biblioteca de modelos generados (ServerStorage.PetNexusBuild.Props y ReplicatedStorage.PetNexusAssets)
local Props = game.ServerStorage.PetNexusBuild.Props
local Assets = game.ReplicatedStorage.PetNexusAssets
local Icons = require(game.ReplicatedStorage.PetNexus.Icons:Clone())

-- Clona un modelo de la biblioteca, lo escala y lo apoya en 'pos' (pivote = centro de la base)
function WB.Prop(parent, name, pos, scale, yawDeg, collide)
	local src = Props:FindFirstChild(name)
	if not src then return nil end
	local m = src:Clone()
	if scale and scale ~= 1 then m:ScaleTo(scale) end
	m:PivotTo(CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg or 0), 0))
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true; d.CanCollide = collide or false; d.CanQuery = collide or false; d.CanTouch = false end
	end
	m.Parent = parent
	return m
end

-- Pilar futurista con orbe (modelo generado). 'height' en studs.
function WB.Pillar(parent, base, height, orbColor, scale)
	local m = WB.Prop(parent, "Pillar", base, (height or 18.7) / 18.7, 180, true)
	if m and orbColor then
		local l = Instance.new("PointLight"); l.Color = orbColor; l.Range = 16; l.Brightness = 1.1
		l.Parent = m.PrimaryPart
	end
	return m
end

function WB.Tree(parent, pos, color, scale, rng)
	return WB.Prop(parent, "PinkTree", pos, (scale or 1) * 0.95, rng:NextNumber(0, 360), true)
end
function WB.Cloud(parent, pos, scale, color, rng)
	color = color or WHITE
	local m = Instance.new("Model"); m.Name = "Cloud"; m.Parent = parent
	local deco = { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false } -- decoración pura: barata
	ball(m, pos, 8 * scale, color, deco)
	for k = 1, 4 do
		local a = k / 4 * math.pi * 2 + rng:NextNumber(0, 0.5)
		ball(m, pos + Vector3.new(math.cos(a) * 4.2, rng:NextNumber(-1.5, 0.5), math.sin(a) * 3) * scale, rng:NextNumber(5, 7) * scale, lighten(color, 0.05), deco)
	end
	return m
end

function WB.Crystal(parent, pos, color, height, rng)
	return WB.Prop(parent, "Crystals", pos, (height or 8) / 8.6, rng:NextNumber(0, 360), false)
end

function WB.Lamp(parent, pos, color)
	return WB.Pillar(parent, pos, 8.5, color)
end

function WB.CottonBush(parent, pos, color, scale, rng)
	return WB.Prop(parent, "PinkTree", pos, 0.45 * (scale or 1), rng:NextNumber(0, 360), false)
end

-- Cordillera-pared: dos filas escalonadas de piezas grandes y solapadas (sin huecos al vacío).
-- pieces = { {Name, MinScale, MaxScale, Sink}, ... } ; outward = dirección hacia afuera del mapa
WB.WallSets = {
	Lobby = { { "CliffBlock", 4.6, 5.6, -20 }, { "MountainPeak", 3.6, 4.4, -16 }, { "CliffBlock", 4.8, 5.8, -20 } },
	["Sky Spawn"] = { { "CrystalCliff", 3.1, 3.7, -18 }, { "MountainPeak", 3.6, 4.4, -16 }, { "CrystalCliff", 3.3, 3.9, -18 } },
	["Cotton Fields"] = { { "CottonHill", 3.4, 4.0, -16 }, { "CottonHill", 3.8, 4.4, -16 }, { "CrystalCliff", 3.0, 3.4, -18 } },
}
function WB.MountainWall(parent, from, to, rng, pieces, outward)
	local m = Instance.new("Model"); m.Name = "MountainWall"; m.Parent = parent
	pieces = pieces or WB.WallSets.Lobby
	local dir = (to - from)
	local len = dir.Magnitude
	dir = dir.Unit
	outward = outward or Vector3.zero
	for row = 0, 1 do
		local d = row == 0 and 0 or 22
		local k = row
		while d <= len + 10 do
			local p = from + dir * d + outward * (row * 34)
			k += 1
			local pc = pieces[(k % #pieces) + 1]
			WB.Prop(m, pc[1], p + Vector3.new(rng:NextNumber(-4, 4), pc[4] + (row == 1 and 10 or 0), rng:NextNumber(-4, 4)), rng:NextNumber(pc[2], pc[3]) * (row == 1 and 1.15 or 1), rng:NextNumber(0, 360), false)
			d += row == 0 and rng:NextNumber(38, 48) or rng:NextNumber(54, 64) -- la fila de atrás más espaciada: menos piezas, mismo relleno
		end
	end
	return m
end

local function barrier(parent, center, size)
	local w = Instance.new("Part")
	w.Name = "Barrier"; w.Anchored = true; w.Transparency = 1; w.CanQuery = false
	w.Size = size; w.Position = center; w.Parent = parent
end

-- Arcoíris de bandas (plano XY rotado por yaw)
function WB.Rainbow(parent, center, radius, yaw)
	local m = Instance.new("Model"); m.Name = "Rainbow"; m.Parent = parent
	local cols = { Color3.fromRGB(255, 120, 150), Color3.fromRGB(255, 180, 110), Color3.fromRGB(255, 235, 120), Color3.fromRGB(140, 235, 150), Color3.fromRGB(120, 200, 255), Color3.fromRGB(190, 150, 255) }
	local base = CFrame.new(center) * CFrame.Angles(0, yaw or 0, 0)
	for b, col in ipairs(cols) do
		local r = radius - (b - 1) * 2.2
		local n = 28
		for k = 0, n - 1 do
			local a0 = k / n * math.pi
			local a1 = (k + 1) / n * math.pi
			local p0 = Vector3.new(math.cos(a0) * r, math.sin(a0) * r, 0)
			local p1 = Vector3.new(math.cos(a1) * r, math.sin(a1) * r, 0)
			local mid = (p0 + p1) / 2
			part(m, { Size = Vector3.new((p1 - p0).Magnitude + 0.3, 2.2, 2.2), CFrame = base * CFrame.lookAt(mid, mid + (p1 - p0)) * CFrame.Angles(0, math.rad(90), 0),
				Color = col, Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false })
		end
	end
	return m
end

---------------------------------------------------------------- piezas de mapa
local function islandUnderside(parent, center, sx, sz, rng)
	part(parent, { Name = "Under1", Size = Vector3.new(sx - 8, 8, sz - 8), Position = center + Vector3.new(0, -8, 0), Color = UNDER1, CastShadow = false, CanCollide = false, CanQuery = false })
	part(parent, { Name = "Under2", Size = Vector3.new(sx - 26, 10, sz - 24), Position = center + Vector3.new(0, -16, 0), Color = UNDER2, CastShadow = false, CanCollide = false, CanQuery = false })
	for _ = 1, 4 do
		local p = center + Vector3.new(rng:NextNumber(-sx / 2, sx / 2), rng:NextNumber(-22, -12), rng:NextNumber(-sz / 2, sz / 2))
		WB.Cloud(parent, p, rng:NextNumber(1.2, 2), nil, rng)
	end
end

local function dashedBorder(parent, center, w, l, inset, y)
	local dash, gap = 3.2, 2.6
	local function run(from, to, alongX)
		local len = (to - from).Magnitude
		local dir = (to - from).Unit
		local d = 0
		while d + dash <= len do
			local mid = from + dir * (d + dash / 2)
			part(parent, { Name = "Dash", Size = alongX and Vector3.new(dash, 0.12, 0.7) or Vector3.new(0.7, 0.12, dash), Position = mid,
				Color = Color3.new(1, 1, 1), CanCollide = false, CastShadow = false })
			d += dash + gap
		end
	end
	local hx, hz = w / 2 - inset, l / 2 - inset
	local c = center + Vector3.new(0, y, 0)
	run(c + Vector3.new(-hx, 0, -hz), c + Vector3.new(hx, 0, -hz), true)
	run(c + Vector3.new(-hx, 0, hz), c + Vector3.new(hx, 0, hz), true)
	run(c + Vector3.new(-hx, 0, -hz), c + Vector3.new(-hx, 0, hz), false)
	run(c + Vector3.new(hx, 0, -hz), c + Vector3.new(hx, 0, hz), false)
end
WB.DashedBorder = dashedBorder

local function sideIsland(parent, center, sx, sz, grass, rng)
	part(parent, { Name = "SideTop", Size = Vector3.new(sx, 3, sz), Position = center + Vector3.new(0, -1.5, 0), Color = grass })
	part(parent, { Name = "SideRim", Size = Vector3.new(sx + 1.5, 2.2, sz + 1.5), Position = center + Vector3.new(0, -3.4, 0), Color = PATH })
	part(parent, { Name = "SideUnder", Size = Vector3.new(sx - 6, 7, sz - 6), Position = center + Vector3.new(0, -8, 0), Color = UNDER1, CastShadow = false, CanCollide = false, CanQuery = false })
	part(parent, { Name = "SideUnder2", Size = Vector3.new(sx - 16, 8, sz - 16), Position = center + Vector3.new(0, -14, 0), Color = UNDER2, CastShadow = false, CanCollide = false, CanQuery = false })
	for _ = 1, 2 do
		WB.Cloud(parent, center + Vector3.new(rng:NextNumber(-sx / 2, sx / 2), rng:NextNumber(-18, -10), rng:NextNumber(-sz / 2, sz / 2)), rng:NextNumber(1, 1.6), nil, rng)
	end
end

local function areaGate(parent, dim, i, center)
	local g = Instance.new("Model"); g.Name = "Gate"; g.Parent = parent
	local half = 24
	WB.Pillar(g, center + Vector3.new(-half - 3, 0, 0), 24, Color3.fromRGB(215, 240, 255), 1.1)
	WB.Pillar(g, center + Vector3.new(half + 3, 0, 0), 24, Color3.fromRGB(215, 240, 255), 1.1)
	local wall = part(g, { Name = "AreaGate", Size = Vector3.new(half * 2 + 1, 26, 1), Position = center + Vector3.new(0, 13, 0),
		Color = Color3.fromRGB(150, 235, 255), Material = Enum.Material.Neon, Transparency = 0.35, CastShadow = false })
	wall:SetAttribute("Dimension", dim)
	wall:SetAttribute("Zone", i)
	CollectionService:AddTag(wall, "AreaGate")
	-- sello invisible de todo el ancho del mundo (camino + islas laterales) y bien alto: no se puede rodear ni saltar la puerta.
	-- El cliente le quita la colisión cuando el área ya está pagada (igual que al muro).
	local seal = part(g, { Name = "GateSeal", Size = Vector3.new(252, 160, 2), Position = center + Vector3.new(0, 70, 0), Transparency = 1, CanQuery = false, CanTouch = false, CastShadow = false })
	seal:SetAttribute("Dimension", dim)
	seal:SetAttribute("Zone", i)
	CollectionService:AddTag(seal, "AreaGateSeal")
	local pp = Instance.new("ProximityPrompt")
	pp.Style = Enum.ProximityPromptStyle.Custom
	pp.ActionText = "Comprar"
	pp.ObjectText = "Area " .. i .. " · " .. Config.AreaName(dim, i)
	pp.MaxActivationDistance = 16
	pp.RequiresLineOfSight = false
	pp.Parent = wall
	local price = Config.ZonePrice(dim, i)
	textSurface(wall, Enum.NormalId.Front, {
		{ Name = "AreaNum", Text = "Area " .. i, Size = UDim2.fromScale(0.8, 0.16), Pos = UDim2.fromScale(0.1, 0.06) },
		{ Name = "AreaName", Text = Config.AreaName(dim, i), Size = UDim2.fromScale(0.94, 0.22), Pos = UDim2.fromScale(0.03, 0.22), Color = Color3.fromRGB(255, 240, 160) },
		{ Name = "Price", Text = Config.FormatNumber(price), Size = UDim2.fromScale(0.5, 0.17), Pos = UDim2.fromScale(0.4, 0.46) },
	})
	local sg = wall:FindFirstChildOfClass("SurfaceGui")
	sg.Price.TextXAlignment = Enum.TextXAlignment.Left
	sg.Price.TextColor3 = Config.CurrencyOf(dim).Color
	return wall
end

---------------------------------------------------------------- temas por área
local function skyCloud(m, c, rng, color)
	local sx = rng:NextNumber() < 0.5 and -1 or 1
	WB.Cloud(m, c + Vector3.new(sx * rng:NextNumber(80, 160), rng:NextNumber(62, 100), rng:NextNumber(-60, 60)), rng:NextNumber(1.5, 2.6), color, rng)
end

local THEMES = {}

THEMES["Sky Spawn"] = function(m, c, a, rng)
	local grass = Color3.fromRGB(165, 240, 175)
	for _, sx in ipairs({ -1, 1 }) do
		local ic = c + Vector3.new(sx * 90, -1, 0)
		sideIsland(m, ic, 52, 140, grass, rng) -- largo completo del área: sin hueco al vacío entre áreas
		local face = sx < 0 and 90 or -90 -- mirando al camino
		-- guardianes: estatuas de ángel custodiando el área
		WB.Prop(m, "AngelStatue", ic + Vector3.new(-sx * 14, 0, -35), 2.7, face, true)
		WB.Prop(m, "AngelStatue", ic + Vector3.new(-sx * 14, 0, 35), 2.7, face, true)
		for k = 1, 3 do
			WB.Tree(m, ic + Vector3.new(sx * rng:NextNumber(4, 16), 0, -50 + k * 25 + rng:NextNumber(-5, 5)), nil, rng:NextNumber(1.1, 1.5), rng)
		end
		for k = 1, 4 do
			WB.Crystal(m, ic + Vector3.new(rng:NextNumber(-18, 18), 0, rng:NextNumber(-58, 58)), nil, rng:NextNumber(7, 12), rng)
		end
		-- mini islas con cascada flotando sobre el borde
		WB.Prop(m, "MiniIsland", ic + Vector3.new(sx * 10, rng:NextNumber(58, 72), rng:NextNumber(-40, -10)), rng:NextNumber(1.3, 1.7), rng:NextNumber(0, 360), false)
		WB.Prop(m, "MiniIsland", ic + Vector3.new(sx * 14, rng:NextNumber(70, 88), rng:NextNumber(15, 45)), rng:NextNumber(1.1, 1.5), rng:NextNumber(0, 360), false)
	end
	for k = 1, 4 do skyCloud(m, c, rng) end
end

THEMES["Cotton Fields"] = function(m, c, a, rng)
	local grass = Color3.fromRGB(255, 205, 228)
	for _, sx in ipairs({ -1, 1 }) do
		local ic = c + Vector3.new(sx * 90, -1, 0)
		sideIsland(m, ic, 52, 140, grass, rng) -- largo completo del área: sin hueco al vacío entre áreas
		local face = sx < 0 and 90 or -90
		for _ = 1, 7 do
			WB.Prop(m, "CottonCandyTree", ic + Vector3.new(rng:NextNumber(-18, 18), 0, rng:NextNumber(-58, 58)), rng:NextNumber(0.9, 1.5), rng:NextNumber(0, 360), true)
		end
		WB.Prop(m, "CandyCart", ic + Vector3.new(-sx * 14, 0, rng:NextNumber(-20, 20)), 1.5, face, true)
		WB.Prop(m, "CottonHill", ic + Vector3.new(sx * 8, -2, -45), 0.55, rng:NextNumber(0, 360), false)
		WB.Prop(m, "CottonHill", ic + Vector3.new(sx * 10, -2, 48), 0.5, rng:NextNumber(0, 360), false)
	end
	WB.Rainbow(m, c + Vector3.new(118, -4, 10), 46, math.rad(90))
	for _ = 1, 5 do skyCloud(m, c, rng, Color3.fromRGB(255, 235, 248)) end
end

local function defaultTheme(m, c, a, rng)
	for _, sx in ipairs({ -1, 1 }) do
		local ic = c + Vector3.new(sx * 90, -1, 0)
		sideIsland(m, ic, 52, 140, lighten(a.Plot, 0.2), rng)
		for k = 1, 5 do WB.Tree(m, ic + Vector3.new(rng:NextNumber(-18, 18), 0, -60 + k * 20), a.Plot, rng:NextNumber(1, 1.4), rng) end
	end
end

---------------------------------------------------------------- API
function WB.BuildArea(dim, i)
	local d = Config.Dimensions[dim]
	local a = d.Areas[i]
	local worldFolder = folder(folder(workspace:WaitForChild("World"), dim), "Areas")
	local old = worldFolder:FindFirstChild("Area_" .. i)
	if old then old:Destroy() end
	local m = Instance.new("Model"); m.Name = "Area_" .. i; m.Parent = worldFolder
	m:SetAttribute("AreaName", a.Name)
	local rng = Random.new(i * 7919 + (d.SeedOrder or d.Order) * 31)
	local c = Config.ZoneCenter(dim, i)

	-- isla principal (camino) y parcela
	part(m, { Name = "Path", Size = Vector3.new(d.ZoneWidth, 4, d.ZoneLength), Position = c + Vector3.new(0, -2, 0), Color = PATH })
	for _, sx in ipairs({ -1, 1 }) do
		part(m, { Name = "Curb", Size = Vector3.new(2.4, 1.2, d.ZoneLength), Position = c + Vector3.new(sx * (d.ZoneWidth / 2 - 1.2), 0.6, 0), Color = PATH_EDGE })
	end
	islandUnderside(m, c, d.ZoneWidth, d.ZoneLength, rng)
	part(m, { Name = "PlotRim", Size = Vector3.new(d.PlotWidth + 5, 0.7, d.PlotLength + 5), Position = c + Vector3.new(0, 0.35, 0), Color = shade(a.Plot, 0.82) })
	part(m, { Name = "Plot", Size = Vector3.new(d.PlotWidth, 0.9, d.PlotLength), Position = c + Vector3.new(0, 0.45, 0), Color = a.Plot })
	dashedBorder(m, c, d.PlotWidth, d.PlotLength, 3, 0.95)

	-- faroles a los lados del camino (cada zona tiene los suyos)
	for _, sx in ipairs({ -1, 1 }) do
		for _, z in ipairs({ -30, 0, 30 }) do
			local lampName = a.Name == "Sky Spawn" and "CloudLamp" or nil
			if lampName then
				WB.Prop(m, lampName, c + Vector3.new(sx * 57, 0, z), 1.25, sx > 0 and -90 or 90, true)
			elseif z ~= 0 then
				WB.Lamp(m, c + Vector3.new(sx * 56, 0, z), lighten(a.Plot, 0.35))
			end
		end
	end

	-- puerta de entrada (el área 1 es libre)
	if i > 1 then
		areaGate(m, dim, i, c - Vector3.new(0, 0, d.ZoneLength / 2))
	end

	local theme = THEMES[a.Name] or defaultTheme
	theme(m, c, a, rng)
	return m
end

-- Tiendas del lobby. kind = "Shop" (normal, Angel Coins) o "Premium" (Robux: gamepasses, mascotas limitadas...).
-- Se colocan en 'pos' mirando al centro del lobby. El mostrador lleva el ProximityPrompt (tag ShopCounter + atributo ShopKind).
local SHOPS = {
	Shop = { Model = "ShopBuilding", Scale = 1.3, Title = "SHOP", Icon = "Shop", SignY = 38, Prompt = "Tienda" },
	Premium = { Model = "PremiumShop", Scale = 1.2, YawOffset = 180, Title = "PREMIUM SHOP", Icon = "Premium", SignY = 41, Prompt = "Premium Shop",
		Glow = Color3.fromRGB(255, 120, 230), Glow2 = Color3.fromRGB(120, 220, 255) },
}
function WB.BuildShop(parent, kind, pos, lookAt)
	local def = SHOPS[kind]
	local v = (lookAt - pos) * Vector3.new(1, 0, 1)
	v = v.Unit
	local yaw = math.deg(math.atan2(-v.X, -v.Z)) -- los modelos de tienda miran a -Z con yaw 0
	local base = Vector3.new(pos.X, 0.4, pos.Z)
	local shop = WB.Prop(parent, def.Model, base, def.Scale, yaw + (def.YawOffset or 0), true) -- YawOffset: modelos cuyo frente mira a +Z
	if shop then shop.Name = kind == "Premium" and "PremiumShop" or "Shop" end
	local face = CFrame.lookAt(base, base + v)
	local counter = part(parent, { Name = kind .. "Counter", Size = Vector3.new(16, 6, 2), CFrame = face * CFrame.new(0, 3, -15), Transparency = 1, CanCollide = false })
	local spp = Instance.new("ProximityPrompt"); spp.Style = Enum.ProximityPromptStyle.Custom; spp.ActionText = def.Prompt; spp.ObjectText = def.Title
	spp.MaxActivationDistance = 14; spp.RequiresLineOfSight = false; spp.Parent = counter
	counter:SetAttribute("ShopKind", kind)
	CollectionService:AddTag(counter, "ShopCounter")
	-- letrero holográfico flotante (texto al frente, mirando al lobby; el cliente dibuja el ícono 3D)
	local sign = part(parent, { Name = kind .. "Sign", Size = Vector3.new(kind == "Premium" and 34 or 24, 6, 0.6), CFrame = face * CFrame.new(0, def.SignY, -4), Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false })
	textSurface(sign, Enum.NormalId.Front, { { Text = def.Title, Size = UDim2.fromScale(kind == "Premium" and 0.7 or 0.6, 0.8), Pos = UDim2.fromScale(kind == "Premium" and 0.27 or 0.36, 0.1) } })
	sign:SetAttribute("IconName", def.Icon)
	sign:SetAttribute("IconFace", "Front")
	if kind == "Premium" then
		local sg = sign:FindFirstChildOfClass("SurfaceGui")
		local lbl = sg and sg:FindFirstChildWhichIsA("TextLabel")
		if lbl then
			local g = Instance.new("UIGradient"); g.Color = ColorSequence.new(Color3.fromRGB(255, 240, 150), Color3.fromRGB(255, 150, 230)); g.Rotation = 90; g.Parent = lbl
		end
		-- brillo místico: luces de gema y destellos
		local core = part(parent, { Name = "PremiumGlow", Size = Vector3.new(1, 1, 1), CFrame = face * CFrame.new(0, 14, 2), Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false })
		local l1 = Instance.new("PointLight"); l1.Color = def.Glow; l1.Range = 22; l1.Brightness = 0.8; l1.Parent = core
		local sp = Instance.new("ParticleEmitter"); sp.Rate = 10; sp.Lifetime = NumberRange.new(1.4, 2.4); sp.Speed = NumberRange.new(1, 2.5)
		sp.SpreadAngle = Vector2.new(180, 180); sp.LightEmission = 1; sp.Size = NumberSequence.new(0.9, 0)
		sp.Color = ColorSequence.new(def.Glow, def.Glow2); sp.Parent = core
		local l2 = Instance.new("PointLight"); l2.Color = def.Glow2; l2.Range = 14; l2.Brightness = 0.6; l2.Parent = counter
	end
	return shop
end

function WB.BuildLobby(dim)
	local d = Config.Dimensions[dim]
	local info = Config.WorldInfo(dim)
	local worldFolder = folder(workspace:WaitForChild("World"), dim)
	local old = worldFolder:FindFirstChild("Lobby")
	if old then old:Destroy() end
	local m = Instance.new("Model"); m.Name = "Lobby"; m.Parent = worldFolder
	local rng = Random.new((d.SeedOrder or d.Order) * 101)
	local c = d.LobbyCenter
	local cyan = Color3.fromRGB(120, 225, 255)

	-- plaza circular flotante
	disc(m, c + Vector3.new(0, -3, 0), 160, 6, Color3.fromRGB(196, 200, 255))
	disc(m, c + Vector3.new(0, 0.05, 0), 128, 0.3, cyan, { Material = Enum.Material.Neon, CanCollide = false, CastShadow = false })
	disc(m, c + Vector3.new(0, 0.15, 0), 122, 0.4, Color3.fromRGB(220, 215, 255))
	disc(m, c + Vector3.new(0, 0.25, 0), 64, 0.4, Color3.fromRGB(255, 212, 240))
	disc(m, c + Vector3.new(0, 0.3, 0), 66, 0.3, Color3.fromRGB(255, 150, 215), { Material = Enum.Material.Neon, CanCollide = false, CastShadow = false })
	disc(m, c + Vector3.new(0, 0.35, 0), 62, 0.4, Color3.fromRGB(255, 220, 244))
	disc(m, c + Vector3.new(0, -10, 0), 148, 10, UNDER1)
	disc(m, c + Vector3.new(0, -19, 0), 116, 10, UNDER2)
	disc(m, c + Vector3.new(0, -27, 0), 70, 8, Color3.fromRGB(170, 158, 228))
	for _ = 1, 10 do
		local a = rng:NextNumber(0, math.pi * 2)
		WB.Cloud(m, c + Vector3.new(math.cos(a) * rng:NextNumber(50, 85), rng:NextNumber(-26, -12), math.sin(a) * rng:NextNumber(50, 85)), rng:NextNumber(1.5, 2.4), nil, rng)
	end
	-- baldosas hexagonales decorativas en el anillo
	for k = 0, 23 do
		local a = k / 24 * math.pi * 2
		local p = c + Vector3.new(math.cos(a) * 48, 0.4, math.sin(a) * 48)
		part(m, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 5, 5), CFrame = CFrame.new(p) * CFrame.Angles(0, 0, math.rad(90)),
			Color = k % 2 == 0 and Color3.fromRGB(160, 185, 255) or Color3.fromRGB(200, 170, 255), CanCollide = false, CastShadow = false })
	end

	-- puente hacia el área 1
	local bridgeZ = c.Z + 80
	part(m, { Name = "Bridge", Size = Vector3.new(44, 4, 22), Position = Vector3.new(c.X, -2, bridgeZ + 2), Color = PATH })
	part(m, { Size = Vector3.new(40, 6, 18), Position = Vector3.new(c.X, -7, bridgeZ + 2), Color = UNDER1 })

	-- fuente central con cristal flotante
	disc(m, c + Vector3.new(0, 1, 0), 30, 2, WHITE)
	disc(m, c + Vector3.new(0, 2.2, 0), 26, 0.6, Color3.fromRGB(90, 210, 255), { Material = Enum.Material.Neon, Transparency = 0.25 })
	disc(m, c + Vector3.new(0, 3.2, 0), 12, 2.2, WHITE)
	disc(m, c + Vector3.new(0, 6.5, 0), 5, 5, Color3.fromRGB(230, 235, 255))
	local core = part(m, { Name = "NexusCrystal", Size = Vector3.new(5, 5, 5), CFrame = CFrame.new(c + Vector3.new(0, 16, 0)) * CFrame.Angles(math.rad(45), math.rad(45), 0),
		Color = Color3.fromRGB(255, 110, 215), Material = Enum.Material.Neon, CanCollide = false })
	local core2 = part(m, { Size = Vector3.new(7.5, 7.5, 7.5), CFrame = core.CFrame, Color = Color3.fromRGB(120, 215, 255), Material = Enum.Material.Glass, Transparency = 0.35, CanCollide = false })
	local pe = Instance.new("ParticleEmitter"); pe.Rate = 14; pe.Lifetime = NumberRange.new(1.5, 2.5); pe.Speed = NumberRange.new(1.5, 3)
	pe.Color = ColorSequence.new(Color3.fromRGB(200, 170, 255), Color3.fromRGB(140, 230, 255)); pe.LightEmission = 1
	pe.Size = NumberSequence.new(0.8, 0); pe.SpreadAngle = Vector2.new(180, 180); pe.Parent = core
	local pl = Instance.new("PointLight"); pl.Color = Color3.fromRGB(190, 170, 255); pl.Range = 26; pl.Brightness = 2; pl.Parent = core
	-- centro: cúmulo de cristales generado flotando sobre la fuente (reemplaza el cubo de partes)
	core.Transparency = 1; core2.Transparency = 1
	WB.Prop(m, "Crystals", c + Vector3.new(0, 9, 0), 1.7, 20, false)
	local title = Instance.new("BillboardGui"); title.Size = UDim2.fromOffset(420, 90); title.StudsOffset = Vector3.new(0, 9, 0)
	title.LightInfluence = 0; title.MaxDistance = 160; title.Parent = core2
	local tl = Instance.new("TextLabel"); tl.BackgroundTransparency = 1; tl.Size = UDim2.fromScale(1, 1); tl.Font = Enum.Font.FredokaOne
	tl.TextScaled = true; tl.Text = info.Lobby:upper(); tl.TextColor3 = Color3.fromRGB(255, 255, 255); tl.Parent = title
	local ts = Instance.new("UIStroke"); ts.Thickness = 5; ts.Color = Color3.fromRGB(110, 70, 200); ts.Parent = tl
	local tg = Instance.new("UIGradient"); tg.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 225, 255)); tg.Rotation = 90; tg.Parent = tl

	-- anillo de pilares (deja libre la entrada norte y la llegada sur) + jardines entre pilares
	local canopies = { Color3.fromRGB(255, 170, 215), Color3.fromRGB(200, 170, 255), Color3.fromRGB(140, 230, 200), Color3.fromRGB(150, 205, 255) }
	for k = 0, 7 do
		local a = math.rad(22.5 + k * 45)
		WB.Pillar(m, c + Vector3.new(math.cos(a) * 72, 0, math.sin(a) * 72), 20, Color3.fromRGB(235, 245, 255), 1)
		local mid = math.rad(45 + k * 45)
		local dir = Vector3.new(math.cos(mid), 0, math.sin(mid))
		local isEntrance = dir.Z > 0.9 or dir.Z < -0.9
		local shopKind = (not isEntrance and dir.Z < -0.5) and (dir.X < 0 and "Shop" or "Premium") or nil -- los dos jardines del lado de la plaza trasera
		if shopKind then
			WB.BuildShop(m, shopKind, c + dir * 61, c)
		elseif not isEntrance then
			local bed = c + dir * 68
			disc(m, bed + Vector3.new(0, 0.6, 0), 16, 1.2, WHITE)
			disc(m, bed + Vector3.new(0, 1.1, 0), 14, 0.4, Color3.fromRGB(150, 230, 160))
			WB.Tree(m, bed + Vector3.new(0, 1.2, 0), canopies[k % #canopies + 1], 1.25, rng)
			WB.Crystal(m, bed + dir:Cross(Vector3.yAxis) * 4.5 + Vector3.new(0, 1.2, 0), k % 2 == 0 and Color3.fromRGB(130, 215, 255) or Color3.fromRGB(255, 150, 220), 7, rng)
		end
	end

	-- arco de entrada al área 1
	local archZ = c.Z + 76
	WB.Pillar(m, Vector3.new(c.X - 19, 0, archZ), 26, cyan, 1.2)
	WB.Pillar(m, Vector3.new(c.X + 19, 0, archZ), 26, cyan, 1.2)
	local beam = part(m, { Name = "ArchSign", Size = Vector3.new(32, 6, 2), Position = Vector3.new(c.X, 24, archZ), Color = Color3.fromRGB(150, 110, 255) })
	textSurface(beam, Enum.NormalId.Back, { { Text = "Area 1 · " .. Config.AreaName(dim, 1), Size = UDim2.fromScale(0.94, 0.8), Pos = UDim2.fromScale(0.03, 0.1) } })
	textSurface(beam, Enum.NormalId.Front, { { Text = info.Lobby, Size = UDim2.fromScale(0.94, 0.8), Pos = UDim2.fromScale(0.03, 0.1) } })

	-- plaza trasera plana (lado opuesto a las áreas): tienda + espacio libre para futuras cosas
	local bz = c.Z - 118
	part(m, { Name = "BackPlaza", Size = Vector3.new(160, 4, 170), Position = Vector3.new(c.X, -2, bz), Color = Color3.fromRGB(200, 204, 255) })
	part(m, { Name = "BackPlazaInset", Size = Vector3.new(140, 0.4, 132), Position = Vector3.new(c.X, 0.2, bz - 10), Color = Color3.fromRGB(222, 218, 255) })
	part(m, { Name = "BackPlazaTrim", Size = Vector3.new(144, 0.3, 136), Position = Vector3.new(c.X, 0.08, bz - 10), Color = Color3.fromRGB(120, 225, 255), Material = Enum.Material.Neon, CanCollide = false, CastShadow = false })
	part(m, { Size = Vector3.new(150, 10, 160), Position = Vector3.new(c.X, -9, bz), Color = UNDER1 })
	part(m, { Size = Vector3.new(120, 10, 130), Position = Vector3.new(c.X, -18, bz), Color = UNDER2 })
	for _, sx in ipairs({ -1, 1 }) do
		part(m, { Name = "Curb", Size = Vector3.new(2.4, 1.2, 170), Position = Vector3.new(c.X + sx * 78.8, 0.6, bz), Color = PATH_EDGE })
	end
	dashedBorder(m, Vector3.new(c.X, 0, bz - 10), 140, 132, 3, 0.45)

	-- plataformas para máquinas futuras (sur-este)
	return m
end

-- Huevo: pedestal futurista + modelo 3D del huevo. Tag "Egg" + atributo EggId en la parte del huevo.
-- La tarjeta de probabilidades, la tecla E y la pastilla de precio las dibuja el cliente (estilo PS99).
function WB.BuildEgg(parent, eggId, pos)
	local egg = Config.Eggs[eggId]
	local old = parent:FindFirstChild(eggId)
	if old then old:Destroy() end
	local m = Instance.new("Model"); m.Name = eggId; m.Parent = parent
	disc(m, pos + Vector3.new(0, 0.6, 0), 12, 1.2, WHITE)
	disc(m, pos + Vector3.new(0, 1.25, 0), 12.6, 0.25, egg.Color, { Material = Enum.Material.Neon, CanCollide = false })
	disc(m, pos + Vector3.new(0, 1.6, 0), 9, 0.8, Color3.fromRGB(236, 238, 255))
	disc(m, pos + Vector3.new(0, 2.05, 0), 7.2, 0.15, egg.Color, { Material = Enum.Material.Neon, CanCollide = false, Transparency = 0.2 })
	local em = Assets.Eggs:FindFirstChild(eggId):Clone()
	local _, sz = em:GetBoundingBox()
	em:ScaleTo(7 / sz.Y)
	em:PivotTo(CFrame.new(pos + Vector3.new(0, 2.1, 0)) * CFrame.Angles(0, math.rad(180), 0))
	em.Name = "EggModel"
	em.Parent = m
	local e = em.PrimaryPart
	e.CanQuery = true
	e:SetAttribute("EggId", eggId)
	CollectionService:AddTag(e, "Egg")
	local pp = Instance.new("ProximityPrompt")
	pp.Style = Enum.ProximityPromptStyle.Custom
	pp.ActionText = "Abrir"
	pp.ObjectText = egg.Display
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.MaxActivationDistance = 12
	pp.RequiresLineOfSight = false
	pp.Parent = e
	local l = Instance.new("PointLight"); l.Color = egg.Color; l.Range = 12; l.Brightness = 1.2; l.Parent = e
	return m
end

function WB.BuildEnvironment()
	local L = game:GetService("Lighting")
	L.ClockTime = 14
	L.Brightness = 2.4
	L.Ambient = Color3.fromRGB(150, 140, 180)
	L.OutdoorAmbient = Color3.fromRGB(205, 195, 235)
	L.EnvironmentDiffuseScale = 0.6
	L.EnvironmentSpecularScale = 0.4
	local atm = L:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere", L)
	atm.Density = 0.26; atm.Offset = 0.1; atm.Color = Color3.fromRGB(255, 232, 248); atm.Decay = Color3.fromRGB(190, 175, 255); atm.Glare = 0.25; atm.Haze = 1.2
	local cc = L:FindFirstChildOfClass("ColorCorrectionEffect") or Instance.new("ColorCorrectionEffect", L)
	cc.Saturation = 0.18; cc.Brightness = 0.03; cc.Contrast = 0.06; cc.TintColor = Color3.fromRGB(255, 250, 255)
	local bloom = L:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect", L)
	bloom.Intensity = 0.7; bloom.Size = 30; bloom.Threshold = 0.92
	local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds", workspace.Terrain)
	clouds.Cover = 0.55; clouds.Density = 0.6; clouds.Color = Color3.fromRGB(255, 240, 250)
	-- mar de nubes abajo
	local env = folder(workspace:WaitForChild("World"), "Environment")
	env:ClearAllChildren()
	part(env, { Name = "CloudSea", Size = Vector3.new(1400, 2, 3600), Position = Vector3.new(0, -70, 1400), Color = Color3.fromRGB(245, 240, 255), CanCollide = false, CastShadow = false })
	local rng = Random.new(5)
	for _ = 1, 42 do
		local p = Vector3.new(rng:NextNumber(-600, 600), rng:NextNumber(-72, -58), rng:NextNumber(-300, 3000))
		if math.abs(p.X) > 60 then
			WB.Cloud(env, p, rng:NextNumber(3, 6), Color3.fromRGB(255, 245, 252), rng)
		end
	end
end

-- Posiciones de huevos (mundo): lobby o costado del área donde se desbloquean
WB.EggSpots = {
	NexusEgg = Vector3.new(48, 0, 50),
	CottonEgg = Vector3.new(56, 0, 285),
}

-- Reconstruye todo el mundo construido: lobby, áreas 1..AreasBuilt y huevos
function WB.BuildWorld(dim)
	local d = Config.Dimensions[dim]
	local wf = workspace.World:FindFirstChild(dim)
	if wf then wf:Destroy() end
	WB.BuildLobby(dim)
	for i = 1, d.AreasBuilt do WB.BuildArea(dim, i) end
	-- cordilleras que rodean el mundo construido: cada tramo usa las piezas de su zona
	local rngW = Random.new((d.SeedOrder or d.Order) * 977)
	local walls = Instance.new("Model"); walls.Name = "Walls"; walls.Parent = workspace.World[dim]
	local X = 168
	local zBack = d.LobbyCenter.Z - 215
	local zLobbyEnd = d.LobbyCenter.Z + 90
	local zEnd = Config.ZoneCenter(dim, d.AreasBuilt).Z + d.ZoneLength / 2
	for _, sx in ipairs({ -1, 1 }) do
		local out = Vector3.new(sx, 0, 0)
		WB.MountainWall(walls, Vector3.new(sx * X, 0, zBack + 36), Vector3.new(sx * X, 0, zLobbyEnd), rngW, WB.WallSets.Lobby, out) -- sin encimarse con la pared trasera en la esquina
		for i = 1, d.AreasBuilt do
			local cz = Config.ZoneCenter(dim, i).Z
			WB.MountainWall(walls, Vector3.new(sx * X, 0, cz - d.ZoneLength / 2), Vector3.new(sx * X, 0, cz + d.ZoneLength / 2), rngW, WB.WallSets[d.Areas[i].Name] or WB.WallSets.Lobby, out)
		end
	end
	WB.MountainWall(walls, Vector3.new(-X, 0, zBack), Vector3.new(X, 0, zBack), rngW, WB.WallSets.Lobby, Vector3.new(0, 0, -1))
	WB.MountainWall(walls, Vector3.new(-X, 0, zEnd + 40), Vector3.new(X, 0, zEnd + 40), rngW, WB.WallSets[d.Areas[d.AreasBuilt].Name] or WB.WallSets.Lobby, Vector3.new(0, 0, 1))
	-- barreras invisibles (el jugador no llega a las montañas)
	local zMid = (zBack + zEnd) / 2
	local zLen = zEnd - zBack + 40
	barrier(walls, Vector3.new(-118, 60, zMid), Vector3.new(4, 160, zLen)) -- justo en el borde de las islas laterales: no hay caída al vacío
	barrier(walls, Vector3.new(118, 60, zMid), Vector3.new(4, 160, zLen))
	barrier(walls, Vector3.new(0, 60, d.LobbyCenter.Z - 205), Vector3.new(260, 140, 4))
	barrier(walls, Vector3.new(0, 60, zEnd + 4), Vector3.new(260, 140, 4))
	local eggs = Instance.new("Model"); eggs.Name = "Eggs"; eggs.Parent = workspace.World[dim]
	for eggId, pos in pairs(WB.EggSpots) do
		if Config.Eggs[eggId].Dimension == dim then WB.BuildEgg(eggs, eggId, pos) end
	end
end

return WB
