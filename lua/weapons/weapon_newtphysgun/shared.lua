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
	self:NetworkVar("Int", 0, "GrabbedBone")
	self:NetworkVar("Vector", 0, "GrabbedLocalPos")
	self:NetworkVar("Float", 0, "GrabbedDist")
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
end

