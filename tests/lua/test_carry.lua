local modulePath = arg[1]
if not modulePath then
	io.stderr:write("missing helper path\n")
	os.exit(1)
end

dofile(modulePath)

local failures = 0

local function fail(msg)
	failures = failures + 1
	io.stderr:write(msg .. "\n")
end

local function eq(actual, expected, msg)
	if actual ~= expected then
		fail((msg or "eq") .. ": got " .. tostring(actual) .. ", expected " .. tostring(expected))
	end
end

local function near(actual, expected, msg)
	if math.abs(actual - expected) > 1e-5 then
		fail((msg or "near") .. ": got " .. tostring(actual) .. ", expected " .. tostring(expected))
	end
end

local function nearVec(actual, x, y, z, msg)
	near(actual.x, x, (msg or "vec") .. ".x")
	near(actual.y, y, (msg or "vec") .. ".y")
	near(actual.z, z, (msg or "vec") .. ".z")
end

local function testWindow()
	local older = {tick = 98, id = "old"}
	local edge = {tick = 99, id = "edge"}
	local death = {tick = 100, id = "death"}
	local hits = {older, edge, death}
	local kept = StickyBlood.HitsInWindow(hits, 100, 1)
	eq(#kept, 2, "window count")
	eq(kept[1], edge, "window keeps the same edge hit")
	eq(kept[2], death, "window keeps the death hit")
	eq(#hits, 3, "window does not drop stored hits")

	local exact = StickyBlood.HitsInWindow(hits, 100, 0)
	eq(#exact, 1, "zero ticks keeps only the death tick")
	eq(exact[1], death, "zero ticks keeps the death hit")

	eq(#StickyBlood.HitsInWindow(nil, 10, 1), 0, "nil hit list")
	eq(#StickyBlood.HitsInWindow({}, 10, 1), 0, "empty hit list")

	local missing = StickyBlood.HitsInWindow({{id = "notick"}, {tick = 10, id = "ok"}}, 10, 0)
	eq(#missing, 1, "hits without a tick are left out")
	eq(missing[1].id, "ok", "ticked hit remains")
end

local function roundtrip(worldPos, worldDir, bonePos, boneAng, label)
	local lpos, ldir = StickyBlood.WorldHitToBone(worldPos, worldDir, bonePos, boneAng)
	local wpos, wdir = StickyBlood.BoneHitToWorld(lpos, ldir, bonePos, boneAng)
	near(wpos.x, worldPos.x, label .. " pos.x")
	near(wpos.y, worldPos.y, label .. " pos.y")
	near(wpos.z, worldPos.z, label .. " pos.z")
	local len = math.sqrt(worldDir.x * worldDir.x + worldDir.y * worldDir.y + worldDir.z * worldDir.z)
	near(wdir.x, worldDir.x / len, label .. " dir.x")
	near(wdir.y, worldDir.y / len, label .. " dir.y")
	near(wdir.z, worldDir.z / len, label .. " dir.z")
	local ldirLen = math.sqrt(ldir.x * ldir.x + ldir.y * ldir.y + ldir.z * ldir.z)
	near(ldirLen, 1, label .. " local dir length")
end

local function testBones()
	local identity = {p = 0, y = 0, r = 0}
	local origin = {x = 0, y = 0, z = 0}
	local lpos, ldir = StickyBlood.WorldHitToBone(
		{x = 3, y = 4, z = 5},
		{x = 0, y = 0, z = 2},
		origin,
		identity
	)
	nearVec(lpos, 3, 4, 5, "identity local pos")
	nearVec(ldir, 0, 0, 1, "identity local dir")

	local bone = {x = 10, y = -4, z = 2}
	lpos, ldir = StickyBlood.WorldHitToBone(bone, {x = 0, y = 1, z = 0}, bone, {p = 15, y = -40, r = 25})
	nearVec(lpos, 0, 0, 0, "hit on the bone origin")

	local yaw90 = {p = 0, y = 90, r = 0}
	lpos, ldir = StickyBlood.WorldHitToBone(
		{x = 0, y = 5, z = 1},
		{x = 0, y = 3, z = 0},
		origin,
		yaw90
	)
	nearVec(lpos, 5, 0, 1, "yaw 90 local pos")
	nearVec(ldir, 1, 0, 0, "yaw 90 local dir")

	roundtrip({x = 12, y = -3, z = 8}, {x = 1, y = 2, z = 2}, {x = 4, y = 5, z = -2}, {p = 20, y = 130, r = -15}, "tilted")
	roundtrip({x = -8, y = 2, z = 1}, {x = -1, y = 0.25, z = 0.5}, {x = 1, y = 1, z = 1}, {p = -80, y = 10, r = 170}, "steep")

	lpos, ldir = StickyBlood.WorldHitToBone(origin, {x = 0, y = 0, z = 0}, origin, identity)
	nearVec(ldir, 0, 0, 1, "zero direction falls back")
	local backPos, backDir = StickyBlood.BoneHitToWorld(lpos, ldir, origin, identity)
	nearVec(backPos, 0, 0, 0, "zero direction position")
	nearVec(backDir, 0, 0, 1, "zero direction restored")
end

local function testDecals()
	eq(StickyBlood.DecalForBloodColor(0), "Blood", "red")
	eq(StickyBlood.DecalForBloodColor(1), "YellowBlood", "yellow")
	eq(StickyBlood.DecalForBloodColor(2), "YellowBlood", "green")
	eq(StickyBlood.DecalForBloodColor(4), "YellowBlood", "antlion")
	eq(StickyBlood.DecalForBloodColor(5), "YellowBlood", "zombie")
	eq(StickyBlood.DecalForBloodColor(6), "YellowBlood", "antlion worker")
	eq(StickyBlood.DecalForBloodColor(3), nil, "mech")
	eq(StickyBlood.DecalForBloodColor(-1), nil, "dont bleed")
	eq(StickyBlood.DecalForBloodColor(nil), nil, "missing colour")
	eq(StickyBlood.DecalForBloodColor(7), nil, "unknown colour")
end

testWindow()
testBones()
testDecals()

if failures > 0 then
	io.stderr:write(failures .. " failure(s)\n")
	os.exit(1)
end

print("ok")
