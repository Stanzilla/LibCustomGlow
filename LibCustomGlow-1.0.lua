--[[
This library contains work of Hendrick "nevcairiel" Leppkes
https://www.wowace.com/projects/libbuttonglow-1-0
]]

-- luacheck: globals CreateFromMixins ObjectPoolMixin CreateTexturePool CreateFramePool

local MAJOR_VERSION = "LibCustomGlow-1.0"
local MINOR_VERSION = 16
if not LibStub then error(MAJOR_VERSION .. " requires LibStub.") end
local lib, oldversion = LibStub:NewLibrary(MAJOR_VERSION, MINOR_VERSION)
if not lib then return end
local Masque = LibStub("Masque", true)

local textureList = {
    ["empty"] = [[Interface\AdventureMap\BrokenIsles\AM_29]],
    ["white"] = [[Interface\BUTTONS\WHITE8X8]],
    ["shine"] = [[Interface\Artifacts\Artifacts]]
}

function lib.RegisterTextures(texture,id)
    textureList[id] = texture
end

lib.glowList = {}
lib.startList = {}
lib.stopList = {}

local GlowParent = UIParent

local GlowMaskPool = CreateFromMixins(ObjectPoolMixin)
lib.GlowMaskPool = GlowMaskPool
local function MaskPoolFactory(maskPool)
    return maskPool.parent:CreateMaskTexture()
end

local MaskPoolResetter = function(maskPool,mask)
    mask:Hide()
    mask:ClearAllPoints()
end

ObjectPoolMixin.OnLoad(GlowMaskPool,MaskPoolFactory,MaskPoolResetter)
GlowMaskPool.parent =  GlowParent

local TexPoolResetter = function(pool,tex)
    local maskNum = tex:GetNumMaskTextures()
    for i = maskNum,1 do
        tex:RemoveMaskTexture(tex:GetMaskTexture(i))
    end
    tex:Hide()
    tex:ClearAllPoints()
end
local GlowTexPool = CreateTexturePool(GlowParent ,"ARTWORK",7,nil,TexPoolResetter)
lib.GlowTexPool = GlowTexPool

local FramePoolResetter = function(framePool,frame)
    frame:SetScript("OnUpdate",nil)
    local parent = frame:GetParent()
    if parent[frame.name] then
        parent[frame.name] = nil
    end
    if frame.textures then
        for _, texture in pairs(frame.textures) do
            GlowTexPool:Release(texture)
        end
    end
    if frame.bg then
        GlowTexPool:Release(frame.bg)
        frame.bg = nil
    end
    if frame.masks then
        for _,mask in pairs(frame.masks) do
            GlowMaskPool:Release(mask)
        end
        frame.masks = nil
    end
    frame.textures = {}
    frame.info = {}
    frame.name = nil
    frame.timer = nil
    frame:Hide()
    frame:ClearAllPoints()
end
local GlowFramePool = CreateFramePool("Frame",GlowParent,nil,FramePoolResetter)
lib.GlowFramePool = GlowFramePool

local function addFrameAndTex(r,color,name,key,N,xOffset,yOffset,texture,texCoord,desaturated,frameLevel)
    key = key or ""
	frameLevel = frameLevel or 8
    if not r[name..key] then
        r[name..key] = GlowFramePool:Acquire()
        r[name..key]:SetParent(r)
        r[name..key].name = name..key
    end
    local f = r[name..key]
	f:SetFrameLevel(r:GetFrameLevel()+frameLevel)
    f:SetPoint("TOPLEFT",r,"TOPLEFT",-xOffset+0.05,yOffset+0.05)
    f:SetPoint("BOTTOMRIGHT",r,"BOTTOMRIGHT",xOffset,-yOffset+0.05)
    f:Show()

    if not f.textures then
        f.textures = {}
    end

    for i=1,N do
        if not f.textures[i] then
            f.textures[i] = GlowTexPool:Acquire()
            f.textures[i]: SetTexture(texture)
            f.textures[i]: SetTexCoord(texCoord[1],texCoord[2],texCoord[3],texCoord[4])
            f.textures[i]: SetDesaturated(desaturated)
            f.textures[i]: SetParent(f)
            f.textures[i]: SetDrawLayer("ARTWORK",7)
        end
        f.textures[i]:SetVertexColor(color[1],color[2],color[3],color[4])
        f.textures[i]:Show()
    end
    while #f.textures>N do
        GlowTexPool:Release(f.textures[#f.textures])
        table.remove(f.textures)
    end
end


local hsvFrame = CreateFrame("Colorselect")
-- HSV transition, for a much prettier color transition in many cases
-- see http://www.wowinterface.com/forums/showthread.php?t=48236
local function GetHSVTransition(perc, c1, c2)
  --get hsv color for colorA
  hsvFrame:SetColorRGB(c1[1], c1[2], c1[3])
  local h1, s1, v1 = hsvFrame:GetColorHSV() -- hue, saturation, value
  --get hsv color for colorB
  hsvFrame:SetColorRGB(c2[1], c2[2], c2[3])
  local h2, s2, v2 = hsvFrame:GetColorHSV() -- hue, saturation, value
  -- find the shortest arc through the color circle, then interpolate
  local diff = h2 - h1
  if diff < -180 then
    diff = diff + 360
  elseif diff > 180 then
    diff = diff - 360
  end

  local h3 = (h1 + perc * diff) % 360
  local s3 = s1 - ( s1 - s2 ) * perc
  local v3 = v1 - ( v1 - v2 ) * perc
  --get the RGB values of the new color
  hsvFrame:SetColorHSV(h3, s3, v3)
  local r, g, b = hsvFrame:GetColorRGB()
  --interpolate alpha
  local a = c1[4] - ( c1[4] - c2[4] ) * perc
  --return the new color
  return {r, g, b, a}
end

local function SetGradA(texture, direction, c1, c2)
	texture:SetGradientAlpha(direction, c1[1], c1[2], c1[3], c1[4], c2[1], c2[2], c2[3], c2[4])
end

---- Tails Funcitons ------------------------------------------------------------------------------------------------

local function BorderGradientCorners(info, elapsed)
	local c1, c2, c3, c4, p1, p2, p3, p4
	local g = info.gradient
	local gN = #g
	local gProg = info.gProgress or 0
	gProg = (gProg + elapsed * info.gFrequency)%1
	info.gProgress = gProg
	
	p1 = (gProg + 0.001)%1
	p2 = (gProg + info.width / (info.width + info.height) / 2)%1
	p3 = (gProg + 0.5) %1
	p4 = (gProg + 0.5 + info.width / (info.width + info.height) / 2)%1
	
	c1 = GetHSVTransition ((p1 * gN) % 1 , g[ceil(p1 * gN)], g[ceil(p1 * gN) % gN + 1])
	c2 = GetHSVTransition ((p2 * gN) % 1 , g[ceil(p2 * gN)], g[ceil(p2 * gN) % gN + 1])
	c3 = GetHSVTransition ((p3 * gN) % 1 , g[ceil(p3 * gN)], g[ceil(p3 * gN) % gN + 1])
	c4 = GetHSVTransition ((p4 * gN) % 1 , g[ceil(p4 * gN)], g[ceil(p4 * gN) % gN + 1])
	return c1, c2, c3, c4
end

local function BorderSet4LinesCenter(f, update)
	local inf = f.info
	local tails = inf.tail.list
	if not(update) then 
		for _, v in pairs(tails) do
			v:ClearAllPoints()
		end
		if inf.mirror then
				tails[1]:SetPoint("TOP", f, "TOP")
				tails[2]:SetPoint("RIGHT", f, "RIGHT")
				tails[3]:SetPoint("BOTTOM", f, "BOTTOM")
				tails[4]:SetPoint("LEFT", f, "LEFT")
				
				tails[5]:Hide()
				tails[6]:Hide()
				tails[7]:Hide()
				tails[8]:Hide()		

				tails[1]:SetHeight(inf.th)
				tails[2]:SetWidth(inf.th)
				tails[3]:SetHeight(inf.th)
				tails[4]:SetWidth(inf.th)				
		else
			if inf.clockwise then
				tails[1]:SetPoint("TOPRIGHT", f, "TOP")
				tails[2]:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -inf.th)
				tails[3]:SetPoint("TOPLEFT", f, "LEFT")
				tails[4]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", inf.th, 0)
				tails[5]:SetPoint("BOTTOMLEFT", f, "BOTTOM")
				tails[6]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, inf.th)
				tails[7]:SetPoint("BOTTOMRIGHT", f, "RIGHT")
				tails[8]:SetPoint("TOPRIGHT", f, "TOPRIGHT", -inf.th, 0)
			else
				tails[1]:SetPoint("TOPLEFT", f, "TOP")
				tails[2]:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -inf.th)
				tails[3]:SetPoint("TOPRIGHT", f, "RIGHT")
				tails[4]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inf.th, 0)
				tails[5]:SetPoint("BOTTOMRIGHT", f, "BOTTOM")
				tails[6]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, inf.th)
				tails[7]:SetPoint("BOTTOMLEFT", f, "LEFT")
				tails[8]:SetPoint("TOPLEFT", f, "TOPLEFT", inf.th, 0)
			end

			tails[5]:Show()
			tails[6]:Show()
			tails[7]:Show()
			tails[8]:Show()
			
			tails[1]:SetHeight(inf.th)
			tails[2]:SetWidth(inf.th)
			tails[3]:SetWidth(inf.th)
			tails[4]:SetHeight(inf.th)
			tails[5]:SetHeight(inf.th)
			tails[6]:SetWidth(inf.th)
			tails[7]:SetWidth(inf.th)
			tails[8]:SetHeight(inf.th)
		end
	end	
	
	local width, height = f:GetSize()
	if inf.mirror then
		tails[1]:SetWidth(width)
		tails[2]:SetHeight(height - inf.th * 2)
		tails[3]:SetWidth(width)
		tails[4]:SetHeight(height - inf.th * 2)
	else
		tails[1]:SetWidth(width / 2)
		tails[2]:SetHeight(height / 2 - inf.th)
		tails[3]:SetHeight(height / 2)
		tails[4]:SetWidth(width / 2 - inf.th)
		tails[5]:SetWidth(width / 2)
		tails[6]:SetHeight(height / 2 - inf.th)
		tails[7]:SetHeight(height / 2)
		tails[8]:SetWidth(width / 2 - inf.th)
	end
end

local function BorderUpdate4LinesCenter(f, progress)
	local inf = f.info
	local tails = inf.tail.list
	local oldProgress = inf.tail.old
	
	if inf.mirror then
		local newW = inf.width * (1 - progress)
		local newH = (inf.height - inf.th * 2) * (1 - progress)
		tails[1]:SetWidth(newW)
		tails[2]:SetHeight(newH)
		tails[3]:SetWidth(newW)
		tails[4]:SetHeight(newH)
	else	
		local cornerP = inf.width / (inf.width + inf.height)
		local updt
		if progress < cornerP then
			if oldProgress > cornerP or oldProgress <= 0 then
				tails[3]:Show()
				tails[4]:Show()
				tails[7]:Show()
				tails[8]:Show()				
				updt = true
			else
				local stageProg = 1 - progress / cornerP
				tails[4]:SetWidth(stageProg * (inf.width / 2 - inf.th))
				tails[8]:SetWidth(stageProg * (inf.width / 2 - inf.th))
			end
		else
			if oldProgress >= 1 or oldProgress < cornerP then
				tails[3]:Show()
				tails[4]:Hide()
				tails[7]:Show()
				tails[8]:Hide()
				updt = true
			else
				local stageProg = (1 - progress) / (1 - cornerP)
				tails[3]:SetHeight(stageProg * (inf.height / 2))
				tails[7]:SetHeight(stageProg * (inf.height / 2))
			end
		end
		
		if progress < (1 - cornerP) then
			if oldProgress > (1 - cornerP) or oldProgress <= 0 then
				tails[1]:Show()
				tails[2]:Show()
				tails[5]:Show()
				tails[6]:Show()
				updt = true
			else
				local stageProg = 1 - progress / (1 - cornerP)
				tails[2]:SetHeight(stageProg * (inf.height / 2 - inf.th))
				tails[6]:SetHeight(stageProg * (inf.height / 2 - inf.th))
			end
		else
			if oldProgress >= 1 or oldProgress < (1 - cornerP) then
				tails[1]:Show()
				tails[2]:Hide()
				tails[5]:Show()
				tails[6]:Hide()
				updt = true
			else
				local stageProg = (1 - progress) / cornerP
				tails[1]:SetWidth(stageProg * (inf.width / 2))
				tails[5]:SetWidth(stageProg * (inf.width / 2))
			end
		end
		
		if updt then
				BorderSet4LinesCenter(f, true)
				if progress < cornerP then
					local stageProg = 1 - progress / cornerP
					tails[4]:SetWidth(stageProg * (inf.width / 2- inf.th))
					tails[8]:SetWidth(stageProg * (inf.width / 2- inf.th))
				else
					local stageProg = (1 - progress) / (1 - cornerP)
					tails[3]:SetHeight(stageProg * (inf.height / 2))
					tails[7]:SetHeight(stageProg * (inf.height / 2))
				end
				
				if progress < (1 - cornerP) then
					local stageProg = 1 - progress / (1 - cornerP)
					tails[2]:SetHeight(stageProg * (inf.height / 2 - inf.th))
					tails[6]:SetHeight(stageProg * (inf.height / 2 - inf.th))
				else
					local stageProg = (1 - progress) / cornerP
					tails[1]:SetWidth(stageProg * (inf.width / 2))
					tails[5]:SetWidth(stageProg * (inf.width / 2))
				end
		end	
	end
	inf.tail.old = progress
end

local function BorderGradient4LinesCenter(f, progress, elapsed)
	local inf = f.info
	local tails = inf.tail.list
	local c1, c2, c3, c4 = BorderGradientCorners(inf, elapsed)
	
	
	if inf.mirror then
		local c1x1 = GetHSVTransition(progress / 2, c2, c1)
		local c1x2 = GetHSVTransition(progress / 2, c1, c2)
		local c2x1 = GetHSVTransition(progress / 2, c4, c1)
		local c2x2 = GetHSVTransition(progress / 2, c1, c4)
		local c3x1 = GetHSVTransition(progress / 2, c3, c4)
		local c3x2 = GetHSVTransition(progress / 2, c4, c3)
		local c4x1 = GetHSVTransition(progress / 2, c3, c2)
		local c4x2 = GetHSVTransition(progress / 2, c2, c3)
		
		SetGradA(tails[1], "HORIZONTAL", c1x1, c1x2)
		SetGradA(tails[2], "VERTICAL", c2x1, c2x2)
		SetGradA(tails[3], "HORIZONTAL", c3x1, c3x2)
		SetGradA(tails[4], "VERTICAL", c4x1, c4x2)
	
	else
		local c12 = GetHSVTransition(0.5, c1, c2)
		local c23 = GetHSVTransition(0.5, c2, c3)
		local c34 = GetHSVTransition(0.5, c3, c4)
		local c41 = GetHSVTransition(0.5, c4, c1)
		
		local cornerP = inf.height / (inf.width + inf.height)
		if inf.clockwise then
			if progress < cornerP then
				local c2x = GetHSVTransition(progress, c23, c2)
				local c6x = GetHSVTransition(progress, c41, c4)
				SetGradA(tails[1], "HORIZONTAL", c2, c12)
				SetGradA(tails[2], "VERTICAL", c2x, c2)
				SetGradA(tails[5], "HORIZONTAL", c34, c4)
				SetGradA(tails[6], "VERTICAL", c4, c6x)
			else
				local c1x = GetHSVTransition(progress, c2, c12)
				local c5x = GetHSVTransition(progress, c4, c34)
				SetGradA(tails[1], "HORIZONTAL", c1x, c12)
				SetGradA(tails[5], "HORIZONTAL", c34, c5x)
			end
			if progress < 1 - cornerP then
				local c4x = GetHSVTransition(progress, c34, c3)
				local c8x = GetHSVTransition(progress, c12, c1)
				SetGradA(tails[3], "VERTICAL", c3, c23)
				SetGradA(tails[4], "HORIZONTAL", c3, c4x)
				SetGradA(tails[7], "VERTICAL", c41, c1)
				SetGradA(tails[8], "HORIZONTAL", c8x, c1)
			else
				local c3x = GetHSVTransition(progress, c3, c34)
				local c7x = GetHSVTransition(progress, c1, c41)
				SetGradA(tails[3], "VERTICAL", c3x, c23)
				SetGradA(tails[7], "VERTICAL", c41, c7x)
			end
		else
			if progress < cornerP then
				local c2x = GetHSVTransition(progress, c41, c1)
				local c6x = GetHSVTransition(progress, c23, c3)
				SetGradA(tails[1], "HORIZONTAL", c12, c1)
				SetGradA(tails[2], "VERTICAL", c2x, c1)
				SetGradA(tails[5], "HORIZONTAL", c3, c34)
				SetGradA(tails[6], "VERTICAL", c3, c6x)
			else
				local c1x = GetHSVTransition(progress, c1, c12)
				local c5x = GetHSVTransition(progress, c3, c34)
				SetGradA(tails[1], "HORIZONTAL", c12, c1x)
				SetGradA(tails[5], "HORIZONTAL", c5x, c34)
			end
			if progress < 1 - cornerP then
				local c4x = GetHSVTransition(progress, c34, c4)
				local c8x = GetHSVTransition(progress, c12, c2)
				SetGradA(tails[3], "VERTICAL", c4, c41)
				SetGradA(tails[4], "HORIZONTAL", c4x, c4)
				SetGradA(tails[7], "VERTICAL", c23, c2)
				SetGradA(tails[8], "HORIZONTAL", c2, c8x)
			else
				local c3x = GetHSVTransition(progress, c4, c41)
				local c7x = GetHSVTransition(progress, c2, c23)
				SetGradA(tails[3], "VERTICAL", c3x, c41)
				SetGradA(tails[7], "VERTICAL", c23, c7x)
			end
		end
	end
