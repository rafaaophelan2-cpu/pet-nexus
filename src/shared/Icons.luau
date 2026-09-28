-- Pet Nexus: íconos 3D renderizados en ViewportFrame (reemplazan emojis). Uso:
--   Icons.Make(parent, "AngelCoin", { Size = UDim2.fromOffset(48,48), Position = ..., ZIndex = ... })
--   Icons.Pet(parent, "Sprout", props)   Icons.Egg(parent, "NexusEgg", props)
-- Orientación por ícono en Icons.Yaw (grados) si el modelo no mira a la cámara.
local RS = game:GetService("ReplicatedStorage")
local lib = RS:WaitForChild("PetNexusAssets")

local Icons = {}
Icons.DefaultYaw = 180 -- los modelos generados miran a +Z
Icons.Yaw = { AngelCoin = 180, Power = 180, Rebirth = 270 }
Icons.Pitch = { Luck = -75 } -- el trébol viene acostado
Icons.Zoom = { World_Nexus = 1.05, Meditation = 1.1 }

local function find(folder, name)
	local f = lib:FindFirstChild(folder)
	return f and f:FindFirstChild(name)
end

local function render(parent, model, props, yaw, pitch, zoom)
	local vf = Instance.new("ViewportFrame")
	vf.BackgroundTransparency = 1
	vf.Ambient = Color3.fromRGB(215, 210, 235)
	vf.LightColor = Color3.fromRGB(255, 255, 255)
	vf.LightDirection = Vector3.new(-0.4, -1, -0.8)
	vf.Size = UDim2.fromOffset(48, 48)
	for k, v in pairs(props or {}) do vf[k] = v end
	if not model then vf.Parent = parent; return vf end
	local m = model:Clone()
	m:PivotTo(CFrame.Angles(math.rad(pitch or 0), math.rad(yaw or 0), 0))
	m.Parent = vf
	local cf, sz = m:GetBoundingBox()
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	local radius = math.max(sz.X, sz.Y, sz.Z) * 0.5
	local dist = radius / math.tan(math.rad(cam.FieldOfView / 2)) * (zoom or 1.12)
	cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(0, radius * 0.18, -dist), cf.Position)
	cam.Parent = vf
	vf.CurrentCamera = cam
	vf:SetAttribute("IconCam", cam.CFrame)
	vf:SetAttribute("IconFov", cam.FieldOfView)
	vf.Parent = parent
	return vf
end

function Icons.Make(parent, name, props)
	local model = find("Icons", name)
	return render(parent, model, props, Icons.Yaw[name] or Icons.DefaultYaw, Icons.Pitch[name], Icons.Zoom[name])
end

function Icons.Pet(parent, name, props)
	return render(parent, find("Pets", name), props, Icons.Yaw["Pet_" .. name] or Icons.DefaultYaw, 0, 1.05)
end

function Icons.Egg(parent, name, props)
	return render(parent, find("Eggs", name), props, Icons.Yaw["Egg_" .. name] or Icons.DefaultYaw, 0, 1.05)
end

-- Símbolo vectorial de cerrar (X) sin imágenes
function Icons.CloseGlyph(parent, color)
	for _, rot in ipairs({ 45, -45 }) do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.fromScale(0.62, 0.16)
		bar.Rotation = rot
		bar.BackgroundColor3 = color or Color3.new(1, 1, 1)
		bar.ZIndex = (parent.ZIndex or 1) + 1
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = bar
		local s = Instance.new("UIStroke"); s.Thickness = 2; s.Parent = bar
		bar.Parent = parent
	end
end

-- Las Camera no se replican: los ViewportFrame creados en el servidor llegan sin cámara.
-- El cliente llama a Icons.RepairReplicated(workspace) para recrearlas desde el atributo IconCam.
local function repair(vf)
	if not vf:IsA("ViewportFrame") then return end
	local cf = vf:GetAttribute("IconCam")
	if not cf or (vf.CurrentCamera and vf.CurrentCamera.Parent == vf) then return end
	local cam = Instance.new("Camera")
	cam.FieldOfView = vf:GetAttribute("IconFov") or 30
	cam.CFrame = cf
	cam.Parent = vf
	vf.CurrentCamera = cam
end
function Icons.RepairReplicated(root)
	for _, d in ipairs(root:GetDescendants()) do repair(d) end
	root.DescendantAdded:Connect(function(d)
		if d:IsA("ViewportFrame") then task.defer(repair, d) end
	end)
end

return Icons
