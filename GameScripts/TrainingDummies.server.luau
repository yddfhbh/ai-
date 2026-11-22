-- TrainingDummies.server.luau
-- Creates and audits three visible R15 training targets.

local Players = game:GetService("Players")
local CoinService = require(script.Parent:WaitForChild("CoinService"))

local DUMMY_COUNT = 3
local DUMMY_HEALTH = 100
local RESPAWN_DELAY = 5
local DUMMY_FOLDER_NAME = "TrainingDummies"

local R15_BODY_PARTS = {
	"Head",
	"UpperTorso",
	"LowerTorso",
	"LeftUpperArm",
	"LeftLowerArm",
	"LeftHand",
	"RightUpperArm",
	"RightLowerArm",
	"RightHand",
	"LeftUpperLeg",
	"LeftLowerLeg",
	"LeftFoot",
	"RightUpperLeg",
	"RightLowerLeg",
	"RightFoot",
}

local oldFolder = workspace:FindFirstChild(DUMMY_FOLDER_NAME)
if oldFolder then
	oldFolder:Destroy()
end

local dummyFolder = Instance.new("Folder")
dummyFolder.Name = DUMMY_FOLDER_NAME
dummyFolder.Parent = workspace

local function applyDummyColors(description: HumanoidDescription)
	-- Keep the valid R15 body asset IDs, but make the target easy to see.
	local ok, errorMessage = pcall(function()
		description.HeadColor = BrickColor.new("Bright yellow")
		description.TorsoColor = BrickColor.new("Bright blue")
		description.LeftArmColor = BrickColor.new("Bright blue")
		description.RightArmColor = BrickColor.new("Bright blue")
		description.LeftLegColor = BrickColor.new("Dark green")
		description.RightLegColor = BrickColor.new("Dark green")
	end)
	if not ok then
		warn("[TrainingDummies] Could not apply diagnostic body colors: " .. tostring(errorMessage))
	end
end

local function getDummyDescription(): HumanoidDescription
	local player = Players:GetPlayers()[1]
	if not player then
		player = Players.PlayerAdded:Wait()
	end

	local character = player.Character or player.CharacterAdded:Wait()
	local playerHumanoid = character:FindFirstChildOfClass("Humanoid")
	if playerHumanoid then
		local ok, description = pcall(function()
			return playerHumanoid:GetAppliedDescription()
		end)
		if ok and description then
			applyDummyColors(description)
			print("[TrainingDummies] Using the player's applied HumanoidDescription for R15 body assets.")
			return description
		end
	end

	local ok, description = pcall(function()
		return Players:GetHumanoidDescriptionFromUserIdAsync(1)
	end)
	if ok and description then
		applyDummyColors(description)
		print("[TrainingDummies] Using Roblox user 1 HumanoidDescription as fallback.")
		return description
	end

	warn("[TrainingDummies] Could not load an avatar description; using an empty description. R15 body assets may be unavailable.")
	local emptyDescription = Instance.new("HumanoidDescription")
	applyDummyColors(emptyDescription)
	return emptyDescription
end

local function getPracticeCFrames(): { CFrame }
	local spawnLocation = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local spawnCFrame = spawnLocation and spawnLocation.CFrame or CFrame.new(0, 0, 0)
	local spawnPosition = spawnLocation and spawnLocation.Position or Vector3.new(0, 0, 0)
	local forward = spawnCFrame.LookVector
	local right = spawnCFrame.RightVector
	local center = spawnPosition + forward * 18

	local function faceSpawn(offset: number): CFrame
		local location = center + right * offset
		local target = Vector3.new(spawnPosition.X, location.Y, spawnPosition.Z)
		return CFrame.lookAt(location, target)
	end

	return {
		faceSpawn(-8),
		faceSpawn(0),
		faceSpawn(8),
	}
end

local function alignFeetToGround(model: Model, groundY: number)
	local boundsCFrame, boundsSize = model:GetBoundingBox()
	local lowestPoint = boundsCFrame.Position.Y - boundsSize.Y / 2
	local correction = groundY - lowestPoint + 0.05
	model:PivotTo(model:GetPivot() + Vector3.new(0, correction, 0))
end