end

local function BorderSet4LinesCorner(f, update)
	local inf = f.info
	local tails = inf.tail.list
	if not(update) then
		for _, v in pairs(tails) do
			v:ClearAllPoints()
		end 
		if inf.mirror then
			tails[1]:SetPoint("TOPRIGHT", f, "TOPRIGHT")
			tails[2]:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -inf.th)
			tails[3]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, inf.th)
			tails[4]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT")
			tails[5]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT")
			tails[6]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, inf.th)
			tails[7]:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -inf.th)
			tails[8]:SetPoint("TOPLEFT", f, "TOPLEFT")

			tails[5]:Show()
			tails[6]:Show()
			tails[7]:Show()
			tails[8]:Show()
			
			tails[1]:SetHeight(inf.th)
			tails[2]:SetWidth(inf.th)
			tails[3]:SetWidth(inf.th)
			tails[4]:SetHeight(inf.th)
			tails[5]:SetHeight(inf.th)
			tails[6]:SetWidth(inf.th)
			tails[7]:SetWidth(inf.th)
			tails[8]:SetHeight(inf.th)
		else
			if inf.clockwise then
				tails[1]:SetPoint("TOPRIGHT", f, "TOPRIGHT")
				tails[2]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT")
				tails[3]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT")
				tails[4]:SetPoint("TOPLEFT", f, "TOPLEFT")
			else
				tails[1]:SetPoint("TOPLEFT", f, "TOPLEFT")
				tails[2]:SetPoint("TOPRIGHT", f, "TOPRIGHT")
				tails[3]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT")
				tails[4]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT")
			end
			tails[5]:Hide()
			tails[6]:Hide()
			tails[7]:Hide()
			tails[8]:Hide()			
			
			tails[1]:SetHeight(inf.th)
			tails[2]:SetWidth(inf.th)
			tails[3]:SetHeight(inf.th)
			tails[4]:SetWidth(inf.th)
		end
	end
	local width, height = f:GetSize()
	if inf.mirror then
		tails[1]:SetWidth(width / 2)
		tails[2]:SetHeight(height / 2 - inf.th)
		tails[3]:SetHeight(height / 2 - inf.th)
		tails[4]:SetWidth(width / 2)
		tails[5]:SetWidth(width / 2)
		tails[6]:SetHeight(height / 2 - inf.th)
		tails[7]:SetHeight(height / 2 - inf.th)
		tails[8]:SetWidth(width / 2)
	else
		tails[1]:SetWidth(width - inf.th)
		tails[2]:SetHeight(height - inf.th)
		tails[3]:SetWidth(width - inf.th)
		tails[4]:SetHeight(height - inf.th)
	end
end

local function BorderUpdate4LinesCorner(f, progress)
	local inf = f.info
	local tails = inf.tail.list
		
	if inf.mirror then
		local newW = inf.width / 2 * (1 - progress)
		local newH = (inf.height / 2 - inf.th) * (1 - progress)
		tails[1]:SetWidth(newW)
		tails[2]:SetHeight(newH)
		tails[3]:SetHeight(newH)
		tails[4]:SetWidth(newW)
		tails[5]:SetWidth(newW)
		tails[6]:SetHeight(newH)
		tails[7]:SetHeight(newH)
		tails[8]:SetWidth(newW)
	else
		local newW = (inf.width - inf.th) * (1 - progress)
		local newH = (inf.height - inf.th) * (1 - progress)
		tails[1]:SetWidth(newW)
		tails[2]:SetHeight(newH)
		tails[3]:SetWidth(newW)
		tails[4]:SetHeight(newH)
	end
end

local function BorderGradient4LinesCorner(f, progress, elapsed)
	local inf = f.info
	local tails = inf.tail.list
	local c1, c2, c3, c4 = BorderGradientCorners(inf, elapsed)
	
	
	if inf.mirror then
		local gradProg = 0.5 + progress / 2
		local c1x = GetHSVTransition(gradProg, c2, c1)
		local c2x = GetHSVTransition(gradProg, c4, c1)
		local c3x = GetHSVTransition(gradProg, c1, c4)
		local c4x = GetHSVTransition(gradProg, c3, c4)
		local c5x = GetHSVTransition(gradProg, c4, c3)
		local c6x = GetHSVTransition(gradProg, c2, c3)
		local c7x = GetHSVTransition(gradProg, c3, c2)
		local c8x = GetHSVTransition(gradProg, c1, c2)
		
		SetGradA(tails[1], "HORIZONTAL", c1x, c1)
		SetGradA(tails[2], "VERTICAL", c2x, c1)
		SetGradA(tails[3], "VERTICAL", c4, c3x)
		SetGradA(tails[4], "HORIZONTAL", c4x, c4)
		SetGradA(tails[5], "HORIZONTAL", c3, c5x)
		SetGradA(tails[6], "VERTICAL", c3, c6x)
		SetGradA(tails[7], "VERTICAL", c7x, c2)
		SetGradA(tails[8], "HORIZONTAL", c2, c8x)
	else
		if inf.clockwise then
			local c1x = GetHSVTransition(progress, c2, c1)
			local c2x = GetHSVTransition(progress, c1, c4)
			local c3x = GetHSVTransition(progress, c4, c3)
			local c4x = GetHSVTransition(progress, c3, c2)
			
			SetGradA(tails[1], "HORIZONTAL", c1x, c1)
			SetGradA(tails[2], "VERTICAL", c4, c2x)
			SetGradA(tails[3], "HORIZONTAL", c3, c3x)
			SetGradA(tails[4], "VERTICAL", c4x, c2)
		else
			local c1x = GetHSVTransition(progress, c1, c2)
			local c2x = GetHSVTransition(progress, c4, c1)
			local c3x = GetHSVTransition(progress, c3, c4)
			local c4x = GetHSVTransition(progress, c2, c3)
			
			SetGradA(tails[1], "HORIZONTAL", c2, c1x)
			SetGradA(tails[2], "VERTICAL", c2x, c1)
			SetGradA(tails[3], "HORIZONTAL", c3x, c4)
			SetGradA(tails[4], "VERTICAL", c4x, c2)
		end
	end
end

local function BorderSet2LinesCenter(f, update)
	local inf = f.info
	local tails = inf.tail.list
	if not(update) then
		for _, v in pairs(tails) do
			v:ClearAllPoints()
		end 
		if inf.mirror then
			if inf.startPoint == "LEFT" or inf.startPoint == "RIGHT" then
				inf.tail.Set1 = f.SetHeight
				inf.tail.Set2 = f.SetWidth
				tails[1]:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -inf.th)
				tails[2]:SetPoint("TOP", f, "TOP")
				tails[3]:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -inf.th)
				tails[4]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, inf.th)
				tails[5]:SetPoint("BOTTOM", f, "BOTTOM")
				tails[6]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, inf.th)
			else
				inf.tail.Set1 = f.SetWidth
				inf.tail.Set2 = f.SetHeight
				tails[1]:SetPoint("TOPLEFT", f, "TOPLEFT", inf.th, 0)
				tails[2]:SetPoint("LEFT", f, "LEFT")
				tails[3]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", inf.th, 0)
				tails[4]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inf.th, 0)
				tails[5]:SetPoint("RIGHT", f, "RIGHT")
				tails[6]:SetPoint("TOPRIGHT", f, "TOPRIGHT", -inf.th, 0)
			end
		else
			if inf.startPoint == "TOP" or inf.startPoint == "BOTTOM" then
				inf.tail.Set1 = f.SetWidth
				inf.tail.Set2 = f.SetHeight				
				if inf.clockwise then
					tails[1]:SetPoint("TOPRIGHT", f, "TOPRIGHT", -inf.th, 0)
					tails[2]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, inf.th)
					tails[3]:SetPoint("BOTTOMLEFT", f, "BOTTOM")
					tails[4]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", inf.th, 0)
					tails[5]:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -inf.th)
					tails[6]:SetPoint("TOPRIGHT", f, "TOP")
				else
					tails[1]:SetPoint("TOPLEFT", f, "TOPLEFT", inf.th, 0)
					tails[2]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, inf.th)
					tails[3]:SetPoint("BOTTOMRIGHT", f, "BOTTOM")
					tails[4]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", - inf.th, 0)
					tails[5]:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -inf.th)
					tails[6]:SetPoint("TOPLEFT", f, "TOP")
				end
			else
				inf.tail.Set1 = f.SetHeight
				inf.tail.Set2 = f.SetWidth				
				if inf.clockwise then
					tails[1]:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -inf.th)
					tails[2]:SetPoint("TOPRIGHT", f, "TOPRIGHT", -inf.th, 0)
					tails[3]:SetPoint("BOTTOMRIGHT", f, "RIGHT")
					tails[4]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, inf.th)
					tails[5]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", inf.th, 0)
					tails[6]:SetPoint("TOPLEFT", f, "LEFT")
				else
					tails[1]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, inf.th)
					tails[2]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inf.th, 0)
					tails[3]:SetPoint("TOPRIGHT", f, "RIGHT")
					tails[4]:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -inf.th)
					tails[5]:SetPoint("TOPLEFT", f, "TOPLEFT", inf.th, 0)
					tails[6]:SetPoint("BOTTOMLEFT", f, "LEFT")
				end		
			end			
		end
		inf.tail.Set2(tails[1], inf.th)
		inf.tail.Set1(tails[2], inf.th)
		inf.tail.Set2(tails[3], inf.th)
		inf.tail.Set2(tails[4], inf.th)
		inf.tail.Set1(tails[5], inf.th)
		inf.tail.Set2(tails[6], inf.th)
	end
	if inf.startPoint == "TOP" or inf.startPoint == "BOTTOM" then
		inf.tail.size1 = f:GetWidth()
		inf.tail.size2 = f:GetHeight()
	else
		inf.tail.size1 = f:GetHeight()
		inf.tail.size2 = f:GetWidth()
	end
	if inf.mirror then
		inf.tail.Set1(tails[1], inf.tail.size1 / 2 - inf.th)
		inf.tail.Set2(tails[2], inf.tail.size2)
		inf.tail.Set1(tails[3], inf.tail.size1 / 2 - inf.th)
		inf.tail.Set1(tails[4], inf.tail.size1 / 2 - inf.th)
		inf.tail.Set2(tails[5], inf.tail.size2)
		inf.tail.Set1(tails[6], inf.tail.size1 / 2 - inf.th)
	else
		inf.tail.Set1(tails[1], inf.tail.size1/2 - inf.th)
		inf.tail.Set2(tails[2], inf.tail.size2- inf.th)
		inf.tail.Set1(tails[3], inf.tail.size1/2)
		inf.tail.Set1(tails[4], inf.tail.size1/2 - inf.th)
		inf.tail.Set2(tails[5], inf.tail.size2 - inf.th)
		inf.tail.Set1(tails[6], inf.tail.size1/2)
	end
end

local function BorderUpdate2LinesCenter(f, progress)
	local inf = f.info
	local tails = inf.tail.list
	local oldProgress = inf.tail.old
	
	if inf.mirror then
		local cornerP = inf.tail.size1 / (inf.tail.size1 + inf.tail.size2)
		if progress < cornerP then
			if oldProgress > cornerP or oldProgress <= 0 then
				for _,v in pairs(tails) do
					v:Show()
				end
				BorderSet2LinesCenter(f, true)
			end
			local stageProg = 1 - progress / cornerP
			inf.tail.Set1(tails[1], stageProg * (inf.tail.size1 / 2 - inf.th))
			inf.tail.Set1(tails[3], stageProg * (inf.tail.size1 / 2 - inf.th))
			inf.tail.Set1(tails[4], stageProg * (inf.tail.size1 / 2 - inf.th))
			inf.tail.Set1(tails[6], stageProg * (inf.tail.size1 / 2 - inf.th))
			
		else
			if oldProgress >= 1 or oldProgress < cornerP then
				tails[1]:Hide()
				tails[2]:Show()
				tails[3]:Hide()
				tails[4]:Hide()
				tails[5]:Show()
				tails[6]:Hide()
				BorderSet2LinesCenter(f, true)
			end
			local stageProg = (1 - progress) / (1 - cornerP)
			inf.tail.Set2(tails[2], stageProg * inf.tail.size2)
			inf.tail.Set2(tails[5], stageProg * inf.tail.size2)
		end
	else	
		local cornerP = inf.tail.size1/2/(inf.tail.size1 + inf.tail.size2)	
		if progress < cornerP then
			if oldProgress > cornerP or oldProgress <= 0 then
				for _, v in pairs(tails) do
					v:Show()
				end			
				BorderSet2LinesCenter(f, true)
			end
			local stageProg = 1 - progress / cornerP
			inf.tail.Set1(tails[1], stageProg * (inf.tail.size1 / 2 - inf.th))
			inf.tail.Set1(tails[4], stageProg * (inf.tail.size1 / 2 - inf.th))
		elseif progress < (1 - cornerP) then
			if oldProgress > (1 - cornerP) or oldProgress <= cornerP then
				tails[1]:Hide()
				tails[2]:Show()
				tails[3]:Show()
				tails[4]:Hide()
				tails[5]:Show()
				tails[6]:Show()
				BorderSet2LinesCenter(f, true)
			end
			local stageProg = (1 - cornerP - progress) / ( 1 - 2 * cornerP)
			inf.tail.Set2(tails[2], stageProg * (inf.tail.size2 - inf.th))
			inf.tail.Set2(tails[5], stageProg * (inf.tail.size2 - inf.th))
		elseif progress < 1 then
			if oldProgress >= 1 or oldProgress < (1 - cornerP) then
				tails[1]:Hide()
				tails[2]:Hide()
				tails[3]:Show()
				tails[4]:Hide()
				tails[5]:Hide()
				tails[6]:Show()
				BorderSet2LinesCenter(f, true)
			end
				local stageProg = (1 - progress) / cornerP
				inf.tail.Set1(tails[3], stageProg * (inf.tail.size1 / 2))
				inf.tail.Set1(tails[6], stageProg * (inf.tail.size1 / 2))
		end
	end
	inf.tail.old = progress
end

