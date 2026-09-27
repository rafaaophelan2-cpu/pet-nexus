-- Pet Nexus: cliente (visuales, HUD, mascotas, efectos). Nada aquí decide economía.
-- Sin emojis: todos los íconos son modelos 3D renderizados (PetNexus.Icons) o símbolos vectoriales.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("PetNexus"):WaitForChild("Config"))
local Icons = require(ReplicatedStorage.PetNexus:WaitForChild("Icons"))
local Assets = ReplicatedStorage:WaitForChild("PetNexusAssets")
local Remotes = ReplicatedStorage.PetNexus:WaitForChild("Remotes")
local camera = workspace.CurrentCamera

local data = nil
local displayed = 0
local INK = Color3.fromRGB(38, 26, 72) -- contorno oscuro violeta (más moderno que negro puro)

---------------------------------------------------------------- helpers de UI
local gui = Instance.new("ScreenGui")
gui.Name = "PetNexusHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local function round(obj, r)
	local c = Instance.new("UICorner"); c.CornerRadius = r or UDim.new(0, 14); c.Parent = obj
end
local function stroke(obj, th, col, trans)
	local s = Instance.new("UIStroke"); s.Thickness = th or 3; s.Color = col or INK; s.Transparency = trans or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.Parent = obj; return s
end
local function gradient(obj, a, b, rot)
	local g = Instance.new("UIGradient"); g.Color = ColorSequence.new(a, b); g.Rotation = rot or 90; g.Parent = obj; return g
end
local function label(parent, props)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextColor3 = Color3.new(1, 1, 1)
	for k, v in pairs(props) do t[k] = v end
	local s = Instance.new("UIStroke"); s.Thickness = 2.5; s.Color = INK; s.Parent = t
	t.Parent = parent
	return t
end
local function glass(parent, props)
	local f = Instance.new("Frame")
	f.BackgroundColor3 = Color3.fromRGB(40, 28, 80)
	f.BackgroundTransparency = 0.35
	for k, v in pairs(props) do f[k] = v end
	round(f, UDim.new(1, 0))
	stroke(f, 2, Color3.new(1, 1, 1), 0.55)
	gradient(f, Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 190, 255), 90)
	f.Parent = parent
	return f
end
local function button(parent, props)
	local b = Instance.new("TextButton")
	b.Font = Enum.Font.FredokaOne
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.AutoButtonColor = true
	for k, v in pairs(props) do b[k] = v end
	round(b, UDim.new(0, 14)); stroke(b, 3)
	local ts = Instance.new("UIStroke"); ts.Thickness = 2; ts.Color = INK; ts.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual; ts.Parent = b
	b.Parent = parent
	return b
end
local function shade(c, f) return Color3.new(c.R * f, c.G * f, c.B * f) end

local function currentWorld()
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if hrp then
		for dim, d in pairs(Config.Dimensions) do
			if Config.ZoneFromPosition(dim, hrp.Position) or (hrp.Position - d.LobbyCenter).Magnitude < 100 then return dim end
		end
	end
	return "Nexus"
end
local function curAmount(dim)
	return data and data.Currency and (data.Currency[dim] or 0) or 0
end

---------------------------------------------------------------- HUD (moneda del mundo + poder)
local hud = Instance.new("Frame")
hud.BackgroundTransparency = 1
hud.Size = UDim2.fromOffset(290, 150)
hud.Position = UDim2.new(0, 16, 0.5, -110)
hud.Parent = gui

local curRow = glass(hud, { Size = UDim2.fromOffset(250, 58), Position = UDim2.fromOffset(34, 6) })
local curIconHolder = Instance.new("Frame"); curIconHolder.BackgroundTransparency = 1; curIconHolder.Size = UDim2.fromOffset(76, 76); curIconHolder.Position = UDim2.fromOffset(-4, -3); curIconHolder.ZIndex = 3; curIconHolder.Parent = hud
local curIconName = nil
local curText = label(curRow, { Text = "0", Size = UDim2.new(1, -60, 0, 44), Position = UDim2.fromOffset(46, 7), TextXAlignment = Enum.TextXAlignment.Left })
gradient(curText, Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 225, 150))
local curName = label(curRow, { Text = "", Size = UDim2.fromOffset(160, 16), Position = UDim2.fromOffset(48, -10), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 236, 170) })

local powRow = glass(hud, { Size = UDim2.fromOffset(200, 48), Position = UDim2.fromOffset(34, 82) })
Icons.Make(hud, "Power", { Size = UDim2.fromOffset(62, 62), Position = UDim2.fromOffset(2, 75), ZIndex = 3 })
local powerText = label(powRow, { Text = "0", Size = UDim2.new(1, -60, 0, 36), Position = UDim2.fromOffset(40, 6), TextXAlignment = Enum.TextXAlignment.Left })
gradient(powerText, Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 225, 255))

local function setCurrencyIcon(dim)
	local cur = Config.CurrencyOf(dim)
	if curIconName == cur.Icon then return end
	curIconName = cur.Icon
	curIconHolder:ClearAllChildren()
	Icons.Make(curIconHolder, cur.Icon, { Size = UDim2.fromScale(1, 1), ZIndex = 3 })
	curName.Text = cur.Name:upper()
	curName.TextColor3 = cur.Color
end
setCurrencyIcon("Nexus")

---------------------------------------------------------------- Esencia + Zona de Meditación (el estado lo decide el servidor: atributos del jugador)
local MED_PURPLE = Color3.fromRGB(215, 175, 255)
local essRow = glass(hud, { Size = UDim2.fromOffset(200, 48), Position = UDim2.fromOffset(34, -64), Visible = false })
local essIcon = Icons.Make(hud, "Meditation", { Size = UDim2.fromOffset(62, 62), Position = UDim2.fromOffset(2, -71), ZIndex = 3, Visible = false })
local essText = label(essRow, { Text = "0", Size = UDim2.new(1, -60, 0, 36), Position = UDim2.fromOffset(40, 6), TextXAlignment = Enum.TextXAlignment.Left })
gradient(essText, Color3.fromRGB(255, 255, 255), MED_PURPLE)
local essHead = label(essRow, { Text = "ESENCIA", Size = UDim2.fromOffset(200, 16), Position = UDim2.fromOffset(42, -10), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = MED_PURPLE })

local medBar = glass(gui, { Size = UDim2.fromOffset(400, 58), Position = UDim2.new(0.5, -200, 1, -150), Visible = false })
local medTitle = label(medBar, { Text = "", Size = UDim2.new(1, -40, 0, 24), Position = UDim2.fromOffset(20, 5) })
local medBg = Instance.new("Frame"); medBg.Size = UDim2.new(1, -60, 0, 14); medBg.Position = UDim2.fromOffset(30, 34)
medBg.BackgroundColor3 = Color3.fromRGB(35, 28, 64); medBg.BackgroundTransparency = 0.2; medBg.Parent = medBar
round(medBg, UDim.new(1, 0)); stroke(medBg, 1.5, Color3.new(1, 1, 1), 0.2)
local medFill = Instance.new("Frame"); medFill.Size = UDim2.fromScale(0, 1); medFill.BackgroundColor3 = Color3.new(1, 1, 1); medFill.Parent = medBg
round(medFill, UDim.new(1, 0))
gradient(medFill, Color3.fromRGB(255, 200, 250), Color3.fromRGB(165, 120, 255), 0)

