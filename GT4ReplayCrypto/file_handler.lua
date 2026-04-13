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
local CYAN   = Color.new(120, 220, 255)
local BG     = Color.new(18, 24, 40)
local PANEL  = Color.new(28, 36, 58)

local STATE_MODE   = 1
local STATE_FOLDER = 2
local STATE_RUN    = 3
local STATE_DONE   = 4

local state = STATE_MODE
local previousPad = 0

local browserPath = System.currentDirectory()
if browserPath == nil or browserPath == "" then
    browserPath = "host:"
end

local currentEntries = {}
local cursorIndex = 1
local scrollOffset = 1
local statusMessage = "Choose a mode."
local selectedFolder = nil
local currentModeIndex = 1
local batchState = nil

local MODES = {
    {
        key = "decode",
        label = "Decode",
        suffix = "_decrypted",
        description = "Decode saved replay files",
    },
    {
        key = "replay",
        label = "Encode Replay",
        suffix = "_replay",
        description = "Encode decrypted replay into replay as saved type",
    },
    {
        key = "demo",
        label = "Encode Demo",
        suffix = "_demo",
        description = "Encode decrypted replay into replay as demo type",
    },
}

local function trimTrailingSlash(path)
    if path == nil then
        return ""
    end
    if string.match(path, "^[^:]+:/$") then
        return path
    end
    return string.gsub(path, "/+$", "")
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

    local data = System.readFile(fd, size)
    System.closeFile(fd)

    if data == nil then
        return nil, "Failed to read file data: " .. path
    end

    return data, size
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

local function writeTextFile(path, text)
    local fd = System.openFile(path, O_WRONLY | O_CREAT | O_TRUNC)
    if fd == nil or fd < 0 then
        return false
    end
    System.writeFile(fd, text, string.len(text))
    System.closeFile(fd)
    return true
end

local function ensureDirectory(path)
    if doesFileExist(path) then
        return true
    end
    local result = System.createDirectory(path)
    return result == 0 or doesFileExist(path)
end

local function justPressed(currentPad, button)
    return Pads.check(currentPad, button) and not Pads.check(previousPad, button)
end

local function drawText(x, y, scale, text, color)
    Font.fmPrint(x, y, scale, text, color or WHITE)
end

local function drawBackground()
    Screen.clear(BG)
    Graphics.drawRect(10, 10, 620, 428, PANEL)
    Graphics.drawRect(10, 10, 620, 34, Color.new(36, 48, 78))
end

local function currentMode()
    return MODES[currentModeIndex]
end

local function getOutputFolderForMode(inputFolder, mode)
    local parent = getParentPath(trimTrailingSlash(inputFolder))
    local base = getBaseName(inputFolder)
    return joinPath(parent, base .. mode.suffix)
end

local function listDirectoryEntries(path)
    local raw = System.listDirectory(path) or {}
    local items = {}

    if not isRootPath(path) then
        items[#items + 1] = {
            name = "..",
            directory = true,
            path = getParentPath(path),
            parent = true,
        }
    end

    for i = 1, #raw do
        local entry = raw[i]
        if entry.name ~= "." and entry.name ~= ".." and entry.directory == true then
            items[#items + 1] = {
                name = entry.name,
                directory = true,
                path = joinPath(path, entry.name),
                parent = false,
            }
        end
    end

    table.sort(items, function(a, b)
        if a.parent ~= b.parent then
            return a.parent
        end
        return string.lower(a.name) < string.lower(b.name)
    end)

    return items
end


local function shouldSkipFile(name)
    if name == nil then
        return true
    end
    return string.lower(name) == "batch_log.txt"
end

local function countFilesInDirectory(path)
    local raw = System.listDirectory(path) or {}
    local count = 0
    for i = 1, #raw do
        local entry = raw[i]
        if entry.name ~= "." and entry.name ~= ".." and entry.directory ~= true and not shouldSkipFile(entry.name) then
            count = count + 1
        end
    end
    return count
end