local function BorderGradient2LinesCenter(f, progress, elapsed)
	local inf = f.info
	local tails = inf.tail.list
	local c1, c2, c3, c4 = BorderGradientCorners(inf, elapsed)
		
	if inf.mirror then
		local cornerP = inf.tail.size1 / (inf.tail.size1 + inf.tail.size2)
		if progress < cornerP then
			local stageProg = progress / cornerP
			if inf.startPoint == "LEFT" or inf.startPoint == "RIGHT" then
				local c23 = GetHSVTransition(0.5, c2, c3)
				local c41 = GetHSVTransition(0.5, c4, c1)
				local c1x = GetHSVTransition(stageProg, c41, c1)
				local c3x = GetHSVTransition(stageProg, c23, c2)
				local c4x = GetHSVTransition(stageProg, c23, c3)
				local c6x = GetHSVTransition(stageProg, c41, c4)
				SetGradA(tails[1], "VERTICAL", c1x, c1)
				SetGradA(tails[2], "HORIZONTAL", c2, c1)
				SetGradA(tails[3], "VERTICAL", c3x, c2)
				SetGradA(tails[4], "VERTICAL", c3, c4x)
				SetGradA(tails[5], "HORIZONTAL", c3, c4)
				SetGradA(tails[6], "VERTICAL", c4, c6x)
			else
				local c12 = GetHSVTransition(0.5, c1, c2)
				local c34 = GetHSVTransition(0.5, c3, c4)
				local c1x = GetHSVTransition(stageProg, c12, c2)
				local c3x = GetHSVTransition(stageProg, c34, c3)
				local c4x = GetHSVTransition(stageProg, c34, c4)
				local c6x = GetHSVTransition(stageProg, c12, c1)
				SetGradA(tails[1], "HORIZONTAL", c2, c1x)
				SetGradA(tails[2], "VERTICAL", c3, c2)
				SetGradA(tails[3], "HORIZONTAL", c3, c3x)
				SetGradA(tails[4], "HORIZONTAL", c4x, c4)
				SetGradA(tails[5], "VERTICAL", c4, c1)
				SetGradA(tails[6], "HORIZONTAL", c6x, c1)
			end
		else
			local stageProg = (progress - cornerP)/ (1 - cornerP) / 2
			if inf.startPoint == "LEFT" or inf.startPoint == "RIGHT" then
				local c2x1 = GetHSVTransition(stageProg, c2, c1)
				local c2x2 = GetHSVTransition(stageProg, c1, c2)
				local c5x1 = GetHSVTransition(stageProg, c3, c4)
				local c5x2 = GetHSVTransition(stageProg, c4, c3)
				SetGradA(tails[2], "HORIZONTAL", c2x1, c2x2)
				SetGradA(tails[5], "HORIZONTAL", c5x1, c5x2)
			else
				local c2x1 = GetHSVTransition(stageProg, c3, c2)
				local c2x2 = GetHSVTransition(stageProg, c2, c3)
				local c5x1 = GetHSVTransition(stageProg, c4, c1)
				local c5x2 = GetHSVTransition(stageProg, c1, c4)
				SetGradA(tails[2], "VERTICAL", c2x1, c2x2)
				SetGradA(tails[5], "VERTICAL", c5x1, c5x2)
			end
		end
	else
		local cornerP = inf.tail.size1 / (inf.tail.size1 + inf.tail.size2) / 2
		if inf.clockwise then
			if progress < cornerP then
				local stageProg = progress / cornerP
				if inf.startPoint == "TOP" or inf.startPoint == "BOTTOM" then
					local c12 = GetHSVTransition(0.5, c1, c2)
					local c34 = GetHSVTransition(0.5, c3, c4)
					local c1x = GetHSVTransition(stageProg, c12, c1)
					local c4x = GetHSVTransition(stageProg, c34, c3)
					
					SetGradA(tails[1], "HORIZONTAL", c1x, c1)
					SetGradA(tails[2], "VERTICAL", c4, c1)
					SetGradA(tails[3], "HORIZONTAL", c34, c4)
					SetGradA(tails[4], "HORIZONTAL", c3, c4x)
					SetGradA(tails[5], "VERTICAL", c3, c2)
					SetGradA(tails[6], "HORIZONTAL", c2, c12)
					
				else
					local c23 = GetHSVTransition(0.5, c2, c3)
					local c41 = GetHSVTransition(0.5, c4, c1)
					local c1x = GetHSVTransition(stageProg, c23, c2)
					local c4x = GetHSVTransition(stageProg, c41, c4)
					
					SetGradA(tails[1], "VERTICAL", c1x, c2)
					SetGradA(tails[2], "HORIZONTAL", c2, c1)
					SetGradA(tails[3], "VERTICAL", c41, c1)
					SetGradA(tails[4], "VERTICAL", c4, c4x)
					SetGradA(tails[5], "HORIZONTAL", c3, c4)
					SetGradA(tails[6], "VERTICAL", c3, c23)
				end
			elseif progress < (1 - cornerP) then
				local stageProg = (progress - cornerP)  / (1 - cornerP * 2)
				if inf.startPoint == "TOP" or inf.startPoint == "BOTTOM" then
					local c12 = GetHSVTransition(0.5, c1, c2)
					local c34 = GetHSVTransition(0.5, c3, c4)
					local c2x = GetHSVTransition(stageProg, c1, c4)
					local c5x = GetHSVTransition(stageProg, c3, c2)
					
					SetGradA(tails[2], "VERTICAL", c4, c2x)
					SetGradA(tails[3], "HORIZONTAL", c34, c4)
					SetGradA(tails[5], "VERTICAL", c5x, c2)
					SetGradA(tails[6], "HORIZONTAL", c2, c12)
					
				else
					local c23 = GetHSVTransition(0.5, c2, c3)
					local c41 = GetHSVTransition(0.5, c4, c1)
					local c2x = GetHSVTransition(stageProg, c2, c1)
					local c5x = GetHSVTransition(stageProg, c4, c3)
					
					SetGradA(tails[2], "HORIZONTAL", c2x, c1)
					SetGradA(tails[3], "VERTICAL", c41, c1)
					SetGradA(tails[5], "HORIZONTAL", c3, c5x)
					SetGradA(tails[6], "VERTICAL", c3, c23)
				end
			else
				local stageProg = (progress - 1 + cornerP) / cornerP
				if inf.startPoint == "TOP" or inf.startPoint == "BOTTOM" then
					local c12 = GetHSVTransition(0.5, c1, c2)
					local c34 = GetHSVTransition(0.5, c3, c4)
					local c3x = GetHSVTransition(stageProg, c4, c34)
					local c6x = GetHSVTransition(stageProg, c2, c12)
					
					SetGradA(tails[3], "HORIZONTAL", c34, c3x)
					SetGradA(tails[6], "HORIZONTAL", c6x, c12)
					
				else
					local c23 = GetHSVTransition(0.5, c2, c3)
					local c41 = GetHSVTransition(0.5, c4, c1)
					local c3x = GetHSVTransition(stageProg, c1, c41)
					local c6x = GetHSVTransition(stageProg, c3, c23)
					
					SetGradA(tails[3], "VERTICAL", c41, c3x)
					SetGradA(tails[6], "VERTICAL", c6x, c23)
				end
			end
		else
			if progress < cornerP then
				local stageProg = progress / cornerP
				if inf.startPoint == "TOP" or inf.startPoint == "BOTTOM" then
					local c12 = GetHSVTransition(0.5, c1, c2)
					local c34 = GetHSVTransition(0.5, c3, c4)
					local c1x = GetHSVTransition(stageProg, c12, c1)
					local c4x = GetHSVTransition(stageProg, c34, c4)
					
					SetGradA(tails[1], "HORIZONTAL", c2, c1x)
					SetGradA(tails[2], "VERTICAL", c3, c2)
					SetGradA(tails[3], "HORIZONTAL", c3, c34)
					SetGradA(tails[4], "HORIZONTAL", c4x, c4)
					SetGradA(tails[5], "VERTICAL", c4, c1)
					SetGradA(tails[6], "HORIZONTAL", c12, c1)
					
				else
					local c23 = GetHSVTransition(0.5, c2, c3)
					local c41 = GetHSVTransition(0.5, c4, c1)
					local c1x = GetHSVTransition(stageProg, c23, c3)
					local c4x = GetHSVTransition(stageProg, c41, c1)
					
					SetGradA(tails[1], "VERTICAL", c3, c1x)
					SetGradA(tails[2], "HORIZONTAL", c3, c4)
					SetGradA(tails[3], "VERTICAL", c4, c41)
					SetGradA(tails[4], "VERTICAL", c4x, c1)
					SetGradA(tails[5], "HORIZONTAL", c2, c1)
					SetGradA(tails[6], "VERTICAL", c23, c2)
				end
			elseif progress < (1 - cornerP) then
				local stageProg = (progress - cornerP)  / (1 - cornerP * 2)
				if inf.startPoint == "TOP" or inf.startPoint == "BOTTOM" then
					local c12 = GetHSVTransition(0.5, c1, c2)
					local c34 = GetHSVTransition(0.5, c3, c4)
					local c2x = GetHSVTransition(stageProg, c2, c3)
					local c5x = GetHSVTransition(stageProg, c4, c1)
					
					SetGradA(tails[2], "VERTICAL", c3, c2x)
					SetGradA(tails[3], "HORIZONTAL", c3, c34)
					SetGradA(tails[5], "VERTICAL", c5x, c1)
					SetGradA(tails[6], "HORIZONTAL", c12, c1)
					
				else
					local c23 = GetHSVTransition(0.5, c2, c3)
					local c41 = GetHSVTransition(0.5, c4, c1)
					local c2x = GetHSVTransition(stageProg, c3, c4)
					local c5x = GetHSVTransition(stageProg, c1, c2)
					
					SetGradA(tails[2], "HORIZONTAL", c2x, c4)
					SetGradA(tails[3], "VERTICAL", c4, c41)
					SetGradA(tails[5], "HORIZONTAL", c2, c5x)
					SetGradA(tails[6], "VERTICAL", c23, c2)
				end
			else
				local stageProg = (progress - 1 + cornerP) / cornerP
				if inf.startPoint == "TOP" or inf.startPoint == "BOTTOM" then
					local c12 = GetHSVTransition(0.5, c1, c2)
					local c34 = GetHSVTransition(0.5, c3, c4)
					local c3x = GetHSVTransition(stageProg, c3, c34)
					local c6x = GetHSVTransition(stageProg, c1, c12)
					
					SetGradA(tails[3], "HORIZONTAL", c3x, c34)
					SetGradA(tails[6], "HORIZONTAL", c12, c6x)
					
				else
					local c23 = GetHSVTransition(0.5, c2, c3)
					local c41 = GetHSVTransition(0.5, c4, c1)
					local c3x = GetHSVTransition(stageProg, c4, c41)
					local c6x = GetHSVTransition(stageProg, c2, c23)
					
					SetGradA(tails[3], "VERTICAL", c3x, c41)
					SetGradA(tails[6], "VERTICAL", c23, c6x)
				end
			end
		end
	end
end

local function BorderSet2LinesCorner(f, update)
	local inf = f.info
	local tails = inf.tail.list
	if not(update) then
		for _, v in pairs(tails) do
			v:ClearAllPoints()
		end 
		if inf.mirror then
			if inf.startPoint == "TOPLEFT" or inf.startPoint == "BOTTOMRIGHT" then
				tails[1]:SetPoint("TOPRIGHT", f, "TOPRIGHT")
				tails[2]:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -inf.th)
				tails[3]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT")
				tails[4]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", inf.th, 0)
			else
				tails[1]:SetPoint("TOPLEFT", f, "TOPLEFT")
				tails[2]:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -inf.th)
				tails[3]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT")
				tails[4]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inf.th, 0)
			end
			tails[1]:SetHeight(inf.th)
			tails[2]:SetWidth(inf.th)
			tails[3]:SetWidth(inf.th)
			tails[4]:SetHeight(inf.th)
		else
			if inf.startPoint == "TOPLEFT" or inf.startPoint == "BOTTOMRIGHT" then
				if inf.clockwise then
					inf.tail.Set1 = f.SetWidth
					inf.tail.Set2 = f.SetHeight
					tails[1]:SetPoint("TOPRIGHT", f, "TOPRIGHT", -inf.th, 0)
					tails[2]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT")
					tails[3]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", inf.th, 0)
					tails[4]:SetPoint("TOPLEFT", f, "TOPLEFT")
				else
					inf.tail.Set1 = f.SetHeight
					inf.tail.Set2 = f.SetWidth					
					tails[1]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, inf.th)
					tails[2]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT")
					tails[3]:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -inf.th)
					tails[4]:SetPoint("TOPLEFT", f, "TOPLEFT")
				end
			else
				if inf.clockwise then
					inf.tail.Set1 = f.SetHeight
					inf.tail.Set2 = f.SetWidth					
					tails[1]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, inf.th)
					tails[2]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT")
					tails[3]:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -inf.th)
					tails[4]:SetPoint("TOPRIGHT", f, "TOPRIGHT")
				else
					inf.tail.Set1 = f.SetWidth
					inf.tail.Set2 = f.SetHeight
					tails[1]:SetPoint("TOPLEFT", f, "TOPLEFT", inf.th, 0)
					tails[2]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT")
					tails[3]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inf.th, 0)
					tails[4]:SetPoint("TOPRIGHT", f, "TOPRIGHT")			
				end
			end
			inf.tail.Set2(tails[1], inf.th)
			inf.tail.Set1(tails[2], inf.th)
			inf.tail.Set2(tails[3], inf.th)
			inf.tail.Set1(tails[4], inf.th)
		end
	end
	
	if inf.mirror then
		tails[1]:SetWidth(f:GetWidth())
		tails[2]:SetHeight(f:GetHeight() - inf.th)
		tails[3]:SetHeight(f:GetHeight())
		tails[4]:SetWidth(f:GetWidth() - inf.th)
	else
		if inf.clockwise and (inf.startPoint == "TOPLEFT" or inf.startPoint == "BOTTOMRIGHT") or
			 not(inf.clockwise) and (inf.startPoint == "BOTTOMLEFT" or inf.startPoint == "TOPRIGHT") then
			inf.tail.size1 = f:GetWidth()
		  inf.tail.size2 = f:GetHeight()
		else
			inf.tail.size1 = f:GetHeight()
		  inf.tail.size2 = f:GetWidth()
		end
		inf.tail.Set1(tails[1], inf.tail.size1 - 2*inf.th)
		inf.tail.Set2(tails[2], inf.tail.size2)
		inf.tail.Set1(tails[3], inf.tail.size1 - 2*inf.th)
		inf.tail.Set2(tails[4], inf.tail.size2)
	end
end

local function BorderUpdate2LinesCorner(f, progress)
	local inf = f.info
	local tails = inf.tail.list
	local oldProgress = inf.tail.old
	if inf.mirror then
		tails[1]:SetWidth((1 - progress) * inf.width)
		tails[2]:SetHeight((1 - progress) * (inf.height - inf.th))
		tails[3]:SetHeight((1 - progress) * inf.height)
		tails[4]:SetWidth((1 - progress) * (inf.width - inf.th))
	else
		local cornerP = inf.tail.size1/(inf.tail.size1 + inf.tail.size2)	
		if progress < cornerP then
			if oldProgress > cornerP or oldProgress <= 0 then
				for _, v in pairs(tails) do
					v:Show()
				end			
				BorderSet2LinesCorner(f, true)
			end
			local stageProg = 1 - progress / cornerP
			inf.tail.Set1(tails[1], stageProg * (inf.tail.size1 - 2*inf.th))
			inf.tail.Set1(tails[3], stageProg * (inf.tail.size1 - 2*inf.th))
		else
			if oldProgress >= 1 or oldProgress < cornerP then
				tails[1]:Hide()
				tails[2]:Show()
				tails[3]:Hide()
				tails[4]:Show()
				BorderSet2LinesCorner(f, true)
			end
				local stageProg = (1 - progress) / (1 - cornerP)
				inf.tail.Set2(tails[2], stageProg * inf.tail.size2)
				inf.tail.Set2(tails[4], stageProg * inf.tail.size2)
		end
	end
	inf.tail.old = progress
end

local function BorderGradient2LinesCorner(f, progress, elapsed)
	local inf = f.info
	local tails = inf.tail.list
	local c1, c2, c3, c4 = BorderGradientCorners(inf, elapsed)
		
	if inf.mirror then
		if inf.startPoint == "TOPLEFT" or inf.startPoint == "BOTTOMRIGHT" then
			local c1x = GetHSVTransition(progress, c2, c1)
			local c2x = GetHSVTransition(progress, c4, c1)
			local c3x = GetHSVTransition(progress, c2, c3)
			local c4x = GetHSVTransition(progress, c4, c3)
			
			SetGradA(tails[1], "HORIZONTAL", c1x, c1)
			SetGradA(tails[2], "VERTICAL", c2x, c1)
			SetGradA(tails[3], "VERTICAL", c3, c3x)
			SetGradA(tails[4], "HORIZONTAL", c3, c4)
		else
			local c1x = GetHSVTransition(progress, c1, c2)
			local c2x = GetHSVTransition(progress, c3, c2)
			local c3x = GetHSVTransition(progress, c1, c4)
			local c4x = GetHSVTransition(progress, c3, c4)
			
			SetGradA(tails[1], "HORIZONTAL", c2, c1x)
			SetGradA(tails[2], "VERTICAL", c2x, c2)
			SetGradA(tails[3], "VERTICAL", c4, c3x)
			SetGradA(tails[4], "HORIZONTAL", c4x, c4)
		end
	else
		local cornerP = inf.tail.size1/(inf.tail.size1 + inf.tail.size2)
		if inf.clockwise then
			if progress < cornerP then
				local stageProg = progress / cornerP
				if inf.startPoint == "TOPLEFT" or inf.startPoint == "BOTTOMRIGHT" then
					local c1x = GetHSVTransition(stageProg, c2, c1)
					local c3x = GetHSVTransition(stageProg, c4, c3)
					
					SetGradA(tails[1], "HORIZONTAL", c1x, c1)
					SetGradA(tails[2], "VERTICAL", c4, c1)
					SetGradA(tails[3], "HORIZONTAL", c3, c3x)
					SetGradA(tails[4], "VERTICAL", c3, c2)
					
				else
					local c1x = GetHSVTransition(stageProg, c1, c4)
					local c3x = GetHSVTransition(stageProg, c3, c2)
					
					SetGradA(tails[1], "VERTICAL", c4, c1x)
					SetGradA(tails[2], "HORIZONTAL", c3, c4)
					SetGradA(tails[3], "VERTICAL", c3x, c2)
					SetGradA(tails[4], "HORIZONTAL", c2, c1)
				end
			else
				local stageProg = (progress - cornerP)  / (1 - cornerP)
				if inf.startPoint == "TOPLEFT" or inf.startPoint == "BOTTOMRIGHT" then
					local c2x = GetHSVTransition(stageProg, c1, c4)
					local c4x = GetHSVTransition(stageProg, c3, c2)
					
					
					SetGradA(tails[2], "VERTICAL", c4, c2x)
					SetGradA(tails[4], "VERTICAL", c4x, c2)
					
				else
					local c2x = GetHSVTransition(stageProg, c4, c3)
					local c4x = GetHSVTransition(stageProg, c2, c1)
					
					SetGradA(tails[2], "HORIZONTAL", c3, c2x)
					SetGradA(tails[4], "HORIZONTAL", c4x, c1)
				end
			end
		else
			if progress < cornerP then
				local stageProg = progress / cornerP
				if inf.startPoint == "TOPLEFT" or inf.startPoint == "BOTTOMRIGHT" then
					local c1x = GetHSVTransition(stageProg, c2, c3)
					local c3x = GetHSVTransition(stageProg, c4, c1)
					
					SetGradA(tails[1], "VERTICAL", c3, c1x)
					SetGradA(tails[2], "HORIZONTAL", c3, c4)
					SetGradA(tails[3], "VERTICAL", c3x, c1)
					SetGradA(tails[4], "HORIZONTAL", c2, c1)
					
				else
					local c1x = GetHSVTransition(stageProg, c1, c2)
					local c3x = GetHSVTransition(stageProg, c3, c4)
					
					SetGradA(tails[1], "HORIZONTAL", c2, c1x)
					SetGradA(tails[2], "VERTICAL", c3, c2)
					SetGradA(tails[3], "HORIZONTAL", c3x, c4)
					SetGradA(tails[4], "VERTICAL", c4, c1)
				end
			else
				local stageProg = (progress - cornerP)  / (1 - cornerP)
				if inf.startPoint == "TOPLEFT" or inf.startPoint == "BOTTOMRIGHT" then
					local c2x = GetHSVTransition(stageProg, c3, c4)
					local c4x = GetHSVTransition(stageProg, c1, c2)
					
					
					SetGradA(tails[2], "HORIZONTAL", c2x, c4)
					SetGradA(tails[4], "HORIZONTAL", c2, c4x)
					
				else
					local c2x = GetHSVTransition(stageProg, c2, c3)
					local c4x = GetHSVTransition(stageProg, c4, c1)
					
					SetGradA(tails[2], "VERTICAL", c3, c2x)
					SetGradA(tails[4], "VERTICAL", c4x, c1)
				end
			end
		end
	end