local function clockText(s)
	s = math.max(0, math.floor(s))
	return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local function updateMeditation()
	local med = Config.Meditation
	local inside = player:GetAttribute("Meditating") == true
	local prog = player:GetAttribute("MeditationProgress") or 0
	local cd = player:GetAttribute("MeditationCooldown") or 0
	local essence = data and data.Essence or 0
	essRow.Visible = essence > 0 or inside or cd > 0
	essIcon.Visible = essRow.Visible
	essText.Text = Config.FormatNumber(essence)
	essHead.Text = cd > 0 and ("ESENCIA · RECARGA " .. clockText(cd)) or "ESENCIA"
	medBar.Visible = inside
	if cd > 0 then
		medTitle.Text = "Meditación en recarga: " .. clockText(cd)
		medFill.BackgroundColor3 = Color3.fromRGB(170, 165, 190)
		medFill.Size = UDim2.fromScale(math.clamp(1 - cd / med.Cooldown, 0, 1), 1)
	else
		medTitle.Text = "Meditando: " .. math.floor(prog / med.SecondsPerEssence) .. " / " .. med.Cap .. " Esencia"
		medFill.BackgroundColor3 = Color3.new(1, 1, 1)
		medFill.Size = UDim2.fromScale(math.clamp(prog / (med.Cap * med.SecondsPerEssence), 0, 1), 1)
	end
end
for _, attr in ipairs({ "Meditating", "MeditationProgress", "MeditationCooldown" }) do
	player:GetAttributeChangedSignal(attr):Connect(updateMeditation)
end

-- notificaciones: píldora de cristal arriba al centro
local notifyFrame = glass(gui, { Size = UDim2.fromOffset(560, 48), Position = UDim2.new(0.5, -280, 0, 92), Visible = false })
local notifyLabel = label(notifyFrame, { Text = "", Size = UDim2.new(1, -40, 1, -12), Position = UDim2.fromOffset(20, 6) })
local function notify(text, color)
	notifyLabel.Text = text
	notifyLabel.TextColor3 = color or Color3.new(1, 1, 1)
	notifyFrame.Visible = true
	notifyFrame.Position = UDim2.new(0.5, -280, 0, 70)
	TweenService:Create(notifyFrame, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Position = UDim2.new(0.5, -280, 0, 92) }):Play()
	local stamp = os.clock()
	notifyFrame:SetAttribute("Stamp", stamp)
	task.delay(2.4, function()
		if notifyFrame:GetAttribute("Stamp") == stamp then notifyFrame.Visible = false end
	end)
end
Remotes.Notify.OnClientEvent:Connect(notify)

---------------------------------------------------------------- puertas de área (visual local + botón Comprar)
local gateGuis = {}
local function setupGate(wall)
	if gateGuis[wall] then return end
	local sg = Instance.new("SurfaceGui")
	sg.Name = "GateBuy"
	sg.Adornee = wall
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 20
	sg.LightInfluence = 0
	sg.ResetOnSpawn = false
	sg.Parent = player:WaitForChild("PlayerGui")
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromScale(0.34, 0.19)
	b.Position = UDim2.fromScale(0.33, 0.68)
	b.BackgroundColor3 = Color3.fromRGB(120, 225, 70)
	b.Font = Enum.Font.FredokaOne
	b.TextScaled = true
	b.Text = "Comprar"
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Parent = sg
	round(b, UDim.new(0.25, 0)); stroke(b, 6)
	local ts = Instance.new("UIStroke"); ts.Thickness = 4; ts.Color = INK; ts.Parent = b
	gradient(b, Color3.fromRGB(165, 250, 100), Color3.fromRGB(60, 180, 40))
	local pad = Instance.new("UIPadding"); pad.PaddingTop = UDim.new(0.14, 0); pad.PaddingBottom = UDim.new(0.14, 0); pad.Parent = b
	b.MouseButton1Click:Connect(function()
		Remotes.BuyArea:FireServer(wall:GetAttribute("Dimension"), wall:GetAttribute("Zone"))
	end)
	Icons.Make(sg, Config.CurrencyOf(wall:GetAttribute("Dimension")).Icon, { Size = UDim2.fromScale(0.13, 0.24), Position = UDim2.fromScale(0.26, 0.42) })
	gateGuis[wall] = sg
end

local gateAnimating = {}
local function updateGates()
	if not data then return end
	for _, wall in ipairs(CollectionService:GetTagged("AreaGate")) do
		setupGate(wall)
		if gateAnimating[wall] then continue end
		local open = (data.Unlocked[wall:GetAttribute("Dimension")] or 0) >= wall:GetAttribute("Zone")
		wall.CanCollide = not open
		wall.Transparency = open and 1 or 0.35
		local info = wall:FindFirstChildOfClass("SurfaceGui")
		if info then info.Enabled = not open end
		gateGuis[wall].Enabled = not open
		local pp = wall:FindFirstChildOfClass("ProximityPrompt")
		if pp then pp.Enabled = not open end
	end
end

---------------------------------------------------------------- mascotas (modelos 3D generados)
local petFolder = Instance.new("Folder")
petFolder.Name = "ClientPets"
petFolder.Parent = workspace
local petModels = {}
local PET_HEIGHT = 3.2

local function buildPet(name)
	local src = Assets.Pets:FindFirstChild(name)
	local m = src:Clone()
	local _, sz = m:GetBoundingBox()
	m:ScaleTo(PET_HEIGHT / sz.Y)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false; d.CastShadow = true end
	end
	local rar = Config.Rarities[Config.Pets[name].Rarity]
	if rar.Order >= 4 then
		local pe = Instance.new("ParticleEmitter")
		pe.Rate = 10; pe.Lifetime = NumberRange.new(0.6, 1.2); pe.Speed = NumberRange.new(0.8, 1.6)
		pe.Color = ColorSequence.new(rar.Color); pe.LightEmission = 1
		pe.Size = NumberSequence.new(0.3, 0); pe.SpreadAngle = Vector2.new(180, 180)
		pe.Parent = m.PrimaryPart
		local light = Instance.new("PointLight"); light.Color = rar.Color; light.Range = 8; light.Brightness = 1.2; light.Parent = m.PrimaryPart
	end
	m.Parent = petFolder
	return m
end

local FLIP = CFrame.Angles(0, math.pi, 0) -- los modelos generados miran a +Z

local function updatePets()
	if not data then return end
	local wanted = {}
	local power = 0
	for _, pet in ipairs(data.Pets) do
		if pet.Equipped then
			wanted[pet.Id] = pet.Name
			power += Config.Pets[pet.Name].Power
		end
	end
	power *= (1 + (data.Rebirths or 0) * 0.5)
	powerText.Text = Config.FormatNumber(power)
	for id, m in pairs(petModels) do
		if not wanted[id] then m:Destroy(); petModels[id] = nil end
	end
	for id, name in pairs(wanted) do
		if not petModels[id] then
			local m = buildPet(name)
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if hrp then m:PivotTo(hrp.CFrame) end
			petModels[id] = m
		end
	end
end

local targetUid, targetModel = nil, nil
local function resolveTarget()
	local uid = player:GetAttribute("Target")
	if uid == targetUid and targetModel and targetModel.Parent then return targetModel end
	targetUid = uid
	targetModel = nil
	if uid and uid ~= "" then
		targetModel = workspace.Breakables:FindFirstChild(uid, true)
	end
	return targetModel
end

local t0 = os.clock()
local worldCheck = 0
RunService.RenderStepped:Connect(function(dt)
	worldCheck += dt
	if worldCheck > 0.5 then
		worldCheck = 0
		setCurrencyIcon(currentWorld())
	end
	if data then
		local target = curAmount(currentWorld())
		displayed += (target - displayed) * math.min(1, dt * 10)
		if math.abs(target - displayed) < 1 then displayed = target end
		curText.Text = Config.FormatNumber(displayed)
	end

	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local groundY = hrp.Position.Y - 3
	local t = os.clock() - t0
	local target = resolveTarget()
	local list = {}
	for _, m in pairs(petModels) do table.insert(list, m) end
	local n = #list
	local alpha = 1 - math.exp(-dt * 9)
	for i, m in ipairs(list) do
		local goal
		if target and target.PrimaryPart then
			local tp = target.PrimaryPart.Position
			local ang = (i / n) * math.pi * 2 + t * 0.6
			local sz = target.PrimaryPart.Size
			local radius = math.max(sz.X, sz.Z) / 2 + 2.4
			local pos = Vector3.new(tp.X + math.cos(ang) * radius, groundY + math.abs(math.sin(t * 9 + i)) * 1.3, tp.Z + math.sin(ang) * radius)
			goal = CFrame.lookAt(pos, Vector3.new(tp.X, pos.Y, tp.Z)) * FLIP
		else
			local x = (i - (n + 1) / 2) * 3.8
			local back = hrp.CFrame * CFrame.new(x, 0, 5.5 + (i % 2) * 1.5)
			local pos = Vector3.new(back.X, groundY + math.abs(math.sin(t * 3 + i)) * 0.35, back.Z)
			goal = CFrame.lookAt(pos, pos + hrp.CFrame.LookVector) * FLIP
		end
		m:PivotTo(m:GetPivot():Lerp(goal, alpha))
	end
end)

