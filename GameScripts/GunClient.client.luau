-- GunClient.client.luau
-- Handles camera aim, ADS, first-person presentation, recoil, and HUD.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local tool = script.Parent
local fireEvent = tool:WaitForChild("FireEvent")
local shotFeedback = tool:WaitForChild("ShotFeedback")

local HIP_FOV = 70
local ADS_FOV = 55
local ADS_TRANSITION_TIME = 0.2
local MOUSE_SENSITIVITY_MULTIPLIER = 0.55
local RANGE = 300

-- The viewmodel aligns its RearSight to the camera center in ADS.
local HIP_OFFSET = CFrame.new(0.72, -0.65, -1.35)
local ADS_SIGHT_DEPTH = 1.15

local equipped = false
local aiming = false
local aimAlpha = 0
local recoil = 0
local originalFov = HIP_FOV
local originalMouseSensitivity = 1
local viewmodel: Model? = nil
local viewmodelParts: { [string]: BasePart } = {}
local localPartCFrames: { [string]: CFrame } = {}
local rearSightLocal: CFrame? = nil
local muzzleLocalPosition = Vector3.zero
local hud: ScreenGui? = nil
local loggedClick = false
local loggedRightClick = false

print("[GunClient] GunClient LocalScript is running for " .. player.Name)

local function makeHud()
	local playerGui = player:WaitForChild("PlayerGui")
	local oldHud = playerGui:FindFirstChild("PistolHUD")
	if oldHud then
		oldHud:Destroy()
	end

	local newHud = Instance.new("ScreenGui")
	newHud.Name = "PistolHUD"
	newHud.IgnoreGuiInset = true
	newHud.ResetOnSpawn = false
	newHud.Parent = playerGui

	local crosshair = Instance.new("Frame")
	crosshair.Name = "Crosshair"
	crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
	crosshair.Position = UDim2.fromScale(0.5, 0.5)
	crosshair.Size = UDim2.fromOffset(4, 4)
	crosshair.BackgroundColor3 = Color3.new(1, 1, 1)
	crosshair.BorderSizePixel = 0
	crosshair.Parent = newHud

	local hitmarker = Instance.new("TextLabel")
	hitmarker.Name = "Hitmarker"
	hitmarker.AnchorPoint = Vector2.new(0.5, 0.5)
	hitmarker.Position = UDim2.fromScale(0.5, 0.5)
	hitmarker.Size = UDim2.fromOffset(42, 42)
	hitmarker.BackgroundTransparency = 1
	hitmarker.Font = Enum.Font.GothamBold
	hitmarker.Text = "X"
	hitmarker.TextColor3 = Color3.new(1, 1, 1)
	hitmarker.TextScaled = true
	hitmarker.TextTransparency = 1
	hitmarker.Parent = newHud

	hud = newHud
	return newHud
end

local function showHitmarker()
	if not hud then
		return
	end
	local hitmarker = hud:FindFirstChild("Hitmarker")
	if not hitmarker or not hitmarker:IsA("TextLabel") then
		return
	end

	hitmarker.TextTransparency = 0
	TweenService:Create(hitmarker, TweenInfo.new(0.16), { TextTransparency = 1 }):Play()
end

local function setCrosshairVisible(visible: boolean)
	if not hud then
		return
	end
	local crosshair = hud:FindFirstChild("Crosshair")
	if crosshair and crosshair:IsA("Frame") then
		crosshair.Visible = visible
	end
end

local function isFirstPerson(camera: Camera): boolean
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	return head ~= nil and (camera.CFrame.Position - head.Position).Magnitude <= 1.6
end

local function getAimRay(camera: Camera): (Vector3, Vector3)
	local viewport = camera.ViewportSize
	local screenPosition: Vector2
	if isFirstPerson(camera) then
		screenPosition = Vector2.new(viewport.X / 2, viewport.Y / 2)
		local ray = camera:ViewportPointToRay(screenPosition.X, screenPosition.Y)
		return ray.Origin, ray.Direction.Unit
	else
		screenPosition = UserInputService:GetMouseLocation()
		local ray = camera:ScreenPointToRay(screenPosition.X, screenPosition.Y)
		return ray.Origin, ray.Direction.Unit
	end