local function refreshFolderEntries()
    currentEntries = listDirectoryEntries(browserPath)
    if cursorIndex < 1 then
        cursorIndex = 1
    end
    if cursorIndex > #currentEntries then
        cursorIndex = math.max(1, #currentEntries)
    end
    if scrollOffset < 1 then
        scrollOffset = 1
    end
end

local function clampScroll()
    local visibleCount = 14
    if cursorIndex < scrollOffset then
        scrollOffset = cursorIndex
    elseif cursorIndex > scrollOffset + visibleCount - 1 then
        scrollOffset = cursorIndex - visibleCount + 1
    end

    if scrollOffset < 1 then
        scrollOffset = 1
    end
end

local function processFileByMode(modeKey, inputData)
    if modeKey == "decode" then
        return GT4ReplayCrypto.decryptReplayString(inputData)
    elseif modeKey == "replay" then
        return GT4ReplayCrypto.makeReplayPayloadString(inputData)
    elseif modeKey == "demo" then
        return GT4ReplayCrypto.makeDemoSerializeReplayString(inputData)
    end

    return nil, nil, "Unknown mode."
end

local function formatVersion(info)
    if info and info.serialize then
        return string.format("%d.%d", info.serialize.major_version or 0, info.serialize.minor_version or 0)
    end
    return "?.?"
end

local function buildOutputName(modeKey, sourceName)
    return sourceName
end

local function beginBatch(folderPath)
    local mode = currentMode()
    local raw = System.listDirectory(folderPath) or {}
    local files = {}

    for i = 1, #raw do
        local entry = raw[i]
        if entry.name ~= "." and entry.name ~= ".." and entry.directory ~= true and not shouldSkipFile(entry.name) then
            files[#files + 1] = {
                name = entry.name,
                path = joinPath(folderPath, entry.name),
            }
        end
    end

    table.sort(files, function(a, b)
        return string.lower(a.name) < string.lower(b.name)
    end)

    local outputDir = getOutputFolderForMode(folderPath, mode)
    if not ensureDirectory(outputDir) then
        statusMessage = "Failed to create output folder: " .. outputDir
        return false
    end

    batchState = {
        mode = mode,
        inputDir = folderPath,
        outputDir = outputDir,
        files = files,
        index = 1,
        success = 0,
        failed = 0,
        skipped = 0,
        logLines = {},
        lastResult = "",
    }

    selectedFolder = folderPath
    state = STATE_RUN

    if #files == 0 then
        batchState.lastResult = "No files found in folder."
    else
        batchState.lastResult = "Starting batch..."
    end

    return true
end

local function writeBatchLog()
    if not batchState then
        return
    end

    local lines = {}
    lines[#lines + 1] = "Mode: " .. tostring(batchState.mode.label)
    lines[#lines + 1] = "InputDir: " .. tostring(batchState.inputDir)
    lines[#lines + 1] = "OutputDir: " .. tostring(batchState.outputDir)
    lines[#lines + 1] = string.format("Success: %d", batchState.success)
    lines[#lines + 1] = string.format("Failed: %d", batchState.failed)
    lines[#lines + 1] = string.format("Skipped: %d", batchState.skipped)
    lines[#lines + 1] = ""

    for i = 1, #batchState.logLines do
        lines[#lines + 1] = batchState.logLines[i]
    end

    writeTextFile(joinPath(batchState.outputDir, "batch_log.txt"), table.concat(lines, "\n"))
end

local function finishBatch()
    writeBatchLog()
    state = STATE_DONE
    if batchState.failed == 0 then
        statusMessage = string.format(
            "%s finished. %d files written to %s",
            batchState.mode.label,
            batchState.success,
            batchState.outputDir
        )
    else
        statusMessage = string.format(
            "%s finished. %d ok, %d failed. See batch_log.txt",
            batchState.mode.label,
            batchState.success,
            batchState.failed
        )
    end
end

local function processNextBatchItem()
    if not batchState then
        return
    end

    if batchState.index > #batchState.files then
        finishBatch()
        return
    end

    local item = batchState.files[batchState.index]
    local outputName = buildOutputName(batchState.mode.key, item.name)
    local outputPath = joinPath(batchState.outputDir, outputName)

    local inputData, readErr = readEntireFile(item.path)
    if not inputData then
        batchState.failed = batchState.failed + 1
        batchState.logLines[#batchState.logLines + 1] = "[FAIL] " .. item.name .. " - " .. tostring(readErr)
        batchState.lastResult = "Failed: " .. item.name
        batchState.index = batchState.index + 1
        return
    end

    local outputData, info, processErr = processFileByMode(batchState.mode.key, inputData)
    if not outputData then
        batchState.failed = batchState.failed + 1
        batchState.logLines[#batchState.logLines + 1] = "[FAIL] " .. item.name .. " - " .. tostring(processErr)
        batchState.lastResult = "Failed: " .. item.name
        batchState.index = batchState.index + 1
        return
    end

    local ok, writeErr = writeEntireFile(outputPath, outputData)
    if not ok then
        batchState.failed = batchState.failed + 1
        batchState.logLines[#batchState.logLines + 1] = "[FAIL] " .. item.name .. " - " .. tostring(writeErr)
        batchState.lastResult = "Failed write: " .. item.name
        batchState.index = batchState.index + 1
        return
    end

    batchState.success = batchState.success + 1
    batchState.logLines[#batchState.logLines + 1] = string.format(
        "[OK] %s -> %s | version=%s | %s -> %s",
        item.name,
        outputName,
        formatVersion(info),
        tostring(info and info.input_layout or "unknown"),
        tostring(info and info.output_layout or "unknown")
    )
    batchState.lastResult = "Processed: " .. item.name
    batchState.index = batchState.index + 1
end

local function updateModeInput(currentPad)
    if justPressed(currentPad, PAD_UP) then
        currentModeIndex = currentModeIndex - 1
        if currentModeIndex < 1 then
            currentModeIndex = #MODES
        end
    elseif justPressed(currentPad, PAD_DOWN) then
        currentModeIndex = currentModeIndex + 1
        if currentModeIndex > #MODES then
            currentModeIndex = 1
        end
    elseif justPressed(currentPad, PAD_CROSS) then
        state = STATE_FOLDER
        browserPath = System.currentDirectory() or browserPath
        refreshFolderEntries()
        statusMessage = "Browse to a folder, then press START to batch process it."
    elseif justPressed(currentPad, PAD_TRIANGLE) then
        System.exitToBrowser()
    end
end

local function updateFolderInput(currentPad)
    if justPressed(currentPad, PAD_UP) then
        cursorIndex = cursorIndex - 1
        if cursorIndex < 1 then
            cursorIndex = math.max(1, #currentEntries)
        end
    elseif justPressed(currentPad, PAD_DOWN) then
        cursorIndex = cursorIndex + 1
        if cursorIndex > #currentEntries then
            cursorIndex = 1
        end
    elseif justPressed(currentPad, PAD_CROSS) then
        local entry = currentEntries[cursorIndex]
        if entry and entry.directory then
            browserPath = entry.path
            cursorIndex = 1
            scrollOffset = 1
            refreshFolderEntries()
        end
    elseif justPressed(currentPad, PAD_CIRCLE) then
        browserPath = getParentPath(browserPath)
        cursorIndex = 1
        scrollOffset = 1
        refreshFolderEntries()
    elseif justPressed(currentPad, PAD_START) then
        beginBatch(browserPath)
    elseif justPressed(currentPad, PAD_SELECT) then
        state = STATE_MODE
        statusMessage = "Choose a mode."
    elseif justPressed(currentPad, PAD_TRIANGLE) then
        System.exitToBrowser()
    end

    clampScroll()
end

local function updateRunInput(currentPad)
    if justPressed(currentPad, PAD_TRIANGLE) then
        System.exitToBrowser()
        return
    end

    processNextBatchItem()
end

local function updateDoneInput(currentPad)
    if justPressed(currentPad, PAD_CROSS) then
        state = STATE_FOLDER
        statusMessage = "Browse to another folder, then press START to batch process it."
        refreshFolderEntries()
    elseif justPressed(currentPad, PAD_SELECT) then
        state = STATE_MODE
        statusMessage = "Choose a mode."
    elseif justPressed(currentPad, PAD_TRIANGLE) then
        System.exitToBrowser()
    end
end

local function drawModeScreen()
    local mode = currentMode()

    drawText(20, 18, 0.8, "GT4 Replay Batch Tool", WHITE)
    drawText(20, 42, 0.6, "Choose operation", CYAN)

    local y = 86
    for i = 1, #MODES do
        local item = MODES[i]
        local color = (i == currentModeIndex) and GREEN or WHITE
        local prefix = (i == currentModeIndex) and "> " or "  "
        drawText(32, y, 0.55, prefix .. item.label, color)
        y = y + 26
    end

    drawText(20, 196, 0.5, mode.description, YELLOW)
    drawText(20, 226, 0.5, "Output folder suffix: " .. mode.suffix, GRAY)

    drawText(20, 382, 0.45, "UP/DOWN = choose  CROSS = continue  TRIANGLE = exit", GRAY)
    drawText(20, 404, 0.45, statusMessage, WHITE)
end

local function drawFolderScreen()
    local mode = currentMode()
    local outputDir = getOutputFolderForMode(browserPath, mode)
    local fileCount = countFilesInDirectory(browserPath)

    drawText(20, 18, 0.8, "GT4 Replay Batch Tool", WHITE)
    drawText(20, 42, 0.55, "Mode: " .. mode.label, CYAN)
    drawText(20, 64, 0.45, "Current folder: " .. browserPath, GRAY)
    drawText(20, 84, 0.45, "Files to process: " .. tostring(fileCount), GRAY)
    drawText(20, 104, 0.45, "Output folder: " .. outputDir, YELLOW)

    local startY = 136
    local visibleCount = 14
    for row = 0, visibleCount - 1 do
        local index = scrollOffset + row
        local entry = currentEntries[index]
        if entry then
            local color = (index == cursorIndex) and GREEN or WHITE
            local prefix = entry.parent and "[..] " or "[DIR] "
            drawText(36, startY + row * 20, 0.45, prefix .. entry.name, color)
        end
    end

    drawText(20, 382, 0.45, "CROSS = open folder  CIRCLE = parent  START = use current folder", GRAY)
    drawText(20, 402, 0.45, "SELECT = mode menu  TRIANGLE = exit", GRAY)
    drawText(20, 422, 0.45, statusMessage, WHITE)
end

local function drawRunScreen()
    local total = 0
    local current = 0
    if batchState then
        total = #batchState.files
        current = math.min(batchState.index, total)
    end

    drawText(20, 18, 0.8, "GT4 Replay Batch Tool", WHITE)
    drawText(20, 42, 0.55, "Running: " .. tostring(batchState and batchState.mode.label or ""), CYAN)
    drawText(20, 66, 0.45, "Input: " .. tostring(batchState and batchState.inputDir or ""), GRAY)
    drawText(20, 86, 0.45, "Output: " .. tostring(batchState and batchState.outputDir or ""), YELLOW)

    drawText(20, 136, 0.55, string.format("Progress: %d / %d", current, total), WHITE)
    drawText(20, 164, 0.5, "Success: " .. tostring(batchState and batchState.success or 0), GREEN)
    drawText(20, 186, 0.5, "Failed: " .. tostring(batchState and batchState.failed or 0), RED)
    drawText(20, 208, 0.5, "Last: " .. tostring(batchState and batchState.lastResult or ""), WHITE)

    drawText(20, 392, 0.45, "Please keep this screen open while files are processed.", GRAY)
    drawText(20, 414, 0.45, "TRIANGLE = exit", GRAY)
end

local function drawDoneScreen()
    drawText(20, 18, 0.8, "GT4 Replay Batch Tool", WHITE)
    drawText(20, 42, 0.55, "Finished: " .. tostring(batchState and batchState.mode.label or ""), CYAN)

    if batchState then
        drawText(20, 86, 0.5, "Input folder: " .. batchState.inputDir, GRAY)
        drawText(20, 108, 0.5, "Output folder: " .. batchState.outputDir, YELLOW)
        drawText(20, 152, 0.55, "Success: " .. tostring(batchState.success), GREEN)
        drawText(20, 176, 0.55, "Failed: " .. tostring(batchState.failed), RED)
        drawText(20, 200, 0.55, "Skipped: " .. tostring(batchState.skipped), WHITE)
        drawText(20, 224, 0.5, "Log saved as batch_log.txt", GRAY)
    end

    drawText(20, 382, 0.45, "CROSS = choose another folder  SELECT = change mode  TRIANGLE = exit", GRAY)
    drawText(20, 404, 0.45, statusMessage, WHITE)
end

refreshFolderEntries()

while true do
    local currentPad = Pads.get()

    drawBackground()
    if state == STATE_MODE then
        updateModeInput(currentPad)
        drawModeScreen()
    elseif state == STATE_FOLDER then
        updateFolderInput(currentPad)
        drawFolderScreen()
    elseif state == STATE_RUN then
        updateRunInput(currentPad)
        drawRunScreen()
    elseif state == STATE_DONE then
        updateDoneInput(currentPad)
        drawDoneScreen()
    end

    Screen.flip()
    Screen.waitVblankStart()
    previousPad = currentPad
end
