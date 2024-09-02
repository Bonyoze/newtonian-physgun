AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

local MIN_DIST = 40
local MAX_DIST = 32768

local PLY_MASS = 85
local MAX_MASS = 1000

local FORCE_LIMIT = 500000

local movetypes = {
	[MOVETYPE_NONE] = true,
	[MOVETYPE_NOCLIP] = true,
	[MOVETYPE_STEP] = true,
	[MOVETYPE_FLY] = true,
	[MOVETYPE_PUSH] = true,
	[MOVETYPE_LADDER] = true
}

local function HasPermission(owner, ent)
	return not ent.CPPICanPhysgun or ent:CPPICanPhysgun(owner)
end

local function GetMass(phys)
	if not phys:IsMoveable() or not phys:IsMotionEnabled() then return math.huge end -- frozen physobj
	local ent = phys:GetEntity()
	if movetypes[ent:GetMoveType()] then return math.huge end -- tough to move
	if ent:IsWorld() then return math.huge end
	if ent:IsFlagSet(FL_FROZEN) then return math.huge end -- frozen player
	if ent:IsPlayer() then return PLY_MASS end
	return phys:GetMass()
end

function SWEP:Think()
	local owner = self:GetOwner()
	if not owner:IsValid() then return end

	if owner:KeyPressed(IN_RELOAD) and owner:GetInfoNum("newtphysgun_freeze", 0) ~= 0 then
		hook.Run("OnPhysgunReload", self, owner)
	end

	if (self.NextThinkTime or 0) > CurTime() then return end

	local firing = owner:KeyDown(IN_ATTACK)
	self:SetFiring(firing)

	local ent = self:GetGrabbedEnt()

	if not firing then
		if ent:IsValid() or ent:IsWorld() then
			self:SetGrabbedEnt()
			hook.Run("PhysgunDrop", owner, ent)
		end
		return
	end

	if not ent:IsValid() and not ent:IsWorld() then
		local shootPos = owner:GetShootPos()
		local shootDir = owner:GetAimVector()

		owner:LagCompensation(true)
		local tr = util.TraceLine({
			start = shootPos,
			endpos = shootPos + shootDir * owner:GetInfoNum("newtphysgun_maxrange", 32768),
			filter = owner,
			mask = MASK_SHOT
		})
		owner:LagCompensation(false)

		ent = tr.Entity
		if not ent:IsValid() and not ent:IsWorld() then return end

		hook.Run("PhysgunPickup", owner, ent)

		local pos, bone = tr.HitPos, tr.PhysicsBone
		bone = bone < ent:GetPhysicsObjectCount() and bone or 0
		local phys = ent:GetPhysicsObjectNum(bone)

		self:SetGrabbedEnt(ent)
		self:SetGrabbedPhysBone(bone)
		self:SetGrabbedLocalPos(IsValid(phys) and phys:WorldToLocal(pos, shootDir:Angle()) or Vector())
		self:SetGrabbedDist(shootPos:Distance(pos))

		if IsValid(phys) and owner:GetInfoNum("newtphysgun_freeze", 0) ~= 0 and HasPermission(owner, ent) then
			phys:EnableMotion(true)
		end

		hook.Run("OnPhysgunPickup", owner, ent)
	elseif owner:KeyPressed(IN_ATTACK2) then
		self:SetGrabbedEnt()
		self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
		self.NextThinkTime = CurTime() + 0.5

		if owner:GetInfoNum("newtphysgun_freeze", 0) ~= 0 and HasPermission(owner, ent) then
			hook.Run("OnPhysgunFreeze", self, ent:GetPhysicsObjectNum(self:GetGrabbedPhysBone()), ent, owner)
		end

		hook.Run("PhysgunDrop", owner, ent)

		return
	end

	local dist = self:GetGrabbedDist()

	local wheel = owner:GetCurrentCommand():GetMouseWheel()
	if wheel ~= 0 then
		dist = math.min(math.max(dist + wheel * owner:GetInfoNum("newtphysgun_wheelspeed", 10), MIN_DIST), MAX_DIST)
		self:SetGrabbedDist(dist)
	end

	local phys = ent:GetPhysicsObjectNum(self:GetGrabbedPhysBone())
	if not IsValid(phys) then return end

	local pos = phys:LocalToWorld(self:GetGrabbedLocalPos())

	local pointVel = phys:GetVelocityAtPoint(pos)

	local mul = HasPermission(owner, ent) and GetMass(phys) or math.huge

	local canForce = mul < math.huge

	mul = math.min(mul, MAX_MASS)

	local force = owner:GetShootPos() + owner:GetAimVector() * dist - pos
	force = force - pointVel * 0.1
	force = force - phys:GetVelocity() * 0.05
	force = force + owner:GetVelocity() * 0.05
	force = force * mul

	if force:Length() > FORCE_LIMIT then
		force = force:GetNormalized() * FORCE_LIMIT
	end

	if force.z < 0 then owner:SetGroundEntity() end

	owner:SetVelocity(-force / PLY_MASS - owner:GetVelocity() * 0.00004 * mul)

	if not canForce or ent == owner:GetGroundEntity() then return end

	if ent:IsPlayer() then
		ent:SetVelocity(force / PLY_MASS)
	else
		phys:Wake()
		phys:ApplyForceOffset(force, pos)
	end
end
