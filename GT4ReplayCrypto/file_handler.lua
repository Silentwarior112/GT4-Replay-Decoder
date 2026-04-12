-- Basic Enceladus file handler
-- Flow:
--   1. Select an input file
--   2. Select an output folder
--   3. Run placeholder processing logic
--
-- Controls:
--   D-Pad Up/Down : Move selection
--   Cross         : Enter folder / confirm input file
--   Circle        : Go to parent folder
--   Start         : Confirm output folder / process file / reset after completion
--   Triangle      : Exit to browser

Screen.setMode(NTSC, 640, 448, CT24, INTERLACED, FIELD)
Font.fmLoad()

local GT4ReplayCrypto = dofile("GT4ReplayCrypto/gt4ReplayCrypto.lua")

local WHITE  = Color.new(255, 255, 255)
local GRAY   = Color.new(170, 170, 170)
local GREEN  = Color.new(80, 255, 120)
local RED    = Color.new(255, 90, 90)
local YELLOW = Color.new(255, 220, 80)

local STAGE_SELECT_INPUT  = 1
local STAGE_SELECT_OUTPUT = 2
local STAGE_DONE          = 3

local stage = STAGE_SELECT_INPUT
local selectedInputFile = nil
local selectedOutputDir = nil
local statusMessage = "Select an input file."

local previousPad = 0
local cursorIndex = 1
local currentEntries = {}

local browserPath = System.currentDirectory()
if browserPath == nil or browserPath == "" then
    browserPath = "host:"
end

local function trimTrailingSlash(path)
    if path == nil then
        return ""
    end

    if string.match(path, "^[^:]+:/$") then
        return path
    end

    return (string.gsub(path, "/+$", ""))
end

local function isRootPath(path)
    if path == nil then
        return true
    end

    return string.match(path, "^[^:]+:$") ~= nil or string.match(path, "^[^:]+:/$") ~= nil
end

local function joinPath(base, name)
    if base == nil or base == "" then
        return name
    end

    local lastChar = string.sub(base, -1)
    if lastChar == "/" or lastChar == ":" then
        return base .. name
    end

    return base .. "/" .. name
end

local function getParentPath(path)
    if isRootPath(path) then
        return path
    end

    local p = trimTrailingSlash(path)

    local deviceRoot = string.match(p, "^([^:]+:)[^/]+$")
    if deviceRoot then
        return deviceRoot
    end

    local parent = string.match(p, "^(.*)/[^/]+$")
    if parent and parent ~= "" then
        if string.match(p, "^[^:]+:/") and string.match(parent, "^[^:]+:$") then
            return parent .. "/"
        end
        return parent
    end

    return path
end

local function getBaseName(path)
    local p = trimTrailingSlash(path)
    return string.match(p, "([^/:]+)$") or p
end

local function splitFileName(name)
    local stem, ext = string.match(name, "^(.*)(%.[^%.]+)$")
    if stem and ext then
        return stem, ext
    end
    return name, ""
end

local function buildOutputName(inputPath)
    local base = getBaseName(inputPath)
    local stem, ext = splitFileName(base)
    return stem .. "_processed" .. ext
end

local function readEntireFile(path)
    local fd = System.openFile(path, O_RDONLY)
    if fd == nil or fd < 0 then
        return nil, "Failed to open input file: " .. path
    end

    local size = System.sizeFile(fd)
    if size == nil or size < 0 then
        System.closeFile(fd)
        return nil, "Failed to read file size: " .. path
    end

    local data, bytesRead = System.readFile(fd, size)
    System.closeFile(fd)

    if data == nil then
        return nil, "Failed to read file data: " .. path
    end

    return data, bytesRead or 0
end

local function writeEntireFile(path, data)
    local fd = System.openFile(path, O_WRONLY | O_CREAT | O_TRUNC)
    if fd == nil or fd < 0 then
        return false, "Failed to create output file: " .. path
    end

    local written = System.writeFile(fd, data, string.len(data))
    System.closeFile(fd)

    if written == nil or written < 0 then
        return false, "Failed to write output file: " .. path
    end

    return true, nil
