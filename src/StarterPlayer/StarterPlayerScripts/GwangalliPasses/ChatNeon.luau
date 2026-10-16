-- GwangalliPasses/ChatNeon (client): the neon name in chat (pass #4). TextChatService.OnIncomingMessage is a
-- single callback that cannot be chained, and nothing in the place sets it today: we claim it only when nobody
-- has (marker attribute TextChatService.GwIncomingOwner), so a later add-on can see it is taken. For a message
-- whose sender has GwNeonName, the sender's display name inside PrefixText becomes a per-letter gradient
-- (rich text) with a ✦; every other part of the prefix (team colours, tags) is left as it was.
-- Legacy chat is handled on the server (NeonName.luau: speaker NameColor + tag).

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local ChatNeon = {}

function ChatNeon.start(ctx: any)
	local P = ctx.P
	if not P.Config.NEON.CHAT then
		return
	end
	local Neon = P.mod("Neon")
	local ok, version = pcall(function()
		return TextChatService.ChatVersion
	end)
	if not ok or version ~= Enum.ChatVersion.TextChatService then
		return
	end
	local owner = TextChatService:GetAttribute("GwIncomingOwner")
	if owner ~= nil and owner ~= "GwangalliPasses" then
		return -- another add-on owns the callback
	end
	TextChatService:SetAttribute("GwIncomingOwner", "GwangalliPasses")
	local cache: { [string]: string } = {}
	local okSet = pcall(function()
		TextChatService.OnIncomingMessage = function(message: TextChatMessage): TextChatMessageProperties?
			local src = message.TextSource
			if not src then
				return nil
			end
			local p = Players:GetPlayerByUserId(src.UserId)
			local id = p and p:GetAttribute(P.Attr.Neon)
			local pal = Neon.get(id)
			if not p or not pal then
				return nil
			end
			local prefix = message.PrefixText
			local name = p.DisplayName
			local s, e = string.find(prefix, name, 1, true)
			if not s then
				return nil
			end
			local key = id .. "|" .. name
			local rich = cache[key]
			if not rich then
				rich = "<font color=\"#FFC247\">✦</font> " .. Neon.rich(name, pal, true)
				cache[key] = rich
			end
			local props = Instance.new("TextChatMessageProperties")
			props.PrefixText = string.sub(prefix, 1, s - 1) .. rich .. string.sub(prefix, (e :: number) + 1)
			return props
		end
	end)
	if not okSet then
		TextChatService:SetAttribute("GwIncomingOwner", nil)
	end
end

return ChatNeon
