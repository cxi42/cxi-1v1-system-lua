-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

-- Remotes
local JoinMatch = ReplicatedStorage:WaitForChild("JoinMatch")
local KnockedOff = ReplicatedStorage:WaitForChild("PlayerKnockedOff")
local WinnerAnnounce = ReplicatedStorage:WaitForChild("WinnerAnnounce")

-- Stage refs
local Stage = script.Parent
local plate1 = Stage.Plate1
local plate2 = Stage.Plate2
local teleportPoint = Stage.T1.Position

-- Config
local MAX_ROUNDS = 3

-- Match Class
local Match = {}
Match.__index = Match

function Match.new(p1, p2)
	local self = setmetatable({}, Match)

	self.Players = {p1, p2}
	self.Scores = {
		[p1.UserId] = 0,
		[p2.UserId] = 0
	}

	self.Active = false
	self.Round = 0

	return self
end

-- Utility
local function getHRP(player)
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function freeze(player, state)
	local hrp = getHRP(player)
	if not hrp then return end
	hrp.Anchored = state
end

local function teleportPlayer(player)
	local hrp = getHRP(player)
	if not hrp then return end

	local offset = CFrame.new(
		math.random(-3,3),
		5,
		math.random(-3,3)
	)

	hrp.CFrame = CFrame.new(teleportPoint) * offset
end

local function playSound(id, parent)
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://"..id
	s.Volume = 1
	s.Parent = parent or SoundService
	s:Play()
	game.Debris:AddItem(s, 3)
end

-- Countdown
function Match:Countdown()
	for i = 3,1,-1 do
		for _,plr in ipairs(self.Players) do
			local hrp = getHRP(plr)
			playSound(6467449877, hrp)
		end
		task.wait(1)
	end
end

-- Round Start
function Match:StartRound()
	self.Round += 1

	for _,plr in ipairs(self.Players) do
		freeze(plr, true)
		teleportPlayer(plr)
	end

	self:Countdown()

	for _,plr in ipairs(self.Players) do
		freeze(plr, false)
		local hrp = getHRP(plr)
		playSound(3199238628, hrp)
	end
end

-- Knockback
function Match:ApplyKnockback(attacker, target)
	local aHRP = getHRP(attacker)
	local tHRP = getHRP(target)

	if not (aHRP and tHRP) then return end

	local direction = (tHRP.Position - aHRP.Position).Unit
	local force = direction * 80 + Vector3.new(0, 35, 0)

	tHRP.AssemblyLinearVelocity = force
end

-- Round End
function Match:Point(winner)
	self.Scores[winner.UserId] += 1

	if self.Scores[winner.UserId] >= MAX_ROUNDS then
		WinnerAnnounce:FireAllClients(winner.Name)
		self:End()
		return
	end

	task.wait(2)
	self:StartRound()
end

-- End Match
function Match:End()
	self.Active = false
	currentMatch = nil
end

-- Global State
local platePlayers = {
	[plate1] = nil,
	[plate2] = nil
}

local currentMatch = nil

-- Plate Logic
local function assignPlayer(player)
	if not platePlayers[plate1] then
		platePlayers[plate1] = player
	elseif not platePlayers[plate2] then
		platePlayers[plate2] = player
	else
		return false
	end
	return true
end

local function removePlayer(player)
	for plate,plr in pairs(platePlayers) do
		if plr == player then
			platePlayers[plate] = nil
		end
	end
end

-- Start Match Check
local function tryStart()
	if currentMatch then return end

	local p1 = platePlayers[plate1]
	local p2 = platePlayers[plate2]

	if p1 and p2 then
		currentMatch = Match.new(p1, p2)
		currentMatch.Active = true
		currentMatch:StartRound()
	end
end

-- Events
JoinMatch.OnServerEvent:Connect(function(player)
	if assignPlayer(player) then
		tryStart()
	end
end)

KnockedOff.OnServerEvent:Connect(function(player)
	if not currentMatch then return end

	local p1, p2 = unpack(currentMatch.Players)

	if player == p1 then
		currentMatch:Point(p2)
	elseif player == p2 then
		currentMatch:Point(p1)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	removePlayer(player)

	if currentMatch then
		currentMatch:End()
	end
end)