end

local function BorderSet1LineCenter(f, update)
	local inf = f.info
	local tails = inf.tail.list
	if not(update) then 
		for _, v in pairs(tails) do
			v:ClearAllPoints()
		end
		if inf.mirror then
			if inf.startPoint == "TOP" then
				inf.tail.Set1 = f.SetWidth
				inf.tail.Set2 = f.SetHeight
				tails[1]:SetPoint("TOPRIGHT", f, "TOPRIGHT", -inf.th, 0)
				tails[2]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, inf.th)
				tails[3]:SetPoint("BOTTOM", f, "BOTTOM")
				tails[4]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, inf.th)
				tails[5]:SetPoint("TOPLEFT", f, "TOPLEFT", inf.th, 0)
			elseif inf.startPoint == "BOTTOM" then
				inf.tail.Set1 = f.SetWidth
				inf.tail.Set2 = f.SetHeight
				tails[1]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inf.th, 0)
				tails[2]:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -inf.th)
				tails[3]:SetPoint("TOP", f, "TOP")
				tails[4]:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -inf.th)
				tails[5]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", inf.th, 0)
			elseif inf.startPoint == "LEFT" then
				inf.tail.Set1 = f.SetHeight
				inf.tail.Set2 = f.SetWidth
				tails[1]:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -inf.th)
				tails[2]:SetPoint("TOPRIGHT", f, "TOPRIGHT", -inf.th, 0)
				tails[3]:SetPoint("RIGHT", f, "RIGHT")
				tails[4]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inf.th, 0)
				tails[5]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, inf.th)
			else				
				inf.tail.Set1 = f.SetHeight
				inf.tail.Set2 = f.SetWidth
				tails[1]:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -inf.th)
				tails[2]:SetPoint("TOPLEFT", f, "TOPLEFT", inf.th, 0)
				tails[3]:SetPoint("LEFT", f, "LEFT")
				tails[4]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", inf.th, 0)
				tails[5]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, inf.th)
			end	
		else
			if inf.clockwise then
				if inf.startPoint == "TOP" then
					inf.tail.Set1 = f.SetWidth
					inf.tail.Set2 = f.SetHeight				
					tails[1]:SetPoint("TOPRIGHT", f, "TOPRIGHT", -inf.th, 0)
					tails[2]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, inf.th)
					tails[3]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", inf.th, 0)
					tails[4]:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -inf.th)
					tails[5]:SetPoint("TOPRIGHT", f, "TOP")
				elseif inf.startPoint == "BOTTOM" then
					inf.tail.Set1 = f.SetWidth
					inf.tail.Set2 = f.SetHeight				
					tails[1]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", inf.th, 0)
					tails[2]:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -inf.th)
					tails[3]:SetPoint("TOPRIGHT", f, "TOPRIGHT", -inf.th, 0)
					tails[4]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, inf.th)
					tails[5]:SetPoint("BOTTOMLEFT", f, "BOTTOM")
				elseif inf.startPoint == "LEFT" then
					inf.tail.Set1 = f.SetHeight
					inf.tail.Set2 = f.SetWidth				
					tails[1]:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -inf.th)
					tails[2]:SetPoint("TOPRIGHT", f, "TOPRIGHT", -inf.th, 0)
					tails[3]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, inf.th)
					tails[4]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", inf.th, 0)
					tails[5]:SetPoint("TOPLEFT", f, "LEFT")				
				else
					inf.tail.Set1 = f.SetHeight
					inf.tail.Set2 = f.SetWidth				
					tails[1]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, inf.th)
					tails[2]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", inf.th, 0)
					tails[3]:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -inf.th)
					tails[4]:SetPoint("TOPRIGHT", f, "TOPRIGHT", -inf.th, 0)
					tails[5]:SetPoint("BOTTOMRIGHT", f, "RIGHT")
				end
			else
				if inf.startPoint == "TOP" then
					inf.tail.Set1 = f.SetWidth
					inf.tail.Set2 = f.SetHeight				
					tails[1]:SetPoint("TOPLEFT", f, "TOPLEFT", inf.th, 0)
					tails[2]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, inf.th)
					tails[3]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inf.th, 0)
					tails[4]:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -inf.th)
					tails[5]:SetPoint("TOPLEFT", f, "TOP")
				elseif inf.startPoint == "BOTTOM" then
					inf.tail.Set1 = f.SetWidth
					inf.tail.Set2 = f.SetHeight				
					tails[1]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inf.th, 0)
					tails[2]:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -inf.th)
					tails[3]:SetPoint("TOPLEFT", f, "TOPLEFT", inf.th, 0)
					tails[4]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, inf.th)
					tails[5]:SetPoint("BOTTOMRIGHT", f, "BOTTOM")
				elseif inf.startPoint == "LEFT" then
					inf.tail.Set1 = f.SetHeight
					inf.tail.Set2 = f.SetWidth				
					tails[1]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, inf.th)
					tails[2]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inf.th, 0)
					tails[3]:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -inf.th)
					tails[4]:SetPoint("TOPLEFT", f, "TOPLEFT", inf.th, 0)
					tails[5]:SetPoint("BOTTOMLEFT", f, "LEFT")				
				else
					inf.tail.Set1 = f.SetHeight
					inf.tail.Set2 = f.SetWidth				
					tails[1]:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -inf.th)
					tails[2]:SetPoint("TOPLEFT", f, "TOPLEFT", inf.th, 0)
					tails[3]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, inf.th)
					tails[4]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inf.th, 0)
					tails[5]:SetPoint("TOPRIGHT", f, "RIGHT")
				end
			end
		
		end	
		inf.tail.Set2(tails[1], inf.th)
		inf.tail.Set1(tails[2], inf.th)
		inf.tail.Set2(tails[3], inf.th)
		inf.tail.Set1(tails[4], inf.th)
		inf.tail.Set2(tails[5], inf.th)
	end
	if inf.startPoint == "TOP" or inf.startPoint == "BOTTOM" then
		inf.tail.size1 = f:GetWidth()
		inf.tail.size2 = f:GetHeight()
	else
		inf.tail.size1 = f:GetHeight()
		inf.tail.size2 = f:GetWidth()
	end
	
	if inf.mirror then
		inf.tail.Set1(tails[1], inf.tail.size1/2 - inf.th)
		inf.tail.Set2(tails[2], inf.tail.size2 - inf.th)
		inf.tail.Set1(tails[3], inf.tail.size1)
		inf.tail.Set2(tails[4], inf.tail.size2 - inf.th)
		inf.tail.Set1(tails[5], inf.tail.size1/2 - inf.th)
	else
		inf.tail.Set1(tails[1], inf.tail.size1/2 - inf.th)
		inf.tail.Set2(tails[2], inf.tail.size2 - inf.th)
		inf.tail.Set1(tails[3], inf.tail.size1 - inf.th)
		inf.tail.Set2(tails[4], inf.tail.size2 - inf.th)
		inf.tail.Set1(tails[5], inf.tail.size1/2)
	end
end

local function BorderUpdate1LineCenter(f, progress)
	local inf = f.info
	local tails = inf.tail.list
	local oldProgress = inf.tail.old
	
	if inf.mirror then
		local cornerP = inf.tail.size1 / (inf.tail.size1 + inf.tail.size2) / 2
		if progress < cornerP then
			if oldProgress > cornerP or oldProgress <= 0 then
				for _, v in pairs(tails) do
					v:Show()
				end			
				BorderSet1LineCenter (f, true)
			end
			local stageProg = 1 - progress / cornerP
			inf.tail.Set1(tails[1], stageProg * (inf.tail.size1 / 2 - inf.th))
			inf.tail.Set1(tails[5], stageProg * (inf.tail.size1 / 2 - inf.th))
		elseif progress < 1 - cornerP then
			if oldProgress > 1 - cornerP or oldProgress <= cornerP then
				tails[1]:Hide()
				tails[2]:Show()
				tails[3]:Show()
				tails[4]:Show()
				tails[5]:Hide()
				BorderSet1LineCenter (f, true)
			end
			local stageProg = (1 - progress - cornerP) / (1 - cornerP * 2)
			inf.tail.Set2(tails[2], stageProg * (inf.tail.size2 - inf.th))
			inf.tail.Set2(tails[4], stageProg * (inf.tail.size2 - inf.th))
		else
			if oldProgress >= 1 or oldProgress <= 1 - cornerP then
				tails[1]:Hide()
				tails[2]:Hide()
				tails[3]:Show()
				tails[4]:Hide()
				tails[5]:Hide()
				BorderSet1LineCenter (f, true)
			end
			local stageProg = (1 - progress) / cornerP
			inf.tail.Set1(tails[3], stageProg * inf.tail.size1)
		end
	else
		local cornerP = inf.tail.size1 / (inf.tail.size1 + inf.tail.size2) / 4
		if progress < cornerP then
			if oldProgress > cornerP or oldProgress <= 0 then
				for _, v in pairs(tails) do
					v:Show()
				end			
				BorderSet1LineCenter (f, true)
			end
			local stageProg = 1 - progress / cornerP
			inf.tail.Set1(tails[1], stageProg * (inf.tail.size1 / 2 - inf.th))
		elseif progress < 0.5 - cornerP then
			if oldProgress > 0.5 - cornerP or oldProgress <= cornerP then
				tails[1]:Hide()
				tails[2]:Show()
				tails[3]:Show()
				tails[4]:Show()
				tails[5]:Show()
				BorderSet1LineCenter (f, true)
			end
			local stageProg = (0.5 - cornerP - progress) / (0.5 - cornerP * 2)
			inf.tail.Set2(tails[2], stageProg * (inf.tail.size2 - inf.th))
		elseif progress < 0.5 + cornerP then
			if oldProgress > 0.5 + cornerP or oldProgress <= 0.5 - cornerP then
				tails[1]:Hide()
				tails[2]:Hide()
				tails[3]:Show()
				tails[4]:Show()
				tails[5]:Show()
				BorderSet1LineCenter (f, true)
			end
			local stageProg = (0.5 + cornerP - progress) / cornerP / 2
			inf.tail.Set1(tails[3], stageProg * (inf.tail.size1 - inf.th))
		elseif progress < 1 - cornerP then
			if oldProgress > 1 - cornerP or oldProgress <= 0.5 + cornerP then
				tails[1]:Hide()
				tails[2]:Hide()
				tails[3]:Hide()
				tails[4]:Show()
				tails[5]:Show()
				BorderSet1LineCenter (f, true)
			end
			local stageProg = (1 - cornerP - progress) / (0.5 - cornerP * 2)
			inf.tail.Set2(tails[4], stageProg * (inf.tail.size2 - inf.th))
		else
			if oldProgress >= 1 or oldProgress <= (1 - cornerP) then
				tails[1]:Hide()
				tails[2]:Hide()
				tails[3]:Hide()
				tails[4]:Hide()
				tails[5]:Show()
				BorderSet1LineCenter (f, true)
			end
			local stageProg = (1 - progress) / cornerP
			inf.tail.Set1(tails[5], stageProg * (inf.tail.size1 / 2))
		end
	end	
	inf.tail.old = progress
end

