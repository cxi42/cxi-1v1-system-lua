--  1v1 system
-- written by: xiaa_fr on roblox, cmcln on discord
-- handles queue, matches, combat, rounds

-- Services
-- Roblox services used for player management, networking, physics timing, etc
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- Remotes
-- RemoteEvents used for communication between client and server
local JoinMatch = ReplicatedStorage:WaitForChild("JoinMatch") -- fired when player joins queue
local KnockedOff = ReplicatedStorage:WaitForChild("PlayerKnockedOff") -- fired when client thinks they fell
local WinnerAnnounce = ReplicatedStorage:WaitForChild("WinnerAnnounce") -- server announces winner to all clients

-- Stage references
-- parts in the map used for queue plates and teleport location
local Stage = script.Parent
local Plate1 = Stage.Plate1
local Plate2 = Stage.Plate2
local TeleportPoint = Stage.T1.Position -- center point players get teleported around

-- Config
-- tweakable gameplay values
local MaxRounds = 3 -- how many points needed to win match
local KnockbackForce = 85 -- horizontal push strength
local KnockbackUp = 35 -- vertical lift applied during hit
local CooldownTime = 1.5 -- delay between valid hits per player

-- States
-- controls what phase the match is currently in
local States = {
	Waiting = 1,   -- idle, no active round
	Countdown = 2, -- pre-round countdown
	InRound = 3    -- active combat
}

-- PlatePlayers
-- tracks which player is standing on which plate
-- key = plate part, value = player occupying it
local PlatePlayers = {
	[Plate1] = nil,
	[Plate2] = nil
}

-- Matches
-- list of all currently active matches (usually small, but supports multiple)
local Matches = {}

-- safely returns a player's character (can be nil if not loaded)
local function GetCharacter(player)
	return player.Character
end

-- safely returns HumanoidRootPart (main physics part used for movement)
local function GetHRP(player)
	local char = GetCharacter(player)
	if not char then return end
	return char:FindFirstChild("HumanoidRootPart")
end

-- plays a temporary sound and auto-cleans it
local function PlaySound(id, parent)
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. id
	s.Volume = 1
	s.Parent = parent or SoundService
	s:Play()
	Debris:AddItem(s, 3) -- removes sound after 3 seconds to prevent buildup
end

-- quick tween helper for small visual effects (like plate pulsing)
local function TweenPart(part, goal)
	local tween = TweenService:Create(part, TweenInfo.new(0.25), goal)
	tween:Play()
end

-- freezes/unfreezes a player by anchoring their root part
-- used during countdown so players can't move early
local function Freeze(player, state)
	local hrp = GetHRP(player)
	if not hrp then return end
	hrp.Anchored = state
end

-- teleports player to arena with slight random offset
-- prevents both players spawning inside each other
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
-- handles hit cooldowns and knockback application
local Combat = {}
Combat.__index = Combat

function Combat.new()
	local self = setmetatable({}, Combat)
	self.Cooldowns = {} -- stores last hit time per player
	return self
end

-- checks if player is allowed to hit again (anti spam)
function Combat:CanHit(player)
	local last = self.Cooldowns[player]
	if not last then return true end
	return os.clock() - last >= CooldownTime
end

-- records hit timestamp
function Combat:RegisterHit(player)
	self.Cooldowns[player] = os.clock()
end

-- applies knockback if attacker is facing target
function Combat:Apply(attacker, target)
	if not self:CanHit(attacker) then return end

	local aHRP = GetHRP(attacker)
	local tHRP = GetHRP(target)
	if not (aHRP and tHRP) then return end

	-- direction from attacker → target
	local direction = (tHRP.Position - aHRP.Position).Unit

	-- dot product checks if attacker is facing target
	-- prevents hitting people behind you
	local facingDot = aHRP.CFrame.LookVector:Dot(direction)
	if facingDot < 0.5 then return end

	self:RegisterHit(attacker)

	-- final velocity applied to target
	local velocity = direction * KnockbackForce + Vector3.new(0, KnockbackUp, 0)
	tHRP.AssemblyLinearVelocity = velocity
end

-- Match class
-- represents a single 1v1 match instance
local Match = {}
Match.__index = Match

function Match.new(p1, p2)
	local self = setmetatable({}, Match)

	self.Players = {p1, p2}

	-- score tracked by UserId so it remains stable
	self.Scores = {
		[p1.UserId] = 0,
		[p2.UserId] = 0
	}

	self.State = States.Waiting
	self.Round = 0
	self.Combat = Combat.new()
	self.LastUpdate = 0 -- used to throttle update loop

	return self
end