-- Clic / toque en un rompible = enviar mascotas ahí
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { workspace:WaitForChild("Breakables") }
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
	local ray = camera:ViewportPointToRay(input.Position.X, input.Position.Y)
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 300, rayParams)
	if hit then
		local model = hit.Instance
		while model and not model:GetAttribute("Uid") do model = model.Parent end
		if model and model:GetAttribute("Uid") then
			Remotes.SetTarget:FireServer(model:GetAttribute("Uid"))
		end
	end
end)

---------------------------------------------------------------- barras de vida de rompibles (cliente)
local pgui = player:WaitForChild("PlayerGui")
local function hpBar(model)
	if not model:IsA("Model") or not model:GetAttribute("Uid") then return end
	local hitbox = model:WaitForChild("Hitbox", 5)
	if not hitbox then return end
	local dim = model:GetAttribute("Dim") or "Nexus"
	local cur = Config.CurrencyOf(dim)
	local bb = Instance.new("BillboardGui")
	bb.Name = "HP_" .. model.Name
	bb.Adornee = hitbox
	bb.Size = UDim2.fromOffset(124, 42)
	bb.StudsOffset = Vector3.new(0, hitbox.Size.Y / 2 + 1.6, 0)
	bb.MaxDistance = 50
	bb.LightInfluence = 0
	bb.ResetOnSpawn = false
	local row = Instance.new("Frame"); row.BackgroundTransparency = 1; row.Size = UDim2.new(1, 0, 0, 22); row.Parent = bb
	Icons.Make(row, cur.Icon, { Size = UDim2.fromOffset(24, 24), Position = UDim2.new(0.5, -48, 0, -1) })
	local val = label(row, { Text = Config.FormatNumber(model:GetAttribute("Reward") or 0), Size = UDim2.new(0, 84, 1, 0), Position = UDim2.new(0.5, -22, 0, 0), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = cur.Color })
	local bg = Instance.new("Frame"); bg.Size = UDim2.new(1, 0, 0, 12); bg.Position = UDim2.fromOffset(0, 26)
	bg.BackgroundColor3 = Color3.fromRGB(35, 28, 64); bg.BackgroundTransparency = 0.2; bg.Parent = bb
	round(bg, UDim.new(1, 0)); stroke(bg, 1.5, Color3.new(1, 1, 1), 0.2)
	local fill = Instance.new("Frame"); fill.Size = UDim2.fromScale(1, 1); fill.BackgroundColor3 = Color3.new(1, 1, 1); fill.Parent = bg
	round(fill, UDim.new(1, 0))
	gradient(fill, Color3.fromRGB(120, 255, 200), Color3.fromRGB(90, 190, 255), 0)
	bb.Parent = pgui
	local function upd()
		local hp, mx = model:GetAttribute("HP") or 1, model:GetAttribute("MaxHP") or 1
		TweenService:Create(fill, TweenInfo.new(0.15), { Size = UDim2.fromScale(math.clamp(hp / mx, 0, 1), 1) }):Play()
	end
	model:GetAttributeChangedSignal("HP"):Connect(upd)
	model.AncestryChanged:Connect(function(_, parent) if not parent then bb:Destroy() end end)
end
local breakFolder = workspace:WaitForChild("Breakables")
for _, d in ipairs(breakFolder:GetDescendants()) do task.spawn(hpBar, d) end
breakFolder.DescendantAdded:Connect(function(d) if d:IsA("Model") and d.Parent and d.Parent.Parent == breakFolder then task.spawn(hpBar, d) end end)

-- letreros del mundo con atributo IconName (ej. la tienda): el cliente dibuja el ícono 3D encima
local function signIcon(part)
	local name = part:GetAttribute("IconName")
	if not name then return end
	local sg = Instance.new("SurfaceGui")
	sg.Adornee = part; sg.Face = Enum.NormalId.Front; sg.LightInfluence = 0; sg.ResetOnSpawn = false
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud; sg.PixelsPerStud = 20
	Icons.Make(sg, name, { Size = UDim2.fromScale(0.26, 0.95), Position = UDim2.fromScale(0.05, 0.02) })
	sg.Parent = pgui
end
task.spawn(function()
	local w = workspace:WaitForChild("World")
	for _, d in ipairs(w:GetDescendants()) do if d:IsA("BasePart") and d:GetAttribute("IconName") then signIcon(d) end end
	w.DescendantAdded:Connect(function(d) if d:IsA("BasePart") and d:GetAttribute("IconName") then signIcon(d) end end)
end)

---------------------------------------------------------------- efectos al romper
local function floatingText(pos, amount, dim)
	local anchor = Instance.new("Part")
	anchor.Anchored = true; anchor.CanCollide = false; anchor.CanQuery = false; anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2); anchor.Position = pos + Vector3.new(0, 3, 0); anchor.Parent = workspace
	local bb = Instance.new("BillboardGui"); bb.Size = UDim2.fromOffset(170, 50); bb.AlwaysOnTop = true; bb.LightInfluence = 0; bb.Parent = anchor
	local cur = Config.CurrencyOf(dim)
	local icon = Icons.Make(bb, cur.Icon, { Size = UDim2.fromOffset(42, 42), Position = UDim2.fromOffset(4, 4) })
	local l = label(bb, { Text = "+" .. Config.FormatNumber(amount), Size = UDim2.new(1, -52, 1, -6), Position = UDim2.fromOffset(48, 3), TextColor3 = cur.Color, TextXAlignment = Enum.TextXAlignment.Left })
	TweenService:Create(anchor, TweenInfo.new(1, Enum.EasingStyle.Quad), { Position = anchor.Position + Vector3.new(0, 5, 0) }):Play()
	TweenService:Create(l, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1 }):Play()
	TweenService:Create(l.UIStroke, TweenInfo.new(1), { Transparency = 1 }):Play()
	TweenService:Create(icon, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { ImageTransparency = 1 }):Play()
	task.delay(1.05, function() anchor:Destroy() end)
end

