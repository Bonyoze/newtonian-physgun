AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

function SWEP:Reload()
	local owner = self:GetOwner()
	if owner:GetInfoNum("newtphysgun_freeze", 0) ~= 0 then
		hook.Run("OnPhysgunReload", self, owner)
	end
end