-- 3 second countdown before round starts
function Match:Countdown()
	self.State = States.Countdown

	for i = 3,1,-1 do
		for _,plr in ipairs(self.Players) do
			PlaySound(6467449877, GetHRP(plr)) -- beep sound
		end
		task.wait(1)
	end
end

-- starts a new round
function Match:StartRound()
	self.Round += 1
	self.State = States.InRound

	-- reset both players
	for _,plr in ipairs(self.Players) do
		Freeze(plr, true) -- lock movement
		Teleport(plr)
	end

	self:Countdown()

	-- allow movement after countdown
	for _,plr in ipairs(self.Players) do
		Freeze(plr, false)
		PlaySound(3199238628, GetHRP(plr)) -- start sound
	end
end

-- gives point to winner and checks if match ends
function Match:Point(winner)
	if not winner then return end
	if not self.Scores[winner.UserId] then return end

	self.Scores[winner.UserId] += 1

	-- if player reached required wins, end match
	if self.Scores[winner.UserId] >= MaxRounds then
		WinnerAnnounce:FireAllClients(winner.Name)
		self:End()
		return
	end

	task.wait(2) -- short delay before next round
	self:StartRound()
end

-- ends match and cleans it up
function Match:End()
	self.State = States.Waiting

	-- ensure players are unfrozen
	for _,plr in ipairs(self.Players) do
		if plr then
			Freeze(plr, false)
		end
	end

	-- remove this match from active list (prevents memory leaks)
	for i, m in ipairs(Matches) do
		if m == self then
			table.remove(Matches, i)
			break
		end
	end

	table.clear(self.Players)
end

-- runs every frame (throttled to ~10 updates/sec)
function Match:Update(dt)
	if self.State ~= States.InRound then return end

	self.LastUpdate += dt
	if self.LastUpdate < 0.1 then return end -- throttle
	self.LastUpdate = 0

	local p1 = self.Players[1]
	local p2 = self.Players[2]
	if not (p1 and p2) then return end

	local hrp1 = GetHRP(p1)
	local hrp2 = GetHRP(p2)
	if not (hrp1 and hrp2) then return end

	local distance = (hrp1.Position - hrp2.Position).Magnitude

	-- if players are close enough, apply combat both ways
	if distance < 6 then
		self.Combat:Apply(p1, p2)
		self.Combat:Apply(p2, p1)
	end
end

-- assigns player to first available plate
local function AssignPlayer(player)
	if not PlatePlayers[Plate1] then
		PlatePlayers[Plate1] = player
	elseif not PlatePlayers[Plate2] then
		PlatePlayers[Plate2] = player
	else
		return false -- both occupied
	end
	return true
end

-- removes player from whichever plate they were on
local function RemovePlayer(player)
	for plate,plr in pairs(PlatePlayers) do
		if plr == player then
			PlatePlayers[plate] = nil
		end
	end
end

-- starts match when both plates have players
local function TryStart()
	local p1 = PlatePlayers[Plate1]
	local p2 = PlatePlayers[Plate2]

	if p1 and p2 then
		local match = Match.new(p1, p2)
		table.insert(Matches, match)
		match:StartRound()
	end
end

-- player joins queue
JoinMatch.OnServerEvent:Connect(function(player)
	if AssignPlayer(player) then
		TryStart()
	end
end)

-- server validates if player actually fell off map
KnockedOff.OnServerEvent:Connect(function(player)
	for _,match in ipairs(Matches) do
		local p1 = match.Players[1]
		local p2 = match.Players[2]

		if player ~= p1 and player ~= p2 then continue end

		local hrp = GetHRP(player)
		if not hrp then return end

		-- only count as fall if below map height
		if hrp.Position.Y > 0 then return end

		if player == p1 then
			match:Point(p2)
		else
			match:Point(p1)
		end
	end
end)

-- cleanup when player leaves game
Players.PlayerRemoving:Connect(function(player)
	RemovePlayer(player)

	for _,match in ipairs(Matches) do
		if table.find(match.Players, player) then
			match:End()
		end
	end
end)

-- main loop updating all matches
RunService.Heartbeat:Connect(function(dt)
	for _,match in ipairs(Matches) do
		match:Update(dt)
	end
end)

-- simple visual effect: plates pulse transparency
local function PulsePlate(plate)
	if not plate:IsA("BasePart") then return end
	TweenPart(plate, {Transparency = 0.3})
	task.wait(0.2)
	TweenPart(plate, {Transparency = 0})
end

task.spawn(function()
	while true do
		PulsePlate(Plate1)
		PulsePlate(Plate2)
		task.wait(2)
	end
end)

-- periodic cleanup to remove players that no longer exist
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
