-- toolName = TNS|Checklist|TNE

local CHECKLIST_PATH = "/SCRIPTS/TOOLS/checklist.md"
local MAX_BYTES = 16384
local MAX_TASKS = 64

local HEADER_Y = 1
local BODY_TOP = 11
local BODY_BOTTOM = 55
local FOOTER_Y = 56
local LINE_HEIGHT = 8
local SMALL_CHAR_WIDTH = 5

local tasks = {}
local selected = 1
local topTask = 1
local completed = 0
local loadError = nil
local errorLines = {}

local function textWidth(value)
  -- lcd.sizeText is not available on monochrome radios such as the T14.
  -- SMLSIZE uses a five-pixel-wide font on the 128x64 display.
  return #value * SMALL_CHAR_WIDTH
end

local function ellipsize(value, maxWidth, force)
  if not force and textWidth(value) <= maxWidth then
    return value
  end

  local suffix = "..."
  local shortened = value
  while #shortened > 0 and textWidth(shortened .. suffix) > maxWidth do
    shortened = string.sub(shortened, 1, #shortened - 1)
  end
  return shortened .. suffix
end

local function wrapText(value, maxWidth)
  local lines = {}
  local current = ""

  for word in string.gmatch(value, "%S+") do
    local candidate = current == "" and word or (current .. " " .. word)
    if textWidth(candidate) <= maxWidth then
      current = candidate
    else
      if current ~= "" then
        lines[#lines + 1] = current
      end

      if textWidth(word) <= maxWidth then
        current = word
      else
        lines[#lines + 1] = ellipsize(word, maxWidth, false)
        current = ""
      end
    end
  end

  if current ~= "" then
    lines[#lines + 1] = current
  end
  if #lines == 0 then
    lines[1] = ""
  end

  if #lines > 2 then
    lines[2] = ellipsize(lines[2], maxWidth, true)
    while #lines > 2 do
      lines[#lines] = nil
    end
  end

  return lines
end

local function setError(message)
  loadError = message
  errorLines = wrapText(message, LCD_W - 4)
end

local function readChecklist()
  local file = io.open(CHECKLIST_PATH, "r")
  if file == nil then
    setError("Missing " .. CHECKLIST_PATH)
    return
  end

  local data = io.read(file, MAX_BYTES + 1)
  io.close(file)

  if data == nil then
    setError("Could not read checklist.md")
    return
  end
  if #data > MAX_BYTES then
    setError("checklist.md is larger than 16 KiB")
    return
  end
  if string.sub(data, 1, 3) == "\239\187\191" then
    data = string.sub(data, 4)
  end

  for line in string.gmatch(data .. "\n", "(.-)\n") do
    line = string.gsub(line, "\r$", "")
    local label = string.match(line, "^%s*[-*]%s+%[[ xX]%]%s+(.+)%s*$")
    if label ~= nil and label ~= "" then
      if #tasks >= MAX_TASKS then
        tasks = {}
        setError("checklist.md has more than 64 tasks")
        return
      end
      tasks[#tasks + 1] = { text = label, done = false }
    end
  end

  if #tasks == 0 then
    setError("No Markdown task items in checklist.md")
    return
  end

  local maxTextWidth = LCD_W - 18
  for i = 1, #tasks do
    tasks[i].lines = wrapText(tasks[i].text, maxTextWidth)
  end
end

local function taskHeight(index)
  return (#tasks[index].lines * LINE_HEIGHT) + 1
end

local function selectionFitsFrom(first)
  local y = BODY_TOP
  for i = first, selected do
    local height = taskHeight(i)
    if y + height > BODY_BOTTOM then
      return false
    end
    y = y + height
  end
  return true
end

local function keepSelectionVisible()
  if selected < topTask then
    topTask = selected
  end
  while topTask < selected and not selectionFitsFrom(topTask) do
    topTask = topTask + 1
  end
end

local function moveSelection(delta)
  local nextSelection = selected + delta
  if nextSelection < 1 then
    nextSelection = 1
  elseif nextSelection > #tasks then
    nextSelection = #tasks
  end
  selected = nextSelection
  keepSelectionVisible()
end

local function playStepDoneSound()
  -- Short ascending confirmation for an individual completed step.
  playTone(660, 10, 4, 0)
  playTone(880, 10, 4, 0)
  playTone(1100, 18, 0, 0)
end

local function playCompletionSound()
  -- Longer celebratory melody for completing the whole checklist.
  playTone(523, 16, 4, 0)
  playTone(659, 16, 4, 0)
  playTone(784, 16, 4, 0)
  playTone(1047, 24, 8, 0)
  playTone(784, 16, 4, 0)
  playTone(880, 16, 4, 0)
  playTone(988, 16, 4, 0)
  playTone(1175, 40, 0, 0)
end

local function toggleSelected()
  local task = tasks[selected]
  task.done = not task.done
  if task.done then
    completed = completed + 1
    if completed == #tasks then
      playCompletionSound()
    else
      playStepDoneSound()
    end
  else
    completed = completed - 1
    playTone(500, 6, 0, 0)
  end
end

local function drawError()
  lcd.clear()
  lcd.drawText(1, HEADER_Y, "Checklist error", SMLSIZE + INVERS)
  lcd.drawLine(0, 9, LCD_W - 1, 9, SOLID, FORCE)

  local y = 13
  for i = 1, #errorLines do
    if y + LINE_HEIGHT > BODY_BOTTOM then
      break
    end
    lcd.drawText(2, y, errorLines[i], SMLSIZE)
    y = y + LINE_HEIGHT
  end

  lcd.drawLine(0, 55, LCD_W - 1, 55, SOLID, FORCE)
  lcd.drawText(1, FOOTER_Y, "RTN exit", SMLSIZE)
end

local function drawChecklist()
  lcd.clear()

  local header
  if completed == #tasks then
    header = "Checklist COMPLETE"
  else
    header = "Checklist " .. completed .. "/" .. #tasks
  end
  lcd.drawText(1, HEADER_Y, header, SMLSIZE + INVERS)
  lcd.drawLine(0, 9, LCD_W - 1, 9, SOLID, FORCE)

  local y = BODY_TOP
  local index = topTask
  while index <= #tasks do
    local task = tasks[index]
    local height = taskHeight(index)
    if y + height > BODY_BOTTOM then
      break
    end

    local flags = SMLSIZE
    if index == selected then
      flags = flags + INVERS
    end

    local marker = task.done and "[x]" or "[ ]"
    lcd.drawText(0, y, marker, flags)
    for lineIndex = 1, #task.lines do
      lcd.drawText(17, y + ((lineIndex - 1) * LINE_HEIGHT), task.lines[lineIndex], flags)
    end

    y = y + height
    index = index + 1
  end

  if topTask > 1 then
    lcd.drawText(LCD_W - 6, HEADER_Y, "^", SMLSIZE)
  elseif index <= #tasks then
    lcd.drawText(LCD_W - 6, HEADER_Y, "v", SMLSIZE)
  end

  lcd.drawLine(0, 55, LCD_W - 1, 55, SOLID, FORCE)
  lcd.drawText(1, FOOTER_Y, "ENT toggle  RTN exit", SMLSIZE)
end

local function init()
  tasks = {}
  selected = 1
  topTask = 1
  completed = 0
  loadError = nil
  errorLines = {}
  readChecklist()
end

local function run(event)
  if event == EVT_EXIT_BREAK then
    return 1
  end

  if loadError ~= nil then
    drawError()
    return 0
  end

  if event == EVT_VIRTUAL_NEXT
      or event == EVT_VIRTUAL_NEXT_REPT
      or event == EVT_VIRTUAL_INC
      or event == EVT_VIRTUAL_INC_REPT then
    moveSelection(1)
  elseif event == EVT_VIRTUAL_PREV
      or event == EVT_VIRTUAL_PREV_REPT
      or event == EVT_VIRTUAL_DEC
      or event == EVT_VIRTUAL_DEC_REPT then
    moveSelection(-1)
  elseif event == EVT_VIRTUAL_ENTER or event == EVT_ENTER_BREAK or event == EVT_ROT_BREAK then
    toggleSelected()
  end

  drawChecklist()
  return 0
end

return { init = init, run = run }