local function coinBurst(pos, count, dim)
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local coinModel = Assets.Currency:FindFirstChild(Config.CurrencyOf(dim).Model)
	for _ = 1, count do
		local c = coinModel:Clone()
		c:ScaleTo(0.35)
		for _, d in ipairs(c:GetDescendants()) do if d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false; d.CanQuery = false end end
		c.Parent = workspace
		local start = CFrame.new(pos + Vector3.new(0, 2, 0))
		local out = pos + Vector3.new(math.random(-5, 5), math.random(3, 6), math.random(-5, 5))
		local tStart = os.clock()
		local conn
		conn = RunService.RenderStepped:Connect(function()
			local e = os.clock() - tStart
			local spin = CFrame.Angles(0, e * 14, 0)
			if e < 0.3 then
				local a = TweenService:GetValue(e / 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				c:PivotTo(CFrame.new(start.Position:Lerp(out, a)) * spin)
			elseif e < 0.7 then
				local a = TweenService:GetValue((e - 0.3) / 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				local dest = hrp and hrp.Parent and hrp.Position or out
				c:PivotTo(CFrame.new(out:Lerp(dest, a)) * spin)
			else
				conn:Disconnect()
				c:Destroy()
			end
		end)
	end
end

Remotes.Damage.OnClientEvent:Connect(function(kind, pos, reward, dim)
	if kind == "break" then
		dim = dim or "Nexus"
		floatingText(pos, reward, dim)
		coinBurst(pos, 4, dim)
		TweenService:Create(curRow, TweenInfo.new(0.08), { Size = UDim2.fromOffset(262, 62) }):Play()
		task.delay(0.08, function()
			TweenService:Create(curRow, TweenInfo.new(0.15), { Size = UDim2.fromOffset(250, 58) }):Play()
		end)
	end
end)

---------------------------------------------------------------- huevos: tarjeta PS99 + pastilla de precio
local function eggCard(eggPart)
	local eggId = eggPart:GetAttribute("EggId")
	local egg = Config.Eggs[eggId]
	if not egg then return end
	local pg = player:WaitForChild("PlayerGui")
	-- tarjeta con mascotas y probabilidades
	local n = #egg.Pets
	local card = Instance.new("BillboardGui")
	card.Name = "EggCard_" .. eggId
	card.Adornee = eggPart
	card.Size = UDim2.fromOffset(24 + n * 86, 118)
	card.StudsOffset = Vector3.new(0, 7.2, 0)
	card.MaxDistance = 34
	card.LightInfluence = 0
	card.ResetOnSpawn = false
	card.Parent = pg
	local bg = Instance.new("Frame"); bg.Size = UDim2.new(1, 0, 1, -14); bg.BackgroundColor3 = Color3.new(1, 1, 1); bg.Parent = card
	round(bg, UDim.new(0, 18)); stroke(bg, 3, Color3.fromRGB(215, 205, 245))
	gradient(bg, Color3.fromRGB(255, 255, 255), Color3.fromRGB(238, 234, 255))
	local tail = Instance.new("Frame"); tail.AnchorPoint = Vector2.new(0.5, 0.5); tail.Size = UDim2.fromOffset(18, 18); tail.Rotation = 45
	tail.Position = UDim2.new(0.5, 0, 1, -15); tail.BackgroundColor3 = Color3.fromRGB(240, 236, 255); tail.BorderSizePixel = 0; tail.ZIndex = 0; tail.Parent = card
	for i, entry in ipairs(egg.Pets) do
		local pet = Config.Pets[entry[1]]
		local rar = Config.Rarities[pet.Rarity]
		local x = 12 + (i - 1) * 86
		local pct = label(bg, { Text = entry[2] .. "%", Size = UDim2.fromOffset(80, 22), Position = UDim2.fromOffset(x, 4), TextColor3 = rar.Color })
		Icons.Pet(bg, entry[1], { Size = UDim2.fromOffset(76, 76), Position = UDim2.fromOffset(x + 2, 24) })
	end
	-- pastilla de precio bajo el huevo
	local pill = Instance.new("BillboardGui")
	pill.Name = "EggPrice_" .. eggId
	pill.Adornee = eggPart
	pill.Size = UDim2.fromOffset(150, 42)
	pill.StudsOffset = Vector3.new(0, -3.3, 0)
	pill.MaxDistance = 40
	pill.LightInfluence = 0
	pill.ResetOnSpawn = false
	pill.Parent = pg
	local pf = Instance.new("Frame"); pf.Size = UDim2.fromScale(1, 1); pf.BackgroundColor3 = Color3.fromRGB(255, 220, 80); pf.Parent = pill
	round(pf, UDim.new(1, 0)); stroke(pf, 3)
	gradient(pf, Color3.fromRGB(255, 240, 140), Color3.fromRGB(255, 195, 50))
	local cur = Config.CurrencyOf(egg.Dimension)
	Icons.Make(pf, cur.Icon, { Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(6, 1) })
	local pl = label(pf, { Text = Config.FormatNumber(egg.Price), Size = UDim2.new(1, -60, 1, -10), Position = UDim2.fromOffset(50, 5), TextXAlignment = Enum.TextXAlignment.Left })
end
local cardDone = {}
local function tryCard(e)
	if cardDone[e] then return end
	cardDone[e] = true
	task.spawn(eggCard, e)
end
for _, e in ipairs(CollectionService:GetTagged("Egg")) do tryCard(e) end
CollectionService:GetInstanceAddedSignal("Egg"):Connect(tryCard)

---------------------------------------------------------------- tecla E personalizada (estilo PS99) para prompts Custom
local promptGuis = {}
ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
	if prompt.Style ~= Enum.ProximityPromptStyle.Custom then return end
	local bb = Instance.new("BillboardGui")
	bb.Adornee = prompt.Parent
	bb.Size = UDim2.fromOffset(96, 110)
	bb.StudsOffset = Vector3.new(0, -1.2, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.ResetOnSpawn = false
	bb.Parent = player:WaitForChild("PlayerGui")
	local key = Instance.new("TextButton")
	key.Size = UDim2.fromOffset(84, 84); key.Position = UDim2.fromOffset(6, 0)
	key.BackgroundColor3 = Color3.new(1, 1, 1)
	key.Font = Enum.Font.FredokaOne; key.TextScaled = true; key.TextColor3 = INK
	key.Text = inputType == Enum.ProximityPromptInputType.Touch and "TAP" or (inputType == Enum.ProximityPromptInputType.Gamepad and "X" or prompt.KeyboardKeyCode.Name)
	key.Parent = bb
	round(key, UDim.new(0, 20)); stroke(key, 4)
	local pad = Instance.new("UIPadding"); pad.PaddingTop = UDim.new(0, 12); pad.PaddingBottom = UDim.new(0, 12); pad.Parent = key
	label(bb, { Text = prompt.ActionText, Size = UDim2.fromOffset(96, 22), Position = UDim2.fromOffset(0, 88) })
	key.MouseButton1Down:Connect(function() prompt:InputHoldBegin() end)
	key.MouseButton1Up:Connect(function() prompt:InputHoldEnd() end)
	key.Size = UDim2.fromOffset(60, 60); key.Position = UDim2.fromOffset(18, 12)
	TweenService:Create(key, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(84, 84), Position = UDim2.fromOffset(6, 0) }):Play()
	promptGuis[prompt] = bb
	prompt.Triggered:Once(function()
		TweenService:Create(key, TweenInfo.new(0.06), { Size = UDim2.fromOffset(74, 74), Position = UDim2.fromOffset(11, 5) }):Play()
	end)
end)
ProximityPromptService.PromptHidden:Connect(function(prompt)
	if promptGuis[prompt] then promptGuis[prompt]:Destroy(); promptGuis[prompt] = nil end
end)

---------------------------------------------------------------- efectos de UI (rayos, chispas, onda, confeti)
local function fx_rays(parent, color, z, size)
	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 0.5); holder.Position = UDim2.fromScale(0.5, 0.45)
	holder.Size = UDim2.fromOffset(size or 700, size or 700); holder.BackgroundTransparency = 1; holder.ZIndex = z; holder.Parent = parent
	for k = 0, 15 do
		local ray = Instance.new("Frame")
		ray.AnchorPoint = Vector2.new(0.5, 0.5); ray.Position = UDim2.fromScale(0.5, 0.5)
		ray.Size = UDim2.new(0, k % 2 == 0 and 46 or 26, 1, 0); ray.Rotation = k * (180 / 16)
		ray.BackgroundColor3 = color; ray.BorderSizePixel = 0; ray.ZIndex = z; ray.Parent = holder
		local g = Instance.new("UIGradient"); g.Rotation = 90
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.35, 0.55), NumberSequenceKeypoint.new(0.5, 0.25), NumberSequenceKeypoint.new(0.65, 0.55), NumberSequenceKeypoint.new(1, 1) })
		g.Parent = ray
	end
	local conn = RunService.RenderStepped:Connect(function(dt) holder.Rotation += dt * 25 end)
	holder.Destroying:Connect(function() conn:Disconnect() end)
	return holder
