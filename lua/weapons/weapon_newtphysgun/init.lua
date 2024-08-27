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

local function GetMass(phys)
	if not phys:IsMoveable() or not phys:IsMotionEnabled() then return MAX_MASS end -- frozen physobj
	local ent = phys:GetEntity()
	if movetypes[ent:GetMoveType()] then return MAX_MASS end -- tough to move
	if ent:IsWorld() then return MAX_MASS end
	if ent:IsFlagSet(FL_FROZEN) then return MAX_MASS end -- frozen player
	if ent:IsPlayer() then return PLY_MASS end
	return math.min(phys:GetMass(), MAX_MASS)
end

function SWEP:Think()
	local owner = self:GetOwner()
	if not owner:IsValid() then return end

	local firing = owner:KeyDown(IN_ATTACK)
	self:SetFiring(firing)

	local ent = self:GetGrabbedEnt()

	if not firing then
		if ent:IsValid() or ent:IsWorld() then
			self:SetGrabbedEnt()
		end
		return
	end

	if owner:KeyPressed(IN_ATTACK) and not ent:IsValid() and not ent:IsWorld() then
		local shootPos = owner:GetShootPos()
		local shootDir = owner:GetAimVector()

		owner:LagCompensation(true)
		local tr = util.TraceLine({
			start = shootPos,
			endpos = shootPos + shootDir * MAX_DIST,
			filter = owner,
			mask = MASK_SHOT
		})
		owner:LagCompensation(false)

		ent = tr.Entity
		if not ent:IsValid() and not ent:IsWorld() then return end

		local pos, bone = tr.HitPos, tr.PhysicsBone
		bone = bone < ent:GetPhysicsObjectCount() and bone or 0

		self:SetGrabbedEnt(ent)

		self:SetGrabbedBone(bone)

		local phys = ent:GetPhysicsObjectNum(bone)
		self:SetGrabbedLocalPos(IsValid(phys) and phys:WorldToLocal(pos, shootDir:Angle()) or Vector())
		self:SetGrabbedDist(shootPos:Distance(pos))

		if not ent.CPPICanPhysgun or ent:CPPICanPhysgun(owner) then
			owner:PhysgunUnfreeze()
		end
	elseif owner:KeyPressed(IN_ATTACK2) and (ent:IsValid() or ent:IsWorld()) then
		self:SetGrabbedEnt()
		if not ent.CPPICanPhysgun or ent:CPPICanPhysgun(owner) then
			hook.Run("OnPhysgunFreeze", self, ent:GetPhysicsObjectNum(self:GetGrabbedBone()), ent, owner)
			self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
		end
		return
	end

	if not ent:IsValid() and not ent:IsWorld() then return end

	local dist = self:GetGrabbedDist()

	local wheel = owner:GetCurrentCommand():GetMouseWheel()
	if wheel ~= 0 then
		dist = math.min(math.max(dist + wheel * owner:GetInfoNum("physgun_wheelspeed", 10), MIN_DIST), MAX_DIST)
		self:SetGrabbedDist(dist)
	end

	local phys = ent:GetPhysicsObjectNum(self:GetGrabbedBone())
	if not IsValid(phys) then return end

	local lpos = self:GetGrabbedLocalPos()

	local angVel = phys:GetAngleVelocity()
	local pointVel = phys:GetVelocity() + phys:LocalToWorld(angVel:GetNormalized():Cross(lpos) * angVel:Length() * math.pi / 180) - phys:GetPos()

	local canForce = true
	if ent.CPPICanPhysgun then canForce = ent:CPPICanPhysgun(owner) end

	local mul = canForce and GetMass(phys) or MAX_MASS

	local pos = phys:LocalToWorld(lpos)

	local force = owner:GetShootPos() + owner:GetAimVector() * dist - pos
	force = force - pointVel * 0.1
	force = force - phys:GetVelocity() * 0.05
	force = force + owner:GetVelocity() * 0.05
	force = force * mul

	if force:Length() > FORCE_LIMIT then
		force = force:GetNormalized() * FORCE_LIMIT
	end

	owner:SetVelocity(-force / PLY_MASS - owner:GetVelocity() * 0.00004 * mul)

	if not canForce then return end

	if ent:IsPlayer() then
		ent:SetVelocity(force / PLY_MASS)
	else
		phys:Wake()
		phys:ApplyForceOffset(force, pos)
	end
end
