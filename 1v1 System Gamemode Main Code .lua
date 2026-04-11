local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Remote events for UI announcements and giving push tool
local WinnerAnnounce = ReplicatedStorage:WaitForChild("WinnerAnnounce")
local RoundWinAnnounce = ReplicatedStorage:WaitForChild("RoundWinAnnounce")
local PushTool = ReplicatedStorage:WaitForChild("PushTool")

local Stage = script.Parent
local Button = Stage.Button
local MainBoard = Stage.MainBoard.SurfaceGui.Frame.Status
local plate1, plate2 = Stage.Plate1, Stage.Plate2
local Announcement = Stage:FindFirstChild("Announcement")
local CountdownLabel = Announcement and Announcement:FindFirstChild("Countdown")
local Holder = Stage:WaitForChild("Holder")
local TeleportPoint = Stage.T1.Position

local inMatch = false
local scores = {}
local maxRounds = 3
local currentRound = 0
local countdownTask

-- Stores which player is on which plate; nil if empty
local platePlayers = { [plate1] = nil, [plate2] = nil }

-- Updates main board text based on match state and player presence
local function updateMainBoard()
	if not inMatch then
		MainBoard.Text = "Waiting..."
		return
	end

	local p1, p2 = platePlayers[plate1], platePlayers[plate2]
	if p1 and p2 then
		MainBoard.Text = scores[p1.UserId] .. " - " .. scores[p2.UserId]
	else
		MainBoard.Text = "Waiting..."
	end
end

-- Updates each plate's mini board with player name and headshot
local function updateBoardForPlate(plate, player)
	local boardName = (plate == plate1) and "Board1" or "Board2"
	local sg = plate:FindFirstChild(boardName)
	if not sg then return end

	local frame = sg:FindFirstChild("SurfaceGui") and sg.SurfaceGui.Frame
	if not frame then return end

	-- If no player, clear display; otherwise, show player's name and Roblox headshot thumbnail
	if not player then
		frame.PlayerName.Text = ""
		frame.PlayerIcon.Image = ""
		return
	end

	frame.PlayerName.Text = player.Name
	frame.PlayerIcon.Image = "https://www.roblox.com/headshot-thumbnail/image?userId=" .. player.UserId .. "&width=420&height=420&format=png"
end

-- Toggles the holder parts' visibility and collisions to control physical interaction
local function setHolderVisibility(visible)
	for _, part in ipairs(Holder:GetChildren()) do
		if part:IsA("BasePart") then
			part.Transparency = visible and 0.5 or 1
			part.CanCollide = visible
		end
	end
end

-- Resets player movement to default speeds; freezing/unfreezing can be handled by changing WalkSpeed and JumpPower
local function freezePlayer(player, freeze)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not hum then return end

	-- Here, always resetting to defaults since no difference in freeze/unfreeze provided
	hum.WalkSpeed = 16
	hum.JumpPower = 50
end

-- Plays 3 beep sounds sequentially at the player's HumanoidRootPart or SoundService if not available
local function playCountdownBeep(player)
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://6467449877"
	sound.Volume = 1
	sound.Parent = player.Character and player.Character:FindFirstChild("HumanoidRootPart") or SoundService

	for _ = 1, 3 do
		sound:Play()
		task.wait(1)
	end
	sound:Destroy()
end

-- Plays a single start sound at the player's location or globally
local function playStartSound(player)
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://3199238628"
	sound.Volume = 1
	sound.Parent = player.Character and player.Character:FindFirstChild("HumanoidRootPart") or SoundService
	sound:Play()
	game.Debris:AddItem(sound, 3) -- clean up after 3 seconds
end

-- Gives the PushTool to the player if they don't already have it, preventing duplicates
local function givePushTool(player)
	local bp = player:FindFirstChild("Backpack")
	if not bp then return end

	if bp:FindFirstChild("PushTool") or (player.Character and player.Character:FindFirstChild("PushTool")) then
		return
	end

	PushTool:Clone().Parent = bp