local function BorderGradient1LineCenter(f, progress, elapsed)
	local inf = f.info
	local tails = inf.tail.list
	local c1, c2, c3, c4 = BorderGradientCorners(inf, elapsed)
	
	local cornerP = inf.tail.size1 / (inf.tail.size1 + inf.tail.size2) / 4
	if inf.mirror then
		local cornerP = inf.tail.size1 / (inf.tail.size1 + inf.tail.size2) / 2
		if progress < cornerP then
			local stageProg = progress / cornerP
			if inf.startPoint == "TOP" then
				local c12 = GetHSVTransition(0.5, c1, c2)
				local c1x = GetHSVTransition(stageProg, c12, c1)
				local c5x = GetHSVTransition(stageProg, c12, c2)
				
				SetGradA(tails[1], "HORIZONTAL", c1x, c1)
				SetGradA(tails[2], "VERTICAL", c4, c1)
				SetGradA(tails[3], "HORIZONTAL", c3, c4)
				SetGradA(tails[4], "VERTICAL", c3, c2)
				SetGradA(tails[5], "HORIZONTAL", c2, c5x)
				
			elseif inf.startPoint == "BOTTOM" then
				local c34 = GetHSVTransition(0.5, c3, c4)
				local c1x = GetHSVTransition(stageProg, c34, c4)
				local c5x = GetHSVTransition(stageProg, c34, c3)
				
				SetGradA(tails[1], "HORIZONTAL", c1x, c4)
				SetGradA(tails[2], "VERTICAL", c4, c1)
				SetGradA(tails[3], "HORIZONTAL", c2, c1)
				SetGradA(tails[4], "VERTICAL", c3, c2)
				SetGradA(tails[5], "HORIZONTAL", c3, c5x)
				
			elseif inf.startPoint == "LEFT" then
				local c23 = GetHSVTransition(0.5, c2, c3)
				local c1x = GetHSVTransition(stageProg, c23, c2)
				local c5x = GetHSVTransition(stageProg, c23, c3)
				
				SetGradA(tails[1], "VERTICAL", c1x, c2)
				SetGradA(tails[2], "HORIZONTAL", c2, c1)
				SetGradA(tails[3], "VERTICAL", c4, c1)
				SetGradA(tails[4], "HORIZONTAL", c3, c4)
				SetGradA(tails[5], "VERTICAL", c3, c5x)
				
			else
				local c41 = GetHSVTransition(0.5, c4, c1)
				local c1x = GetHSVTransition(stageProg, c41, c1)
				local c5x = GetHSVTransition(stageProg, c41, c4)
				
				SetGradA(tails[1], "VERTICAL", c1x, c1)
				SetGradA(tails[2], "HORIZONTAL", c2, c1)
				SetGradA(tails[3], "VERTICAL", c3, c2)
				SetGradA(tails[4], "HORIZONTAL", c3, c4)
				SetGradA(tails[5], "VERTICAL", c4, c5x)
			end
		elseif progress < (1 - cornerP) then
			local stageProg = (progress - cornerP)  / (1 - cornerP * 2)
			if inf.startPoint == "TOP" then
				local c2x = GetHSVTransition(stageProg, c1, c4)
				local c4x = GetHSVTransition(stageProg, c2, c3)
				
				SetGradA(tails[2], "VERTICAL", c4, c2x)
				SetGradA(tails[3], "HORIZONTAL", c3, c4)
				SetGradA(tails[4], "VERTICAL", c3, c4x)
			elseif inf.startPoint == "BOTTOM" then
				local c2x = GetHSVTransition(stageProg, c4, c1)
				local c4x = GetHSVTransition(stageProg, c3, c2)
				
				SetGradA(tails[2], "VERTICAL", c2x, c1)
				SetGradA(tails[3], "HORIZONTAL", c2, c1)
				SetGradA(tails[4], "VERTICAL", c4x, c2)
			elseif inf.startPoint == "LEFT" then
				local c2x = GetHSVTransition(stageProg, c2, c1)
				local c4x = GetHSVTransition(stageProg, c3, c4)
				
				SetGradA(tails[2], "HORIZONTAL", c2x, c1)
				SetGradA(tails[3], "VERTICAL", c4, c1)
				SetGradA(tails[4], "HORIZONTAL", c4x, c4)
			else
				local c2x = GetHSVTransition(stageProg, c1, c2)
				local c4x = GetHSVTransition(stageProg, c4, c3)
				
				SetGradA(tails[2], "HORIZONTAL", c2, c2x)
				SetGradA(tails[3], "VERTICAL", c3, c2)
				SetGradA(tails[4], "HORIZONTAL", c3, c4x)
			end
		else
			local stageProg = (progress - 1 + 0.5) / cornerP
			if inf.startPoint == "TOP" then
				local c34 = GetHSVTransition(0.5, c3, c4)
				local c3x1 = GetHSVTransition(stageProg, c3, c34)
				local c3x2 = GetHSVTransition(stageProg, c4, c34)
				
				SetGradA(tails[3], "HORIZONTAL", c3x1, c3x2)
			elseif inf.startPoint == "BOTTOM" then
				local c12 = GetHSVTransition(0.5, c1, c2)
				local c3x1 = GetHSVTransition(stageProg, c2, c12)
				local c3x2 = GetHSVTransition(stageProg, c1, c12)
				
				SetGradA(tails[3], "HORIZONTAL", c3x1, c3x2)
			elseif inf.startPoint == "LEFT" then
				local c41 = GetHSVTransition(0.5, c4, c1)
				local c3x1 = GetHSVTransition(stageProg, c4, c41)
				local c3x2 = GetHSVTransition(stageProg, c1, c41)
				
				SetGradA(tails[3], "VERTICAL", c3x1, c3x2)
			else
				local c23 = GetHSVTransition(0.5, c2, c3)
				local c3x1 = GetHSVTransition(stageProg, c3, c23)
				local c3x2 = GetHSVTransition(stageProg, c2, c23)
				
				SetGradA(tails[3], "VERTICAL", c3x1, c3x2)
			end
		end
	else
		if inf.clockwise then
			if progress < cornerP then
				local stageProg = progress / cornerP
				if inf.startPoint == "TOP" then
					local c12 = GetHSVTransition(0.5, c1, c2)
					local c1x = GetHSVTransition(stageProg, c12, c1)
					SetGradA(tails[1], "HORIZONTAL", c1x, c1)
					SetGradA(tails[2], "VERTICAL", c4, c1)
					SetGradA(tails[3], "HORIZONTAL", c3, c4)
					SetGradA(tails[4], "VERTICAL", c3, c2)
					SetGradA(tails[5], "HORIZONTAL", c2, c12)				
					
				elseif inf.startPoint == "BOTTOM" then
					local c34 = GetHSVTransition(0.5, c3, c4)
					local c1x = GetHSVTransition(stageProg, c34, c3)
					SetGradA(tails[1], "HORIZONTAL", c3, c1x)
					SetGradA(tails[2], "VERTICAL", c3, c2)
					SetGradA(tails[3], "HORIZONTAL", c2, c1)
					SetGradA(tails[4], "VERTICAL", c4, c1)
					SetGradA(tails[5], "HORIZONTAL", c34, c4)
					
				elseif inf.startPoint == "LEFT" then
					local c23 = GetHSVTransition(0.5, c2, c3)
					local c1x = GetHSVTransition(stageProg, c23, c2)
					SetGradA(tails[1], "VERTICAL", c1x, c2)
					SetGradA(tails[2], "HORIZONTAL", c2, c1)
					SetGradA(tails[3], "VERTICAL", c4, c1)
					SetGradA(tails[4], "HORIZONTAL", c3, c4)
					SetGradA(tails[5], "VERTICAL", c3, c23)
				
				else
					local c41 = GetHSVTransition(0.5, c4, c1)
					local c1x = GetHSVTransition(stageProg, c41, c4)
					SetGradA(tails[1], "VERTICAL", c4, c1x)
					SetGradA(tails[2], "HORIZONTAL", c3, c4)
					SetGradA(tails[3], "VERTICAL", c3, c2)
					SetGradA(tails[4], "HORIZONTAL", c2, c1)
					SetGradA(tails[5], "VERTICAL", c41, c1)	
				end
			elseif progress < 0.5 - cornerP then
				local stageProg = (progress - cornerP) / (0.5 - cornerP * 2)
				if inf.startPoint == "TOP" then
					local c12 = GetHSVTransition(0.5, c1, c2)
					local c2x = GetHSVTransition(stageProg, c1, c4)
					SetGradA(tails[2], "VERTICAL", c4, c2x)
					SetGradA(tails[3], "HORIZONTAL", c3, c4)
					SetGradA(tails[4], "VERTICAL", c3, c2)
					SetGradA(tails[5], "HORIZONTAL", c2, c12)				
					
				elseif inf.startPoint == "BOTTOM" then
					local c34 = GetHSVTransition(0.5, c3, c4)
					local c2x = GetHSVTransition(stageProg, c3, c2)
					SetGradA(tails[2], "VERTICAL", c2x, c2)
					SetGradA(tails[3], "HORIZONTAL", c2, c1)
					SetGradA(tails[4], "VERTICAL", c4, c1)
					SetGradA(tails[5], "HORIZONTAL", c34, c4)
					
				elseif inf.startPoint == "LEFT" then
					local c23 = GetHSVTransition(0.5, c2, c3)
					local c2x = GetHSVTransition(stageProg, c2, c1)
					SetGradA(tails[2], "HORIZONTAL", c2x, c1)
					SetGradA(tails[3], "VERTICAL", c4, c1)
					SetGradA(tails[4], "HORIZONTAL", c3, c4)
					SetGradA(tails[5], "VERTICAL", c3, c23)
				
				else
					local c41 = GetHSVTransition(0.5, c4, c1)
					local c2x = GetHSVTransition(stageProg, c4, c3)
					SetGradA(tails[2], "HORIZONTAL", c3, c2x)
					SetGradA(tails[3], "VERTICAL", c3, c2)
					SetGradA(tails[4], "HORIZONTAL", c2, c1)
					SetGradA(tails[5], "VERTICAL", c41, c1)	
				end
			elseif progress < 0.5 + cornerP then
				local stageProg = (progress - 0.5 + cornerP) / cornerP / 2
				if inf.startPoint == "TOP" then
					local c12 = GetHSVTransition(0.5, c1, c2)
					local c3x = GetHSVTransition(stageProg, c4, c3)
					SetGradA(tails[3], "HORIZONTAL", c3, c3x)
					SetGradA(tails[4], "VERTICAL", c3, c2)
					SetGradA(tails[5], "HORIZONTAL", c2, c12)				
					
				elseif inf.startPoint == "BOTTOM" then
					local c34 = GetHSVTransition(0.5, c3, c4)
					local c3x = GetHSVTransition(stageProg, c2, c1)
					SetGradA(tails[3], "HORIZONTAL", c3x, c1)
					SetGradA(tails[4], "VERTICAL", c4, c1)
					SetGradA(tails[5], "HORIZONTAL", c34, c4)
					
				elseif inf.startPoint == "LEFT" then
					local c23 = GetHSVTransition(0.5, c2, c3)
					local c3x = GetHSVTransition(stageProg, c1, c4)
					SetGradA(tails[3], "VERTICAL", c4, c3x)
					SetGradA(tails[4], "HORIZONTAL", c3, c4)
					SetGradA(tails[5], "VERTICAL", c3, c23)
				
				else
					local c41 = GetHSVTransition(0.5, c4, c1)
					local c3x = GetHSVTransition(stageProg, c3, c2)
					SetGradA(tails[3], "VERTICAL", c3x, c2)
					SetGradA(tails[4], "HORIZONTAL", c2, c1)
					SetGradA(tails[5], "VERTICAL", c41, c1)	
				end
			elseif progress < 1 - cornerP then
				local stageProg = (progress - 0.5 - cornerP) / (0.5 - cornerP * 2)
				if inf.startPoint == "TOP" then
					local c12 = GetHSVTransition(0.5, c1, c2)
					local c4x = GetHSVTransition(stageProg, c3, c2)
					SetGradA(tails[4], "VERTICAL", c4x, c2)
					SetGradA(tails[5], "HORIZONTAL", c2, c12)				
					
				elseif inf.startPoint == "BOTTOM" then
					local c34 = GetHSVTransition(0.5, c3, c4)
					local c4x = GetHSVTransition(stageProg, c1, c4)
					SetGradA(tails[4], "VERTICAL", c4, c4x)
					SetGradA(tails[5], "HORIZONTAL", c34, c4)
					
				elseif inf.startPoint == "LEFT" then
					local c23 = GetHSVTransition(0.5, c2, c3)
					local c4x = GetHSVTransition(stageProg, c4, c3)
					SetGradA(tails[4], "HORIZONTAL", c3, c4x)
					SetGradA(tails[5], "VERTICAL", c3, c23)
				
				else
					local c41 = GetHSVTransition(0.5, c4, c1)
					local c4x = GetHSVTransition(stageProg, c2, c1)
					SetGradA(tails[4], "HORIZONTAL", c4x, c1)
					SetGradA(tails[5], "VERTICAL", c41, c1)	
				end
			else
				local stageProg = (progress - 1 + cornerP) / cornerP
				if inf.startPoint == "TOP" then
					local c12 = GetHSVTransition(0.5, c1, c2)
					local c5x = GetHSVTransition(stageProg, c2, c12)
					SetGradA(tails[5], "HORIZONTAL", c5x, c12)				
					
				elseif inf.startPoint == "BOTTOM" then
					local c34 = GetHSVTransition(0.5, c3, c4)
					local c5x = GetHSVTransition(stageProg, c4, c34)
					SetGradA(tails[5], "HORIZONTAL", c34, c5x)
					
				elseif inf.startPoint == "LEFT" then
					local c23 = GetHSVTransition(0.5, c2, c3)
					local c5x = GetHSVTransition(stageProg, c3, c23)
					SetGradA(tails[5], "VERTICAL", c5x, c23)
				
				else
					local c41 = GetHSVTransition(0.5, c4, c1)
					local c5x = GetHSVTransition(stageProg, c1, c41)
					SetGradA(tails[5], "VERTICAL", c41, c5x)
				end
			end
		else
			if progress < cornerP then
				local stageProg = progress / cornerP
				if inf.startPoint == "TOP" then
					local c12 = GetHSVTransition(0.5, c1, c2)
					local c1x = GetHSVTransition(stageProg, c2, c12)
					SetGradA(tails[1], "HORIZONTAL", c2, c1x)
					SetGradA(tails[2], "VERTICAL", c3, c2)
					SetGradA(tails[3], "HORIZONTAL", c3, c4)
					SetGradA(tails[4], "VERTICAL", c4, c1)
					SetGradA(tails[5], "HORIZONTAL", c12, c1)				
					
				elseif inf.startPoint == "BOTTOM" then
					local c34 = GetHSVTransition(0.5, c3, c4)
					local c1x = GetHSVTransition(stageProg, c34, c4)
					SetGradA(tails[1], "HORIZONTAL", c1x, c4)
					SetGradA(tails[2], "VERTICAL", c4, c1)
					SetGradA(tails[3], "HORIZONTAL", c2, c1)
					SetGradA(tails[4], "VERTICAL", c3, c2)
					SetGradA(tails[5], "HORIZONTAL", c3, c34)
					
				elseif inf.startPoint == "LEFT" then
					local c23 = GetHSVTransition(0.5, c2, c3)
					local c1x = GetHSVTransition(stageProg, c3, c23)
					SetGradA(tails[1], "VERTICAL", c3, c1x)
					SetGradA(tails[2], "HORIZONTAL", c3, c4)
					SetGradA(tails[3], "VERTICAL", c4, c1)
					SetGradA(tails[4], "HORIZONTAL", c2, c1)
					SetGradA(tails[5], "VERTICAL", c23, c2)
				
				else
					local c41 = GetHSVTransition(0.5, c4, c1)
					local c1x = GetHSVTransition(stageProg, c41, c1)
					SetGradA(tails[1], "VERTICAL", c1x, c1)
					SetGradA(tails[2], "HORIZONTAL", c2, c1)
					SetGradA(tails[3], "VERTICAL", c3, c2)
					SetGradA(tails[4], "HORIZONTAL", c3, c4)
					SetGradA(tails[5], "VERTICAL", c4, c41)	
				end
			elseif progress < 0.5 - cornerP then
				local stageProg = (progress - cornerP) / (0.5 - cornerP * 2)
				if inf.startPoint == "TOP" then
					local c12 = GetHSVTransition(0.5, c1, c2)
					local c2x = GetHSVTransition(stageProg, c2, c3)
					SetGradA(tails[2], "VERTICAL", c3, c2x)
					SetGradA(tails[3], "HORIZONTAL", c3, c4)
					SetGradA(tails[4], "VERTICAL", c4, c1)
					SetGradA(tails[5], "HORIZONTAL", c12, c1)				
					
				elseif inf.startPoint == "BOTTOM" then
					local c34 = GetHSVTransition(0.5, c3, c4)
					local c2x = GetHSVTransition(stageProg, c4, c1)
					SetGradA(tails[2], "VERTICAL", c2x, c1)
					SetGradA(tails[3], "HORIZONTAL", c2, c1)
					SetGradA(tails[4], "VERTICAL", c3, c2)
					SetGradA(tails[5], "HORIZONTAL", c3, c34)
					
				elseif inf.startPoint == "LEFT" then
					local c23 = GetHSVTransition(0.5, c2, c3)
					local c2x = GetHSVTransition(stageProg, c3, c4)
					SetGradA(tails[2], "HORIZONTAL", c2x, c4)
					SetGradA(tails[3], "VERTICAL", c4, c1)
					SetGradA(tails[4], "HORIZONTAL", c2, c1)
					SetGradA(tails[5], "VERTICAL", c23, c2)
				
				else
					local c41 = GetHSVTransition(0.5, c4, c1)
					local c2x = GetHSVTransition(stageProg, c1, c2)
					SetGradA(tails[2], "HORIZONTAL", c2, c2x)
					SetGradA(tails[3], "VERTICAL", c3, c2)
					SetGradA(tails[4], "HORIZONTAL", c3, c4)
					SetGradA(tails[5], "VERTICAL", c4, c41)	
				end
			elseif progress < 0.5 + cornerP then
				local stageProg = (progress - 0.5 + cornerP) / cornerP / 2
				if inf.startPoint == "TOP" then
					local c12 = GetHSVTransition(0.5, c1, c2)
					local c3x = GetHSVTransition(stageProg, c3, c4)
					SetGradA(tails[3], "HORIZONTAL", c3x, c4)
					SetGradA(tails[4], "VERTICAL", c4, c1)
					SetGradA(tails[5], "HORIZONTAL", c12, c1)				
					
				elseif inf.startPoint == "BOTTOM" then
					local c34 = GetHSVTransition(0.5, c3, c4)
					local c3x = GetHSVTransition(stageProg, c1, c2)
					SetGradA(tails[3], "HORIZONTAL", c2, c3x)
					SetGradA(tails[4], "VERTICAL", c3, c2)
					SetGradA(tails[5], "HORIZONTAL", c3, c34)
					
				elseif inf.startPoint == "LEFT" then
					local c23 = GetHSVTransition(0.5, c2, c3)
					local c3x = GetHSVTransition(stageProg, c4, c1)
					SetGradA(tails[3], "VERTICAL", c3x, c1)
					SetGradA(tails[4], "HORIZONTAL", c2, c1)
					SetGradA(tails[5], "VERTICAL", c23, c2)
				
				else
					local c41 = GetHSVTransition(0.5, c4, c1)
					local c3x = GetHSVTransition(stageProg, c2, c3)
					SetGradA(tails[3], "VERTICAL", c3, c3x)
					SetGradA(tails[4], "HORIZONTAL", c3, c4)
					SetGradA(tails[5], "VERTICAL", c4, c41)	
				end
			elseif progress < 1 - cornerP then
				local stageProg = (progress - 0.5 - cornerP) / (0.5 - cornerP * 2)
				if inf.startPoint == "TOP" then
					local c12 = GetHSVTransition(0.5, c1, c2)
					local c4x = GetHSVTransition(stageProg, c4, c1)
					SetGradA(tails[4], "VERTICAL", c4x, c1)
					SetGradA(tails[5], "HORIZONTAL", c12, c1)				
					
				elseif inf.startPoint == "BOTTOM" then
					local c34 = GetHSVTransition(0.5, c3, c4)
					local c4x = GetHSVTransition(stageProg, c2, c3)
					SetGradA(tails[4], "VERTICAL", c3, c4x)
					SetGradA(tails[5], "HORIZONTAL", c3, c34)
					
				elseif inf.startPoint == "LEFT" then
					local c23 = GetHSVTransition(0.5, c2, c3)
					local c4x = GetHSVTransition(stageProg, c1, c2)
					SetGradA(tails[4], "HORIZONTAL", c2, c4x)
					SetGradA(tails[5], "VERTICAL", c23, c2)
				
				else
					local c41 = GetHSVTransition(0.5, c4, c1)
					local c4x = GetHSVTransition(stageProg, c3, c4)
					SetGradA(tails[4], "HORIZONTAL", c4x, c4)
					SetGradA(tails[5], "VERTICAL", c4, c41)	
				end
			else
				local stageProg = (progress - 1 + cornerP) / cornerP
				if inf.startPoint == "TOP" then
					local c12 = GetHSVTransition(0.5, c1, c2)
					local c5x = GetHSVTransition(stageProg, c1, c12)
					SetGradA(tails[5], "HORIZONTAL", c12, c5x)				
					
				elseif inf.startPoint == "BOTTOM" then
					local c34 = GetHSVTransition(0.5, c3, c4)
					local c5x = GetHSVTransition(stageProg, c3, c34)
					SetGradA(tails[5], "HORIZONTAL", c5x, c34)
					
				elseif inf.startPoint == "LEFT" then
					local c23 = GetHSVTransition(0.5, c2, c3)
					local c5x = GetHSVTransition(stageProg, c2, c23)
					SetGradA(tails[5], "VERTICAL", c23, c5x)
				
				else
					local c41 = GetHSVTransition(0.5, c4, c1)
					local c5x = GetHSVTransition(stageProg, c4, c41)
					SetGradA(tails[5], "VERTICAL", c5x, c41)	
				end
			end
		end
	end
