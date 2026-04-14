-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- Remotes
local JoinMatch = ReplicatedStorage:WaitForChild("JoinMatch")
local KnockedOff = ReplicatedStorage:WaitForChild("PlayerKnockedOff")
local WinnerAnnounce = ReplicatedStorage:WaitForChild("WinnerAnnounce")

-- Stage
local Stage = script.Parent
local plate1 = Stage.Plate1
local plate2 = Stage.Plate2
local teleportPoint = Stage.T1.Position

-- Config
local MAX_ROUNDS = 3
local KNOCKBACK_FORCE = 85
local KNOCKBACK_UP = 35
local COOLDOWN_TIME = 1.5

-- States
local States = {
	Waiting = 1,
	Countdown = 2,
	InRound = 3
}

-- Storage
local platePlayers = {
	[plate1] = nil,
	[plate2] = nil
}

local currentMatch = nil

-- Utilities
local function getCharacter(player)
	return player.Character
end

local function getHRP(player)
	local char = getCharacter(player)
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function playSound(id, parent)
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. id
	s.Volume = 1
	s.Parent = parent or SoundService
	s:Play()
	Debris:AddItem(s, 3)
end

local function tweenPart(part, goal)
	local tween = TweenService:Create(part, TweenInfo.new(0.25), goal)
	tween:Play()
end

-- Player control
local function freeze(player, state)
	local hrp = getHRP(player)
	if not hrp then return end
	hrp.Anchored = state
end

local function teleport(player)
	local hrp = getHRP(player)
	if not hrp then return end

	local offset = CFrame.new(
		math.random(-3,3),
		5,
		math.random(-3,3)
	)

	hrp.CFrame = CFrame.new(teleportPoint) * offset
end

-- Combat system
local Combat = {}
Combat.__index = Combat

function Combat.new()
	local self = setmetatable({}, Combat)
	self.Cooldowns = {}
	return self
end

function Combat:CanHit(player)
	local last = self.Cooldowns[player]
	if not last then return true end
	return tick() - last >= COOLDOWN_TIME
end

function Combat:RegisterHit(player)
	self.Cooldowns[player] = tick()
end

function Combat:Apply(attacker, target)
	if not self:CanHit(attacker) then return end

	local aHRP = getHRP(attacker)
	local tHRP = getHRP(target)
	if not (aHRP and tHRP) then return end

	self:RegisterHit(attacker)

	local direction = (tHRP.Position - aHRP.Position).Unit
	local velocity = direction * KNOCKBACK_FORCE + Vector3.new(0, KNOCKBACK_UP, 0)

	tHRP.AssemblyLinearVelocity = velocity
end

-- Match class
local Match = {}
Match.__index = Match

function Match.new(p1, p2)
	local self = setmetatable({}, Match)

	self.Players = {p1, p2}
	self.Scores = {
		[p1.UserId] = 0,
		[p2.UserId] = 0
	}

	self.State = States.Waiting
	self.Round = 0
	self.Combat = Combat.new()
	self.LastUpdate = 0

	return self
end

-- Countdown
function Match:Countdown()
	self.State = States.Countdown

	for i = 3,1,-1 do
		for _,plr in ipairs(self.Players) do
			playSound(6467449877, getHRP(plr))
		end
		task.wait(1)
	end
end

-- Start round
function Match:StartRound()
	self.Round += 1
	self.State = States.InRound

	for _,plr in ipairs(self.Players) do
		freeze(plr, true)
		teleport(plr)
	end

	self:Countdown()

	for _,plr in ipairs(self.Players) do
		freeze(plr, false)
		playSound(3199238628, getHRP(plr))
	end
end

-- Point handling
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

-- End match
function Match:End()
	self.State = States.Waiting
	currentMatch = nil
end

-- Update loop
function Match:Update(dt)
	if self.State ~= States.InRound then return end

	self.LastUpdate += dt

	if self.LastUpdate < 0.1 then return end
	self.LastUpdate = 0

	local p1 = self.Players[1]
	local p2 = self.Players[2]

	if not (p1 and p2) then return end

	local hrp1 = getHRP(p1)
	local hrp2 = getHRP(p2)

	if not (hrp1 and hrp2) then return end

	local distance = (hrp1.Position - hrp2.Position).Magnitude

	if distance < 6 then
		self.Combat:Apply(p1, p2)
		self.Combat:Apply(p2, p1)
	end
end

-- Plate logic
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

-- Start match
local function tryStart()
	if currentMatch then return end

	local p1 = platePlayers[plate1]
	local p2 = platePlayers[plate2]

	if p1 and p2 then
		currentMatch = Match.new(p1, p2)
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

	local p1 = currentMatch.Players[1]
	local p2 = currentMatch.Players[2]

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

-- Heartbeat loop
RunService.Heartbeat:Connect(function(dt)
	if currentMatch then
		currentMatch:Update(dt)
	end
end)

-- Visual pulse
local function pulsePlate(plate)
	if not plate:IsA("BasePart") then return end
	tweenPart(plate, {Transparency = 0.3})
	task.wait(0.2)
	tweenPart(plate, {Transparency = 0})
end

-- Random pulse loop
task.spawn(function()
	while true do
		pulsePlate(plate1)
		pulsePlate(plate2)
		task.wait(2)
	end
end)

-- Safety cleanup loop
task.spawn(function()
	while true do
		for player,_ in pairs(platePlayers) do
			if player and not player.Parent then
				removePlayer(player)
			end
		end
		task.wait(5)
	end
end)
