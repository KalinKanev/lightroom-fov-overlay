-- tests/test_dof.lua
-- Run with: lua tests/test_dof.lua

local FOVCalculator = dofile("fovoverlay.lrplugin/FOVCalculator.lua")

local pass, fail = 0, 0
local function check(desc, got, expected, tolerance)
  tolerance = tolerance or 0.001
  local ok = (got == expected) or (type(got) == "number" and math.abs(got - expected) < tolerance)
  if ok then
    pass = pass + 1
    print("  PASS  " .. desc)
  else
    fail = fail + 1
    print("  FAIL  " .. desc .. "  got=" .. tostring(got) .. "  expected=" .. tostring(expected))
  end
end

-- Case 1: Normal finite DoF (300mm f/5.6, 4m, full-frame)
-- CoC = 0.029/1.0 = 0.029mm
-- H = 300^2 / (5.6 * 0.029) + 300 = 554487mm
-- Near = H*d/(H+d) = 554487*4000/558487 = 3971.4mm = 3.971m
-- Far  = H*d/(H-d) = 554487*4000/550487 = 4029.0mm = 4.029m
local r1 = FOVCalculator.calculateDoF(300, 5.6, 4, 1.0)
check("r1 not nil",        r1 ~= nil,          true)
check("r1.isInfinity",     r1.isInfinity,      false)
check("r1.near",           r1.near,            3.971, 0.005)
check("r1.far",            r1.far,             4.029, 0.005)
check("r1.span",           r1.span,            0.058, 0.005)
check("r1.hyperfocal",     r1.hyperfocal,      554.487, 0.5)

-- Case 2: Focus distance beyond hyperfocal → far = nil
-- 50mm f/22, 30m, full-frame
-- H = 50^2 / (22*0.029) + 50 = 2500/0.638 + 50 = 3968mm = 3.968m
-- d=30m >> H=3.968m → far=nil
local r2 = FOVCalculator.calculateDoF(50, 22, 30, 1.0)
check("r2.far is nil",     r2.far,             nil)
check("r2.near exists",    r2.near ~= nil,     true)
check("r2.hyperfocal",     r2.hyperfocal,      3.968, 0.05)

-- Case 3: Encoded infinity (65535m)
local r3 = FOVCalculator.calculateDoF(300, 5.6, 65535, 1.0)
check("r3.isInfinity",     r3.isInfinity,      true)
check("r3.near is nil",    r3.near,            nil)
check("r3.far is nil",     r3.far,             nil)
check("r3.span is nil",    r3.span,            nil)
check("r3.hyperfocal set", r3.hyperfocal ~= nil, true)

-- Case 4: Crop sensor (50mm lens, cropFactor=1.5 → APS-C)
-- CoC = 0.029/1.5 = 0.01933mm
-- H = 50^2 / (5.6*0.01933) + 50 = 2500/0.1083 + 50 = 23118mm = 23.1m
local r4 = FOVCalculator.calculateDoF(50, 5.6, 4, 1.5)
check("r4.hyperfocal",     r4.hyperfocal,      23.1, 0.5)
check("r4.near exists",    r4.near ~= nil,     true)

-- Case 5: Invalid inputs → nil
check("nil fl",    FOVCalculator.calculateDoF(nil, 5.6, 4, 1.0), nil)
check("zero fl",   FOVCalculator.calculateDoF(0, 5.6, 4, 1.0), nil)
check("nil N",     FOVCalculator.calculateDoF(300, nil, 4, 1.0), nil)
check("nil dist",  FOVCalculator.calculateDoF(300, 5.6, nil, 1.0), nil)

print(string.format("\n%d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
