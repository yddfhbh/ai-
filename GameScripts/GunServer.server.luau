-- GunServer.server.luau
-- Builds a basic pistol and validates every shot on the server.

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local TOOL_NAME = "BasicPistol"
local DAMAGE = 25
local FIRE_INTERVAL = 0.3
local RANGE = 300

local clientTemplate = script.Parent:WaitForChild("GunClient")
local lastShotAt: { [Player]: number } = {}
local loggedShotFor: { [Player]: boolean } = {}

print("[GunServer] GunServer.server.luau started.")

local function makePart(parent: Instance, name: string, size: Vector3, color: Color3, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.CastShadow = false
	part.Parent = parent
	return part
end

local function weldToHandle(handle: BasePart, part: BasePart, offset: CFrame)
	part.CFrame = handle.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = part
	weld.Parent = handle
end

local function configureToolPhysics(tool: Tool)
	local handle = tool:FindFirstChild("Handle")
	for _, object in tool:GetDescendants() do
		if object:IsA("BasePart") then
			object.Anchored = false
			object.CanCollide = false
			object.CanTouch = false
			object.Massless = true
		elseif object:IsA("WeldConstraint") then
			if not handle or object.Part0 ~= handle or not object.Part1 or object.Part1.Parent ~= tool then
				warn("[GunServer] Unexpected gun WeldConstraint: " .. object:GetFullName())
			end
		end
	end

	if handle and handle:IsA("BasePart") then
		-- The server raycast uses the muzzle attachment; the handle itself is not a hit target.
		handle.CanQuery = true
		print(("[GunServer] Handle physics Anchored=%s CanCollide=%s CanTouch=%s Massless=%s"):format(
			tostring(handle.Anchored),
			tostring(handle.CanCollide),
			tostring(handle.CanTouch),
			tostring(handle.Massless)
		))
	end
end

local function createPistol(): Tool
	local tool = Instance.new("Tool")
	tool.Name = TOOL_NAME
	tool.ToolTip = "무제한 탄약 권총"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.Grip = CFrame.new(0, -0.25, -0.6)

	local handle = makePart(tool, "Handle", Vector3.new(0.45, 0.8, 1.5), Color3.fromRGB(35, 35, 40), Enum.Material.Metal)
	handle.CanQuery = true

	local barrel = makePart(tool, "Barrel", Vector3.new(0.28, 0.28, 1.5), Color3.fromRGB(15, 15, 18), Enum.Material.Metal)
	weldToHandle(handle, barrel, CFrame.new(0, 0.2, -1.2))

	local grip = makePart(tool, "Grip", Vector3.new(0.4, 1.1, 0.5), Color3.fromRGB(20, 20, 25), Enum.Material.SmoothPlastic)
	weldToHandle(handle, grip, CFrame.new(0, -0.75, 0.2) * CFrame.Angles(math.rad(-12), 0, 0))

	local rearSight = makePart(tool, "RearSight", Vector3.new(0.5, 0.15, 0.15), Color3.fromRGB(220, 220, 220), Enum.Material.Metal)
	weldToHandle(handle, rearSight, CFrame.new(0, 0.42, -0.35))

	local frontSight = makePart(tool, "FrontSight", Vector3.new(0.12, 0.22, 0.12), Color3.fromRGB(255, 240, 120), Enum.Material.Metal)
	weldToHandle(handle, frontSight, CFrame.new(0, 0.42, -1.85))

	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = Vector3.new(0, 0.2, -1.95)
	muzzle.Parent = handle

	local fireEvent = Instance.new("RemoteEvent")
	fireEvent.Name = "FireEvent"
	fireEvent.Parent = tool

	local shotFeedback = Instance.new("RemoteEvent")
	shotFeedback.Name = "ShotFeedback"
	shotFeedback.Parent = tool

	local client = clientTemplate:Clone()
	client.Name = "GunClient"
	client.Parent = tool
	configureToolPhysics(tool)
	tool.Equipped:Connect(function()
		local character = tool.Parent
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local rightGrip = character and character:FindFirstChild("RightGrip", true)
		print(("[GunServer] Equipped parent=%s humanoid=%s root=%s RightGrip=%s"):format(
			character and character.Name or "none",
			tostring(humanoid ~= nil),
			tostring(root ~= nil),
			tostring(rightGrip ~= nil)
		))
	end)

	return tool
end

local function createTracer(startPosition: Vector3, endPosition: Vector3)
	local distance = (endPosition - startPosition).Magnitude
	if distance <= 0 then
		return
	end

	local tracer = Instance.new("Part")
	tracer.Name = "BulletTracer"
	tracer.Anchored = true
	tracer.CanCollide = false
	tracer.CanTouch = false
	tracer.CanQuery = false
	tracer.Material = Enum.Material.Neon
	tracer.Color = Color3.fromRGB(255, 240, 120)
	tracer.Size = Vector3.new(0.08, 0.08, distance)
	tracer.CFrame = CFrame.lookAt((startPosition + endPosition) / 2, endPosition)
	tracer.Parent = workspace
	Debris:AddItem(tracer, 0.08)
end

local function createMuzzleFlash(position: Vector3)
	local flash = Instance.new("Part")
	flash.Name = "MuzzleFlash"
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.new(0.45, 0.45, 0.45)
	flash.Position = position
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanTouch = false
	flash.CanQuery = false
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 180, 35)
	flash.Parent = workspace

	local light = Instance.new("PointLight")
	light.Color = flash.Color
	light.Brightness = 4
	light.Range = 8
	light.Parent = flash
	Debris:AddItem(flash, 0.06)
