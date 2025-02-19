SWEP.PrintName = "Newtonian Physics Gun"
SWEP.Author = "Bonyoze"
SWEP.Purpose = "A F=MA compliant physgun"

SWEP.Spawnable = true

SWEP.ViewModelFOV = 54
SWEP.ViewModel = "models/weapons/c_superphyscannon.mdl"
SWEP.WorldModel = "models/weapons/w_physics.mdl"

SWEP.DrawAmmo = false
SWEP.Slot = 0
SWEP.SlotPos = 3

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

SWEP.UseHands = true

function SWEP:SetupDataTables()
	self:NetworkVar("Bool", 0, "Firing")
	self:NetworkVar("Entity", 0, "GrabbedEnt")
	self:NetworkVar("Entity", 1, "GrabbedEntServer")
	self:NetworkVar("Int", 0, "GrabbedPhysBone")
	self:NetworkVar("Vector", 0, "GrabbedLocalPos")
	self:NetworkVar("Float", 0, "GrabbedDist")
	self:NetworkVar("Float", 1, "NextThinkTime")
	if CLIENT then
		self:NetworkVarNotify("Firing", self.OnFiringChanged)
	end
end

function SWEP:Initialize()
	self:SetHoldType("physgun")
	self:SetSkin(1)
end

function SWEP:PrimaryAttack()
	self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
end

function SWEP:SecondaryAttack() end

function SWEP:OnDrop()
	self:SetFiring(false)
	self:SetGrabbedEnt()
	self:SetGrabbedEntServer()
end

function SWEP:OnRemove()
	self:SetFiring(false)
	self:SetGrabbedEnt()
	self:SetGrabbedEntServer()
end

local MIN_DIST = 40
local MAX_DIST = 32768

local PLY_MASS = 85
local MAX_MASS = 1000

local SPEED_LIMIT = 4000

local movetypes = {
	[MOVETYPE_NONE] = true,
	[MOVETYPE_NOCLIP] = true,
	[MOVETYPE_STEP] = true,
	[MOVETYPE_FLY] = true,
	[MOVETYPE_PUSH] = true,
	[MOVETYPE_LADDER] = true
}

local function IsAllowedEntity(ent)
	if not ent:IsValid() then return ent:IsWorld() end
	return ent:GetInternalVariable("m_lifeState") == 0
end

local function HasPermission(owner, ent)
	return not ent.CPPICanPhysgun or ent:CPPICanPhysgun(owner)
end