end

local function destroyViewmodel()
	if viewmodel then
		viewmodel:Destroy()
		viewmodel = nil
	end
	table.clear(viewmodelParts)
	table.clear(localPartCFrames)
	rearSightLocal = nil
end

local function createViewmodel()
	destroyViewmodel()
	local camera = workspace.CurrentCamera
	local oldViewmodel = camera and camera:FindFirstChild("PistolViewmodel")
	if oldViewmodel then
		oldViewmodel:Destroy()
	end

	local sourceHandle = tool:FindFirstChild("Handle")
	if not sourceHandle or not sourceHandle:IsA("BasePart") then
		return
	end

	local newViewmodel = Instance.new("Model")
	newViewmodel.Name = "PistolViewmodel"
	newViewmodel.Parent = workspace.CurrentCamera
	viewmodel = newViewmodel

	for _, source in tool:GetChildren() do
		if source:IsA("BasePart") then
			-- Build a fresh visual-only Part. Nothing from the real Tool is cloned,
			-- so no WeldConstraint, Motor6D, Attachment, or physics state can leak into the camera.
			local copy = Instance.new("Part")
			copy.Name = source.Name
			copy.Size = source.Size
			if source:IsA("Part") then
				copy.Shape = source.Shape
			end
			copy.Color = source.Color
			copy.Material = source.Material
			copy.Transparency = source.Transparency
			copy.Anchored = true
			copy.CanCollide = false
			copy.CanTouch = false
			copy.CanQuery = false
			copy.Massless = true
			copy.LocalTransparencyModifier = 0
			copy.Parent = newViewmodel
			viewmodelParts[source.Name] = copy
			localPartCFrames[source.Name] = sourceHandle.CFrame:ToObjectSpace(source.CFrame)
		end
	end

	local rearSight = tool:FindFirstChild("RearSight")
	if rearSight and rearSight:IsA("BasePart") then
		rearSightLocal = localPartCFrames[rearSight.Name]
	end

	local muzzle = sourceHandle:FindFirstChild("Muzzle")
	if muzzle and muzzle:IsA("Attachment") then
		muzzleLocalPosition = muzzle.Position
	end
end

local function setRealToolVisibility(visible: boolean)
	for _, object in tool:GetChildren() do
		if object:IsA("BasePart") then
			object.LocalTransparencyModifier = visible and 0 or 1
		end
	end
end

local function setViewmodelCFrame(handleCFrame: CFrame)
	if not viewmodel then
		return
	end
	for name, part in viewmodelParts do
		local localCFrame = localPartCFrames[name]
		if localCFrame then
			part.CFrame = handleCFrame * localCFrame
		end
	end
end

local function getHipHandleCFrame(camera: Camera): CFrame
	return camera.CFrame * HIP_OFFSET * CFrame.Angles(math.rad(-recoil), 0, 0)
end

local function getAdsHandleCFrame(camera: Camera): CFrame
	if not rearSightLocal then
		return getHipHandleCFrame(camera)
	end

	local desiredRearSight = camera.CFrame * CFrame.new(0, 0, -ADS_SIGHT_DEPTH)
	return desiredRearSight * rearSightLocal:Inverse() * CFrame.Angles(math.rad(-recoil), 0, 0)
end

