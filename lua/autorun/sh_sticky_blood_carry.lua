StickyBlood = StickyBlood or {}

local function components(v)
	return v.x or 0, v.y or 0, v.z or 0
end

local function unit(x, y, z)
	local len = math.sqrt(x * x + y * y + z * z)
	if len <= 1e-8 then
		return {x = 0, y = 0, z = 1}
	end
	return {x = x / len, y = y / len, z = z / len}
end

local function angles(ang)
	local pitch = ang.p
	if pitch == nil then pitch = ang.pitch or 0 end
	local yaw = ang.y
	if yaw == nil then yaw = ang.yaw or 0 end
	local roll = ang.r
	if roll == nil then roll = ang.roll or 0 end
	return pitch, yaw, roll
end

-- Source AngleMatrix columns: local X (forward), local Y (left), local Z (up).
local function boneAxes(ang)
	local pitch, yaw, roll = angles(ang)
	pitch, yaw, roll = math.rad(pitch), math.rad(yaw), math.rad(roll)
	local sp, cp = math.sin(pitch), math.cos(pitch)
	local sy, cy = math.sin(yaw), math.cos(yaw)
	local sr, cr = math.sin(roll), math.cos(roll)
	local xAxis = {x = cp * cy, y = cp * sy, z = -sp}
	local yAxis = {x = sr * sp * cy - cr * sy, y = sr * sp * sy + cr * cy, z = sr * cp}
	local zAxis = {x = cr * sp * cy + sr * sy, y = cr * sp * sy - sr * cy, z = cr * cp}
	return xAxis, yAxis, zAxis
end

local function dot(ax, ay, az, b)
	return ax * b.x + ay * b.y + az * b.z
end

function StickyBlood.HitsInWindow(hits, deathTick, carryTicks)
	local kept = {}
	if not hits then return kept end
	local minTick = deathTick - (carryTicks or 0)
	for i = 1, #hits do
		local hit = hits[i]
		if hit.tick and hit.tick >= minTick then
			kept[#kept + 1] = hit
		end
	end
	return kept
end

function StickyBlood.WorldHitToBone(worldPos, worldDir, bonePos, boneAng)
	local xAxis, yAxis, zAxis = boneAxes(boneAng)
	local px, py, pz = components(worldPos)
	local bx, by, bz = components(bonePos)
	local dx, dy, dz = px - bx, py - by, pz - bz
	local dirx, diry, dirz = components(worldDir)
	local lpos = {
		x = dot(dx, dy, dz, xAxis),
		y = dot(dx, dy, dz, yAxis),
		z = dot(dx, dy, dz, zAxis),
	}
	local ldir = unit(
		dot(dirx, diry, dirz, xAxis),
		dot(dirx, diry, dirz, yAxis),
		dot(dirx, diry, dirz, zAxis)
	)
	return lpos, ldir
end

function StickyBlood.BoneHitToWorld(localPos, localDir, bonePos, boneAng)
	local xAxis, yAxis, zAxis = boneAxes(boneAng)
	local lx, ly, lz = components(localPos)
	local dx, dy, dz = components(localDir)
	local bx, by, bz = components(bonePos)
	local wpos = {
		x = bx + lx * xAxis.x + ly * yAxis.x + lz * zAxis.x,
		y = by + lx * xAxis.y + ly * yAxis.y + lz * zAxis.y,
		z = bz + lx * xAxis.z + ly * yAxis.z + lz * zAxis.z,
	}
	local wdir = unit(
		dx * xAxis.x + dy * yAxis.x + dz * zAxis.x,
		dx * xAxis.y + dy * yAxis.y + dz * zAxis.y,
		dx * xAxis.z + dy * yAxis.z + dz * zAxis.z
	)
	return wpos, wdir
end

-- BLOOD_COLOR_RED = 0, YELLOW = 1, GREEN = 2, MECH = 3, ANTLION = 4,
-- ZOMBIE = 5, ANTLION_WORKER = 6, DONT_BLEED = -1.
-- Worker uses the same yellow decal as the other antlion colours.
function StickyBlood.DecalForBloodColor(color)
	color = tonumber(color)
	if not color then return nil end
	if color == 0 then return "Blood" end
	if color == 1 or color == 2 or color == 4 or color == 5 or color == 6 then
		return "YellowBlood"
	end
	return nil
end

function StickyBlood.DebugCarry(side, body, recorded, sent, applied, retries)
	if not GetConVar then return end
	local cv = GetConVar("sticky_blood_debug")
	if not cv or cv:GetInt() ~= 1 then return end
	local id = body
	if type(body) ~= "number" then
		id = -1
		if IsValid and IsValid(body) and body.EntIndex then
			id = body:EntIndex()
		end
	end
	print(string.format(
		"StickyBlood carry %s body=%s recorded=%d sent=%d applied=%d retries=%d",
		tostring(side),
		tostring(id),
		recorded or 0,
		sent or 0,
		applied or 0,
		retries or 0
	))
end

function StickyBlood.WriteCarryList(blood, hits)
	blood = tonumber(blood) or -1
	blood = math.floor(blood)
	if blood < -128 then blood = -128 end
	if blood > 127 then blood = 127 end
	net.WriteInt(blood, 8)
	local count = 0
	if hits then count = #hits end
	if count > 255 then count = 255 end
	net.WriteUInt(count, 8)
	for i = 1, count do
		local hit = hits[i]
		local bone = hit.bone or 0
		if bone < 0 then bone = 0 end
		if bone > 255 then bone = 255 end
		net.WriteUInt(math.floor(bone), 8)
		local pos = hit.pos
		net.WriteVector(Vector(pos.x, pos.y, pos.z))
		local dir = hit.dir
		local normal = Vector(dir.x, dir.y, dir.z)
		if normal:LengthSqr() <= 1e-8 then
			normal = Vector(0, 0, 1)
		else
			normal:Normalize()
		end
		net.WriteNormal(normal)
	end
end

function StickyBlood.ReadCarryList()
	local blood = net.ReadInt(8)
	local count = net.ReadUInt(8)
	local hits = {}
	for i = 1, count do
		hits[i] = {
			bone = net.ReadUInt(8),
			pos = net.ReadVector(),
			dir = net.ReadNormal(),
		}
	end
	return blood, hits
end

if CreateConVar and not (GetConVar and GetConVar("sticky_blood_carry")) then
	local flags = FCVAR_ARCHIVE + FCVAR_REPLICATED
	CreateConVar("sticky_blood_carry", "1", flags, "Keep death-tick bullet hits on the ragdoll (1 on, 0 off)", 0, 1)
	CreateConVar("sticky_blood_carry_ticks", "1", flags, "Server ticks before death whose bullet hits are kept", 0, 32)
	CreateConVar("sticky_blood_carry_window", "0.3", flags, "Seconds after ragdoll creation to keep bullet hits on it", 0, 5)
	CreateConVar("sticky_blood_carry_max", "32", flags, "Maximum bullet hits carried onto one body", 1, 255)
	CreateConVar("sticky_blood_debug", "0", flags, "Print one line each time bullet hits are carried", 0, 1)
end
