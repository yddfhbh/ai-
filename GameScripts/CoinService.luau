-- CoinService.module.luau
-- Static coins and dropped coins use the same create/collect functions.

local Players = game:GetService("Players")
local CoinService = {}
local COIN_FOLDER_NAME = "Coins"
local COIN_COLOR = Color3.fromRGB(255, 221, 0)

local function getCoinFolder(): Folder
	local folder = workspace:FindFirstChild(COIN_FOLDER_NAME)
	if folder and folder:IsA("Folder") then
		return folder
	end

	local newFolder = Instance.new("Folder")
	newFolder.Name = COIN_FOLDER_NAME
	newFolder.Parent = workspace
	return newFolder
end

function CoinService.ResetFolder()
	local oldFolder = workspace:FindFirstChild(COIN_FOLDER_NAME)
	if oldFolder then
		oldFolder:Destroy()
	end
	return getCoinFolder()
end

local function collectCoin(coin: BasePart, hit: BasePart)
	if not coin.Parent or coin:GetAttribute("Collected") then
		return
	end

	local character = hit:FindFirstAncestorOfClass("Model")
	if not character or not character:FindFirstChildOfClass("Humanoid") then
		return
	end

	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end

	coin:SetAttribute("Collected", true)
	local leaderstats = player:FindFirstChild("leaderstats")
	local score = leaderstats and leaderstats:FindFirstChild("Score")
	if score and score:IsA("IntValue") then
		score.Value += 1
	end
	coin:Destroy()
end

function CoinService.CreateCoin(position: Vector3, name: string, anchored: boolean)
	local coin = Instance.new("Part")
	coin.Name = name
	coin.Shape = Enum.PartType.Cylinder
	coin.Size = Vector3.new(0.6, 3, 3)
	coin.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	coin.Color = COIN_COLOR
	coin.Material = Enum.Material.Neon
	coin.Anchored = anchored
	coin.CanCollide = not anchored
	coin.CanTouch = true
	coin.Parent = getCoinFolder()

	local light = Instance.new("PointLight")
	light.Color = COIN_COLOR
	light.Brightness = 1.5
	light.Range = 8
	light.Parent = coin

	coin.Touched:Connect(function(hit)
		collectCoin(coin, hit)
	end)
	return coin
end

function CoinService.DropCoins(position: Vector3, amount: number)
	local offsets = {
		Vector3.new(-3, 3, 0),
		Vector3.new(0, 3, 2.5),
		Vector3.new(3, 3, 0),
	}

	for index = 1, amount do
		local offset = offsets[((index - 1) % #offsets) + 1]
		CoinService.CreateCoin(position + offset, "DroppedCoin", false)
	end
end

return CoinService
