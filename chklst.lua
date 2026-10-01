-- EdgeTX monochrome telemetry/display script entry point.
-- The filename is intentionally six characters for EdgeTX compatibility.

local loader = loadScript("/SCRIPTS/TOOLS/Checklist.lua")

if loader == nil then
  local function run()
    lcd.clear()
    lcd.drawText(1, 2, "Checklist error", SMLSIZE + INVERS)
    lcd.drawText(1, 16, "Missing:", SMLSIZE)
    lcd.drawText(1, 25, "/SCRIPTS/TOOLS/", SMLSIZE)
    lcd.drawText(1, 34, "Checklist.lua", SMLSIZE)
  end

  return { run = run }
end

local checklist = loader()

local function init()
  if checklist.init ~= nil then
    checklist.init()
  end
end

local function run(event)
  -- Telemetry/display scripts do not return an exit value. The firmware owns
  -- screen navigation, while the shared implementation handles checklist keys.
  checklist.run(event)
end

return { init = init, run = run }
