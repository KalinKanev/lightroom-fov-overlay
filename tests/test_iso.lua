-- tests/test_iso.lua
-- Run from repo root: lua tests/test_iso.lua

local FOVCalculator = dofile("fovoverlay.lrplugin/FOVCalculator.lua")

local pass, fail = 0, 0
local function check(desc, got, expected, tolerance)
  tolerance = tolerance or 0.001
  local ok = (got == expected) or (type(got) == "number" and type(expected) == "number" and math.abs(got - expected) < tolerance)
  if ok then
    pass = pass + 1
    print("  PASS  " .. desc)
  else
    fail = fail + 1
    print("  FAIL  " .. desc .. "  got=" .. tostring(got) .. "  expected=" .. tostring(expected))
  end
end

-- parseISO
check("parseISO number",        FOVCalculator.parseISO(3200),        3200)
check("parseISO 'ISO 3200'",    FOVCalculator.parseISO("ISO 3200"),  3200)
check("parseISO '12,800'",      FOVCalculator.parseISO("12,800"),    12800)
check("parseISO nil",           FOVCalculator.parseISO(nil),         nil)
check("parseISO zero",          FOVCalculator.parseISO(0),           nil)
check("parseISO garbage",       FOVCalculator.parseISO("abc"),       nil)

-- roundToThirdStopISO
check("round 6400 exact",       FOVCalculator.roundToThirdStopISO(6400),   6400)
check("round 7000 -> 6400",     FOVCalculator.roundToThirdStopISO(7000),   6400)
check("round 900 -> 1000",      FOVCalculator.roundToThirdStopISO(900),    1000)
check("round beyond table",     FOVCalculator.roundToThirdStopISO(500000), 500000)
check("round nil",              FOVCalculator.roundToThirdStopISO(nil),    nil)

-- equivalentISO: 2x linear crop = 4x area = +2 EV
local e1 = FOVCalculator.equivalentISO(800, 4000000, 1000000)
check("e1 ratio",   e1.ratio,   4)
check("e1 stops",   e1.stops,   2)
check("e1 iso",     e1.iso,     3200)
check("e1 display", e1.display, 3200)

-- 1.5x linear crop (DX-style) = 2.25x area = +1.17 EV, ISO 400 -> 900 -> shown as 1000
local e2 = FOVCalculator.equivalentISO(400, 2.25, 1)
check("e2 stops",   e2.stops,   1.1699, 0.001)
check("e2 iso",     e2.iso,     900)
check("e2 display", e2.display, 1000)

-- No ISO in metadata: stops still computed
local e3 = FOVCalculator.equivalentISO(nil, 4, 1)
check("e3 stops",   e3.stops,   2)
check("e3 iso nil", e3.iso,     nil)

-- Invalid areas
check("invalid area nil", FOVCalculator.equivalentISO(800, 0, 1), nil)
check("invalid crop nil", FOVCalculator.equivalentISO(800, 1, nil), nil)

-- Full-frame equivalence: APS-C (1.5x) uncropped ISO 800 -> 800 * 2.25 = 1800 -> shown as 2000
local e4 = FOVCalculator.equivalentISO(800, 1, 1, 1.5)
check("e4 ratio",   e4.ratio,   2.25)
check("e4 iso",     e4.iso,     1800)
check("e4 display", e4.display, 2000)
-- APS-C plus a 2x crop: area x4, sensor x2.25 -> ratio 9
local e5 = FOVCalculator.equivalentISO(400, 4, 1, 1.5)
check("e5 ratio",   e5.ratio,   9)
check("e5 iso",     e5.iso,     3600)
-- Factor nil or 1 means no sensor conversion
check("e6 nil factor", FOVCalculator.equivalentISO(800, 4, 1, nil).ratio, 4)

-- formatISOValue
check("fmt full",     FOVCalculator.formatISOValue(e1, "~", true),  "~ISO 3200 (+2.0 EV)")
check("fmt short",    FOVCalculator.formatISOValue(e1, "~", false), "~ISO 3200")
check("fmt no iso",   FOVCalculator.formatISOValue(e3, "~", true),  "+2.0 EV")
check("fmt no iso s", FOVCalculator.formatISOValue(e3, "~", false), "+2.0 EV")
check("fmt nil",      FOVCalculator.formatISOValue(nil, "~", true), "")

-- selectLabeledFLs: rects sorted outermost first; 300 is too close to 200
local rects = {
  { focalLength = 200, top = 100 },
  { focalLength = 300, top = 110 },
  { focalLength = 400, top = 200 },
}
local s1 = FOVCalculator.selectLabeledFLs(rects, { 200, 300, 400 }, 1.0, 30)
check("s1 200 labeled",   s1[200], true)
check("s1 300 skipped",   s1[300], nil)
check("s1 400 labeled",   s1[400], true)
local s2 = FOVCalculator.selectLabeledFLs(rects, { 300, 400 }, 1.0, 30)
check("s2 300 labeled (200 hidden)", s2[300], true)
check("s2 400 labeled",   s2[400], true)
local s3 = FOVCalculator.selectLabeledFLs(rects, { 200, 300, 400 }, 0.1, 30)
check("s3 scaled: only 200", s3[200] == true and s3[300] == nil and s3[400] == nil, true)

print(string.format("\n%d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
