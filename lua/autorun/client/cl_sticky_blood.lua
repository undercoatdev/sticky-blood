local function snatchOnce(dest, src)
	if not IsValid(dest) or not IsValid(src) then return false end
	if dest == src then return false end
	if dest.StickySnatchedFrom == src then return true end
	local ok = pcall(function()
		dest:SnatchModelInstance(src)
	end)
	if not ok then return false end
	dest.StickySnatchedFrom = src
	return true
end

local function ragdollNear(pos, model, src)
	local best, bestDist
	for _, rag in ipairs(ents.FindInSphere(pos, 96)) do
		if rag:GetClass() == "prop_ragdoll" and rag:GetModel() == model and rag.StickySnatchedFrom ~= src then
			local dist = rag:GetPos():DistToSqr(pos)
			if not bestDist or dist < bestDist then
				best = rag
				bestDist = dist
			end
		end
	end
	return best
end

hook.Add("CreateClientsideRagdoll", "StickyBlood", function(npc, rag)
	snatchOnce(rag, npc)
end)

hook.Add("EntityRemoved", "StickyBlood", function(npc)
	local isBody, pos, model = false, nil, nil
	pcall(function()
		isBody = npc:IsNPC() or npc:IsNextBot()
		pos = npc:GetPos()
		model = npc:GetModel()
	end)
	if not isBody or not pos or not model then return end

	local rag = ragdollNear(pos, model, npc)
	if snatchOnce(rag, npc) then return end

	local deadline = CurTime() + 1
	local name = "StickyBlood_WaitRag_" .. tostring(npc:EntIndex()) .. "_" .. math.floor(pos.x) .. "_" .. math.floor(pos.y)
	hook.Add("Think", name, function()
		if CurTime() > deadline then
			hook.Remove("Think", name)
			return
		end
		local found = ragdollNear(pos, model, npc)
		if snatchOnce(found, npc) then
			hook.Remove("Think", name)
		end
	end)
end)

local frozenMaterials = {}
local stampWhite = Color(255, 255, 255)

local function texturePath(raw)
	if not raw or raw == "" then return nil end
	raw = string.gsub(raw, "^materials/", "")
	raw = string.gsub(raw, "%.vtf$", "")
	raw = string.gsub(raw, "\\", "/")
	if raw == "" then return nil end
	return raw
end

local function vtfFrameCount(tex)
	local data = file.Read("materials/" .. tex .. ".vtf", "GAME")
	if not data or #data < 26 then return nil end
	if string.sub(data, 1, 4) ~= "VTF\0" then return nil end
	local frames = string.byte(data, 25) + string.byte(data, 26) * 256
	if frames < 1 then return nil end
	return frames
end

local function frozenMaterial(tex, frame)
	local key = tex .. ":" .. frame
	local cached = frozenMaterials[key]
	if cached then return cached end
	local mat = CreateMaterial("sticky_blood_freeze_" .. util.CRC(key), "VertexLitGeneric", {
		["$basetexture"] = tex,
		["$frame"] = tostring(frame),
		["$vertexcolor"] = "1",
		["$vertexalpha"] = "1",
		["$decalscale"] = "0.02",
	})
	frozenMaterials[key] = mat
	return mat
end

local function isBody(ent)
	if not IsValid(ent) then return false end
	if ent:IsNPC() or ent:IsNextBot() then return true end
	return ent:GetClass() == "prop_ragdoll"
end

local function stampFinishedGif(plate)
	local path, owner, pos, normal, scale
	local ok = pcall(function()
		path = string.lower(plate:GetMaterial() or "")
		owner = plate:GetOwner()
		if not IsValid(owner) then owner = plate:GetParent() end
		pos = plate:GetPos()
		normal = plate:GetUp()
		scale = plate:GetModelScale()
	end)
	if not ok or not path or not pos or not normal then return end
	if not string.find(path, "animated_blood/", 1, true) and not string.find(path, "decals/flesh/animated/", 1, true) then return end
	if string.find(path, "lastframe", 1, true) then return end
	if not isBody(owner) then return end
	if not scale or scale < 0.05 then return end
	if normal:LengthSqr() < 0.01 then return end

	local src = Material(path)
	if src:IsError() then return end
	local tex = texturePath(src:GetString("$basetexture"))
	if not tex then return end
	local frames = vtfFrameCount(tex)
	if not frames then return end

	local radius = 2.5 * scale
	util.DecalEx(frozenMaterial(tex, frames - 1), owner, pos, normal, stampWhite, radius, radius)
end

hook.Add("EntityRemoved", "StickyBlood_FreezeFrame", stampFinishedGif)

net.Receive("StickyBlood_Transfer", function()
	local destId = net.ReadUInt(16)
	local srcId = net.ReadUInt(16)
	local token = net.ReadUInt(16)
	local deadline = CurTime() + 1
	local name = "StickyBlood_Watch_" .. destId .. "_" .. srcId .. "_" .. token
	local acked = false
	local function attempt()
		local done = snatchOnce(Entity(destId), Entity(srcId))
		if done and token > 0 and not acked then
			acked = true
			net.Start("StickyBlood_Revived")
			net.WriteUInt(token, 16)
			net.SendToServer()
		end
		return done
	end
	if attempt() then return end
	hook.Add("Think", name, function()
		if attempt() or CurTime() > deadline then
			hook.Remove("Think", name)
		end
	end)
end)
