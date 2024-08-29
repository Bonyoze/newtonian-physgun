include("shared.lua")

CreateClientConVar("newtphysgun_maxrange", 32768, true, true, "The maximum range of the newtonian physgun", 128, 32768)
CreateClientConVar("newtphysgun_wheelspeed", 20, true, true, "The sensitivity of wheel scrolling with the newtonian physgun", -10000, 10000)
CreateClientConVar("newtphysgun_freeze", 0, true, true, "Should the newtonian physgun freeze/unfreeze objects like the normal physgun", 0, 1)

local physbeama = Material("sprites/physbeama")
local physg_glow1 = Material("sprites/physg_glow1")
local physg_glow2 = Material("sprites/physg_glow2")

local num = 30
local frac = 1 / (num - 1)

local function DrawBeam(pos1, tangent, pos2, clr)
	clr = clr:ToColor()

	local time = CurTime()
	for j = 1, 4 do
		local w = math.random() * 4
		local t = (time + j) % 4 / 4
		render.SetMaterial(physbeama)
		render.StartBeam(num)
		for i = 0, num - 1 do
			render.AddBeam(math.QuadraticBezier(frac * i, pos1, tangent, pos2), w, t, clr)
		end
		render.EndBeam()

		local s = math.random() * 8
		render.SetMaterial(physg_glow1)
		render.DrawSprite(pos2, s, s, clr)

		s = math.random() * 8
		render.SetMaterial(physg_glow2)
		render.DrawSprite(pos2, s, s, clr)
	end
end

hook.Add("PreDrawEffects", "NewtPhysgun", function()
	for _, ply in player.Iterator() do
		local wep = ply:GetActiveWeapon()
		if not wep:IsValid() or wep:GetClass() ~= "weapon_newtphysgun" then continue end

		if not wep:GetFiring() then continue end

		local ent = wep:GetGrabbedEnt()
		if not ent:IsValid() and not ent:IsWorld() then continue end

		local bone = wep:GetGrabbedBone()
		local lpos = wep:GetGrabbedLocalPos()

		if hook.Run("DrawPhysgunBeam", ply, wep, true, ent, bone, lpos) == false then continue end

		local obj = wep:LookupAttachment("core")
		if obj < 1 then continue end

		local pos1 = wep:GetAttachment(obj).Pos

		local tangent = pos1 + ply:GetAimVector() * wep:GetGrabbedDist() / 2

		local pos2
		if bone == 0 then
			pos2 = LocalToWorld(lpos, Angle(), ent:GetPos(), ent:GetAngles())
		else
			local matrix = ent:GetBoneMatrix(bone) or Matrix()
			pos2 = LocalToWorld(lpos, Angle(), matrix:GetTranslation(), matrix:GetAngles())
		end

		local color = ply:GetWeaponColor()

		DrawBeam(pos1, tangent, pos2, color)
	end
end)

local function FormatViewModelAttachment(origin, from)
	local view = render.GetViewSetup()

	local eyePos = view.origin
	local eyesRot = view.angles
	local offset = origin - eyePos
	local forward = eyesRot:Forward()

	local viewX = math.tan(view.fovviewmodel_unscaled * math.pi / 360)

	if viewX == 0 then
		forward:Mul(forward:Dot(offset))
		eyePos:Add(forward)
		return eyePos
	end

	local worldX = math.tan(view.fov_unscaled * math.pi / 360)

	if worldX == 0 then
		forward:Mul(forward:Dot(offset))
		eyePos:Add(forward)
		return eyePos
	end

	local right = eyesRot:Right()
	local up = eyesRot:Up()

	local factor = from and worldX / viewX or viewX / worldX

	right:Mul(right:Dot(offset) * factor)
	up:Mul(up:Dot(offset) * factor)
	forward:Mul(forward:Dot(offset))

	eyePos:Add(right)
	eyePos:Add(up)
	eyePos:Add(forward)

	return eyePos
end

function SWEP:PostDrawViewModel(vm, _, ply)
	if not self:GetFiring() then return end

	local ent = self:GetGrabbedEnt()
	if not ent:IsValid() and not ent:IsWorld() then return end

	local bone = self:GetGrabbedBone()
	local lpos = self:GetGrabbedLocalPos()

	if hook.Run("DrawPhysgunBeam", ply, self, true, ent, bone, lpos) == false then return end

	local obj = vm:LookupAttachment("muzzle")
	if obj < 1 then return end

	local pos1 = vm:GetAttachment(obj).Pos
	pos1 = FormatViewModelAttachment(pos1)

	local tangent = pos1 + ply:GetAimVector() * self:GetGrabbedDist() / 2

	local pos2
	if bone == 0 then
		pos2 = LocalToWorld(lpos, Angle(), ent:GetPos(), ent:GetAngles())
	else
		local matrix = ent:GetBoneMatrix(bone) or Matrix()
		pos2 = LocalToWorld(lpos, Angle(), matrix:GetTranslation(), matrix:GetAngles())
	end
	pos2 = FormatViewModelAttachment(pos2)

	local color = ply:GetWeaponColor()

	DrawBeam(pos1, tangent, pos2, color)
end

hook.Add("HUDShouldDraw", "NewtPhysgun", function(name)
	if name ~= "CHudWeaponSelection" then return end

	local wep = LocalPlayer():GetActiveWeapon()
	if not wep:IsValid() or wep:GetClass() ~= "weapon_newtphysgun" then return end

	if not wep:GetFiring() then return end

	return false
end)