local function CheckEntityVelocity(vel)
	if vel.x > -SPEED_LIMIT and vel.x < SPEED_LIMIT and
		vel.y > -SPEED_LIMIT and vel.y < SPEED_LIMIT and
		vel.z > -SPEED_LIMIT and vel.z < SPEED_LIMIT
	then return end
	vel:Mul(SPEED_LIMIT / vel:Length())
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
	if self:GetNextThinkTime() > CurTime() then return end

	local owner = self:GetOwner()

	local firing = owner:KeyDown(IN_ATTACK)
	self:SetFiring(firing)

	local ent = self:GetGrabbedEnt()

	if not firing then
		if ent:IsValid() or ent:IsWorld() then
			self:SetGrabbedEnt()
			self:SetGrabbedEntServer()
		end
		return
	end

	if not IsAllowedEntity(ent) then
		local shootPos = owner:GetShootPos()
		local shootDir = owner:GetAimVector()

		local range = owner:GetInfoNum("newtphysgun_maxrange", 32768)
		if range == 0 then range = 32768 end

		owner:LagCompensation(true)
		local tr = util.TraceLine({
			start = shootPos,
			endpos = shootPos + shootDir * range,
			filter = owner,
			mask = MASK_SHOT
		})
		owner:LagCompensation(false)

		ent = tr.Entity
		if not IsAllowedEntity(ent) then return end

		if CLIENT and ent:IsWorld() and (not IsValid(self:GetGrabbedEntServer()) or self:GetGrabbedEntServer() == ent) then
			local pos = tr.HitPos
			self:SetGrabbedEnt(ent)
			self:SetGrabbedLocalPos(ent:WorldToLocal(pos, shootDir:Angle()))
			self:SetGrabbedDist(shootPos:Distance(pos))
		end

		if SERVER then
			if ent:IsWorld() and self:GetGrabbedEntServer() == ent then
				local pos = tr.HitPos
				self:SetGrabbedEnt(ent)
				self:SetGrabbedEntServer(ent)
				self:SetGrabbedLocalPos(ent:WorldToLocal(pos, shootDir:Angle()))
				self:SetGrabbedDist(shootPos:Distance(pos))
			else
				if CLIENT then return end
				local pos, bone = tr.HitPos, tr.PhysicsBone
				bone = bone < ent:GetPhysicsObjectCount() and bone or 0
				local phys = ent:GetPhysicsObjectNum(bone)

				self:SetGrabbedEnt(ent)
				self:SetGrabbedEntServer(ent)
				self:SetGrabbedPhysBone(bone)
				self:SetGrabbedLocalPos(IsValid(phys) and phys:WorldToLocal(pos, shootDir:Angle()) or Vector())
				self:SetGrabbedDist(shootPos:Distance(pos))

				if IsValid(phys) and owner:GetInfoNum("newtphysgun_freeze", 0) ~= 0 and HasPermission(owner, ent) then
					phys:EnableMotion(true)
				end
			end
		end
	elseif owner:KeyPressed(IN_ATTACK2) then
		self:SetGrabbedEnt()
		self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
		self:SetNextThinkTime(CurTime() + 0.5)

		if SERVER then
			self:SetGrabbedEntServer()
			if not ent:IsPlayer() and owner:GetInfoNum("newtphysgun_freeze", 0) ~= 0 and HasPermission(owner, ent) then
				hook.Run("OnPhysgunFreeze", self, ent:GetPhysicsObjectNum(self:GetGrabbedPhysBone()), ent, owner)
			end
		end
		return
	end

	local dist = self:GetGrabbedDist()

	local wheel = owner:GetCurrentCommand():GetMouseWheel()
	if wheel ~= 0 then
		dist = math.min(math.max(dist + wheel * owner:GetInfoNum("newtphysgun_wheelspeed", 10), MIN_DIST), MAX_DIST)
		self:SetGrabbedDist(dist)
	end

	if ent:IsWorld() and (not IsValid(self:GetGrabbedEntServer()) or self:GetGrabbedEntServer() == ent) then
		local isPlayer = ent:IsPlayer()
		local vel = isPlayer and ent:GetVelocity() or ent:GetVelocity()
		local pos = ent:LocalToWorld(self:GetGrabbedLocalPos())
	
		local force = owner:GetShootPos() + owner:GetAimVector() * dist - pos
		force = force - vel * 0.05
		force = force + owner:GetVelocity() * 0.05
		force = force * MAX_MASS
	
		local ownerVel = -force / PLY_MASS + owner:GetAbsVelocity()
		CheckEntityVelocity(ownerVel)
		if ownerVel.z > 0 then owner:SetGroundEntity() end
		owner:SetLocalVelocity(ownerVel)
		return
	end

	if CLIENT then return end

	local phys = ent:GetPhysicsObjectNum(self:GetGrabbedPhysBone())
	if not IsValid(phys) then return end

	local isPlayer = ent:IsPlayer()
	local vel = isPlayer and ent:GetVelocity() or phys:GetVelocity()
	local pos = phys:LocalToWorld(self:GetGrabbedLocalPos())
	local pointVel = isPlayer and vel or phys:GetVelocityAtPoint(pos)

	local mul = HasPermission(owner, ent) and GetMass(phys) or math.huge
	local canForce = mul < math.huge
	mul = math.min(mul, MAX_MASS)

	local force = owner:GetShootPos() + owner:GetAimVector() * dist - pos
	force = force - pointVel * 0.1
	force = force - vel * 0.05
	force = force + owner:GetVelocity() * 0.05
	force = force * mul

	local ownerVel = -force / PLY_MASS + owner:GetAbsVelocity()
	CheckEntityVelocity(ownerVel)
	if ownerVel.z > 0 then owner:SetGroundEntity() end
	owner:SetLocalVelocity(ownerVel)

	if not canForce or ent == owner:GetGroundEntity() then return end

	if isPlayer then
		local entVel = force / PLY_MASS + ent:GetAbsVelocity()
		CheckEntityVelocity(entVel)
		if entVel.z > 0 then ent:SetGroundEntity() end
		ent:SetLocalVelocity(entVel)
	else
		phys:Wake()
		phys:ApplyForceOffset(force, pos)
	end
end