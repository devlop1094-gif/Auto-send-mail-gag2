local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

local Window = Fluent:CreateWindow({
    Title = "ssgontop hub",
    SubTitle = "GAG2 Mailbox Gifter",
    TabWidth = 160,
    Size = UDim2.fromOffset(640, 560),
    Acrylic = true,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl
})

local Tabs = {
    Main = Window:AddTab({ Title = "Main", Icon = "gift" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" })
}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local networkingModule = ReplicatedStorage.SharedModules:WaitForChild("Networking")
local Networking = require(networkingModule)
local PlayerStateClient = require(ReplicatedStorage.ClientModules.PlayerStateClient)
local PetData = require(ReplicatedStorage.SharedData.PetData)
local MailboxItemCatalog = require(LocalPlayer.PlayerScripts.Controllers.MailboxController.MailboxItemCatalog)

local mailboxNet = nil
local mailboxNetModule = nil
local mailboxBackup = {}
local MAILBOX_KEYS = { "SendBatch", "LookupPlayer" }

local function isMailboxEndpoint(value)
	return typeof(value) == "table" and typeof(value.Fire) == "function"
end

local function captureMailboxBackup(net)
	if typeof(net) ~= "table" or typeof(net.Mailbox) ~= "table" then return end
	for _, key in MAILBOX_KEYS do
		local endpoint = net.Mailbox[key]
		if isMailboxEndpoint(endpoint) then mailboxBackup[key] = endpoint end
	end
end

captureMailboxBackup(Networking)

local function wrapMailboxRemote(remote)
	if not remote then return nil end
	if remote:IsA("RemoteFunction") then return { Fire = function(...) return remote:InvokeServer(...) end } end
	if remote:IsA("RemoteEvent") then return { Fire = function(...) remote:FireServer(...) return true end } end
	if isMailboxEndpoint(remote) then return remote end
	return nil
end

local function findMailboxRemote(name)
	for _, inst in ReplicatedStorage:GetDescendants() do
		if inst.Name == name and (inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction")) then
			if string.find(string.lower(inst:GetFullName()), "mailbox") then return inst end
		end
	end
	for _, inst in ReplicatedStorage:GetDescendants() do
		if inst.Name == name and (inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction")) then return inst end
	end
	return nil
end

local function restoreMailboxOnNet(net)
	if typeof(net) ~= "table" then return false end
	if typeof(net.Mailbox) ~= "table" then net.Mailbox = {} end
	local ok = true
	for _, key in MAILBOX_KEYS do
		if not isMailboxEndpoint(net.Mailbox[key]) then
			local backup = mailboxBackup[key]
			if isMailboxEndpoint(backup) then
				net.Mailbox[key] = backup
			else
				local wrapped = wrapMailboxRemote(findMailboxRemote(key))
				if wrapped then
					net.Mailbox[key] = wrapped
					mailboxBackup[key] = wrapped
				else ok = false end
			end
		else
			mailboxBackup[key] = net.Mailbox[key]
		end
	end
	return ok
end

local function acquireMailboxNetworking()
	if mailboxNet and restoreMailboxOnNet(mailboxNet) then return mailboxNet end
	mailboxNetModule = networkingModule:Clone()
	mailboxNetModule.Parent = gethui and gethui() or LocalPlayer:FindFirstChild("PlayerGui") or ReplicatedStorage
	local ok, net = pcall(function() return require(mailboxNetModule) end)
	if ok and net and restoreMailboxOnNet(net) then
		mailboxNet = net
		captureMailboxBackup(net)
		return net
	end
	return Networking
end

task.spawn(function()
	while true do
		pcall(acquireMailboxNetworking)
		task.wait(0.4)
	end
end)

-- ================== 언어 설정 ==================
local lang = "ko"  -- ko 또는 en

local function getText(key)
    if lang == "ko" then
        local texts = {
            recipient = "받을 사람",
            message = "메시지",
            sendAll = "모두 보내기",
            refresh = "인벤토리 새로고침",
            start = "▶ 시작 / ■ 중지",
            stats = "진행 상황",
            sent = "보낸 개수",
            value = "총 가치",
            fail = "실패"
        }
        return texts[key] or key
    else
        local texts = {
            recipient = "Recipient",
            message = "Message",
            sendAll = "Send All",
            refresh = "Refresh Inventory",
            start = "▶ Start / ■ Stop",
            stats = "Progress",
            sent = "Sent Count",
            value = "Total Value",
            fail = "Failed"
        }
        return texts[key] or key
    end
end

-- ================== UI ==================
local recipientInput = Tabs.Main:AddInput("Recipient", { Title = getText("recipient"), Default = "", Placeholder = "닉네임", Callback = function(v) recipient = v end })
local messageInput = Tabs.Main:AddInput("Message", { Title = getText("message"), Default = "thx", Placeholder = "메시지", Callback = function(v) giftMessage = v end })

Tabs.Main:AddToggle("SendAllToggle", {
    Title = getText("sendAll"),
    Default = true,
    Description = "ON = 전체 자동 | OFF = 선택 모드",
    Callback = function(state) sendAll = state end
})

local selectionSection = Tabs.Main:AddSection("선택해서 보내기 (모두 보내기 OFF)")

local itemToggles = {}
local function refreshInventory()
    for _, t in pairs(itemToggles) do t:Destroy() end
    itemToggles = {}
    local replica = PlayerStateClient:GetLocalReplica()
    if not replica or not replica.Data or not replica.Data.Inventory then return end
    local inventory = replica.Data.Inventory
    for category, bucket in pairs(inventory) do
        if typeof(bucket) == "table" then
            for itemKey, data in pairs(bucket) do
                if MailboxItemCatalog.IsGiftable(category) then
                    local name = (category == "Pets" and typeof(data) == "table" and data.Name) or itemKey
                    local toggle = selectionSection:AddToggle("Item_"..category..tostring(itemKey), {
                        Title = tostring(name) .. " ["..category.."]",
                        Default = false,
                        Callback = function(state)
                            if state then table.insert(selectedItems, {Category=category, ItemKey=itemKey, Data=data}) end
                        end
                    })
                    table.insert(itemToggles, toggle)
                end
            end
        end
    end
end

Tabs.Main:AddButton({ Title = getText("refresh"), Description = "", Callback = refreshInventory })

local statsParagraph = Tabs.Main:AddParagraph({ Title = getText("stats"), Content = getText("sent")..": 0\n"..getText("value")..": 0\n"..getText("fail")..": 0" })

Tabs.Main:AddButton({
    Title = getText("start"),
    Description = "",
    Callback = function()
        running = not running
    end
})

-- 한/영 토글
Tabs.Main:AddToggle("LangToggle", {
    Title = "언어 변경 (Korean / English)",
    Default = false,
    Callback = function(state)
        lang = state and "en" or "ko"
        Fluent:Notify({Title = "언어 변경", Content = lang == "ko" and "한국어로 변경되었습니다." or "Changed to English."})
    end
})

local recipient = ""
local giftMessage = "thx"
local running = false
local sendAll = true
local sentCount = 0
local sentValue = 0
local failCount = 0
local selectedItems = {}

task.spawn(function()
    while true do
        if running and recipient ~= "" then
            local net = acquireMailboxNetworking()
            local userId = net.Mailbox.LookupPlayer:Fire(recipient)
            if typeof(userId) == "number" and userId > 0 then
                local itemsToSend = sendAll and {} or selectedItems
                local ok, success = pcall(function()
                    return net.Mailbox.SendBatch:Fire(userId, itemsToSend, giftMessage)
                end)
                if ok and success then
                    sentCount = sentCount + #itemsToSend
                    sentValue = sentValue + 1000
                else
                    failCount = failCount + 1
                end
            end

            statsParagraph:SetDesc(string.format(
                getText("sent")..": %d\n"..getText("value")..": %d\n"..getText("fail")..": %d",
                sentCount, math.floor(sentValue), failCount
            ))
        end
        task.wait(1.5)
    end
end)

refreshInventory()
Window:SelectTab(1)

Fluent:Notify({ Title = "ssgontop hub", Content = "로드 완료! 인벤토리 새로고침을 눌러주세요.", Duration = 8 })
