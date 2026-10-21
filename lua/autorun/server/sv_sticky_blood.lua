StickyBlood = StickyBlood or {}
StickyBlood.Pending = StickyBlood.Pending or {}

util.AddNetworkString("StickyBlood_Transfer")
util.AddNetworkString("StickyBlood_Carry")
util.AddNetworkString("StickyBlood_Revived")

StickyBlood.HitLog = StickyBlood.HitLog or {}

local function convarNumber(name, default, lo, hi, integer)
	local cv = GetConVar(name)
	local n = default
	if cv then
		if integer then
			n = cv:GetInt()
		else
			n = cv:GetFloat()
		end
	end
	if n < lo then n = lo end
	if n > hi then n = hi end
	return n
end

local function carryEnabled()
	local cv = GetConVar("sticky_blood_carry")
	if not cv then return true end
	return cv:GetInt() ~= 0
end

local function carryTicks()
	return convarNumber("sticky_blood_carry_ticks", 1, 0, 32, true)
end

local function carryWindow()
	return convarNumber("sticky_blood_carry_window", 0.3, 0, 5, false)
end

local function carryMax()
	return convarNumber("sticky_blood_carry_max", 32, 1, 255, true)
end

local function isBulletDamage(dmginfo)
	if dmginfo.IsBulletDamage and dmginfo:IsBulletDamage() then return true end
	if DMG_BUCKSHOT and dmginfo.IsDamageType and dmginfo:IsDamageType(DMG_BUCKSHOT) then
		return true
	end
	return false
end

local function hitDirection(dmginfo, pos)
	local force = dmginfo.GetDamageForce and dmginfo:GetDamageForce()
	if force and force.LengthSqr and force:LengthSqr() > 1e-8 then
		return force:GetNormalized()
	end
	local attacker = dmginfo.GetAttacker and dmginfo:GetAttacker()
	if IsValid(attacker) then
		local origin
		if attacker.EyePos then
			origin = attacker:EyePos()
		end
		if not origin and attacker.GetPos then
			origin = attacker:GetPos()
		end
		if origin then
			local delta = pos - origin
			if delta:LengthSqr() > 1e-8 then
				return delta:GetNormalized()
			end
		end
	end
	return Vector(0, 0, 1)
end