end

local function getHumanoidFromHit(instance: Instance): Humanoid?
	local model = instance:FindFirstAncestorOfClass("Model")
	if not model then
		return nil
	end
	return model:FindFirstChildOfClass("Humanoid")
end

local function handleShot(
	player: Player,
	tool: Tool,
	cameraOrigin: Vector3,
	cameraDirection: Vector3,
	clientMuzzlePosition: Vector3
)
	if typeof(cameraOrigin) ~= "Vector3"
		or typeof(cameraDirection) ~= "Vector3"
		or typeof(clientMuzzlePosition) ~= "Vector3" then
		return
	end

	local character = player.Character
	if not character or tool.Parent ~= character then
		return
	end
	if not loggedShotFor[player] then
		loggedShotFor[player] = true
		print("[GunServer] First FireEvent received from " .. player.Name)
	end

	local now = os.clock()
	if now - (lastShotAt[player] or 0) < FIRE_INTERVAL then
		return
	end
	lastShotAt[player] = now

	local handle = tool:FindFirstChild("Handle")
	local muzzle = handle and handle:FindFirstChild("Muzzle")
	if not handle or not muzzle or not muzzle:IsA("Attachment") then
		return
	end

	local serverMuzzlePosition = muzzle.WorldPosition
	if (clientMuzzlePosition - serverMuzzlePosition).Magnitude > 3 then
		return
	end
	if (cameraOrigin - character:GetPivot().Position).Magnitude > 35 then
		return
	end
	if cameraDirection.Magnitude < 0.9 or cameraDirection.Magnitude > 1.1 then
		return
	end
	cameraDirection = cameraDirection.Unit

	local origin = clientMuzzlePosition
	local cameraParams = RaycastParams.new()
	cameraParams.FilterType = Enum.RaycastFilterType.Exclude
	cameraParams.FilterDescendantsInstances = { character }
	cameraParams.IgnoreWater = true

	-- First find what the camera is aiming at. This removes camera-to-muzzle parallax.
	local cameraRay = workspace:Raycast(cameraOrigin, cameraDirection * RANGE, cameraParams)
	local aimPoint = cameraRay and cameraRay.Position or (cameraOrigin + cameraDirection * RANGE)
	local direction = aimPoint - origin
	if direction.Magnitude < 0.01 then
		return
	end
	local rayDirection = direction.Unit * math.min(direction.Magnitude, RANGE)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true

	local result = workspace:Raycast(origin, rayDirection, params)
	local hitPosition = result and result.Position or (origin + rayDirection)
	createTracer(origin, hitPosition)
	createMuzzleFlash(origin)

	local didDamage = false
	if result then
		local humanoid = getHumanoidFromHit(result.Instance)
		if humanoid and humanoid.Health > 0 then
			humanoid:TakeDamage(DAMAGE)
			didDamage = true
		end
	end

	local shotFeedback = tool:FindFirstChild("ShotFeedback")
	if shotFeedback and shotFeedback:IsA("RemoteEvent") then
		shotFeedback:FireClient(player, didDamage)
	end
end

local function givePistol(player: Player)
	local backpack = player:WaitForChild("Backpack")
	if backpack:FindFirstChild(TOOL_NAME) or (player.Character and player.Character:FindFirstChild(TOOL_NAME)) then
		return
	end

	local tool = createPistol()
	local fireEvent = tool:FindFirstChild("FireEvent")
	if fireEvent and fireEvent:IsA("RemoteEvent") then
		fireEvent.OnServerEvent:Connect(function(shooter, cameraOrigin, cameraDirection, clientMuzzlePosition)
			handleShot(shooter, tool, cameraOrigin, cameraDirection, clientMuzzlePosition)
		end)
	end
	tool.Parent = backpack
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		task.wait(0.2)
		givePistol(player)
	end)
	if player.Character then
		givePistol(player)
	end
end)

for _, player in Players:GetPlayers() do
	if player.Character then
		givePistol(player)
	else
		player.CharacterAdded:Connect(function()
			task.wait(0.2)
			givePistol(player)
		end)
	end
end

Players.PlayerRemoving:Connect(function(player)
	lastShotAt[player] = nil
	loggedShotFor[player] = nil
end)
