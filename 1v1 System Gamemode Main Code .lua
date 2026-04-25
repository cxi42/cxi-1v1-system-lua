-- simple 1v1 system
-- written by: xiaa_fr on roblox, cmcln on discord
-- handles queue, matches, combat, rounds

-- services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- remotes
local JoinMatch = ReplicatedStorage:WaitForChild("JoinMatch")
local KnockedOff = ReplicatedStorage:WaitForChild("PlayerKnockedOff")
local WinnerAnnounce = ReplicatedStorage:WaitForChild("WinnerAnnounce")

-- stage references
local Stage = script.Parent
local Plate1 = Stage.Plate1
local Plate2 = Stage.Plate2
local TeleportPoint = Stage.T1.Position

-- config
local MaxRounds = 3
local KnockbackForce = 85
local KnockbackUp = 35
local CooldownTime = 1.5

-- states for match flow
local States = {
Waiting = 1,
Countdown = 2,
InRound = 3
}

-- who is standing on what plate
local PlatePlayers = {
[Plate1] = nil,
[Plate2] = nil
}

-- active matches list
local Matches = {}

-- gets character safely
local function GetCharacter(player)
return player.Character
end

-- gets humanoid root part safely
local function GetHRP(player)
local char = GetCharacter(player)
if not char then return end
return char:FindFirstChild("HumanoidRootPart")
end

-- quick sound helper
local function PlaySound(id, parent)
local s = Instance.new("Sound")
s.SoundId = "rbxassetid://" .. id
s.Volume = 1
s.Parent = parent or SoundService
s:Play()
Debris:AddItem(s, 3)
end

-- small tween helper for visuals
local function TweenPart(part, goal)
local tween = TweenService:Create(part, TweenInfo.new(0.25), goal)
tween:Play()
end

-- freeze player so they cant move during countdown
local function Freeze(player, state)
local hrp = GetHRP(player)
if not hrp then return end
hrp.Anchored = state
end

-- teleport player with slight offset so they dont overlap
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

-- combat system
local Combat = {}
Combat.__index = Combat

function Combat.new()
local self = setmetatable({}, Combat)
self.Cooldowns = {}
return self
end

-- prevents hit spam
function Combat:CanHit(player)
local last = self.Cooldowns[player]
if not last then return true end
return os.clock() - last >= CooldownTime
end

function Combat:RegisterHit(player)
self.Cooldowns[player] = os.clock()
end

-- applies knockback if attacker is actually facing target
function Combat:Apply(attacker, target)
if not self:CanHit(attacker) then return end

local aHRP = GetHRP(attacker)
local tHRP = GetHRP(target)
if not (aHRP and tHRP) then return end

local direction = (tHRP.Position - aHRP.Position).Unit
local facingDot = aHRP.CFrame.LookVector:Dot(direction)

-- stops hitting people behind you
if facingDot < 0.5 then return end

self:RegisterHit(attacker)

local velocity = direction * KnockbackForce + Vector3.new(0, KnockbackUp, 0)
tHRP.AssemblyLinearVelocity = velocity

end

-- match class
local Match = {}
Match.__index = Match

function Match.new(p1, p2)
local self = setmetatable({}, Match)

```
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
```

end

-- countdown before each round
function Match:Countdown()
self.State = States.Countdown

for i = 3,1,-1 do
	for _,plr in ipairs(self.Players) do
		PlaySound(6467449877, GetHRP(plr))
	end
	task.wait(1)
end

end

-- starts a round
function Match:StartRound()
self.Round += 1
self.State = States.InRound

-- reset players
for _,plr in ipairs(self.Players) do
	Freeze(plr, true)
	Teleport(plr)
end

self:Countdown()

-- unfreeze after countdown
for _,plr in ipairs(self.Players) do
	Freeze(plr, false)
	PlaySound(3199238628, GetHRP(plr))
end

end

-- gives a point and checks win condition
function Match:Point(winner)
if not winner then return end
if not self.Scores[winner.UserId] then return end

```
self.Scores[winner.UserId] += 1

-- match finished
if self.Scores[winner.UserId] >= MaxRounds then
	WinnerAnnounce:FireAllClients(winner.Name)
	self:End()
	return
end

task.wait(2)
self:StartRound()

end

-- ends match and cleans it up
function Match:End()
self.State = States.Waiting

for _,plr in ipairs(self.Players) do
	if plr then
		Freeze(plr, false)
	end
end

-- remove from matches list (important, stops memory buildup)
for i, m in ipairs(Matches) do
	if m == self then
		table.remove(Matches, i)
		break
	end
end

table.clear(self.Players)

end

-- runs every frame (throttled)
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

-- simple proximity combat
if distance < 6 then
	self.Combat:Apply(p1, p2)
	self.Combat:Apply(p2, p1)
end

end

-- assigns player to free plate
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

-- removes player from plates
local function RemovePlayer(player)
for plate,plr in pairs(PlatePlayers) do
if plr == player then
PlatePlayers[plate] = nil
end
end
end

-- starts match if both plates filled
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

-- validates knockoff (server sided check)
KnockedOff.OnServerEvent:Connect(function(player)
for _,match in ipairs(Matches) do
local p1 = match.Players[1]
local p2 = match.Players[2]

	if player ~= p1 and player ~= p2 then continue end

	local hrp = GetHRP(player)
	if not hrp then return end

	-- only count if they actually fell
	if hrp.Position.Y > 0 then return end

	if player == p1 then
		match:Point(p2)
	else
		match:Point(p1)
	end
end

end)

-- cleanup when player leaves
Players.PlayerRemoving:Connect(function(player)
RemovePlayer(player)

for _,match in ipairs(Matches) do
	if table.find(match.Players, player) then
		match:End()
	end
end

end)

-- main loop
RunService.Heartbeat:Connect(function(dt)
for _,match in ipairs(Matches) do
match:Update(dt)
end
end)

-- plate visual pulse (just for feel)
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

-- safety cleanup loop
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