local function updatePresentation(deltaTime: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local targetAlpha = aiming and equipped and 1 or 0
	local transitionSpeed = math.min(deltaTime / ADS_TRANSITION_TIME, 1)
	aimAlpha += (targetAlpha - aimAlpha) * transitionSpeed
	recoil = math.max(0, recoil - deltaTime * 10)

	local targetFov = aiming and equipped and ADS_FOV or originalFov
	camera.FieldOfView += (targetFov - camera.FieldOfView) * transitionSpeed

	local firstPerson = equipped and isFirstPerson(camera)
	if viewmodel then
		if firstPerson then
			setRealToolVisibility(false)
			local hipCFrame = getHipHandleCFrame(camera)
			local adsCFrame = getAdsHandleCFrame(camera)
			setViewmodelCFrame(hipCFrame:Lerp(adsCFrame, aimAlpha))
			for _, part in viewmodelParts do
				part.LocalTransparencyModifier = 0
			end
		else
			setRealToolVisibility(true)
			for _, part in viewmodelParts do
				part.LocalTransparencyModifier = 1
			end
		end
	end

	setCrosshairVisible(not aiming or aimAlpha < 0.8)
end

local function setAiming(value: boolean)
	if value and not equipped then
		return
	end
	aiming = value
	if value then
		pcall(function()
			UserInputService.MouseDeltaSensitivity = originalMouseSensitivity * MOUSE_SENSITIVITY_MULTIPLIER
		end)
	else
		pcall(function()
			UserInputService.MouseDeltaSensitivity = originalMouseSensitivity
		end)
	end
end

local function fire()
	if not equipped then
		return
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local cameraOrigin, cameraDirection = getAimRay(camera)
	local muzzlePosition = cameraOrigin
	local muzzle = tool:FindFirstChild("Handle") and tool.Handle:FindFirstChild("Muzzle")
	if muzzle and muzzle:IsA("Attachment") then
		muzzlePosition = muzzle.WorldPosition
	end

	if isFirstPerson(camera) and viewmodel then
		local viewmodelHandle = viewmodelParts.Handle
		if viewmodelHandle then
			local handleCFrame = viewmodelHandle.CFrame
			muzzlePosition = (handleCFrame * CFrame.new(muzzleLocalPosition)).Position
		end
	end

	recoil = 2.2
	if not loggedClick then
		loggedClick = true
		print("[GunClient] Left click detected; sending FireEvent to server.")
	end
	fireEvent:FireServer(cameraOrigin, cameraDirection, muzzlePosition)
end

tool.Equipped:Connect(function()
	equipped = true
	aiming = false
	local camera = workspace.CurrentCamera
	if camera then
		originalFov = camera.FieldOfView
	end
	pcall(function()
		originalMouseSensitivity = UserInputService.MouseDeltaSensitivity
	end)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	print(("[GunClient] Tool Equipped. Humanoid=%s State=%s PlatformStand=%s Sit=%s"):format(
		tostring(humanoid ~= nil),
		humanoid and tostring(humanoid:GetState()) or "none",
		humanoid and tostring(humanoid.PlatformStand) or "none",
		humanoid and tostring(humanoid.Sit) or "none"
	))
	makeHud()
	createViewmodel()
end)

tool.Unequipped:Connect(function()
	equipped = false
	aiming = false
	setAiming(false)
	destroyViewmodel()
	setRealToolVisibility(true)
	local camera = workspace.CurrentCamera
	if camera then
		camera.FieldOfView = originalFov
	end
	setCrosshairVisible(false)
end)

tool.Activated:Connect(fire)

UserInputService.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		if not loggedRightClick then
			loggedRightClick = true
			print("[GunClient] Right click detected.")
		end
		setAiming(true)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		setAiming(false)
	end
end)

shotFeedback.OnClientEvent:Connect(function(didDamage: boolean)
	if didDamage then
		showHitmarker()
	end
end)

RunService.RenderStepped:Connect(updatePresentation)

local function connectDeathReset(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid then
		humanoid.Died:Connect(function()
			aiming = false
			equipped = false
			setAiming(false)
			destroyViewmodel()
			local camera = workspace.CurrentCamera
			if camera then
				camera.FieldOfView = originalFov
			end
		end)
	end
end

player.CharacterAdded:Connect(connectDeathReset)
if player.Character then
	connectDeathReset(player.Character)
end