end

local function fx_burst(parent, center, colors, count, z, dist)
	for k = 1, count do
		local p = Instance.new("Frame")
		local s = math.random(8, 20)
		p.AnchorPoint = Vector2.new(0.5, 0.5); p.Size = UDim2.fromOffset(s, s); p.Position = center
		p.Rotation = 45; p.BackgroundColor3 = colors[math.random(1, #colors)]; p.BorderSizePixel = 0; p.ZIndex = z; p.Parent = parent
		if k % 3 == 0 then round(p, UDim.new(1, 0)) end
		local a = math.random() * math.pi * 2
		local d = (dist or 260) * (0.5 + math.random() * 0.6)
		local target = center + UDim2.fromOffset(math.cos(a) * d, math.sin(a) * d)
		local tw = TweenService:Create(p, TweenInfo.new(0.7 + math.random() * 0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ Position = target, Rotation = 45 + math.random(-180, 180), BackgroundTransparency = 1, Size = UDim2.fromOffset(2, 2) })
		tw:Play()
		tw.Completed:Connect(function() p:Destroy() end)
	end
end

local function fx_wave(parent, center, color, z)
	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5); ring.Position = center; ring.Size = UDim2.fromOffset(40, 40)
	ring.BackgroundTransparency = 1; ring.ZIndex = z; ring.Parent = parent
	round(ring, UDim.new(1, 0))
	local st = Instance.new("UIStroke"); st.Thickness = 10; st.Color = color; st.Parent = ring
	TweenService:Create(ring, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(900, 900) }):Play()
	local tw = TweenService:Create(st, TweenInfo.new(0.6), { Transparency = 1, Thickness = 1 })
	tw:Play()
	tw.Completed:Connect(function() ring:Destroy() end)
end

local CONFETTI = { Color3.fromRGB(255, 120, 170), Color3.fromRGB(120, 220, 255), Color3.fromRGB(255, 225, 100), Color3.fromRGB(170, 130, 255), Color3.fromRGB(140, 240, 170) }
local function fx_confetti(parent, count, z)
	for _ = 1, count do
		local p = Instance.new("Frame")
		p.Size = UDim2.fromOffset(math.random(8, 14), math.random(14, 22)); p.BorderSizePixel = 0
		p.BackgroundColor3 = CONFETTI[math.random(1, #CONFETTI)]; p.ZIndex = z; p.Rotation = math.random(0, 360)
		p.Position = UDim2.new(math.random(), 0, 0, -30); p.Parent = parent
		local tw = TweenService:Create(p, TweenInfo.new(1.6 + math.random() * 1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
			{ Position = UDim2.new(p.Position.X.Scale + (math.random() - 0.5) * 0.25, 0, 1.1, 0), Rotation = p.Rotation + math.random(-540, 540) })
		tw:Play()
		tw.Completed:Connect(function() p:Destroy() end)
	end
end

local function shakeCamera(duration, strength)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local t = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local e = os.clock() - t
		if e > duration then hum.CameraOffset = Vector3.zero; conn:Disconnect(); return end
		local k = strength * (1 - e / duration)
		hum.CameraOffset = Vector3.new((math.random() - 0.5) * k, (math.random() - 0.5) * k, 0)
	end)
end

---------------------------------------------------------------- animación de huevo (3D + efectos)
local hatchQueue = {}
local hatching = false
local blur = Instance.new("BlurEffect"); blur.Size = 0; blur.Parent = Lighting

local function wobbleWorldEgg(eggId)
	for _, e in ipairs(CollectionService:GetTagged("Egg")) do
		if e:GetAttribute("EggId") == eggId then
			local model = e:FindFirstAncestorOfClass("Model")
			if model then
				local base = model:GetPivot()
				task.spawn(function()
					for k = 1, 10 do
						local a = math.rad((k % 2 == 0 and 1 or -1) * (4 + k))
						model:PivotTo(base * CFrame.Angles(0, 0, a))
						task.wait(0.05)
					end
					model:PivotTo(base)
				end)
			end
		end
	end
end

local function playHatch(eggId, petName, forced)
	hatching = true
	wobbleWorldEgg(eggId)
	local def = Config.Pets[petName]
	local rar = Config.Rarities[def.Rarity]
	local center = UDim2.fromScale(0.5, 0.45)
	local overlay = Instance.new("Frame")
	overlay.Size = UDim2.fromScale(1, 1); overlay.BackgroundColor3 = Color3.fromRGB(18, 10, 42); overlay.BackgroundTransparency = 1
	overlay.ZIndex = 50; overlay.Parent = gui
	TweenService:Create(overlay, TweenInfo.new(0.25), { BackgroundTransparency = 0.4 }):Play()
	TweenService:Create(blur, TweenInfo.new(0.25), { Size = 16 }):Play()

	-- 1) el huevo entra, brilla y tiembla cada vez más fuerte
	local eggColor = Config.Eggs[eggId] and Config.Eggs[eggId].Color or Color3.new(1, 1, 1)
	local raysEgg = fx_rays(overlay, eggColor, 51, 520)
	raysEgg.Position = center
	local eggV = Icons.Egg(overlay, eggId, { AnchorPoint = Vector2.new(0.5, 0.5), Position = center, Size = UDim2.fromOffset(0, 0), ZIndex = 52 })
	TweenService:Create(eggV, TweenInfo.new(0.4, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(300, 300) }):Play()
	task.wait(0.45)
	local cracks = {}
	for k = 1, 18 do
		local amp = 4 + k * 1.4
		local dur = math.max(0.03, 0.1 - k * 0.004)
		local grow = 300 + k * 3
		TweenService:Create(eggV, TweenInfo.new(dur), { Rotation = (k % 2 == 0) and amp or -amp, Size = UDim2.fromOffset(grow, grow) }):Play()
		if k % 4 == 0 then
			-- grietas de luz sobre el huevo
			local c = Instance.new("Frame")
			c.AnchorPoint = Vector2.new(0.5, 0.5); c.BorderSizePixel = 0; c.ZIndex = 53
			c.Size = UDim2.fromOffset(math.random(60, 110), 5); c.Rotation = math.random(-60, 60)
			c.Position = center + UDim2.fromOffset(math.random(-50, 50), math.random(-60, 60))
			c.BackgroundColor3 = Color3.fromRGB(255, 250, 220); c.Parent = overlay
			round(c, UDim.new(1, 0))
			table.insert(cracks, c)
			fx_burst(overlay, c.Position, { Color3.new(1, 1, 1), eggColor }, 6, 53, 90)
		end
		task.wait(dur)
	end

	-- 2) estalla: destello + onda + chispas
	local flash = Instance.new("Frame")
	flash.Size = UDim2.fromScale(1, 1); flash.BackgroundColor3 = rar.Order >= 3 and rar.Color or Color3.new(1, 1, 1)
	flash.ZIndex = 60; flash.Parent = overlay
	TweenService:Create(flash, TweenInfo.new(0.7), { BackgroundTransparency = 1 }):Play()
	for _, c in ipairs(cracks) do c:Destroy() end
	eggV:Destroy(); raysEgg:Destroy()
	fx_wave(overlay, center, rar.Color, 54)
	fx_burst(overlay, center, { rar.Color, Color3.new(1, 1, 1), Color3.fromRGB(255, 230, 140) }, 40, 55, 320)
	shakeCamera(0.35, rar.Order >= 4 and 1.4 or 0.6)

	-- 3) aparece la mascota con rayos del color de su rareza
	local rays = fx_rays(overlay, rar.Color, 51, 760)
	rays.Position = center
	local petV = Icons.Pet(overlay, petName, { AnchorPoint = Vector2.new(0.5, 0.5), Position = center, Size = UDim2.fromOffset(0, 0), ZIndex = 56 })
	TweenService:Create(petV, TweenInfo.new(0.5, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(330, 330) }):Play()
	local bob = RunService.RenderStepped:Connect(function()
		petV.Position = center + UDim2.fromOffset(0, math.sin(os.clock() * 3) * 8)
	end)
	local nm = label(overlay, { Text = petName, Size = UDim2.fromOffset(520, 70), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.45, 175), ZIndex = 57, TextTransparency = 1 })
	nm.UIStroke.Thickness = 4
	local rl = label(overlay, { Text = def.Rarity:upper() .. "  ·  " .. def.Power .. " poder", TextColor3 = rar.Color, Size = UDim2.fromOffset(520, 38),
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.45, 245), ZIndex = 57, TextTransparency = 1 })
	TweenService:Create(nm, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
	TweenService:Create(rl, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
	-- brillo que recorre el texto de rareza
	local shine = Instance.new("UIGradient")
	shine.Color = ColorSequence.new(Color3.new(1, 1, 1))
	shine.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.45, 0), NumberSequenceKeypoint.new(0.5, 0.7), NumberSequenceKeypoint.new(0.55, 0), NumberSequenceKeypoint.new(1, 0) })
	shine.Offset = Vector2.new(-1, 0); shine.Parent = rl
	TweenService:Create(shine, TweenInfo.new(0.9, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1), { Offset = Vector2.new(1, 0) }):Play()
	if forced then
		label(overlay, { Text = "Garantía activada", TextColor3 = Color3.fromRGB(255, 225, 120), Size = UDim2.fromOffset(400, 30),
			AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.45, 288), ZIndex = 57 })
	end
	if rar.Order >= 3 then fx_confetti(overlay, rar.Order >= 4 and 70 or 35, 58) end
	task.wait(rar.Order >= 4 and 2.8 or 1.9)
	bob:Disconnect()
	TweenService:Create(blur, TweenInfo.new(0.3), { Size = 0 }):Play()
	TweenService:Create(overlay, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
	TweenService:Create(petV, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Size = UDim2.fromOffset(0, 0) }):Play()
	task.wait(0.27)
	overlay:Destroy()
	hatching = false
	if #hatchQueue > 0 then
		local nxt = table.remove(hatchQueue, 1)
		task.spawn(playHatch, table.unpack(nxt))
	end
