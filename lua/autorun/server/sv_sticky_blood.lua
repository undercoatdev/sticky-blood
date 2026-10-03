StickyBlood = StickyBlood or {}
StickyBlood.Pending = StickyBlood.Pending or {}

util.AddNetworkString("StickyBlood_Transfer")
util.AddNetworkString("StickyBlood_Revived")

local function forceServerRagdolls()
	RunConsoleCommand("ai_serverragdolls", "1")
end

hook.Add("Initialize", "StickyBlood_ServerRagdolls", forceServerRagdolls)
forceServerRagdolls()

local function captureBodygroups(ent)
	local groups = {}
	local count = 0
	if ent.GetNumBodyGroups then
		count = ent:GetNumBodyGroups() or 0
	end
	for i = 0, count - 1 do
		groups[#groups + 1] = {i, ent:GetBodygroup(i)}
	end
	return groups
end

local function applyBodygroups(ent, groups)
	if not groups then return end
	for _, pair in ipairs(groups) do
		ent:SetBodygroup(pair[1], pair[2])
	end
end

function StickyBlood.Remember(rag, npc)
	if not IsValid(rag) or not IsValid(npc) then return end
	rag.StickyClass = npc:GetClass()
	rag.StickyModel = npc:GetModel()
	rag.StickySkin = npc:GetSkin()
	rag.StickyBodygroups = captureBodygroups(npc)
	if npc.GetBloodColor then
		rag.StickyBlood = npc:GetBloodColor()
	end
end

function StickyBlood.RequestSnatch(dest, src)
	if not IsValid(dest) or not IsValid(src) then return end
	StickyBlood.Token = (StickyBlood.Token or 0) + 1
	if StickyBlood.Token > 65535 then
		StickyBlood.Token = 1
	end
	local token = StickyBlood.Token
	StickyBlood.Pending[token] = src

	net.Start("StickyBlood_Transfer")
	net.WriteUInt(dest:EntIndex(), 16)
	net.WriteUInt(src:EntIndex(), 16)
	net.WriteUInt(token, 16)
	net.Broadcast()

	timer.Simple(1, function()
		local ent = StickyBlood.Pending[token]
		if not ent then return end
		StickyBlood.Pending[token] = nil
		if IsValid(ent) then
			ent:Remove()
		end
	end)
end

local function spawnStanding(class, model, skin, groups, blood, pos, yaw)
	if not class or class == "" then return end
	local npc = ents.Create(class)
	if not IsValid(npc) then return end
	npc:SetPos(pos + Vector(0, 0, 8))
	npc:SetAngles(Angle(0, yaw or 0, 0))
	if model and model ~= "" then
		npc:SetModel(model)
	end
	npc:Spawn()
	npc:Activate()
	if model and model ~= "" then
		npc:SetModel(model)
	end
	if skin then
		npc:SetSkin(skin)
	end
	applyBodygroups(npc, groups)
	if blood and npc.SetBloodColor then
		npc:SetBloodColor(blood)
	end
	npc:DropToFloor()
	return npc
end

function StickyBlood.ReviveRagdoll(rag)
	if not IsValid(rag) or rag:GetClass() ~= "prop_ragdoll" then return end
	if not rag.StickyClass then return end
	local npc = spawnStanding(
		rag.StickyClass,
		rag.StickyModel,
		rag.StickySkin,
		rag.StickyBodygroups,
		rag.StickyBlood,
		rag:GetPos(),
		rag:GetAngles().y
	)
	if not IsValid(npc) then return end
	StickyBlood.RequestSnatch(npc, rag)
end

function StickyBlood.ReviveDeadNPC(npc)
	if not IsValid(npc) or not npc:IsNPC() then return end
	if npc:Health() > 0 then return end
	local fresh = spawnStanding(
		npc:GetClass(),
		npc:GetModel(),
		npc:GetSkin(),
		captureBodygroups(npc),
		npc.GetBloodColor and npc:GetBloodColor() or nil,
		npc:GetPos(),
		npc:GetAngles().y
	)
	if not IsValid(fresh) then return end
	StickyBlood.RequestSnatch(fresh, npc)
end

hook.Add("CreateEntityRagdoll", "StickyBlood", function(npc, rag)
	if not IsValid(npc) or not IsValid(rag) then return end
	if not npc:IsNPC() and not npc:IsNextBot() then return end
	StickyBlood.Remember(rag, npc)

	net.Start("StickyBlood_Transfer")
	net.WriteUInt(rag:EntIndex(), 16)
	net.WriteUInt(npc:EntIndex(), 16)
	net.WriteUInt(0, 16)
	net.Broadcast()
end)

net.Receive("StickyBlood_Revived", function(_, ply)
	if not IsValid(ply) then return end
	local token = net.ReadUInt(16)
	local ent = StickyBlood.Pending[token]
	if not ent then return end
	StickyBlood.Pending[token] = nil
	if IsValid(ent) then
		ent:Remove()
	end
end)