local function auditAndPrepareModel(model: Model, index: number, humanoid: Humanoid, root: BasePart)
	local partCount = 0
	local motorCount = 0
	local missingParts = {}

	for _, object in model:GetDescendants() do
		if object:IsA("BasePart") then
			partCount += 1
			if object.Transparency > 0 or object.LocalTransparencyModifier > 0 then
				warn(("[TrainingDummies][%d] Transparency before fix: %s T=%.2f LTM=%.2f"):format(
					index,
					object:GetFullName(),
					object.Transparency,
					object.LocalTransparencyModifier
				))
			end
			object.Transparency = 0
			object.LocalTransparencyModifier = 0
			object.CanQuery = true
			object.CanCollide = false
		elseif object:IsA("Motor6D") then
			motorCount += 1
		end
	end

	for _, partName in R15_BODY_PARTS do
		local part = model:FindFirstChild(partName, true)
		if not part or not part:IsA("BasePart") then
			table.insert(missingParts, partName)
			warn(("[TrainingDummies][%d] MISSING R15 body part: %s"):format(index, partName))
		else
			if partName == "Head" then
				part.Color = Color3.fromRGB(255, 221, 80)
			elseif string.find(partName, "Torso") or string.find(partName, "Arm") or string.find(partName, "Hand") then
				part.Color = Color3.fromRGB(60, 145, 255)
			else
				part.Color = Color3.fromRGB(70, 190, 90)
			end
			if part.Size.Magnitude < 0.1 then
				warn(("[TrainingDummies][%d] Suspicious zero-size body part: %s Size=%s"):format(index, partName, tostring(part.Size)))
			end
			print(("[TrainingDummies][%d] %s present Pos=%s T=%.2f LTM=%.2f"):format(
				index,
				partName,
				tostring(part.Position),
				part.Transparency,
				part.LocalTransparencyModifier
			))
		end
	end

	print(("[TrainingDummies][%d] parts=%d bodyParts=%d motors=%d rig=%s root=%s"):format(
		index,
		partCount,
		#R15_BODY_PARTS - #missingParts,
		motorCount,
		tostring(humanoid.RigType),
		tostring(root.Position)
	))

	if #missingParts > 0 then
		warn(("[TrainingDummies][%d] R15 validation failed; missing: %s"):format(index, table.concat(missingParts, ", ")))
	end
	if motorCount < 15 then
		warn(("[TrainingDummies][%d] Expected at least 15 Motor6D joints, found %d."):format(index, motorCount))
	end
	if partCount < 16 then
		warn(("[TrainingDummies][%d] Expected body parts plus HumanoidRootPart, found only %d BaseParts."):format(index, partCount))
	end

	-- Keep the complete Motor6D rig intact. Anchoring only the root keeps the model still.
	root.Anchored = true
	root.CanCollide = false
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.AutoRotate = false
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
end

local function addHealthDisplay(model: Model, humanoid: Humanoid)
	local head = model:WaitForChild("Head", 10)
	if not head or not head:IsA("BasePart") then
		warn("[TrainingDummies] Cannot add health display because Head is missing in " .. model.Name)
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DummyHealthDisplay"
	billboard.Adornee = head
	billboard.AlwaysOnTop = true
	billboard.Size = UDim2.fromOffset(180, 55)
	billboard.StudsOffset = Vector3.new(0, 3.5, 0)
	billboard.Parent = head

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.new(1, 0, 0, 25)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Text = utf8.char(0xC5F0, 0xC2B5, 0xC6A9, 0xB354, 0xBBF8)
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextScaled = true
	nameLabel.TextStrokeTransparency = 0.25
	nameLabel.Parent = billboard

	local barBackground = Instance.new("Frame")
	barBackground.Name = "HealthBarBackground"
	barBackground.Position = UDim2.fromOffset(10, 30)
	barBackground.Size = UDim2.new(1, -20, 0, 16)
	barBackground.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
	barBackground.BorderSizePixel = 0
	barBackground.Parent = billboard

	local barFill = Instance.new("Frame")
	barFill.Name = "HealthBarFill"
	barFill.Size = UDim2.fromScale(1, 1)
	barFill.BackgroundColor3 = Color3.fromRGB(60, 220, 75)
	barFill.BorderSizePixel = 0
	barFill.Parent = barBackground

	local function updateHealthBar(health: number)
		local ratio = math.clamp(health / DUMMY_HEALTH, 0, 1)
		barFill.Size = UDim2.fromScale(ratio, 1)
		if ratio <= 0.3 then
			barFill.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
		elseif ratio <= 0.6 then
			barFill.BackgroundColor3 = Color3.fromRGB(240, 190, 45)
		else
			barFill.BackgroundColor3 = Color3.fromRGB(60, 220, 75)
		end
	end

	humanoid.HealthChanged:Connect(updateHealthBar)
	updateHealthBar(humanoid.Health)
end

local function createDummy(index: number, spawnCFrame: CFrame, description: HumanoidDescription, groundY: number)
	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromDescriptionAsync(description, Enum.HumanoidRigType.R15)
	end)

	if not ok then
		warn(("[TrainingDummies][%d] CreateHumanoidModelFromDescriptionAsync failed: %s"):format(index, tostring(result)))
		return false
	end
	if not result or not result:IsA("Model") then
		warn(("[TrainingDummies][%d] API returned an invalid model: %s"):format(index, tostring(result)))
		return false
	end

	local model = result
	model.Name = "TrainingDummy" .. index
	model:SetAttribute("IsTrainingDummy", true)
	model:SetAttribute("DummyIndex", index)
	model.Parent = dummyFolder
	model:PivotTo(spawnCFrame)

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart", true)
	if not humanoid or not root or not root:IsA("BasePart") then
		warn(("[TrainingDummies][%d] Model is missing Humanoid or HumanoidRootPart."):format(index))
		model:Destroy()
		return false
	end

	alignFeetToGround(model, groundY)
	humanoid.MaxHealth = DUMMY_HEALTH
	humanoid.Health = DUMMY_HEALTH
	auditAndPrepareModel(model, index, humanoid, root)
	addHealthDisplay(model, humanoid)

	local handledDeath = false
	humanoid.Died:Connect(function()
		if handledDeath then
			return
		end
		handledDeath = true
		CoinService.DropCoins(root.Position, 3)
		model:Destroy()
		task.delay(RESPAWN_DELAY, function()
			createDummy(index, spawnCFrame, description, groundY)
		end)
	end)

	return true
end

local spawnLocation = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
local groundY = spawnLocation and spawnLocation.Position.Y or 0
local descriptions = getDummyDescription()
local positions = getPracticeCFrames()
local createdCount = 0

for index = 1, DUMMY_COUNT do
	if createDummy(index, positions[index], descriptions, groundY) then
		createdCount += 1
	end
end

print(("[TrainingDummies] Created %d/%d R15 training dummies."):format(createdCount, DUMMY_COUNT))
