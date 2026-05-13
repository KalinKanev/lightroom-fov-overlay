-- Run from repo root: lua tests/test_orientation.lua
local FOVCalculator = dofile("fovoverlay.lrplugin/FOVCalculator.lua")

local passed, failed = 0, 0
local function check(label, got, expected)
  if got == expected then
    passed = passed + 1
  else
    failed = failed + 1
    print("FAIL: " .. label .. " — got " .. tostring(got) .. ", want " .. tostring(expected))
  end
end

check("AB (normal landscape)",    FOVCalculator.orientationToDegrees("AB"),  0)
check("BC (90° CW portrait)",     FOVCalculator.orientationToDegrees("BC"),  90)
check("CD (180°)",                FOVCalculator.orientationToDegrees("CD"),  180)
check("DA (270° CW portrait)",    FOVCalculator.orientationToDegrees("DA"),  270)
check("nil → 0",                  FOVCalculator.orientationToDegrees(nil),   0)
check("unknown string → 0",       FOVCalculator.orientationToDegrees("XY"),  0)
check("empty string → 0",         FOVCalculator.orientationToDegrees(""),    0)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