end

local function BorderSet1LineCorner(f, update)
	local inf = f.info
	local tails = inf.tail.list
	if not(update) then
		for _, v in pairs(tails) do
			v:ClearAllPoints()
		end
		if inf.mirror then
			if inf.startPoint == "TOPLEFT" then			
				tails[1]:SetPoint("TOPRIGHT", f, "TOPRIGHT", -inf.th, 0)
				tails[2]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, inf.th)
				tails[3]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, inf.th)
				tails[4]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT")
			elseif inf.startPoint == "TOPRIGHT" then				
				tails[1]:SetPoint("TOPLEFT", f, "TOPLEFT", inf.th, 0)
				tails[2]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, inf.th)
				tails[3]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, inf.th)
				tails[4]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT")
			elseif inf.startPoint == "BOTTOMRIGHT" then			
				tails[1]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", inf.th, 0)
				tails[2]:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -inf.th)
				tails[3]:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -inf.th)
				tails[4]:SetPoint("TOPLEFT", f, "TOPLEFT")				
			else			
				tails[1]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inf.th, 0)
				tails[2]:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -inf.th)
				tails[3]:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -inf.th)
				tails[4]:SetPoint("TOPRIGHT", f, "TOPRIGHT")
			end
			tails[1]:SetHeight(inf.th)
			tails[2]:SetWidth(inf.th)
			tails[3]:SetWidth(inf.th)
			tails[4]:SetHeight(inf.th)
		else
			if inf.clockwise then
				if inf.startPoint == "TOPRIGHT" then
					inf.tail.Set1 = f.SetHeight
					inf.tail.Set2 = f.SetWidth				
					tails[1]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, inf.th)
					tails[2]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", inf.th, 0)
					tails[3]:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -inf.th)
					tails[4]:SetPoint("TOPRIGHT", f, "TOPRIGHT")
				elseif inf.startPoint == "BOTTOMLEFT" then
					inf.tail.Set1 = f.SetHeight
					inf.tail.Set2 = f.SetWidth				
					tails[1]:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -inf.th)
					tails[2]:SetPoint("TOPRIGHT", f, "TOPRIGHT", -inf.th, 0)
					tails[3]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, inf.th)
					tails[4]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT")
				elseif inf.startPoint == "TOPLEFT" then
					inf.tail.Set1 = f.SetWidth
					inf.tail.Set2 = f.SetHeight						
					tails[1]:SetPoint("TOPRIGHT", f, "TOPRIGHT", -inf.th, 0)
					tails[2]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, inf.th)
					tails[3]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", inf.th, 0)
					tails[4]:SetPoint("TOPLEFT", f, "TOPLEFT")		
				else
					inf.tail.Set1 = f.SetWidth
					inf.tail.Set2 = f.SetHeight				
					tails[1]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", inf.th, 0)
					tails[2]:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -inf.th)
					tails[3]:SetPoint("TOPRIGHT", f, "TOPRIGHT", -inf.th, 0 )
					tails[4]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT")
				end
			else
				if inf.startPoint == "TOPRIGHT" then
					inf.tail.Set1 = f.SetWidth
					inf.tail.Set2 = f.SetHeight	
					tails[1]:SetPoint("TOPLEFT", f, "TOPLEFT", inf.th, 0)
					tails[2]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, inf.th)
					tails[3]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inf.th, 0)
					tails[4]:SetPoint("TOPRIGHT", f, "TOPRIGHT")
				elseif inf.startPoint == "BOTTOMLEFT" then
					inf.tail.Set1 = f.SetWidth
					inf.tail.Set2 = f.SetHeight				
					tails[1]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inf.th, 0)
					tails[2]:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -inf.th)
					tails[3]:SetPoint("TOPLEFT", f, "TOPLEFT", inf.th, 0)
					tails[4]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT")
				elseif inf.startPoint == "TOPLEFT" then
					inf.tail.Set1 = f.SetHeight
					inf.tail.Set2 = f.SetWidth				
					tails[1]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, inf.th)
					tails[2]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inf.th, 0)
					tails[3]:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -inf.th)
					tails[4]:SetPoint("TOPLEFT", f, "TOPLEFT")		
				else
					inf.tail.Set1 = f.SetHeight
					inf.tail.Set2 = f.SetWidth
					tails[1]:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -inf.th)
					tails[2]:SetPoint("TOPLEFT", f, "TOPLEFT", inf.th, 0)
					tails[3]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, inf.th)
					tails[4]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT")		
				end
			end
			
			inf.tail.Set2(tails[1], inf.th)
			inf.tail.Set1(tails[2], inf.th)
			inf.tail.Set2(tails[3], inf.th)
			inf.tail.Set1(tails[4], inf.th)
		end
	end
	
	if inf.mirror then
		tails[1]:SetWidth(f:GetWidth() - inf.th)
		tails[2]:SetHeight(f:GetHeight() - inf.th)
		tails[3]:SetHeight(f:GetHeight() - 2*inf.th)
		tails[4]:SetWidth(f:GetWidth())
	else
		if inf.clockwise and (inf.startPoint == "TOPLEFT" or inf.startPoint == "BOTTOMRIGHT") 
			or not(inf.clockwise) and (inf.startPoint == "TOPRIGHT" or inf.startPoint == "BOTTOMLEFT")then
			inf.tail.size1 = f:GetWidth()
			inf.tail.size2 = f:GetHeight()
		else
			inf.tail.size1 = f:GetHeight()
			inf.tail.size2 = f:GetWidth()
		end
		inf.tail.Set1(tails[1], inf.tail.size1 - 2*inf.th)
		inf.tail.Set2(tails[2], inf.tail.size2 - inf.th)
		inf.tail.Set1(tails[3], inf.tail.size1 - inf.th)
		inf.tail.Set2(tails[4], inf.tail.size2)
	end
end

local function BorderUpdate1LineCorner(f, progress)
	local inf = f.info
	local tails = inf.tail.list
	local oldProgress = inf.tail.old
	
	if inf.mirror then
		local cornerP = inf.width / (inf.width + inf.height)
		local updt
		if progress < cornerP then
			if oldProgress > cornerP or oldProgress <= 0 then
				tails[1]:Show()
				tails[2]:Show()				
				updt = true
			else
				local stageProg = 1 - progress / cornerP
				tails[1]:SetWidth(stageProg * (inf.width - inf.th))
			end
		else
			if oldProgress >= 1 or oldProgress < cornerP then
				tails[1]:Hide()
				tails[2]:Show()
				updt = true
			else
				local stageProg = (1 - progress) / (1 - cornerP)
				tails[2]:SetHeight(stageProg * (inf.height - inf.th))
			end
		end
		
		if progress < (1 - cornerP) then
			if oldProgress > (1 - cornerP) or oldProgress <= 0 then
				tails[3]:Show()
				tails[4]:Show()				
				updt = true
			else
				local stageProg = 1 - progress / (1 - cornerP)
				tails[3]:SetHeight(stageProg * (inf.height - 2*inf.th))
			end
		else
			if oldProgress >= 1 or oldProgress < (1 - cornerP) then
				tails[3]:Hide()
				tails[4]:Show()
				updt = true
			else
				local stageProg = (1 - progress) / cornerP
				tails[4]:SetWidth(stageProg * (inf.width))
			end
		end
		
		if updt then
				BorderSet1LineCorner(f, true)
				if progress < cornerP then
					local stageProg = 1 - progress / cornerP
					tails[1]:SetWidth(stageProg * (inf.width - inf.th))
				else
					local stageProg = (1 - progress) / (1 - cornerP)
					tails[2]:SetHeight(stageProg * (inf.height - inf.th))
				end
				if progress < (1 - cornerP) then
					local stageProg = 1 - progress / (1 - cornerP)
					tails[3]:SetHeight(stageProg * (inf.height - 2*inf.th))
				else
					local stageProg = (1 - progress) / cornerP
					tails[4]:SetWidth(stageProg * (inf.width))
				end
		end			
	else
		local cornerP = inf.tail.size1 / (inf.tail.size1 + inf.tail.size2) / 2
		if progress < cornerP then
			if oldProgress > cornerP or oldProgress <= 0 then
				for _, v in pairs(tails) do
					v:Show()
				end			
				BorderSet1LineCorner (f, true)
			end
			local stageProg = 1 - progress / cornerP
			inf.tail.Set1(tails[1], stageProg * (inf.tail.size1 - 2*inf.th))
		elseif progress < 0.5 then
			if oldProgress > 0.5 or oldProgress <= cornerP then
				tails[1]:Hide()
				tails[2]:Show()
				tails[3]:Show()
				tails[4]:Show()
				BorderSet1LineCorner (f, true)
			end
			local stageProg = (0.5 - progress) / (0.5 - cornerP)
			inf.tail.Set2(tails[2], stageProg * (inf.tail.size2 - inf.th))
		elseif progress < (0.5 + cornerP) then
			if oldProgress > (0.5 + cornerP) or oldProgress <= 0.5 then
				tails[1]:Hide()
				tails[2]:Hide()
				tails[3]:Show()
				tails[4]:Show()
				BorderSet1LineCorner (f, true)
			end
			local stageProg = (0.5 + cornerP - progress) / cornerP
			inf.tail.Set1(tails[3], stageProg * (inf.tail.size1 - inf.th))
		else
			if oldProgress >= 1 or oldProgress <= (1 - cornerP) then
				tails[1]:Hide()
				tails[2]:Hide()
				tails[3]:Hide()
				tails[4]:Show()
				BorderSet1LineCorner (f, true)
			end
			local stageProg = (1 - progress ) / (0.5 - cornerP)
			inf.tail.Set2(tails[4], stageProg * inf.tail.size2)
		end
	end
	inf.tail.old = progress
end

