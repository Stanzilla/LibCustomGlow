CustomGlow = CustomGlow or {}
CustomGlow.L = {}
local L = CustomGlow.L
L["Bling"] = "Bling"
L["Creates Bling over target region"] = "Creates Bling over target region"
L["Flash"] = "Flash"
L["Type of flash"] = "Type of flash"
L["Start point"] = "Start point"


-- Make missing translations available
setmetatable(CustomGlow.L, {__index = function(self, key)
  self[key] = (key or "")
  return key
end})