end

-- Removes PushTool from both backpack and character to fully take it away from the player
local function removePushTool(player)
	local bp = player:FindFirstChild("Backpack")
	if bp then
		local tool = bp:FindFirstChild("PushTool")
		if tool then tool:Destroy() end
	end

	local char = player.Character
	if char then
		local tool = char:FindFirstChild("PushTool")
		if tool then tool:Destroy() end
	end
end

-- Displays countdown on UI and freezes players during countdown, then plays sounds before starting match
local function showCountdownAndFreeze()
	if not CountdownLabel then return end

	-- Freeze players to prevent movement during countdown
	for _, player in pairs(platePlayers) do
		freezePlayer(player, true)
	end

	CountdownLabel.Visible = true
	for i = 3, 1, -1 do
		CountdownLabel.Text = tostring(i)
		task.wait(1)
	end
	CountdownLabel.Visible = false

	-- Play countdown beeps and start sounds asynchronously to avoid blocking
	for _, player in pairs(platePlayers) do
		task.spawn(function()
			playCountdownBeep(player)
			playStartSound(player)
		end)
	end

	task.wait(3) -- Wait for sounds to finish

	-- Unfreeze players so match can start
	for _, player in pairs(platePlayers) do
		freezePlayer(player, false)
	end
end

-- Activates a randomly chosen Ender platform by toggling transparency and collisions, deactivates others
local function pickRandomEnder()
	local enders = {}

	for _, child in ipairs(Button:GetChildren()) do
		if child.Name == "Ender" then
			table.insert(enders, child)
		end
	end

	if #enders == 0 then return end

	local chosen = enders[math.random(1, #enders)]

	-- Disable all Ender platforms initially
	for _, ender in ipairs(enders) do
		for _, desc in ipairs(ender:GetDescendants()) do
			if desc:IsA("BasePart") then
				desc.Transparency = 1
				desc.CanCollide = false
			end
		end
	end

	-- Enable only the chosen Ender platform
	for _, desc in ipairs(chosen:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Transparency = 0
			desc.CanCollide = true
		end
	end

	return chosen
end

-- Teleports players to start zone and freezes them, gives PushTool, then plays start sounds
local function prepPlayersForRound()
	for _, player in pairs(platePlayers) do
		local char = player.Character
		if not (char and char:FindFirstChild("HumanoidRootPart")) then
			continue
		end

		-- Teleport player slightly randomized around teleport point, lifted 5 studs up
		char:PivotTo(CFrame.new(TeleportPoint + Vector3.new(math.random(-3, 3), 5, math.random(-3, 3))))

		freezePlayer(player, true)
		givePushTool(player)
	end

	-- Play countdown beeps and start sounds without blocking
	for _, player in pairs(platePlayers) do
		task.spawn(function()
			playCountdownBeep(player)
			playStartSound(player)
		end)
	end

	task.wait(3) -- Wait for sounds

	-- Unfreeze players for gameplay
	for _, player in pairs(platePlayers) do
		freezePlayer(player, false)
	end
end

-- Starts the overall match, resets rounds and scores, updates UI and activates holder visuals
local function startMatch()
	inMatch = true
	currentRound = 0
	local p1, p2 = platePlayers[plate1], platePlayers[plate2]

	-- Initialize scores dictionary
	scores = { [p1.UserId] = 0, [p2.UserId] = 0 }

	updateMainBoard()
	updateBoardForPlate(plate1, p1)
	updateBoardForPlate(plate2, p2)

	setHolderVisibility(true)
	task.delay(3, function() setHolderVisibility(false) end)

	pickRandomEnder()
	prepPlayersForRound()
end

-- Resets the match environment for the next round without resetting scores or players
local function resetMatch()
	setHolderVisibility(true)
	task.delay(3, function() setHolderVisibility(false) end)
	pickRandomEnder()
	prepPlayersForRound()
end

-- Cancels any ongoing countdown coroutine
local function cancelCountdown()
	if countdownTask then
		task.cancel(countdownTask)
		countdownTask = nil
	end
end

-- Manages countdown to match start, checking for valid player conditions each second
local function countdownAndStart()
	countdownTask = task.spawn(function()
		for i = 5, 1, -1 do
			local p1, p2 = platePlayers[plate1], platePlayers[plate2]

			-- If either plate is empty, cancel countdown
			if not (p1 and p2) then
				Announcement.Countdown.Visible = false
				cancelCountdown()
				return
			end

			Announcement.Countdown.Text = "Starting in " .. i
			Announcement.Countdown.Visible = true
			task.wait(1)
		end

		Announcement.Countdown.Visible = false
		startMatch()
	end)
end

-- Adds a player to the first empty plate if available, and starts countdown if both plates filled
local function addPlayerToPlate(player)
	if platePlayers[plate1] == nil then
		platePlayers[plate1] = player
	elseif platePlayers[plate2] == nil then
		platePlayers[plate2] = player
	else
		-- Both plates occupied
		return false
	end

	updateBoardForPlate(plate1, platePlayers[plate1])
	updateBoardForPlate(plate2, platePlayers[plate2])
	updateMainBoard()

	-- Start countdown once both plates have players and match is not in progress
	if platePlayers[plate1] and platePlayers[plate2] and not inMatch then
		countdownAndStart()
	end

	return true
end

-- Removes player from plate if present, resets their score, and updates UI
local function removePlayerFromPlate(player)
	for plate, plr in pairs(platePlayers) do
		if plr == player then
			platePlayers[plate] = nil
			scores[player.UserId] = nil
			updateBoardForPlate(plate, nil)
			updateMainBoard()
			break
		end
	end
end

-- Cleans up after match ends, removes push tools, resets variables, updates UI
local function endMatch()
	for _, player in pairs(platePlayers) do
		if player then
			removePushTool(player)
		end
	end

	inMatch = false
	currentRound = 0
	scores = {}
	updateMainBoard()
	updateBoardForPlate(plate1, nil)
	updateBoardForPlate(plate2, nil)
	setHolderVisibility(false)
end

-- Called when a player is knocked off their plate, handles scoring and match progress
local function playerKnockedOff(player)
	if not inMatch then return end

	-- Ensure player is in the match
	local p1, p2 = platePlayers[plate1], platePlayers[plate2]
	if player ~= p1 and player ~= p2 then return end

	-- Increment opponent's score
	local winner = (player == p1) and p2 or p1
	if not winner then return end

	scores[winner.UserId] = (scores[winner.UserId] or 0) + 1
	updateMainBoard()

	-- If max rounds reached, announce winner and end match
	if scores[winner.UserId] >= maxRounds then
		WinnerAnnounce:FireAllClients(winner.Name)
		endMatch()
		return
	end

	-- Otherwise, reset match for next round
	resetMatch()
end

-- RemoteEvent handler: player requests to join match
local JoinMatchEvent = ReplicatedStorage:WaitForChild("JoinMatch")

JoinMatchEvent.OnServerEvent:Connect(function(player)
	if not addPlayerToPlate(player) then
		-- Could send feedback: "Match full"
	end
end)

-- RemoteEvent handler: player knocked off detected by client or other means
local KnockedOffEvent = ReplicatedStorage:WaitForChild("PlayerKnockedOff")

KnockedOffEvent.OnServerEvent:Connect(function(player)
	playerKnockedOff(player)
end)

-- Player leave cleanup
Players.PlayerRemoving:Connect(function(player)
	removePlayerFromPlate(player)
	if inMatch and (platePlayers[plate1] == nil or platePlayers[plate2] == nil) then
		endMatch()
	end
end)

-- Initialize UI state
updateMainBoard()
updateBoardForPlate(plate1, nil)
updateBoardForPlate(plate2, nil)
setHolderVisibility(false)