end

---------------------------------------------------------------- animación de desbloqueo de área
local function playUnlock(dim, zone)
	local wall
	for _, w in ipairs(CollectionService:GetTagged("AreaGate")) do
		if w:GetAttribute("Dimension") == dim and w:GetAttribute("Zone") == zone then wall = w end
	end
	if wall then
		gateAnimating[wall] = true
		if gateGuis[wall] then gateGuis[wall].Enabled = false end
		local info = wall:FindFirstChildOfClass("SurfaceGui"); if info then info.Enabled = false end
		local pp = wall:FindFirstChildOfClass("ProximityPrompt"); if pp then pp.Enabled = false end
		-- destello blanco, chispas 3D y el muro se desvanece hacia arriba
		local att = Instance.new("Attachment"); att.Parent = wall
		local pe = Instance.new("ParticleEmitter")
		pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		pe.Color = ColorSequence.new(Color3.fromRGB(150, 235, 255), Color3.fromRGB(255, 170, 230))
		pe.LightEmission = 1; pe.Size = NumberSequence.new(1.6, 0); pe.Lifetime = NumberRange.new(0.8, 1.6)
		pe.Speed = NumberRange.new(15, 35); pe.SpreadAngle = Vector2.new(180, 180); pe.Rate = 0
		pe.Shape = Enum.ParticleEmitterShape.Box; pe.Parent = att
		pe:Emit(160)
		local origColor, origSize, origCF = wall.Color, wall.Size, wall.CFrame
		wall.Color = Color3.new(1, 1, 1); wall.Transparency = 0.05
		TweenService:Create(wall, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Transparency = 1, Size = Vector3.new(origSize.X * 1.08, 0.2, origSize.Z), CFrame = origCF + Vector3.new(0, origSize.Y / 2, 0) }):Play()
		shakeCamera(0.45, 0.8)
		task.delay(1.6, function()
			wall.Size = origSize; wall.CFrame = origCF; wall.Color = origColor
			att:Destroy()
			gateAnimating[wall] = nil
			updateGates()
		end)
	end
	-- cartel central con rayos y confeti
	local ov = Instance.new("Frame"); ov.Size = UDim2.fromScale(1, 1); ov.BackgroundTransparency = 1; ov.ZIndex = 40; ov.Parent = gui
	local center = UDim2.fromScale(0.5, 0.32)
	local rays = fx_rays(ov, Color3.fromRGB(255, 235, 150), 40, 560)
	rays.Position = center
	local head = label(ov, { Text = "¡ÁREA DESBLOQUEADA!", AnchorPoint = Vector2.new(0.5, 0.5), Position = center - UDim2.fromOffset(0, 48), Size = UDim2.fromOffset(0, 0), TextColor3 = Color3.fromRGB(255, 225, 110), ZIndex = 42 })
	local name = label(ov, { Text = Config.AreaName(dim, zone), AnchorPoint = Vector2.new(0.5, 0.5), Position = center + UDim2.fromOffset(0, 16), Size = UDim2.fromOffset(0, 0), ZIndex = 42 })
	name.UIStroke.Thickness = 5
	gradient(name, Color3.new(1, 1, 1), Color3.fromRGB(190, 225, 255))
	local sub = label(ov, { Text = "Area " .. zone, AnchorPoint = Vector2.new(0.5, 0.5), Position = center + UDim2.fromOffset(0, 72), Size = UDim2.fromOffset(0, 0), TextColor3 = Color3.fromRGB(200, 230, 255), ZIndex = 42 })
	TweenService:Create(head, TweenInfo.new(0.4, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(520, 46) }):Play()
	task.wait(0.08)
	TweenService:Create(name, TweenInfo.new(0.5, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(640, 84) }):Play()
	TweenService:Create(sub, TweenInfo.new(0.5, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(240, 30) }):Play()
	fx_burst(ov, center, CONFETTI, 36, 41, 300)
	fx_confetti(ov, 60, 43)
	task.wait(2.6)
	for _, o in ipairs({ head, name, sub }) do
		TweenService:Create(o, TweenInfo.new(0.35), { TextTransparency = 1 }):Play()
		TweenService:Create(o.UIStroke, TweenInfo.new(0.35), { Transparency = 1 }):Play()
	end
	for _, r in ipairs(rays:GetChildren()) do TweenService:Create(r, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play() end
	task.wait(0.4)
	ov:Destroy()
end
Remotes.AreaUnlocked.OnClientEvent:Connect(function(dim, zone) task.spawn(playUnlock, dim, zone) end)

Remotes.HatchResult.OnClientEvent:Connect(function(eggId, petName, forced)
	if hatching then table.insert(hatchQueue, { eggId, petName, forced })
	else task.spawn(playHatch, eggId, petName, forced) end
end)

---------------------------------------------------------------- menú de teletransporte (estilo PS99, íconos 3D)
local tpButton = Instance.new("TextButton")
tpButton.Name = "TPButton"
tpButton.Text = ""
tpButton.Size = UDim2.fromOffset(86, 86)
tpButton.Position = UDim2.new(0, 22, 0.5, 52)
tpButton.BackgroundColor3 = Color3.fromRGB(150, 110, 255)
tpButton.Parent = gui
round(tpButton, UDim.new(0, 22)); stroke(tpButton, 3, Color3.new(1, 1, 1), 0.3)
gradient(tpButton, Color3.fromRGB(190, 160, 255), Color3.fromRGB(110, 70, 235))
Icons.Make(tpButton, "Teleport", { Size = UDim2.fromOffset(64, 64), Position = UDim2.fromOffset(11, 2) })
label(tpButton, { Text = "TELEPORT", Size = UDim2.new(1, -10, 0, 16), Position = UDim2.fromOffset(5, 66) })

local PANEL_W, PANEL_H = 800, 540
local panel = Instance.new("Frame")
panel.Name = "TeleportPanel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.53)
panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
panel.BackgroundTransparency = 1
panel.Visible = false
panel.ZIndex = 20
panel.Parent = gui
local panelScale = Instance.new("UIScale"); panelScale.Parent = panel

Icons.Make(panel, "Teleport", { Size = UDim2.fromOffset(78, 78), Position = UDim2.fromOffset(28, -16), ZIndex = 26 })
local titleLbl = label(panel, { Text = "Teleport!", Size = UDim2.fromOffset(380, 62), Position = UDim2.fromOffset(110, -6), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 25 })
titleLbl.UIStroke.Thickness = 5
gradient(titleLbl, Color3.new(1, 1, 1), Color3.fromRGB(200, 230, 255))

local body = Instance.new("Frame")
body.Size = UDim2.new(1, -120, 1, -70)
body.Position = UDim2.fromOffset(120, 60)
body.BackgroundColor3 = Color3.fromRGB(252, 252, 255)
body.ZIndex = 20
body.Parent = panel
round(body, UDim.new(0, 24)); stroke(body, 4)

local closeBtn = button(panel, { Text = "", Size = UDim2.fromOffset(58, 58), Position = UDim2.new(1, -46, 0, 34), BackgroundColor3 = Color3.fromRGB(255, 70, 100), ZIndex = 26 })
gradient(closeBtn, Color3.fromRGB(255, 120, 140), Color3.fromRGB(235, 50, 85))
Icons.CloseGlyph(closeBtn)

local tabs = Instance.new("Frame")
tabs.Size = UDim2.new(0, 100, 1, -100)
tabs.Position = UDim2.fromOffset(10, 80)
tabs.BackgroundColor3 = Color3.fromRGB(252, 252, 255)
tabs.ZIndex = 21
tabs.Parent = panel
round(tabs, UDim.new(0, 26)); stroke(tabs, 4)
local tl = Instance.new("UIListLayout"); tl.Padding = UDim.new(0, 4); tl.HorizontalAlignment = Enum.HorizontalAlignment.Center; tl.SortOrder = Enum.SortOrder.LayoutOrder; tl.Parent = tabs
local tp = Instance.new("UIPadding"); tp.PaddingTop = UDim.new(0, 10); tp.Parent = tabs

local content = Instance.new("ScrollingFrame")
content.Size = UDim2.new(1, -24, 1, -86)
content.Position = UDim2.fromOffset(12, 12)
content.BackgroundTransparency = 1
content.BorderSizePixel = 0
content.ScrollBarThickness = 6
content.CanvasSize = UDim2.new()
content.ZIndex = 21
content.Parent = body

local prog = Instance.new("Frame")
prog.Size = UDim2.new(1, -60, 0, 58)
prog.Position = UDim2.new(0, 30, 1, -70)
prog.BackgroundColor3 = Color3.new(1, 1, 1)
prog.ZIndex = 22
prog.Parent = body
round(prog, UDim.new(0, 29)); stroke(prog, 4)
local progTitle = label(prog, { Text = "", Size = UDim2.new(1, -40, 0, 26), Position = UDim2.fromOffset(20, 2), ZIndex = 23 })
local progBg = Instance.new("Frame"); progBg.Size = UDim2.new(1, -80, 0, 14); progBg.Position = UDim2.fromOffset(40, 32)
progBg.BackgroundColor3 = Color3.fromRGB(215, 220, 235); progBg.ZIndex = 23; progBg.Parent = prog
round(progBg, UDim.new(1, 0))
local progFill = Instance.new("Frame"); progFill.Size = UDim2.fromScale(0, 1); progFill.BackgroundColor3 = Color3.new(1, 1, 1); progFill.ZIndex = 24; progFill.Parent = progBg
round(progFill, UDim.new(1, 0))
gradient(progFill, Color3.fromRGB(120, 230, 255), Color3.fromRGB(150, 120, 255), 0)

local selectedDim = "Nexus"
local function currentZone(dim)
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp or not Config.Dimensions[dim] then return nil end
	return Config.ZoneFromPosition(dim, hrp.Position)
end
local function requestTp(dest, zone)
	Remotes.Teleport:FireServer(dest, zone)
	panel.Visible = false
end
local refreshPanel
local function clear(frame)
	for _, c in ipairs(frame:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
end
local function arrow(parent, center, dir)
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(30, 30)
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromOffset(center.X, center.Y)
	holder.Rotation = dir == "right" and 0 or (dir == "left" and 180 or 90)
	holder.ZIndex = 22
	holder.Parent = parent
	local function bar(size, pos, rot)
		local f = Instance.new("Frame"); f.AnchorPoint = Vector2.new(0.5, 0.5); f.Size = size; f.Position = pos; f.Rotation = rot
		f.BackgroundColor3 = INK; f.ZIndex = 22; f.Parent = holder
		round(f, UDim.new(1, 0))
	end
	bar(UDim2.fromOffset(24, 7), UDim2.fromOffset(12, 15), 0)
	bar(UDim2.fromOffset(15, 7), UDim2.fromOffset(21, 10), 40)
	bar(UDim2.fromOffset(15, 7), UDim2.fromOffset(21, 20), -40)
end

local function card(parent, pos, size, idx, name, open, here, features)
	local base = open and Color3.fromRGB(115, 220, 75) or Color3.fromRGB(175, 172, 195)
	local b = button(parent, { Text = "", Size = size, Position = pos, BackgroundColor3 = base, AutoButtonColor = open, ZIndex = 22 })
	gradient(b, base:Lerp(Color3.new(1, 1, 1), 0.2), shade(base, 0.82))
	if here then b.UIStroke.Color = Color3.fromRGB(255, 205, 60); b.UIStroke.Thickness = 5 end
	if not open then
		Icons.Make(b, "Lock", { Size = UDim2.fromOffset(26, 26), Position = UDim2.fromOffset(14, 2), ZIndex = 24 })
	end
	label(b, { Text = "#" .. idx, Size = UDim2.new(1, open and -10 or -44, 0, 24), Position = UDim2.fromOffset(open and 5 or 38, 4), ZIndex = 23 })
	label(b, { Text = name, Size = UDim2.new(1, -10, 0, 28), Position = UDim2.fromOffset(5, 30), ZIndex = 23 })
	if here then Icons.Make(b, "Pin", { Size = UDim2.fromOffset(32, 32), Position = UDim2.new(1, -24, 0, -14), ZIndex = 25 }) end
	local chips = {}
	for _, f in ipairs(features or {}) do
		local mdef = Config.Machines[f]
		if mdef and (mdef.Built or Config.ShowPlannedMachines) then table.insert(chips, mdef) end
	end
	if #chips > 0 then
		local row = Instance.new("Frame")
		row.BackgroundColor3 = Color3.new(1, 1, 1)
		row.AnchorPoint = Vector2.new(0.5, 0)
		row.Size = UDim2.fromOffset(10 + #chips * 30, 30)
		row.Position = UDim2.new(0.5, 0, 1, -33)
		row.ZIndex = 24
		row.Parent = b
		round(row, UDim.new(1, 0)); stroke(row, 3)
		for k, mdef in ipairs(chips) do
			Icons.Make(row, mdef.Icon, { Size = UDim2.fromOffset(28, 28), Position = UDim2.fromOffset(6 + (k - 1) * 30, 1), ZIndex = 25 })
		end
	end
	return b
end

local function tab(order, iconName, text, selected, color, onClick)
	local b = button(tabs, { Text = "", Size = UDim2.fromOffset(84, 64), BackgroundColor3 = selected and color:Lerp(Color3.new(1, 1, 1), 0.55) or Color3.new(1, 1, 1), LayoutOrder = order, ZIndex = 22 })
	b.UIStroke.Thickness = selected and 3 or 0
	Icons.Make(b, iconName, { Size = UDim2.fromOffset(42, 42), Position = UDim2.new(0.5, -21, 0, 0), ZIndex = 23 })
	label(b, { Text = text, Size = UDim2.new(1, -4, 0, 18), Position = UDim2.fromOffset(2, 43), ZIndex = 23 })
	b.MouseButton1Click:Connect(onClick)
end

local function buildTabs()
	clear(tabs)
	tab(0, "Shop", "Lobby", false, Color3.new(1, 1, 1), function() requestTp(selectedDim, 0) end)
	for i, w in ipairs(Config.DimensionList) do
		local playable = Config.Dimensions[w.Id] ~= nil and data and (data.Unlocked[w.Id] or 0) >= 1
		local iconName = playable and (Assets.Icons:FindFirstChild("World_" .. w.Id) and "World_" .. w.Id or "Pin") or "Lock"
		tab(i, iconName, w.Display, w.Id == selectedDim, w.Color, function() selectedDim = w.Id; refreshPanel() end)
	end
	tabs.Size = UDim2.fromOffset(100, 20 + (#Config.DimensionList + 1) * 68)
end

refreshPanel = function()
	if not data then return end
	buildTabs()
	clear(content)
	local info = Config.WorldInfo(selectedDim)
	local d = Config.Dimensions[selectedDim]
	local unlocked = data.Unlocked[selectedDim] or 0
	if not d or unlocked < 1 then
		content.CanvasSize = UDim2.new()
		local prev
		for i, w in ipairs(Config.DimensionList) do
			if w.Id == selectedDim and i > 1 then prev = Config.DimensionList[i - 1] end
		end
		Icons.Make(content, "Lock", { Size = UDim2.fromOffset(110, 110), Position = UDim2.new(0.5, -55, 0, 20), ZIndex = 22 })
		label(content, { Text = info.Display, Size = UDim2.new(1, -40, 0, 56), Position = UDim2.fromOffset(20, 140), TextColor3 = info.Color, ZIndex = 22 })
		label(content, { Text = d and "Bloqueado" or "Próximamente", Size = UDim2.new(1, -40, 0, 36), Position = UDim2.fromOffset(20, 200), TextColor3 = Color3.fromRGB(255, 215, 90), ZIndex = 22 })
		if prev and prev.Vehicle then
			label(content, { Text = "Se llega en el " .. prev.Vehicle .. " al final de " .. prev.Display .. " (requiere Esencia)",
				Size = UDim2.new(1, -60, 0, 28), Position = UDim2.fromOffset(30, 246), ZIndex = 22 })
		end
		progTitle.Text = info.Display
		progFill.Size = UDim2.fromScale(0, 1)
		return
	end
	local here = currentZone(selectedDim)
	local cols, cw, ch, gx, gy = 5, 104, 96, 20, 34
	for idx = 1, d.ZoneCount do
		local r = math.floor((idx - 1) / cols)
		local k = (idx - 1) % cols
		local c = (r % 2 == 0) and k or (cols - 1 - k)
		local x = 10 + c * (cw + gx)
		local y = 12 + r * (ch + gy)
		local area = d.Areas[idx]
		local open = idx <= unlocked
		local built = idx <= d.AreasBuilt
		local b = card(content, UDim2.fromOffset(x, y), UDim2.fromOffset(cw, ch), idx, area.Name, open, here == idx, area.Features)
		b.MouseButton1Click:Connect(function()
			if not open then
				notify(built and ("Desbloquea " .. area.Name .. " primero") or (area.Name .. " llega en el próximo update"), Color3.fromRGB(255, 170, 130))
				return
			end
			if here == idx then return end
			requestTp(selectedDim, idx)
		end)
		if idx < d.ZoneCount then
			if k < cols - 1 then
				local ax = (r % 2 == 0) and (x + cw + gx / 2) or (x - gx / 2)
				arrow(content, Vector2.new(ax, y + ch / 2), (r % 2 == 0) and "right" or "left")
			else
				arrow(content, Vector2.new(x + cw / 2, y + ch + gy / 2), "down")
			end
		end
	end
	content.CanvasSize = UDim2.fromOffset(0, 24 + math.ceil(d.ZoneCount / cols) * (ch + gy))
	local pct = math.floor(unlocked / d.ZoneCount * 100)
	progTitle.Text = "Progreso de " .. info.Display .. ": " .. pct .. "% completado"
	progFill.Size = UDim2.fromScale(unlocked / d.ZoneCount, 1)
	if here then content.CanvasPosition = Vector2.new(0, math.max(0, math.floor((here - 1) / cols) * (ch + gy) - 40)) end
end

local function fitPanel()
	local vp = camera.ViewportSize
	panelScale.Scale = math.clamp(math.min(vp.X / (PANEL_W + 60), vp.Y / (PANEL_H + 60)), 0.45, 1)
end
camera:GetPropertyChangedSignal("ViewportSize"):Connect(fitPanel)
fitPanel()

local function togglePanel(show)
	if show == nil then show = not panel.Visible end
	if show then
		for _, w in ipairs(Config.DimensionList) do if currentZone(w.Id) then selectedDim = w.Id end end
		refreshPanel()
		fitPanel()
		local target = panelScale.Scale
		panelScale.Scale = target * 0.85
		panel.Visible = true
		TweenService:Create(panelScale, TweenInfo.new(0.22, Enum.EasingStyle.Back), { Scale = target }):Play()
	else
		panel.Visible = false
	end
end
tpButton.MouseButton1Click:Connect(function() togglePanel() end)
closeBtn.MouseButton1Click:Connect(function() togglePanel(false) end)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.T then togglePanel() end
end)

---------------------------------------------------------------- cartel de área al entrar
local areaBanner = label(gui, { Text = "", Size = UDim2.fromOffset(700, 64), Position = UDim2.new(0.5, -350, 0, 20), TextTransparency = 1 })
areaBanner.UIStroke.Thickness = 4
areaBanner.UIStroke.Transparency = 1
gradient(areaBanner, Color3.new(1, 1, 1), Color3.fromRGB(210, 230, 255))
local lastPlace
local function showBanner(text)
	areaBanner.Text = text
	areaBanner.TextTransparency = 0
	areaBanner.UIStroke.Transparency = 0
	areaBanner.Position = UDim2.new(0.5, -350, 0, 0)
	TweenService:Create(areaBanner, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Position = UDim2.new(0.5, -350, 0, 20) }):Play()
	local stamp = os.clock()
	areaBanner:SetAttribute("Stamp", stamp)
	task.delay(2.6, function()
		if areaBanner:GetAttribute("Stamp") ~= stamp then return end
		TweenService:Create(areaBanner, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
		TweenService:Create(areaBanner.UIStroke, TweenInfo.new(0.5), { Transparency = 1 }):Play()
	end)
end
task.spawn(function()
	while true do
		task.wait(0.4)
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local place
			for dim, d in pairs(Config.Dimensions) do
				local z = Config.ZoneFromPosition(dim, hrp.Position)
				if z then
					place = dim .. ":" .. z
					if place ~= lastPlace then showBanner("Area " .. z .. " · " .. Config.AreaName(dim, z)) end
				elseif (hrp.Position - d.LobbyCenter).Magnitude < 85 then
					place = dim .. ":lobby"
					if place ~= lastPlace then showBanner(Config.WorldInfo(dim).Lobby) end
				end
			end
			lastPlace = place or lastPlace
		end
	end
end)

---------------------------------------------------------------- sync
Remotes.DataSync.OnClientEvent:Connect(function(newData)
	local first = data == nil
	data = newData
	if first then displayed = curAmount(currentWorld()) end
	updatePets()
	updateGates()
	updateMeditation()
	if panel.Visible then refreshPanel() end
end)
