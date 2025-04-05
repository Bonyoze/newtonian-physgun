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

-- movetypes that make a player tough to move
local movetypes = {
	[MOVETYPE_NONE] = true,
	[MOVETYPE_NOCLIP] = true,
	[MOVETYPE_STEP] = true,
	[MOVETYPE_FLY] = true,
	[MOVETYPE_PUSH] = true,
	[MOVETYPE_LADDER] = true
}

-- npcs that can exist with physics after death
local npcs = {
	npc_combine_camera = true,
	npc_turret_ceiling = true,
	npc_turret_floor = true,
	npc_turret_floor_resistance = true
}

local function GetTargetEntity(ent)
	local parent = ent:GetParent()
	if parent:IsValid() then return GetTargetEntity(parent) end
	return ent
end

local function IsAllowedEntity(ent)
	if not ent:IsValid() then return ent:IsWorld() end
	-- avoid holding onto certain npcs that exist without physics for a few seconds after death
	if SERVER then return npcs[ent:GetClass()] or ent:GetInternalVariable("m_lifeState") == 0 end
	return true
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

local isSinglePlayer = game.SinglePlayer()

function SWEP:Think()
	if self:GetNextThinkTime() > CurTime() then return end

	local owner = self:GetOwner()

	local firing = owner:KeyDown(IN_ATTACK)
	if CLIENT and isSinglePlayer then firing = self:GetFiring() end
	if self:GetFiring() ~= firing then self:SetFiring(firing) end

	local ent = self:GetGrabbedEnt()

	if not firing then
		if ent:IsValid() or ent:IsWorld() then
			self:SetGrabbedEnt()
			if SERVER then self:SetGrabbedEntServer() end
		end
		return
	end

	if not IsAllowedEntity(ent) then
		local shootPos = owner:GetShootPos()
		local shootDir = owner:GetAimVector()

		local range = owner:GetInfoNum("newtphysgun_maxrange", 32768)
		if range == 0 then range = 32768 end

		owner:LagCompensation(true)
		local tr = util.TraceHull({ -- util.TraceLine won't hit parented entities but util.TraceHull will
			start = shootPos,
			endpos = shootPos + shootDir * range,
			filter = owner,
			mask = MASK_SHOT_HULL -- allows grabbing whatever a bullet can hit (including "grate" props)
		})
		owner:LagCompensation(false)

		ent = tr.Entity
		if not IsAllowedEntity(ent) then return end

		if SERVER then
			-- try get the root parent entity so we can grab parented entities correctly (except for ragdolls which seem to ignore being parented)
			local target = ent:GetPhysicsObjectCount() <= 1 and GetTargetEntity(ent) or ent

			local pos = tr.HitPos
			local bone = ent == target and tr.PhysicsBone or 0 -- use the first physobj if the entity is parented

			local phys = target:GetPhysicsObjectNum(bone)
			local isValidPhysics = IsValid(phys)

			self:SetGrabbedEnt(ent)
			self:SetGrabbedEntServer(target)
			self:SetGrabbedPhysBone(bone)
			self:SetGrabbedLocalPos((not target:IsPlayer() and isValidPhysics and target:GetSolid() ~= SOLID_BBOX) and phys:WorldToLocal(pos) or pos - target:GetPos())
			self:SetGrabbedDist(shootPos:Distance(pos))

			if isValidPhysics and owner:GetInfoNum("newtphysgun_freeze", 0) ~= 0 and HasPermission(owner, ent) then
				phys:EnableMotion(true)
			end
		elseif ent:IsWorld() and not self:GetGrabbedEntServer():IsValid() then -- the world doesn't move so we can easily grab it clientside
			local pos = tr.HitPos
			self:SetGrabbedEnt(ent)
			self:SetGrabbedPhysBone(0)
			self:SetGrabbedLocalPos(pos)
			self:SetGrabbedDist(shootPos:Distance(pos))
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

	if SERVER then
		local wheel = owner:GetCurrentCommand():GetMouseWheel()
		if wheel ~= 0 then
			dist = math.min(math.max(dist + wheel * owner:GetInfoNum("newtphysgun_wheelspeed", 10), MIN_DIST), MAX_DIST)
			self:SetGrabbedDist(dist)
		end
	end

	-- world grabbing with clientside prediction
	if ent:IsWorld() and not self:GetGrabbedEntServer():IsValid() then
		local pos = self:GetGrabbedLocalPos()

		local force = owner:GetShootPos() + owner:GetAimVector() * dist - pos
		force = force + owner:GetVelocity() * 0.05
		force = force * MAX_MASS

		local ownerVel = -force / PLY_MASS + owner:GetAbsVelocity()
		CheckEntityVelocity(ownerVel)
		if ownerVel.z > 10 then owner:SetGroundEntity() end
		owner:SetLocalVelocity(ownerVel)
		return
	end

	if CLIENT then return end

	local target = self:GetGrabbedEntServer()
	if not target:IsValid() and not target:IsWorld() then return end

	local isPlayer = target:IsPlayer()

	local phys = target:GetPhysicsObjectNum(self:GetGrabbedPhysBone())
	local isValidPhysics = IsValid(phys)

	-- we can't use the physobj when calculating point velocity for players and certain npcs
	local isValidProp = not isPlayer and isValidPhysics and target:GetSolid() ~= SOLID_BBOX

	local vel = isValidProp and phys:GetVelocity() or target:GetVelocity()
	local pos = isValidProp and phys:LocalToWorld(self:GetGrabbedLocalPos()) or target:GetPos() + self:GetGrabbedLocalPos()
	local pointVel = isValidProp and phys:GetVelocityAtPoint(pos) or vel

	-- if the entity's physobj is invalid we can't get its mass and if it's parented we won't be able to move it
	local mul = isValidPhysics and ent == target and HasPermission(owner, ent) and GetMass(phys) or math.huge
	local canForce = mul < math.huge
	mul = math.min(mul, MAX_MASS)

	local force = owner:GetShootPos() + owner:GetAimVector() * dist - pos
	force = force - pointVel * 0.1
	force = force - vel * 0.05
	force = force + owner:GetVelocity() * 0.05
	force = force * mul

	local ownerVel = -force / PLY_MASS + owner:GetAbsVelocity()
	CheckEntityVelocity(ownerVel)
	if ownerVel.z > 10 then owner:SetGroundEntity() end
	owner:SetLocalVelocity(ownerVel)

	if not canForce or ent == owner:GetGroundEntity() then return end -- ground entity check mostly prevents prop surfing

	if isPlayer then
		local entVel = force / PLY_MASS + ent:GetAbsVelocity()
		CheckEntityVelocity(entVel)
		if entVel.z > 10 then ent:SetGroundEntity() end
		ent:SetLocalVelocity(entVel)
	elseif isValidPhysics then
		phys:Wake()
		phys:ApplyForceOffset(force, pos)
	end
end