local function BorderGradient1LineCorner(f, progress, elapsed)
	local inf = f.info
	local tails = inf.tail.list
	local c1, c2, c3, c4 = BorderGradientCorners(inf, elapsed)
	
	if inf.mirror then
		local cornerP = inf.width/(inf.width + inf.height)
		if progress < cornerP then
			local stageProg = progress / cornerP
			if inf.startPoint == "TOPLEFT" then
				local c1x = GetHSVTransition(stageProg, c2, c1)
				
				SetGradA(tails[1], "HORIZONTAL", c1x, c1)
				SetGradA(tails[2], "VERTICAL", c4, c1)
				
			elseif inf.startPoint == "TOPRIGHT" then
				local c1x = GetHSVTransition(stageProg, c1, c2)
				
				SetGradA(tails[1], "HORIZONTAL", c2, c1x)
				SetGradA(tails[2], "VERTICAL", c3, c2)
				
			elseif inf.startPoint == "BOTTOMRIGHT" then
				local c1x = GetHSVTransition(stageProg, c4, c3)
				
				SetGradA(tails[1], "HORIZONTAL", c3, c1x)
				SetGradA(tails[2], "VERTICAL", c3, c2)
				
			else
				local c1x = GetHSVTransition(stageProg, c3, c4)
				
				SetGradA(tails[1], "HORIZONTAL", c1x, c4)
				SetGradA(tails[2], "VERTICAL", c4, c1)
			end
		else
			local stageProg = (progress - cornerP)  / (1 - cornerP)
			if inf.startPoint == "TOPLEFT" then
				local c2x = GetHSVTransition(stageProg, c1, c4)

				SetGradA(tails[2], "VERTICAL", c4, c2x)
				
			elseif inf.startPoint == "TOPRIGHT" then
				local c2x = GetHSVTransition(stageProg, c2, c3)
				
				SetGradA(tails[2], "VERTICAL", c3, c2x)
				
			elseif inf.startPoint == "BOTTOMRIGHT" then
				local c2x = GetHSVTransition(stageProg, c3, c2)
				
				SetGradA(tails[2], "VERTICAL", c2x, c2)
				
			else
				local c2x = GetHSVTransition(stageProg, c4, c1)
				
				SetGradA(tails[2], "VERTICAL", c2x, c1)
			end
		end
		if progress < (1 - cornerP) then
			local stageProg = progress / (1 - cornerP)
			if inf.startPoint == "TOPLEFT" then
				local c3x = GetHSVTransition(stageProg, c2, c3)
				
				SetGradA(tails[3], "VERTICAL", c3, c3x)
				SetGradA(tails[4], "HORIZONTAL", c3, c4)
				
			elseif inf.startPoint == "TOPRIGHT" then
				local c3x = GetHSVTransition(stageProg, c1, c4)
				
				SetGradA(tails[3], "VERTICAL", c4, c3x)
				SetGradA(tails[4], "HORIZONTAL", c3, c4)
				
			elseif inf.startPoint == "BOTTOMRIGHT" then
				local c3x = GetHSVTransition(stageProg, c4, c1)
				
				SetGradA(tails[3], "VERTICAL", c3x, c1)
				SetGradA(tails[4], "HORIZONTAL", c2, c1)
				
			else
				local c3x = GetHSVTransition(stageProg, c3, c2)
				
				SetGradA(tails[3], "VERTICAL", c3x, c2)
				SetGradA(tails[4], "HORIZONTAL", c2, c1)
			end
		else
			local stageProg = (progress + cornerP - 1)  / cornerP
			if inf.startPoint == "TOPLEFT" then
				local c4x = GetHSVTransition(stageProg, c3, c4)

				SetGradA(tails[4], "HORIZONTAL", c4x, c4)
				
			elseif inf.startPoint == "TOPRIGHT" then
				local c4x = GetHSVTransition(stageProg, c4, c3)
				
				SetGradA(tails[4], "HORIZONTAL", c3, c4x)
				
			elseif inf.startPoint == "BOTTOMRIGHT" then
				local c4x = GetHSVTransition(stageProg, c1, c2)
				
				SetGradA(tails[4], "HORIZONTAL", c2, c4x)
				
			else
				local c4x = GetHSVTransition(stageProg, c2, c1)
				
				SetGradA(tails[4], "HORIZONTAL", c4x, c1)
			end
		end
	else
		local cornerP = inf.tail.size1 / (inf.tail.size1 + inf.tail.size2) / 2
		if inf.clockwise then
			if progress < cornerP then
				local stageProg = progress / cornerP
				if inf.startPoint == "TOPRIGHT" then
					local c1x = GetHSVTransition(stageProg, c1, c4)
					SetGradA(tails[1], "VERTICAL", c4, c1x)
					SetGradA(tails[2], "HORIZONTAL", c3, c4)
					SetGradA(tails[3], "VERTICAL", c3, c2)
					SetGradA(tails[4], "HORIZONTAL", c2, c1)
				elseif inf.startPoint == "BOTTOMLEFT" then
					local c1x = GetHSVTransition(stageProg, c3, c2)
					SetGradA(tails[1], "VERTICAL", c1x, c2)
					SetGradA(tails[2], "HORIZONTAL", c2, c1)
					SetGradA(tails[3], "VERTICAL", c4, c1)
					SetGradA(tails[4], "HORIZONTAL", c3, c4)
				elseif inf.startPoint == "TOPLEFT" then
					local c1x = GetHSVTransition(stageProg, c2, c1)
					SetGradA(tails[1], "HORIZONTAL", c1x, c1)
					SetGradA(tails[2], "VERTICAL", c4, c1)
					SetGradA(tails[3], "HORIZONTAL", c3, c4)
					SetGradA(tails[4], "VERTICAL", c3, c2)
				else
					local c1x = GetHSVTransition(stageProg, c4, c3)
					SetGradA(tails[1], "HORIZONTAL", c3, c1x)
					SetGradA(tails[2], "VERTICAL", c3, c2)
					SetGradA(tails[3], "HORIZONTAL", c2, c1)
					SetGradA(tails[4], "VERTICAL", c4, c1)
				end
			elseif progress < 0.5 then
				local stageProg = (progress - cornerP) / (0.5 - cornerP)
				if inf.startPoint == "TOPRIGHT" then
					local c2x = GetHSVTransition(stageProg, c4, c3)
					SetGradA(tails[2], "HORIZONTAL", c3, c2x)
					SetGradA(tails[3], "VERTICAL", c3, c2)
					SetGradA(tails[4], "HORIZONTAL", c2, c1)
				elseif inf.startPoint == "BOTTOMLEFT" then
					local c2x = GetHSVTransition(stageProg, c2, c1)
					SetGradA(tails[2], "HORIZONTAL", c2x, c1)
					SetGradA(tails[3], "VERTICAL", c4, c1)
					SetGradA(tails[4], "HORIZONTAL", c3, c4)
				elseif inf.startPoint == "TOPLEFT" then
					local c2x = GetHSVTransition(stageProg, c1, c4)
					SetGradA(tails[2], "VERTICAL", c4, c2x)
					SetGradA(tails[3], "HORIZONTAL", c3, c4)
					SetGradA(tails[4], "VERTICAL", c3, c2)
				else
					local c2x = GetHSVTransition(stageProg, c3, c2)
					SetGradA(tails[2], "VERTICAL", c2x, c2)
					SetGradA(tails[3], "HORIZONTAL", c2, c1)
					SetGradA(tails[4], "VERTICAL", c4, c1)
				end
			elseif progress < 0.5 + cornerP then
				local stageProg = (progress - 0.5) / cornerP
				if inf.startPoint == "TOPRIGHT" then
					local c3x = GetHSVTransition(stageProg, c3, c2)
					SetGradA(tails[3], "VERTICAL", c3x, c2)
					SetGradA(tails[4], "HORIZONTAL", c2, c1)
				elseif inf.startPoint == "BOTTOMLEFT" then
					local c3x = GetHSVTransition(stageProg, c1, c4)
					SetGradA(tails[3], "VERTICAL", c4, c3x)
					SetGradA(tails[4], "HORIZONTAL", c3, c4)
				elseif inf.startPoint == "TOPLEFT" then
					local c3x = GetHSVTransition(stageProg, c4, c3)
					SetGradA(tails[3], "HORIZONTAL", c3, c3x)
					SetGradA(tails[4], "VERTICAL", c3, c2)
				else
					local c3x = GetHSVTransition(stageProg, c2, c1)
					SetGradA(tails[3], "HORIZONTAL", c3x, c1)
					SetGradA(tails[4], "VERTICAL", c4, c1)
				end
			else
				local stageProg = (progress - 0.5 - cornerP) / (0.5 - cornerP)
				if inf.startPoint == "TOPRIGHT" then
					local c4x = GetHSVTransition(stageProg, c2, c3)
					SetGradA(tails[4], "HORIZONTAL", c4x, c1)
				elseif inf.startPoint == "BOTTOMLEFT" then
					local c4x = GetHSVTransition(stageProg, c4, c3)
					SetGradA(tails[4], "HORIZONTAL", c3, c4x)
				elseif inf.startPoint == "TOPLEFT" then
					local c4x = GetHSVTransition(stageProg, c3, c2)
					SetGradA(tails[4], "VERTICAL", c4x, c2)
				else
					local c4x = GetHSVTransition(stageProg, c1, c4)
					SetGradA(tails[4], "VERTICAL", c4, c4x)
				end
			end
		else
			if progress < cornerP then
				local stageProg = progress / cornerP
				if inf.startPoint == "TOPRIGHT" then
					local c1x = GetHSVTransition(stageProg, c1, c2)
					SetGradA(tails[1], "HORIZONTAL", c2, c1x)
					SetGradA(tails[2], "VERTICAL", c3, c2)
					SetGradA(tails[3], "HORIZONTAL", c3, c4)
					SetGradA(tails[4], "VERTICAL", c4, c1)
				elseif inf.startPoint == "BOTTOMLEFT" then
					local c1x = GetHSVTransition(stageProg, c3, c4)
					SetGradA(tails[1], "HORIZONTAL", c1x, c4)
					SetGradA(tails[2], "VERTICAL", c4, c1)
					SetGradA(tails[3], "HORIZONTAL", c2, c1)
					SetGradA(tails[4], "VERTICAL", c3, c2)
				elseif inf.startPoint == "TOPLEFT" then
					local c1x = GetHSVTransition(stageProg, c2, c3)
					SetGradA(tails[1], "VERTICAL", c3, c1x)
					SetGradA(tails[2], "HORIZONTAL", c3, c4)
					SetGradA(tails[3], "VERTICAL", c4, c1)
					SetGradA(tails[4], "HORIZONTAL", c2, c1)
				else
					local c1x = GetHSVTransition(stageProg, c4, c1)
					SetGradA(tails[1], "VERTICAL", c1x, c1)
					SetGradA(tails[2], "HORIZONTAL", c2, c1)
					SetGradA(tails[3], "VERTICAL", c3, c2)
					SetGradA(tails[4], "HORIZONTAL", c3, c4)
				end
			elseif progress < 0.5 then
				local stageProg = (progress - cornerP) / (0.5 - cornerP)
				if inf.startPoint == "TOPRIGHT" then
					local c2x = GetHSVTransition(stageProg, c2, c3)
					SetGradA(tails[2], "VERTICAL", c3, c2x)
					SetGradA(tails[3], "HORIZONTAL", c3, c4)
					SetGradA(tails[4], "VERTICAL", c4, c1)
				elseif inf.startPoint == "BOTTOMLEFT" then
					local c2x = GetHSVTransition(stageProg, c4, c1)
					SetGradA(tails[2], "VERTICAL", c2x, c1)
					SetGradA(tails[3], "HORIZONTAL", c2, c1)
					SetGradA(tails[4], "VERTICAL", c3, c2)
				elseif inf.startPoint == "TOPLEFT" then
					local c2x = GetHSVTransition(stageProg, c3, c4)
					SetGradA(tails[2], "HORIZONTAL", c2x, c4)
					SetGradA(tails[3], "VERTICAL", c4, c1)
					SetGradA(tails[4], "HORIZONTAL", c2, c1)
				else
					local c2x = GetHSVTransition(stageProg, c1, c2)
					SetGradA(tails[2], "HORIZONTAL", c2, c2x)
					SetGradA(tails[3], "VERTICAL", c3, c2)
					SetGradA(tails[4], "HORIZONTAL", c3, c4)
				end
			elseif progress < 0.5 + cornerP then
				local stageProg = (progress - 0.5) / cornerP
				if inf.startPoint == "TOPRIGHT" then
					local c3x = GetHSVTransition(stageProg, c3, c4)
					SetGradA(tails[3], "HORIZONTAL", c3x, c4)
					SetGradA(tails[4], "VERTICAL", c4, c1)
				elseif inf.startPoint == "BOTTOMLEFT" then
					local c3x = GetHSVTransition(stageProg, c1, c2)
					SetGradA(tails[3], "HORIZONTAL", c2, c3x)
					SetGradA(tails[4], "VERTICAL", c3, c2)
				elseif inf.startPoint == "TOPLEFT" then
					local c3x = GetHSVTransition(stageProg, c4, c1)
					SetGradA(tails[3], "VERTICAL", c3x, c1)
					SetGradA(tails[4], "HORIZONTAL", c2, c1)
				else
					local c3x = GetHSVTransition(stageProg, c2, c3)
					SetGradA(tails[3], "VERTICAL", c3, c3x)
					SetGradA(tails[4], "HORIZONTAL", c3, c4)
				end
			else
				local stageProg = (progress - 0.5 - cornerP) / (0.5 - cornerP)
				if inf.startPoint == "TOPRIGHT" then
					local c4x = GetHSVTransition(stageProg, c4, c1)
					SetGradA(tails[4], "VERTICAL", c4x, c1)
				elseif inf.startPoint == "BOTTOMLEFT" then
					local c4x = GetHSVTransition(stageProg, c2, c3)
					SetGradA(tails[4], "VERTICAL", c3, c4x)
				elseif inf.startPoint == "TOPLEFT" then
					local c4x = GetHSVTransition(stageProg, c1, c2)
					SetGradA(tails[4], "HORIZONTAL", c2, c4x)
				else
					local c4x = GetHSVTransition(stageProg, c3, c4)
					SetGradA(tails[4], "HORIZONTAL", c4x, c4)
				end
			end
		end
	end
end

local borderF = {
	["TOPLEFT"] = {
		[1] = {
			Set = BorderSet1LineCorner,
			Update = BorderUpdate1LineCorner,
			Gradient = BorderGradient1LineCorner,
			tailN = 4
			},
		[2] = {
			Set = BorderSet2LinesCorner,
			Update = BorderUpdate2LinesCorner,
			Gradient = BorderGradient2LinesCorner,
			tailN = 4
			},
		[4] = {
			Set = BorderSet4LinesCorner,
			Update = BorderUpdate4LinesCorner,
			Gradient = BorderGradient4LinesCorner,
			tailN = 8
			}
	},
	["TOP"] = {
		[1] = {
			Set = BorderSet1LineCenter,
			Update = BorderUpdate1LineCenter,
			Gradient = BorderGradient1LineCenter,
			tailN = 5
			},
		[2] = {
			Set = BorderSet2LinesCenter,
			Update = BorderUpdate2LinesCenter,
			Gradient = BorderGradient2LinesCenter,
			tailN = 6
			},
		[4] = {
			Set = BorderSet4LinesCenter,
			Update = BorderUpdate4LinesCenter,
			Gradient = BorderGradient4LinesCenter,
			tailN = 8
			}
	}
}

borderF["TOPRIGHT"] = borderF["TOPLEFT"]
borderF["BOTTOMRIGHT"] = borderF["TOPLEFT"]
borderF["BOTTOMLEFT"] = borderF["TOPLEFT"]
borderF["LEFT"] = borderF["TOP"]
borderF["BOTTOM"] = borderF["TOP"]
borderF["RIGHT"] = borderF["TOP"]

--Pixel Glow Functions--
local pCalc1 = function(progress,s,th,p)
    local c
    if progress>p[3] or progress<p[0] then
        c = 0
    elseif progress>p[2] then
        c =s-th-(progress-p[2])/(p[3]-p[2])*(s-th)
    elseif progress>p[1] then
        c =s-th
    else
        c = (progress-p[0])/(p[1]-p[0])*(s-th)
    end
    return math.floor(c+0.5)
end

local pCalc2 = function(progress,s,th,p)
    local c
    if progress>p[3] then
        c = s-th-(progress-p[3])/(p[0]+1-p[3])*(s-th)
    elseif progress>p[2] then
        c = s-th
    elseif progress>p[1] then
        c = (progress-p[1])/(p[2]-p[1])*(s-th)
    elseif progress>p[0] then
        c = 0
    else
        c = s-th-(progress+1-p[3])/(p[0]+1-p[3])*(s-th)
    end
    return math.floor(c+0.5)
end

local  pUpdate = function(self,elapsed)
    self.timer = self.timer+elapsed/self.info.period
    if self.timer>1 or self.timer <-1 then
        self.timer = self.timer%1
    end
    local progress = self.timer
    local width,height = self:GetSize()
    if width ~= self.info.width or height ~= self.info.height then
        local perimeter = 2*(width+height)
        if not (perimeter>0) then
            return
        end
        self.info.width = width
        self.info.height = height
        self.info.pTLx = {
            [0] = (height+self.info.length/2)/perimeter,
            [1] = (height+width+self.info.length/2)/perimeter,
            [2] = (2*height+width-self.info.length/2)/perimeter,
            [3] = 1-self.info.length/2/perimeter
        }
        self.info.pTLy ={
            [0] = (height-self.info.length/2)/perimeter,
            [1] = (height+width+self.info.length/2)/perimeter,
            [2] = (height*2+width+self.info.length/2)/perimeter,
            [3] = 1-self.info.length/2/perimeter
        }
        self.info.pBRx ={
            [0] = self.info.length/2/perimeter,
            [1] = (height-self.info.length/2)/perimeter,
            [2] = (height+width-self.info.length/2)/perimeter,
            [3] = (height*2+width+self.info.length/2)/perimeter
        }
        self.info.pBRy ={
            [0] = self.info.length/2/perimeter,
            [1] = (height+self.info.length/2)/perimeter,
            [2] = (height+width-self.info.length/2)/perimeter,
            [3] = (height*2+width-self.info.length/2)/perimeter
        }
    end
    if self:IsShown() then
        if not (self.masks[1]:IsShown()) then
            self.masks[1]:Show()
            self.masks[1]:SetPoint("TOPLEFT",self,"TOPLEFT",self.info.th,-self.info.th)
            self.masks[1]:SetPoint("BOTTOMRIGHT",self,"BOTTOMRIGHT",-self.info.th,self.info.th)
        end
        if self.masks[2] and not(self.masks[2]:IsShown()) then
            self.masks[2]:Show()
            self.masks[2]:SetPoint("TOPLEFT",self,"TOPLEFT",self.info.th+1,-self.info.th-1)
            self.masks[2]:SetPoint("BOTTOMRIGHT",self,"BOTTOMRIGHT",-self.info.th-1,self.info.th+1)
        end
        if self.bg and not(self.bg:IsShown()) then
            self.bg:Show()
        end
        for k,line  in pairs(self.textures) do
            line:SetPoint("TOPLEFT",self,"TOPLEFT",pCalc1((progress+self.info.step*(k-1))%1,width,self.info.th,self.info.pTLx),-pCalc2((progress+self.info.step*(k-1))%1,height,self.info.th,self.info.pTLy))
            line:SetPoint("BOTTOMRIGHT",self,"TOPLEFT",self.info.th+pCalc2((progress+self.info.step*(k-1))%1,width,self.info.th,self.info.pBRx),-height+pCalc1((progress+self.info.step*(k-1))%1,height,self.info.th,self.info.pBRy))
        end
    end
end

function lib.PixelGlow_Start(r,color,N,frequency,length,th,xOffset,yOffset,border,key,frameLevel)
    if not r then
        return
    end
    if not color then
        color = {0.95,0.95,0.32,1}
    end

    if not(N and N>0) then
        N = 8
    end

    local period
    if frequency then
        if not(frequency>0 or frequency<0) then
            period = 4
        else
            period = 1/frequency
        end
    else
        period = 4
    end
    local width,height = r:GetSize()
    length = length or math.floor((width+height)*(2/N-0.1))
    length = min(length,min(width,height))
    th = th or 1
    xOffset = xOffset or 0
    yOffset = yOffset or 0
    key = key or ""

    addFrameAndTex(r,color,"_PixelGlow",key,N,xOffset,yOffset,textureList.white,{0,1,0,1},nil,frameLevel)
    local f = r["_PixelGlow"..key]
    if not f.masks then
        f.masks = {}
    end
    if not f.masks[1] then
        f.masks[1] = GlowMaskPool:Acquire()
        f.masks[1]:SetTexture(textureList.empty, "CLAMPTOWHITE","CLAMPTOWHITE")
        f.masks[1]:Show()
    end
    f.masks[1]:SetPoint("TOPLEFT",f,"TOPLEFT",th,-th)
    f.masks[1]:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-th,th)

    if not(border==false) then
        if not f.masks[2] then
            f.masks[2] = GlowMaskPool:Acquire()
            f.masks[2]:SetTexture(textureList.empty, "CLAMPTOWHITE","CLAMPTOWHITE")
        end
        f.masks[2]:SetPoint("TOPLEFT",f,"TOPLEFT",th+1,-th-1)
        f.masks[2]:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-th-1,th+1)

        if not f.bg then
            f.bg = GlowTexPool:Acquire()
            f.bg:SetColorTexture(0.1,0.1,0.1,0.8)
            f.bg:SetParent(f)
            f.bg:SetAllPoints(f)
            f.bg:SetDrawLayer("ARTWORK",6)
            f.bg:AddMaskTexture(f.masks[2])
        end
    else
        if f.bg then
            GlowTexPool:Release(f.bg)
            f.bg = nil
        end
        if f.masks[2] then
            GlowMaskPool:Release(f.masks[2])
            f.masks[2] = nil
        end
    end
    for _,tex in pairs(f.textures) do
        if tex:GetNumMaskTextures() < 1 then
            tex:AddMaskTexture(f.masks[1])
        end
    end
    f.timer = f.timer or 0
    f.info = f.info or {}
    f.info.step = 1/N
    f.info.period = period
    f.info.th = th
    if f.info.length ~= length then
        f.info.width = nil
        f.info.length = length
    end
    pUpdate(f, 0)
    f:SetScript("OnUpdate",pUpdate)
