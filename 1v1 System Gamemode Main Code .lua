-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- Remotes
-- These are the communication bridges between client and server
-- The server stays authoritative, clients only request or notify
local JoinMatch = ReplicatedStorage:WaitForChild("JoinMatch")
local KnockedOff = ReplicatedStorage:WaitForChild("PlayerKnockedOff")
local WinnerAnnounce = ReplicatedStorage:WaitForChild("WinnerAnnounce")

-- Stage
-- References to important parts of the arena
-- Plates act as join slots, teleportPoint is where players spawn for rounds
local Stage = script.Parent
local Plate1 = Stage.Plate1
local Plate2 = Stage.Plate2
local TeleportPoint = Stage.T1.Position

-- Config
-- Centralized balancing values so gameplay can be tuned without touching logic
local MaxRounds = 3
local KnockbackForce = 85
local KnockbackUp = 35
local CooldownTime = 1.5

-- States
-- Simple state machine to control match flow
-- Numbers are used instead of strings for faster comparisons
local States = {
	Waiting = 1,
	Countdown = 2,
	InRound = 3
}

-- Plate storage
-- Keeps track of which player is occupying each plate
-- This acts as a lightweight matchmaking system
local PlatePlayers = {
	[Plate1] = nil,
	[Plate2] = nil
}

-- Current active match
-- Only one match runs at a time in this system
local CurrentMatch = nil

-- Utility
-- Helper functions to safely access character components

local function GetCharacter(player)
	return player.Character
end

-- HumanoidRootPart is required for positioning and physics
-- If it's missing, the player is likely not fully loaded
local function GetHRP(player)
	local char = GetCharacter(player)
	return char and char:FindFirstChild("HumanoidRootPart")
end

-- Creates and plays a temporary sound
-- Debris is used so sounds clean themselves up automatically
local function PlaySound(id, parent)
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. id
	s.Volume = 1
	s.Parent = parent or SoundService
	s:Play()
	Debris:AddItem(s, 3)
end

-- Small tween helper used for visual feedback (plates pulsing)
local function TweenPart(part, goal)
	local tween = TweenService:Create(part, TweenInfo.new(0.25), goal)
	tween:Play()
end

-- Player control
-- Used to temporarily disable movement during countdowns

local function Freeze(player, state)
	local hrp = GetHRP(player)
	if not hrp then return end
	hrp.Anchored = state
end

-- Teleports player to arena with slight randomness
-- Prevents players from spawning inside each other
local function Teleport(player)
	local hrp = GetHRP(player)
	if not hrp then return end

	local offset = CFrame.new(
		math.random(-3,3),
		5,
		math.random(-3,3)
	)

	hrp.CFrame = CFrame.new(TeleportPoint) * offset
end

-- Combat system
-- Handles hit cooldowns and knockback logic
-- Separated into its own object to keep Match class cleaner

local Combat = {}
Combat.__index = Combat

function Combat.new()
	local self = setmetatable({}, Combat)
	self.Cooldowns = {}
	return self
end

-- Prevents spam hits by enforcing a cooldown per player
function Combat:CanHit(player)
	local last = self.Cooldowns[player]
	if not last then return true end
	return tick() - last >= CooldownTime
end

function Combat:RegisterHit(player)
	self.Cooldowns[player] = tick()
end

-- Applies knockback using physics instead of teleporting
-- This creates a more natural and skill-based interaction
function Combat:Apply(attacker, target)
	if not self:CanHit(attacker) then return end

	local aHRP = GetHRP(attacker)
	local tHRP = GetHRP(target)
	if not (aHRP and tHRP) then return end

	self:RegisterHit(attacker)

	local direction = (tHRP.Position - aHRP.Position).Unit
	local velocity = direction * KnockbackForce + Vector3.new(0, KnockbackUp, 0)

	tHRP.AssemblyLinearVelocity = velocity
end

-- Match class
-- Encapsulates an entire 1v1 match lifecycle

local Match = {}
Match.__index = Match

function Match.new(p1, p2)
	local self = setmetatable({}, Match)

	self.Players = {p1, p2}

	-- Score tracked by UserId to avoid issues if player objects change
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

