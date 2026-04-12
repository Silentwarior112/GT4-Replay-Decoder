local CRC32 = {}

local POLY1 = 0xEDB88320
CRC32.checksum_0x77073096 = {}

local function u32(value)
    return value & 0xFFFFFFFF
end

local function init_crc_tables()
    for i = 0, 255 do
        local fwd = i
        for _ = 1, 8 do
            if (fwd & 1) == 1 then
                fwd = u32((fwd >> 1) ~ POLY1)
            else
                fwd = u32(fwd >> 1)
            end
        end

        CRC32.checksum_0x77073096[i] = fwd
    end
end

function CRC32.crc32_0x77073096(bytes, startIndex, length)
    local checksum = 0xFFFFFFFF
    local startPos = startIndex or 1
    local finalPos = startPos + length - 1

    for i = startPos, finalPos do
        checksum = u32(CRC32.checksum_0x77073096[(checksum ~ bytes[i]) & 0xFF] ~ (checksum >> 8))
    end

    return u32(~checksum)
end

init_crc_tables()

return CRC32
