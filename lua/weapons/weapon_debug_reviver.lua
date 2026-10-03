SWEP.PrintName = "Debug Reviver"
SWEP.Author = "Sticky Blood"
SWEP.Category = "Weapons"
SWEP.Spawnable = true
SWEP.AdminOnly = false
SWEP.UseHands = true
SWEP.ViewModel = "models/weapons/c_toolgun.mdl"
SWEP.WorldModel = "models/weapons/w_toolgun.mdl"
SWEP.HoldType = "pistol"
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"
SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

function SWEP:Initialize()
	self:SetHoldType(self.HoldType)
end

function SWEP:PrimaryAttack()
	self:SetNextPrimaryFire(CurTime() + 0.4)
	if CLIENT then return end

	local owner = self:GetOwner()
	if not IsValid(owner) then return end

	local tr = util.TraceLine({
		start = owner:GetShootPos(),
		endpos = owner:GetShootPos() + owner:GetAimVector() * 4000,
		filter = owner,
	})
	local ent = tr.Entity
	if not IsValid(ent) then return end

	if ent:GetClass() == "prop_ragdoll" then
		StickyBlood.ReviveRagdoll(ent)
	elseif ent:IsNPC() and ent:Health() <= 0 then
		StickyBlood.ReviveDeadNPC(ent)
	end
end

function SWEP:SecondaryAttack()
end