end



local function safeWriteTextFile(path, text)
    local fd = System.openFile(path, O_WRONLY | O_CREAT | O_TRUNC)
    if fd == nil or fd < 0 then
        return false
    end
    System.writeFile(fd, text, string.len(text))
    System.closeFile(fd)
    return true
end

local function processSelectedFile(inputPath, outputDir, inputData)
    local outputData, replayInfo, err = GT4ReplayCrypto.decryptReplayString(inputData)
    if not outputData then
        return nil, nil, err or "Replay decode failed."
    end

    local base = getBaseName(inputPath)
    local stem, ext = splitFileName(base)
    local outputFileName = stem .. "_decoded" .. ext

    local versionText = string.format("%d.%d", replayInfo.major_version, replayInfo.minor_version)
    statusMessage = "Decoded replay version " .. versionText

    return outputData, outputFileName, nil
end

local function runSelectedJob()
    if not selectedInputFile then
        return false, "No input file selected."
    end

    if not selectedOutputDir then
        return false, "No output folder selected."
    end

    local inputData, err = readEntireFile(selectedInputFile)
    if not inputData then
        return false, err
    end

    local outputData, outputName, processErr = processSelectedFile(selectedInputFile, selectedOutputDir, inputData)
    if outputData == nil then
        local debugPath = joinPath(selectedOutputDir or browserPath or "host:", "gt4_debug.txt")
        local debugText = (processErr or "Processing failed.") .. "Input: " .. tostring(selectedInputFile) .. "OutputDir: " .. tostring(selectedOutputDir) .. "" safeWriteTextFile(debugPath, debugText)
        return false, (processErr or "Processing failed.") .. " [debug saved: gt4_debug.txt]"
    end

    if outputName == nil or outputName == "" then
        outputName = buildOutputName(selectedInputFile)
    end

    local outputPath = joinPath(selectedOutputDir, outputName)
    local ok, writeErr = writeEntireFile(outputPath, outputData)
    if not ok then
        return false, writeErr
    end

    return true, "Done: " .. outputPath
end

local function refreshEntries()
    local raw = System.listDirectory(browserPath) or {}
    local items = {}

    if not isRootPath(browserPath) then
        table.insert(items, {
            name = "..",
            directory = true,
            path = getParentPath(browserPath),
            parent = true,
        })
    end

    for i = 1, #raw do
        local entry = raw[i]
        if entry.name ~= "." and entry.name ~= ".." then
            table.insert(items, {
                name = entry.name,
                directory = entry.directory == true,
                size = entry.size,
                path = joinPath(browserPath, entry.name),
                parent = false,
            })
        end
    end

    table.sort(items, function(a, b)
        if a.parent ~= b.parent then
            return a.parent
        end
        if a.directory ~= b.directory then
            return a.directory
        end
        return string.lower(a.name) < string.lower(b.name)
    end)

    currentEntries = items

    if cursorIndex < 1 then
        cursorIndex = 1
    end
    if cursorIndex > #currentEntries then
        cursorIndex = #currentEntries
    end
    if cursorIndex < 1 then
        cursorIndex = 1
    end
end

local function moveCursor(delta)
    if #currentEntries == 0 then
        cursorIndex = 1
        return
    end

    cursorIndex = cursorIndex + delta
    if cursorIndex < 1 then
        cursorIndex = #currentEntries
    elseif cursorIndex > #currentEntries then
        cursorIndex = 1
    end
end

local function wasPressed(now, button)
    return (now & button) ~= 0 and (previousPad & button) == 0
end

local function enterDirectory(path)
    browserPath = path
    cursorIndex = 1
    refreshEntries()
end

