-- CoinGame.server.luau
-- Creates the initial coins and the player Score leaderboard.

local Players = game:GetService("Players")
local CoinService = require(script.Parent:WaitForChild("CoinService"))

local COIN_COUNT = 10
local coinPositions = {
	Vector3.new(-24, 3, -18), Vector3.new(-8, 3, -18),
	Vector3.new(8, 3, -18), Vector3.new(24, 3, -18),
	Vector3.new(-24, 3, 0), Vector3.new(-8, 3, 0),
	Vector3.new(8, 3, 0), Vector3.new(24, 3, 0),
	Vector3.new(-12, 3, 18), Vector3.new(12, 3, 18),
}

local function setupLeaderstats(player: Player)
	if player:FindFirstChild("leaderstats") then
		return
	end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local score = Instance.new("IntValue")
	score.Name = "Score"
	score.Value = 0
	score.Parent = leaderstats
end

local function connectPlayerCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end

	humanoid.Died:Connect(function()
		local root = character:FindFirstChild("HumanoidRootPart")
		if root then
			CoinService.DropCoins(root.Position, 3)
		end
	end)
end

local function setupPlayer(player: Player)
	setupLeaderstats(player)
	player.CharacterAdded:Connect(connectPlayerCharacter)
	if player.Character then
		connectPlayerCharacter(player.Character)
	end
end

Players.PlayerAdded:Connect(setupPlayer)
for _, player in Players:GetPlayers() do
	setupPlayer(player)
end

CoinService.ResetFolder()
for index = 1, COIN_COUNT do
	CoinService.CreateCoin(coinPositions[index], "Coin" .. index, true)
end

print(("Created %d initial coins."):format(COIN_COUNT))