end

function lib.PixelGlow_Stop(r,key)
    if not r then
        return
    end
    key = key or ""
    if not r["_PixelGlow"..key] then
        return false
    else
        GlowFramePool:Release(r["_PixelGlow"..key])
    end
end

table.insert(lib.glowList, "Pixel Glow")
lib.startList["Pixel Glow"] = lib.PixelGlow_Start
lib.stopList["Pixel Glow"] = lib.PixelGlow_Stop


--Autocast Glow Funcitons--
local function acUpdate(self,elapsed)
    local width,height = self:GetSize()
    if width ~= self.info.width or height ~= self.info.height then
        self.info.width = width
        self.info.height = height
        self.info.perimeter = 2*(width+height)
        self.info.bottomlim = height*2+width
        self.info.rightlim = height+width
        self.info.space = self.info.perimeter/self.info.N
    end

    local texIndex = 0;
    for k=1,4 do
        self.timer[k] = self.timer[k]+elapsed/(self.info.period*k)
        if self.timer[k] > 1 or self.timer[k] <-1 then
            self.timer[k] = self.timer[k]%1
        end
        for i = 1,self.info.N do
            texIndex = texIndex+1
            local position = (self.info.space*i+self.info.perimeter*self.timer[k])%self.info.perimeter
            if position>self.info.bottomlim then
                self.textures[texIndex]: SetPoint("CENTER",self,"BOTTOMRIGHT",-position+self.info.bottomlim,0)
            elseif position>self.info.rightlim then
                self.textures[texIndex]: SetPoint("CENTER",self,"TOPRIGHT",0,-position+self.info.rightlim)
            elseif position>self.info.height then
                self.textures[texIndex]: SetPoint("CENTER",self,"TOPLEFT",position-self.info.height,0)
            else
                self.textures[texIndex]: SetPoint("CENTER",self,"BOTTOMLEFT",0,position)
            end
        end
    end
end

function lib.AutoCastGlow_Start(r,color,N,frequency,scale,xOffset,yOffset,key,frameLevel)
    if not r then
        return
    end

    if not color then
        color = {0.95,0.95,0.32,1}
    end

    if not(N and N>0) then
        N = 4
    end

    local period
    if frequency then
        if not(frequency>0 or frequency<0) then
            period = 8
        else
            period = 1/frequency
        end
    else
        period = 8
    end
    scale = scale or 1
    xOffset = xOffset or 0
    yOffset = yOffset or 0
    key = key or ""

    addFrameAndTex(r,color,"_AutoCastGlow",key,N*4,xOffset,yOffset,textureList.shine,{0.8115234375,0.9169921875,0.8798828125,0.9853515625},true, frameLevel)
    local f = r["_AutoCastGlow"..key]
    local sizes = {7,6,5,4}
    for k,size in pairs(sizes) do
        for i = 1,N do
            f.textures[i+N*(k-1)]:SetSize(size*scale,size*scale)
        end
    end
    f.timer = f.timer or {0,0,0,0}
    f.info = f.info or {}
    f.info.N = N
    f.info.period = period
    f:SetScript("OnUpdate",acUpdate)
end

function lib.AutoCastGlow_Stop(r,key)
    if not r then
        return
    end

    key = key or ""
    if not r["_AutoCastGlow"..key] then
        return false
    else
        GlowFramePool:Release(r["_AutoCastGlow"..key])
    end
end

table.insert(lib.glowList, "Autocast Shine")
lib.startList["Autocast Shine"] = lib.AutoCastGlow_Start
lib.stopList["Autocast Shine"] = lib.AutoCastGlow_Stop

--Action Button Glow--
local function ButtonGlowResetter(framePool,frame)
    frame:SetScript("OnUpdate",nil)
    local parent = frame:GetParent()
    if parent._ButtonGlow then
        parent._ButtonGlow = nil
    end
    frame:Hide()
    frame:ClearAllPoints()
end
local ButtonGlowPool = CreateFramePool("Frame",GlowParent,nil,ButtonGlowResetter)
lib.ButtonGlowPool = ButtonGlowPool

local function CreateScaleAnim(group, target, order, duration, x, y, delay)
    local scale = group:CreateAnimation("Scale")
    scale:SetChildKey(target)
    scale:SetOrder(order)
    scale:SetDuration(duration)
    scale:SetScale(x, y)

    if delay then
        scale:SetStartDelay(delay)
    end
end

local function CreateAlphaAnim(group, target, order, duration, fromAlpha, toAlpha, delay, appear)
    local alpha = group:CreateAnimation("Alpha")
    alpha:SetChildKey(target)
    alpha:SetOrder(order)
    alpha:SetDuration(duration)
    alpha:SetFromAlpha(fromAlpha)
    alpha:SetToAlpha(toAlpha)
    if delay then
        alpha:SetStartDelay(delay)
    end
    if appear then
        table.insert(group.appear, alpha)
    else
        table.insert(group.fade, alpha)
    end
end

local function AnimIn_OnPlay(group)
    local frame = group:GetParent()
    local frameWidth, frameHeight = frame:GetSize()
    frame.spark:SetSize(frameWidth, frameHeight)
    frame.spark:SetAlpha(not(frame.color) and 1.0 or 0.3*frame.color[4])
    frame.innerGlow:SetSize(frameWidth / 2, frameHeight / 2)
    frame.innerGlow:SetAlpha(not(frame.color) and 1.0 or frame.color[4])
    frame.innerGlowOver:SetAlpha(not(frame.color) and 1.0 or frame.color[4])
    frame.outerGlow:SetSize(frameWidth * 2, frameHeight * 2)
    frame.outerGlow:SetAlpha(not(frame.color) and 1.0 or frame.color[4])
    frame.outerGlowOver:SetAlpha(not(frame.color) and 1.0 or frame.color[4])
    frame.ants:SetSize(frameWidth * 0.85, frameHeight * 0.85)
    frame.ants:SetAlpha(0)
    frame:Show()
end

local function AnimIn_OnFinished(group)
    local frame = group:GetParent()
    local frameWidth, frameHeight = frame:GetSize()
    frame.spark:SetAlpha(0)
    frame.innerGlow:SetAlpha(0)
    frame.innerGlow:SetSize(frameWidth, frameHeight)
    frame.innerGlowOver:SetAlpha(0.0)
    frame.outerGlow:SetSize(frameWidth, frameHeight)
    frame.outerGlowOver:SetAlpha(0.0)
    frame.outerGlowOver:SetSize(frameWidth, frameHeight)
    frame.ants:SetAlpha(not(frame.color) and 1.0 or frame.color[4])
end

local function AnimIn_OnStop(group)
    local frame = group:GetParent()
    local frameWidth, frameHeight = frame:GetSize()
    frame.spark:SetAlpha(0)
    frame.innerGlow:SetAlpha(0)
    frame.innerGlowOver:SetAlpha(0.0)
    frame.outerGlowOver:SetAlpha(0.0)
end

local function bgHide(self)
    if self.animOut:IsPlaying() then
        self.animOut:Stop()
        ButtonGlowPool:Release(self)
    end
end

local function bgUpdate(self, elapsed)
    AnimateTexCoords(self.ants, 256, 256, 48, 48, 22, elapsed, self.throttle);
    local cooldown = self:GetParent().cooldown;
    if(cooldown and cooldown:IsShown() and cooldown:GetCooldownDuration() > 3000) then
        self:SetAlpha(0.5);
    else
        self:SetAlpha(1.0);
    end
end

local function configureButtonGlow(f,alpha)
    f.spark = f:CreateTexture(nil, "BACKGROUND")
    f.spark:SetPoint("CENTER")
    f.spark:SetAlpha(0)
    f.spark:SetTexture([[Interface\SpellActivationOverlay\IconAlert]])
    f.spark:SetTexCoord(0.00781250, 0.61718750, 0.00390625, 0.26953125)

    -- inner glow
    f.innerGlow = f:CreateTexture(nil, "ARTWORK")
    f.innerGlow:SetPoint("CENTER")
    f.innerGlow:SetAlpha(0)
    f.innerGlow:SetTexture([[Interface\SpellActivationOverlay\IconAlert]])
    f.innerGlow:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)

    -- inner glow over
    f.innerGlowOver = f:CreateTexture(nil, "ARTWORK")
    f.innerGlowOver:SetPoint("TOPLEFT", f.innerGlow, "TOPLEFT")
    f.innerGlowOver:SetPoint("BOTTOMRIGHT", f.innerGlow, "BOTTOMRIGHT")
    f.innerGlowOver:SetAlpha(0)
    f.innerGlowOver:SetTexture([[Interface\SpellActivationOverlay\IconAlert]])
    f.innerGlowOver:SetTexCoord(0.00781250, 0.50781250, 0.53515625, 0.78515625)

    -- outer glow
    f.outerGlow = f:CreateTexture(nil, "ARTWORK")
    f.outerGlow:SetPoint("CENTER")
    f.outerGlow:SetAlpha(0)
    f.outerGlow:SetTexture([[Interface\SpellActivationOverlay\IconAlert]])
    f.outerGlow:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)

    -- outer glow over
    f.outerGlowOver = f:CreateTexture(nil, "ARTWORK")
    f.outerGlowOver:SetPoint("TOPLEFT", f.outerGlow, "TOPLEFT")
    f.outerGlowOver:SetPoint("BOTTOMRIGHT", f.outerGlow, "BOTTOMRIGHT")
    f.outerGlowOver:SetAlpha(0)
    f.outerGlowOver:SetTexture([[Interface\SpellActivationOverlay\IconAlert]])
    f.outerGlowOver:SetTexCoord(0.00781250, 0.50781250, 0.53515625, 0.78515625)

    -- ants
    f.ants = f:CreateTexture(nil, "OVERLAY")
    f.ants:SetPoint("CENTER")
    f.ants:SetAlpha(0)
    f.ants:SetTexture([[Interface\SpellActivationOverlay\IconAlertAnts]])

    f.animIn = f:CreateAnimationGroup()
    f.animIn.appear = {}
    f.animIn.fade = {}
    CreateScaleAnim(f.animIn, "spark",          1, 0.2, 1.5, 1.5)
    CreateAlphaAnim(f.animIn, "spark",          1, 0.2, 0, alpha, nil, true)
    CreateScaleAnim(f.animIn, "innerGlow",      1, 0.3, 2, 2)
    CreateScaleAnim(f.animIn, "innerGlowOver",  1, 0.3, 2, 2)
    CreateAlphaAnim(f.animIn, "innerGlowOver",  1, 0.3, alpha, 0, nil, false)
    CreateScaleAnim(f.animIn, "outerGlow",      1, 0.3, 0.5, 0.5)
    CreateScaleAnim(f.animIn, "outerGlowOver",  1, 0.3, 0.5, 0.5)
    CreateAlphaAnim(f.animIn, "outerGlowOver",  1, 0.3, alpha, 0, nil, false)
    CreateScaleAnim(f.animIn, "spark",          1, 0.2, 2/3, 2/3, 0.2)
    CreateAlphaAnim(f.animIn, "spark",          1, 0.2, alpha, 0, 0.2, false)
    CreateAlphaAnim(f.animIn, "innerGlow",      1, 0.2, alpha, 0, 0.3, false)
    CreateAlphaAnim(f.animIn, "ants",           1, 0.2, 0, alpha, 0.3, true)
    f.animIn:SetScript("OnPlay", AnimIn_OnPlay)
    f.animIn:SetScript("OnStop", AnimIn_OnStop)
    f.animIn:SetScript("OnFinished", AnimIn_OnFinished)

    f.animOut = f:CreateAnimationGroup()
    f.animOut.appear = {}
    f.animOut.fade = {}
    CreateAlphaAnim(f.animOut, "outerGlowOver", 1, 0.2, 0, alpha, nil, true)
    CreateAlphaAnim(f.animOut, "ants",          1, 0.2, alpha, 0, nil, false)
    CreateAlphaAnim(f.animOut, "outerGlowOver", 2, 0.2, alpha, 0, nil, false)
    CreateAlphaAnim(f.animOut, "outerGlow",     2, 0.2, alpha, 0, nil, false)
    f.animOut:SetScript("OnFinished", function(self) ButtonGlowPool:Release(self:GetParent())  end)

    f:SetScript("OnHide", bgHide)
end

local function updateAlphaAnim(f,alpha)
    for _,anim in pairs(f.animIn.appear) do
        anim:SetToAlpha(alpha)
    end
    for _,anim in pairs(f.animIn.fade) do
        anim:SetFromAlpha(alpha)
    end
    for _,anim in pairs(f.animOut.appear) do
        anim:SetToAlpha(alpha)
    end
    for _,anim in pairs(f.animOut.fade) do
        anim:SetFromAlpha(alpha)
    end
end

local ButtonGlowTextures = {["spark"] = true,["innerGlow"] = true,["innerGlowOver"] = true,["outerGlow"] = true,["outerGlowOver"] = true,["ants"] = true}

function lib.ButtonGlow_Start(r,color,frequency,frameLevel)
    if not r then
        return
    end
	frameLevel = frameLevel or 8;
    local throttle
    if frequency and frequency > 0 then
        throttle = 0.25/frequency*0.01
    else
        throttle = 0.01
    end
    if r._ButtonGlow then
        local f = r._ButtonGlow
        local width,height = r:GetSize()
        f:SetFrameLevel(r:GetFrameLevel()+frameLevel)
        f:SetSize(width*1.4 , height*1.4)
        f:SetPoint("TOPLEFT", r, "TOPLEFT", -width * 0.2, height * 0.2)
        f:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", width * 0.2, -height * 0.2)
        f.ants:SetSize(width*1.4*0.85, height*1.4*0.85)
		AnimIn_OnFinished(f.animIn)
		if f.animOut:IsPlaying() then
            f.animOut:Stop()
            f.animIn:Play()
        end

        if not(color) then
            for texture in pairs(ButtonGlowTextures) do
                f[texture]:SetDesaturated(nil)
                f[texture]:SetVertexColor(1,1,1)
                f[texture]:SetAlpha(f[texture]:GetAlpha()/(f.color and f.color[4] or 1))
                updateAlphaAnim(f, 1)
            end
            f.color = false
        else
            for texture in pairs(ButtonGlowTextures) do
                f[texture]:SetDesaturated(1)
                f[texture]:SetVertexColor(color[1],color[2],color[3])
                f[texture]:SetAlpha(f[texture]:GetAlpha()/(f.color and f.color[4] or 1)*color[4])
                updateAlphaAnim(f,color and color[4] or 1)
            end
            f.color = color
        end
        f.throttle = throttle
    else
        local f, new = ButtonGlowPool:Acquire()
        if new then
            configureButtonGlow(f,color and color[4] or 1)
        else
            updateAlphaAnim(f,color and color[4] or 1)
        end
        r._ButtonGlow = f
        local width,height = r:GetSize()
        f:SetParent(r)
        f:SetFrameLevel(r:GetFrameLevel()+frameLevel)
        f:SetSize(width * 1.4, height * 1.4)
        f:SetPoint("TOPLEFT", r, "TOPLEFT", -width * 0.2, height * 0.2)
        f:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", width * 0.2, -height * 0.2)
        if not(color) then
            f.color = false
            for texture in pairs(ButtonGlowTextures) do
                f[texture]:SetDesaturated(nil)
                f[texture]:SetVertexColor(1,1,1)
            end
        else
            f.color = color
            for texture in pairs(ButtonGlowTextures) do
                f[texture]:SetDesaturated(1)
                f[texture]:SetVertexColor(color[1],color[2],color[3])
            end
        end
        f.throttle = throttle
        f:SetScript("OnUpdate", bgUpdate)

        f.animIn:Play()

        if Masque and Masque.UpdateSpellAlert and (not r.overlay or not issecurevariable(r, "overlay")) then
            local old_overlay = r.overlay
            r.overlay = f
            Masque:UpdateSpellAlert(r)
            r.overlay = old_overlay
        end
    end
end

function lib.ButtonGlow_Stop(r)
    if r._ButtonGlow then
        if r._ButtonGlow.animIn:IsPlaying() then
            r._ButtonGlow.animIn:Stop()
            ButtonGlowPool:Release(r._ButtonGlow)
        elseif r:IsVisible() then
            r._ButtonGlow.animOut:Play()
        else
            ButtonGlowPool:Release(r._ButtonGlow)
        end
    end
end

table.insert(lib.glowList, "Action Button Glow")
lib.startList["Action Button Glow"] = lib.ButtonGlow_Start
lib.stopList["Action Button Glow"] = lib.ButtonGlow_Stop