local function resetFlow()
    stage = STAGE_SELECT_INPUT
    selectedInputFile = nil
    selectedOutputDir = nil
    statusMessage = "Select an input file."
    cursorIndex = 1
    refreshEntries()
end

local function handleCross(entry)
    if not entry then
        return
    end

    if entry.directory then
        enterDirectory(entry.path)
        return
    end

    if stage == STAGE_SELECT_INPUT then
        selectedInputFile = entry.path
        selectedOutputDir = browserPath
        stage = STAGE_SELECT_OUTPUT
        statusMessage = "Input selected. Now choose an output folder and press START to decode."
        refreshEntries()
    else
        statusMessage = "Select a folder for output. Press START to confirm the current folder."
    end
end

local function handleCircle()
    local parent = getParentPath(browserPath)
    if parent ~= browserPath then
        enterDirectory(parent)
    end
end

local function handleStart()
    if stage == STAGE_SELECT_OUTPUT then
        selectedOutputDir = browserPath
        local ok, resultMessage = runSelectedJob()
        statusMessage = resultMessage
        if ok then
            stage = STAGE_DONE
        end
    elseif stage == STAGE_DONE then
        resetFlow()
    end
end

local function drawLine(y, text, color)
    Font.fmPrint(20, y, 0.45, text, color or WHITE)
end

local function formatEntry(entry)
    if entry.directory then
        return "[DIR] " .. entry.name
    end

    if entry.size ~= nil then
        return string.format("[FILE] %s (%d bytes)", entry.name, entry.size)
    end

    return "[FILE] " .. entry.name
end

local function drawUI()
    Screen.clear(Color.new(20, 24, 30))

    drawLine(20, "Enceladus GT4 Replay Decoder", YELLOW)
    drawLine(44, "Path: " .. browserPath, GRAY)

    if stage == STAGE_SELECT_INPUT then
        drawLine(68, "Step 1: Choose input file with CROSS", GREEN)
    elseif stage == STAGE_SELECT_OUTPUT then
        drawLine(68, "Step 2: Choose output folder, then press START to decode", GREEN)
    else
        drawLine(68, "Completed. Press START to begin another job", GREEN)
    end

    drawLine(92, "Input:  " .. (selectedInputFile or "<none>"), WHITE)
    drawLine(112, "Output: " .. (selectedOutputDir or "<none>"), WHITE)
    drawLine(132, statusMessage, YELLOW)

    local startY = 168
    local maxRows = 11
    local firstRow = 1

    if cursorIndex > maxRows then
        firstRow = cursorIndex - maxRows + 1
    end

    if #currentEntries == 0 then
        drawLine(startY, "<empty directory>", RED)
    else
        for row = 0, maxRows - 1 do
            local index = firstRow + row
            local entry = currentEntries[index]
            if entry then
                local prefix = (index == cursorIndex) and "> " or "  "
                local color = (index == cursorIndex) and GREEN or WHITE
                drawLine(startY + row * 20, prefix .. formatEntry(entry), color)
            end
        end
    end

    drawLine(396, "UP/DOWN Move   CROSS Enter/Select   CIRCLE Up   START Confirm   TRIANGLE Exit", GRAY)
    Screen.flip()
end

refreshEntries()

while true do
    local pad = Pads.get(0)

    if wasPressed(pad, PAD_UP) then
        moveCursor(-1)
    end

    if wasPressed(pad, PAD_DOWN) then
        moveCursor(1)
    end

    if wasPressed(pad, PAD_CROSS) then
        handleCross(currentEntries[cursorIndex])
    end

    if wasPressed(pad, PAD_CIRCLE) then
        handleCircle()
    end

    if wasPressed(pad, PAD_START) then
        handleStart()
    end

    if wasPressed(pad, PAD_TRIANGLE) then
        Font.fmUnload()
        System.exitToBrowser()
    end

    drawUI()
    Screen.waitVblankStart()
    previousPad = pad
end
