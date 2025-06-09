local Server = {}

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local DataStore = DataStoreService:GetDataStore("A110") -- you can rename these to what you need
local LocalData = require(script.Parent.LocalData)
local LockStore = DataStoreService:GetDataStore("A110LOCKS")
local Backup = DataStoreService:GetDataStore("A110BACKUPS")
local playerCache = {} -- serves as random access memory for data (RAM)

local OnDataLoaded = game:GetService("ReplicatedStorage").RemoteFunctions.ImportantData.OnDataLoaded

local LTIMEOUT = 50

-- checks for any empty values/corrupted values
local function IsAllZero(data)
	for _, v in pairs(data) do
		if v ~= 0 then
			return false
		end
	end
	return true
end

local function checkLocks(UserID) -- checking any available locks on the players data
	local lockKey = "lock_" .. UserID
	local now = os.time()
	
	local success,lockdata = pcall(function()
		return LockStore:GetAsync(lockKey)
	end)
	if not success then
		warn("Failed to achieve lock.", UserID)
		return false
	end
	
	if lockdata == nil or (now - lockdata.timestamp) > LTIMEOUT then
		local lockValue = {
			serverId = game.JobId,
			timestamp = now
		}
		
		local success2, err = pcall(function()
			LockStore:SetAsync(lockKey, lockValue)
		end)
		
		if success2 then
			return true
		else
			warn("Kicking player, failed to set lock:", err)
			game.Players:GetPlayerByUserId(UserID):Kick("Couldnt get lock. Data error 2, rejoin in {50} seconds.", err) -- should never happen, contact draddev on discord if executed.
			return false
		end
		
		
	end
	
end

local function Server.releaseLock(userId) -- releases the player lock, used on player removal.
	local lockKey = "lock_" .. userId
	local success, err = pcall(function()
		LockStore:RemoveAsync(lockKey)
	end)
	if success then print("Lock Released") end
end

-- converts a folder with intvalues into a set of values i.e packing it into a table with jsonencode
local function LeaderstatsToTable(leaderstats)
	local data = {}
	for _, stat in pairs(leaderstats:GetChildren()) do
		print("Packing stat:", stat.Name, "=", stat.Value)
		data[stat.Name] = stat.Value
	end
	print("Converted Leaderstats Table:", data)
	return data
end

-- should ALWAYS be called before anything else, as it unpacks data and caches it.
function Server.GetData(player)
	local locked = checkLocks(player.UserId)
	if not locked then
		-- couldnt lock the code stupid ditly ahh dummy
		player:Kick("Your data is currently in use, please try again shortly.")
		return
	end


	local success, data = pcall(function()
		return DataStore:GetAsync(player.UserId)
	end)



	if success then
		if data then
			print("Raw Data From Store:", data)
			local decoded = HttpService:JSONDecode(data)
			print("Decoded Data Table:", decoded)

			if IsAllZero(decoded) then
				print("All values were 0 — using template instead.")
				local template = LocalData.DataTemplate
				playerCache[player.UserId] = template -- gives the player the default set of data
				return template
			else
				playerCache[player.UserId] = decoded
				return decoded
			end
		else
			print("No data found. Using template.")
			local template = LocalData.DataTemplate
			playerCache[player.UserId] = template
			return template
		end
	else
		warn("Data loading failed!")
		player:Kick("Data Issue, rejoin (Data Error 1)") -- shouldnt ever happen, but here for precautions. line execution indicates a roblox server error.
	end
end

-- initializes the players data, serves as a backbone.
function Server.LoadData(player)
	local playerData = playerCache[player.UserId]
	local LS = Instance.new("Folder")
	LS.Name = "leaderstats"
	LS.Parent = player

	local function makeStat(name, value)
		local val = Instance.new("IntValue")
		val.Name = name
		val.Value = value
		val.Parent = LS
	end
	
	makeStat("Fragments", playerData.Fragments or 0) -- these are renamable to your liking
	makeStat("Sector", playerData.Sector or 0)
	makeStat("Stability", playerData.Stability or 0)
	OnDataLoaded:FireClient(player)
end

-- used to pack sets of values into a table.
function Server.EncodeTest(player) -- test is in the name because it is currently being worked on, but in a 100% working state. slowly being rolled out
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local statsTable = LeaderstatsToTable(leaderstats)
		local encodedStats = HttpService:JSONEncode(statsTable)
		print("Encoded JSON:", encodedStats)
		return encodedStats
	else
		warn("No leaderstats found for", player.Name) -- could mean the players leaderstats have been removed by a third party.
		return nil
	end
end


function Server.SaveData(player)
	local timestamp = os.time()
	local backupKey = player.UserId .. ":" .. timestamp
	
	pcall(function()
		Backup:SetAsync(backupKey, Server.EncodeTest(player)) -- saving the backup
	end)
	
	local encodedStats = Server.EncodeTest(player)
	if not encodedStats then
		warn("Could not encode stats for " .. player.Name)
		return
	end

	local success, err = pcall(function()
		DataStore:SetAsync(player.UserId, encodedStats)
	end)

	if success then
		print("Data saved for", player.Name)
	else
		warn("Could not save data for", player.Name, err)
	end
	print("Saved data with backup.".. player.UserId)
end

function ROLLBACK_DATA(userId) -- used to rollback any data if needed, i.e data is corrupted
	local AttemptKeys = {
		userId .. ":" .. tostring(os.time() - 60),
		userId .. ":" .. tostring(os.time() - 120),
		userId .. ":" .. tostring(os.time() - 180)
	}
	
	for _, key in ipairs(AttemptKeys) do
		local success, data = pcall(function()
			return Backup:GetAsync(key)
		end)
		if success and data then
			return data
		else
			warn("Critical Data Issue, Could not process rollback.")
			return
		end
	end
	
	return nil
end

function Server.OnPlayerRemoving(plr)
	Server.SaveData(plr)
	Server.ReleaseLock(plr.UserId)
end

local function Init(plr)
	local remote = game:GetService("ReplicatedStorage").RemoteFunctions.ImportantData.LoadingSector
	local sector = playerCache[plr].Sector
	local spawns = workspace.Spawns
	if spawns then
		plr:LoadCharacter()
		plr.Character.HumanoidRootPart.CFrame = spawns.Sector1:FindFirstChild(plr.Name).CFrame
		remote:FireClient(plr)
	end
end

local function WIPE_DATA(plr) -- here incase you need to wipe somebodys data, in the case of a cheater or such.
	if playerCache[plr] then
		playerCache[plr] = nil
		plr:Kick("Wiping data") -- kicks the player before wiping data so it doesnt save anything
		local success, err = pcall(function()
			DataStore:RemoveAsync(plr.UserId) -- removes the player from the server, but keeps the backup incase it was a mistake.
		end)
		if success then
			print("Data wiped for", plr.Name)
		else
			warn("Failed to wipe data for", plr.Name, err)
		end
	end
end

local function ClearBackups(userId) -- should never be used, but here incase you do need it.
	local AttemptKeys = {
		userId .. ":" .. tostring(os.time() - 60),
		userId .. ":" .. tostring(os.time() - 120),
		userId .. ":" .. tostring(os.time() - 180)
	}
	for _,key in ipairs(AttemptKeys) do -- checking every key for the backup
		local success, data = pcall(function()
			Backup:GetAsync(key, userId)
		end)
		if success and data then
			Backup:RemoveAsync(key) -- if a key is found, then remove the data.
		end
	end
end

return Server