-- Countdown phase before each round starts
-- Freezes players to ensure fairness
function Match:Countdown()
	self.State = States.Countdown

	for i = 3,1,-1 do
		for _,plr in ipairs(self.Players) do
			PlaySound(6467449877, GetHRP(plr))
		end
		task.wait(1)
	end
end

-- Starts a new round
-- Handles teleporting, freezing, and countdown timing
function Match:StartRound()
	self.Round += 1
	self.State = States.InRound

	for _,plr in ipairs(self.Players) do
		Freeze(plr, true)
		Teleport(plr)
	end

	self:Countdown()

	for _,plr in ipairs(self.Players) do
		Freeze(plr, false)
		PlaySound(3199238628, GetHRP(plr))
	end
end

-- Handles scoring and match progression
function Match:Point(winner)
	self.Scores[winner.UserId] += 1

	if self.Scores[winner.UserId] >= MaxRounds then
		WinnerAnnounce:FireAllClients(winner.Name)
		self:End()
		return
	end

	task.wait(2)
	self:StartRound()
end

-- Ends match and resets system
function Match:End()
	self.State = States.Waiting
	CurrentMatch = nil
end

-- Main update loop for combat detection
-- Runs periodically instead of every frame for performance
function Match:Update(dt)
	if self.State ~= States.InRound then return end

	self.LastUpdate += dt
	if self.LastUpdate < 0.1 then return end
	self.LastUpdate = 0

	local p1 = self.Players[1]
	local p2 = self.Players[2]
	if not (p1 and p2) then return end

	local hrp1 = GetHRP(p1)
	local hrp2 = GetHRP(p2)
	if not (hrp1 and hrp2) then return end

	local distance = (hrp1.Position - hrp2.Position).Magnitude

	-- If players are close enough, apply knockback to both
	-- This creates a "clash" mechanic rather than one-sided hits
	if distance < 6 then
		self.Combat:Apply(p1, p2)
		self.Combat:Apply(p2, p1)
	end
end

-- Plate logic
-- Handles assigning and removing players from join spots

local function AssignPlayer(player)
	if not PlatePlayers[Plate1] then
		PlatePlayers[Plate1] = player
	elseif not PlatePlayers[Plate2] then
		PlatePlayers[Plate2] = player
	else
		return false
	end
	return true
end

local function RemovePlayer(player)
	for plate,plr in pairs(PlatePlayers) do
		if plr == player then
			PlatePlayers[plate] = nil
		end
	end
end

-- Attempts to start a match when both slots are filled
local function TryStart()
	if CurrentMatch then return end

	local p1 = PlatePlayers[Plate1]
	local p2 = PlatePlayers[Plate2]

	if p1 and p2 then
		CurrentMatch = Match.new(p1, p2)
		CurrentMatch:StartRound()
	end
end

-- Events

JoinMatch.OnServerEvent:Connect(function(player)
	if AssignPlayer(player) then
		TryStart()
	end
end)

KnockedOff.OnServerEvent:Connect(function(player)
	if not CurrentMatch then return end

	local p1 = CurrentMatch.Players[1]
	local p2 = CurrentMatch.Players[2]

	if player == p1 then
		CurrentMatch:Point(p2)
	elseif player == p2 then
		CurrentMatch:Point(p1)
	end
end)

-- Ensures players are cleaned up if they leave mid-match
Players.PlayerRemoving:Connect(function(player)
	RemovePlayer(player)

	if CurrentMatch then
		CurrentMatch:End()
	end
end)

-- Heartbeat loop drives match updates
RunService.Heartbeat:Connect(function(dt)
	if CurrentMatch then
		CurrentMatch:Update(dt)
	end
end)

-- Visual pulse
-- Gives plates life so they don’t feel static

local function PulsePlate(plate)
	if not plate:IsA("BasePart") then return end
	TweenPart(plate, {Transparency = 0.3})
	task.wait(0.2)
	TweenPart(plate, {Transparency = 0})
end

-- Runs continuously to animate plates
task.spawn(function()
	while true do
		PulsePlate(Plate1)
		PulsePlate(Plate2)
		task.wait(2)
	end
end)

-- Safety cleanup
-- Handles edge cases where players disappear unexpectedly
task.spawn(function()
	while true do
		for player,_ in pairs(PlatePlayers) do
			if player and not player.Parent then
				RemovePlayer(player)
			end
		end
		task.wait(5)
	end
end)
