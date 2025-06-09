local Server = {}

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local DataStore = DataStoreService:GetDataStore("A110") -- you can change the names of all these datastores to personal preference.
local LocalData = require(script.Parent.LocalData) -- this block is explained in readme
local LockStore = DataStoreService:GetDataStore("A110LOCKS")
local Backup = DataStoreService:GetDataStore("A110BACKUPS")
local playerCache = {} -- table where all players are cached, acts as server random access memory (RAM)

local OnDataLoaded = game:GetService("ReplicatedStorage").RemoteFunctions.ImportantData.OnDataLoaded

local LTIMEOUT = 50 -- lock debounce

-- Confirms data is working
local function IsAllZero(data)
	for _, v in pairs(data) do
		if v ~= 0 then
		return false -- lets you know if the player has data values of 0, which in my case shouldnt happen, applies in applicable regions of your game.
		end
	end
	return true
end

local function checkLocks(UserID) -- checks for any session locks on the player
	local lockKey = "lock_" .. UserID
	local now = os.time()
	
	local success,lockdata = pcall(function()
		return LockStore:GetAsync(lockKey)
	end)
	if not success then
		warn("Failed to achieve lock.", UserID)
		return false
	end
	
	if lockdata == nil or (now - lockdata.timestamp) > LTIMEOUT then -- checks if there is no lock or the lock has timed out
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
			game.Players:GetPlayerByUserId(UserID):Kick("Couldnt get lock. Data error 2, rejoin in {50} seconds.", err) -- kicks the player since data could not be accessed, this usually indicates a critical issue and you should contact draddev on discord if any case happens.
			return false
		end
		
		
	end
	
end

function Server.releaseLock(userId) -- this can be used on player leaving to release any locks on the player
	local lockKey = "lock_" .. userId
	local success, err = pcall(function()
		LockStore:RemoveAsync(lockKey)
	end)
	if success then print("Lock Released") end
end

-- Converts folders to a table, not limited to leaderstats
local function LeaderstatsToTable(leaderstats)
	local data = {}
	for _, stat in pairs(leaderstats:GetChildren()) do -- packing all values applicable in the folder into a table
		print("Packing stat:", stat.Name, "=", stat.Value)
		data[stat.Name] = stat.Value
	end
	print("Converted Leaderstats Table:", data)
	return data
end

-- Always call this before anything else on game start to prevent glitches.
function Server.GetData(player) -- loads all data, basically initiates the game.
	local locked = checkLocks(player.UserId)
	if not locked then
		-- This will kick the player if their session lock is in use.
		player:Kick("Your data is currently in use, please try again shortly.")
		return
	end


	local success, data = pcall(function()
		return DataStore:GetAsync(player.UserId) -- basically just grabbing data stored in datastores
	end)



	if success then
		if data then
			print("Raw Data From Store:", data)
			local decoded = HttpService:JSONDecode(data) -- unpacks packed data, which gets packed in line 148
			print("Decoded Data Table:", decoded)

			if IsAllZero(decoded) then
				print("All values were 0 — using template instead.")
				local template = LocalData.DataTemplate
				playerCache[player.UserId] = template
				return template
			else
				playerCache[player.UserId] = decoded
				return decoded
			end
		else
			print("No data found. Using template.")
			local template = LocalData.DataTemplate -- Data couldnt be found so it is reverting to default templates, you should have a seperate module for this (suggested, less blocky, easier to edit)
			playerCache[player.UserId] = template
			return template
		end
	else
		warn("Data loading failed!")
		player:Kick("Data Issue, rejoin (Data Error 1)")
	end
end

-- Load data
function Server.LoadData(player) -- loads data, SHOULD NOT BE CALLED BEFORE GETDATA
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

	makeStat("yournamehere", playerData.yournamehere or 0) -- these should be named after your data, these are all lines in my game, but with their respective names.
	makeStat("yournamehere", playerData.yournamehere or 0)
	makeStat("yournamehere", playerData.yournamehere or 0)
	OnDataLoaded:FireClient(player)
end

-- Function to encode data
function Server.EncodeTest(player) -- currently being improved on, hence the "test" in it, but it is in a working state and works 100%.
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local statsTable = LeaderstatsToTable(leaderstats)
		local encodedStats = HttpService:JSONEncode(statsTable)
		print("Encoded JSON:", encodedStats)
		return encodedStats
	else
		warn("No leaderstats found for", player.Name)
		return nil
	end
end


function Server.SaveData(player) -- saves player data, should be called every 60 seconds and on player leaving.
	local timestamp = os.time()
	local backupKey = player.UserId .. ":" .. timestamp
	
	pcall(function()
		Backup:SetAsync(backupKey, Server.EncodeTest(player))
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

local function ROLLBACK_DATA(userId) -- data rollbacking, should only be used in cases of data corruption, cheating, or glitches.
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
			warn("Critical Data Issue, Could not process rollback.") -- in this case either revert to a screenshot or completely reset the data. Data snapshots on the cloud will be added soon.
			return
		end
	end
	
	return nil
end

return Server
