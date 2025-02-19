include("shared.lua")

CreateClientConVar("newtphysgun_maxrange", 32768, true, true, "The maximum range of the newtonian physgun", 128, 32768)
CreateClientConVar("newtphysgun_wheelspeed", 20, true, true, "The sensitivity of wheel scrolling with the newtonian physgun", -10000, 10000)
CreateClientConVar("newtphysgun_freeze", 0, true, true, "Should the newtonian physgun freeze/unfreeze like the normal physgun", 0, 1)

local physbeama = Material("sprites/physbeama")
local physg_glow1 = Material("sprites/physg_glow1")
local physg_glow2 = Material("sprites/physg_glow2")

local function QuadraticBezier(frac, p0, p1, p2)
	local frac2 = frac * frac
	local inv = 1 - frac
	local inv2 = inv * inv
	return inv2 * p0 + 2 * inv * frac * p1 + frac2 * p2
end

local num = 30
local frac = 1 / (num - 1)

local function DrawBeam(pos1, tangent, pos2, color)
	color = color:ToColor()

	local time = CurTime()
	for i = 1, 4 do
		local w = math.random() * 4
		local t = (time + i) % 4 / 4
		render.SetMaterial(physbeama)
		render.StartBeam(num)
		for j = 0, num - 1 do
			render.AddBeam(QuadraticBezier(frac * j, pos1, tangent, pos2), w, t, color)
		end
		render.EndBeam()

		local s = math.random() * 8
		render.SetMaterial(physg_glow1)
		render.DrawSprite(pos2, s, s, color)

		s = math.random() * 8
		render.SetMaterial(physg_glow2)
		render.DrawSprite(pos2, s, s, color)
	end
end

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

local angle_zero = Angle()

local function LocalToWorldBone(lpos, ent, bone)
	if ent:GetSolid() == SOLID_BBOX then return ent:GetPos() + lpos end -- fix for players and most npcs
	bone = ent:TranslatePhysBoneToBone(bone)
	local matrix = ent:GetBoneMatrix(bone)
	if not matrix then return LocalToWorld(lpos, angle_zero, ent:GetPos(), ent:GetAngles()) end
	return LocalToWorld(lpos, angle_zero, matrix:GetTranslation(), matrix:GetAngles())
end

local activeWeps = {}

function SWEP:OnFiringChanged(_, _, firing)
	if firing then
		activeWeps[self] = true
	else
		activeWeps[self] = nil
	end
end

local viewModelDrawn = false

function SWEP:ViewModelDrawn(vm)
	if not self:GetFiring() then return end

	local ent = self:GetGrabbedEnt()
	if not ent:IsValid() and not ent:IsWorld() then return end

	local owner = LocalPlayer()

	local bone = self:GetGrabbedPhysBone()
	local lpos = self:GetGrabbedLocalPos()

	if hook.Run("DrawPhysgunBeam", owner, self, true, ent, bone, lpos) == false then return end

	local obj = vm:LookupAttachment("muzzle")
	if obj < 1 then return end

	local pos1 = vm:GetAttachment(obj).Pos
	pos1 = FormatViewModelAttachment(pos1)

	local tangent = pos1 + owner:GetAimVector() * self:GetGrabbedDist() / 2

	local pos2 = LocalToWorldBone(lpos, ent, bone)
	pos2 = FormatViewModelAttachment(pos2)

	local color = owner:GetWeaponColor()

	DrawBeam(pos1, tangent, pos2, color)

	viewModelDrawn = true
end

hook.Add("PreDrawEffects", "NewtPhysgun", function()
	local lply
	if viewModelDrawn then
		lply = LocalPlayer()
	end

	for wep in pairs(activeWeps) do
		if not wep:IsValid() then activeWeps[wep] = nil continue end

		local owner = wep:GetOwner()
		if not owner:IsValid() then continue end

		-- if the local player already drew the beam with the view model, don't draw it again
		if viewModelDrawn and owner == lply then continue end

		local ent = wep:GetGrabbedEnt()
		if not ent:IsValid() and not ent:IsWorld() then continue end

		local bone = wep:GetGrabbedPhysBone()
		local lpos = wep:GetGrabbedLocalPos()

		if hook.Run("DrawPhysgunBeam", owner, wep, true, ent, bone, lpos) == false then continue end

		local obj = wep:LookupAttachment("core")
		if obj < 1 then continue end

		local pos1 = wep:GetAttachment(obj).Pos

		local tangent = pos1 + owner:GetAimVector() * wep:GetGrabbedDist() / 2

		local pos2 = LocalToWorldBone(lpos, ent, bone)

		local color = owner:GetWeaponColor()

		DrawBeam(pos1, tangent, pos2, color)
	end

	-- reset for next frame
	viewModelDrawn = false
end)

local movetypes = {
	[MOVETYPE_NONE] = true,
	[MOVETYPE_NOCLIP] = true,
	[MOVETYPE_STEP] = true,
	[MOVETYPE_FLY] = true,
	[MOVETYPE_PUSH] = true,
	[MOVETYPE_LADDER] = true
}

-- fix glitchy clientside falling
hook.Add("FinishMove", "NewtPhysgun", function(ply, mv)
	if activeWeps[ply:GetActiveWeapon()] and not movetypes[ply:GetMoveType()] and not ply:IsOnGround() then
		ply:SetNetworkOrigin(mv:GetOrigin())
		return true
	end
end)

local mWheelBtns = {
	[MOUSE_WHEEL_UP] = true,
	[MOUSE_WHEEL_DOWN] = true
}

-- prevent binds if mouse scrolling (like invnext and invprev)
hook.Add("PlayerBindPress", "NewtPhysgun", function(ply, _, _, code)
	if mWheelBtns[code] and activeWeps[ply:GetActiveWeapon()] then
		return true
	end
end)