local function pushCapped(list, hit, maxn)
	list[#list + 1] = hit
	while #list > maxn do
		table.remove(list, 1)
	end
end

local function boneLocalHit(ent, pos, dir)
	local count = 0
	if ent.GetBoneCount then
		count = ent:GetBoneCount() or 0
	end
	if count < 1 then return nil end
	if count > 256 then count = 256 end
	local best, bestDist, bestPos, bestAng
	for i = 0, count - 1 do
		local matrix = ent.GetBoneMatrix and ent:GetBoneMatrix(i)
		if matrix then
			local bpos = matrix:GetTranslation()
			local dist = bpos:DistToSqr(pos)
			if not bestDist or dist < bestDist then
				best = i
				bestDist = dist
				bestPos = bpos
				bestAng = matrix:GetAngles()
			end
		end
	end
	if best == nil or not bestPos or not bestAng then return nil end
	local lpos, ldir = StickyBlood.WorldHitToBone(pos, dir, bestPos, bestAng)
	return {bone = best, pos = lpos, dir = ldir}
end

local function storedBlood(rag, npc)
	if rag and rag.StickyBlood ~= nil then return rag.StickyBlood end
	if npc and npc.GetBloodColor then return npc:GetBloodColor() end
	return -1
end

local function takeDeathHits(npc)
	local log = StickyBlood.HitLog[npc]
	StickyBlood.HitLog[npc] = nil
	local recorded = log and #log or 0
	if not carryEnabled() then return recorded, {} end
	local selected = StickyBlood.HitsInWindow(log, engine.TickCount(), carryTicks())
	local hits = {}
	local maxn = carryMax()
	for i = 1, #selected do
		local hit = selected[i]
		local localHit = boneLocalHit(npc, hit.pos, hit.dir)
		if localHit then
			hits[#hits + 1] = localHit
		end
	end
	while #hits > maxn do
		table.remove(hits, 1)
	end
	return recorded, hits
end

local function flushLateHits(rag, bodyId)
	if not IsValid(rag) then return end
	rag.StickyCarryUntil = nil
	local late = rag.StickyCarryLate or {}
	rag.StickyCarryLate = nil
	rag.StickyCarryBudget = nil
	local sent = #late
	if sent > 0 then
		net.Start("StickyBlood_Carry")
		net.WriteUInt(rag:EntIndex(), 16)
		StickyBlood.WriteCarryList(storedBlood(rag), late)
		net.Broadcast()
	end
	if sent > 0 then
		StickyBlood.DebugCarry("server", bodyId or rag:EntIndex(), sent, sent, 0, 0)
	end
end

local function armCarryWindow(rag, sentCount)
	if not carryEnabled() then return end
	local window = carryWindow()
	local budget = carryMax() - sentCount
	if budget < 1 or window <= 0 then return end
	rag.StickyCarryUntil = CurTime() + window
	rag.StickyCarryBudget = budget
	rag.StickyCarryLate = {}
	local bodyId = rag:EntIndex()
	local name = "StickyBlood_Carry_" .. bodyId
	timer.Create(name, window, 1, function()
		flushLateHits(rag, bodyId)
	end)
end

local function recordHit(ent, dmginfo)
	local pos = dmginfo.GetDamagePosition and dmginfo:GetDamagePosition()
	if not pos then return end
	pos = Vector(pos.x, pos.y, pos.z)
	local dir = hitDirection(dmginfo, pos)

	if ent.StickyCarryUntil and CurTime() <= ent.StickyCarryUntil and ent:GetClass() == "prop_ragdoll" then
		local late = ent.StickyCarryLate
		local budget = ent.StickyCarryBudget or 0
		if not late or #late >= budget then return end
		local localHit = boneLocalHit(ent, pos, dir)
		if not localHit then return end
		late[#late + 1] = localHit
		return
	end

	local isBody = (ent.IsNPC and ent:IsNPC()) or (ent.IsNextBot and ent:IsNextBot())
	if not isBody then return end
	local list = StickyBlood.HitLog[ent]
	if not list then
		list = {}
		StickyBlood.HitLog[ent] = list
	end
	pushCapped(list, {
		pos = pos,
		dir = dir,
		tick = engine.TickCount(),
	}, carryMax())
end

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
	StickyBlood.WriteCarryList(-1, nil)
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

	local recorded, hits = takeDeathHits(npc)
	local blood = storedBlood(rag, npc)
	net.Start("StickyBlood_Transfer")
	net.WriteUInt(rag:EntIndex(), 16)
	net.WriteUInt(npc:EntIndex(), 16)
	net.WriteUInt(0, 16)
	StickyBlood.WriteCarryList(blood, hits)
	net.Broadcast()
	if recorded > 0 or #hits > 0 then
		StickyBlood.DebugCarry("server", rag:EntIndex(), recorded, #hits, 0, 0)
	end
	armCarryWindow(rag, #hits)
end)

hook.Add("EntityTakeDamage", "StickyBlood_Carry", function(ent, dmginfo)
	if not carryEnabled() then return end
	if not IsValid(ent) or not dmginfo then return end
	if not isBulletDamage(dmginfo) then return end
	recordHit(ent, dmginfo)
end)

hook.Add("EntityRemoved", "StickyBlood_CarryCleanup", function(ent)
	StickyBlood.HitLog[ent] = nil
	local idx
	pcall(function()
		idx = ent:EntIndex()
	end)
	if idx and idx > 0 then
		timer.Remove("StickyBlood_Carry_" .. idx)
	end
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
