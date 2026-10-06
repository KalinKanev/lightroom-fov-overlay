-- tests/test_selection.lua
-- Run from repo root: lua tests/test_selection.lua

local FOVCalculator = dofile("fovoverlay.lrplugin/FOVCalculator.lua")

local pass, fail = 0, 0
local function check(desc, got, expected)
  if got == expected then
    pass = pass + 1
    print("  PASS  " .. desc)
  else
    fail = fail + 1
    print("  FAIL  " .. desc .. "  got=" .. tostring(got) .. "  expected=" .. tostring(expected))
  end
end

local fls = { 400, 420, 450, 500, 560, 600, 800, 1000, 1200, 1400, 1600, 2000 }

-- Uncropped: the 4 FLs just longer than the shot FL
local s1 = FOVCalculator.defaultSelectedFLs(fls, 420, 4)
check("s1 450", s1[450], true)
check("s1 600", s1[600], true)
check("s1 800 not", s1[800], nil)
check("s1 420 not (equal)", s1[420], nil)

-- Cropped to 1065mm equiv: the 4 FLs just tighter than the crop
local s2 = FOVCalculator.defaultSelectedFLs(fls, 1065, 4)
check("s2 1000 not (wider)", s2[1000], nil)
check("s2 1200", s2[1200], true)
check("s2 1400", s2[1400], true)
check("s2 1600", s2[1600], true)
check("s2 2000", s2[2000], true)

-- Fewer than 4 available
local s3 = FOVCalculator.defaultSelectedFLs(fls, 1500, 4)
check("s3 1600", s3[1600], true)
check("s3 2000", s3[2000], true)
check("s3 1400 not", s3[1400], nil)

print(string.format("\n%d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
