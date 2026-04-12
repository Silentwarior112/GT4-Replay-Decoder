local MTRandom = rawget(_G, "__MTRandomModule") or dofile("GT4ReplayCrypto/MTRandom.lua")
local CRC32 = rawget(_G, "__CRC32Module") or dofile("GT4ReplayCrypto/CRC32.lua")

local SharedCrypto = {}

SharedCrypto.EncryptUnit_HdrLen = 0x08

local function u32(value)
    return value & 0xFFFFFFFF
end

local function f32(value)
    return string.unpack("<f", string.pack("<f", value))
end

local function read_u32_le(bytes, index)
    return u32(
        bytes[index]
        | (bytes[index + 1] << 8)
        | (bytes[index + 2] << 16)
        | (bytes[index + 3] << 24)
    )
end

local function write_u32_le(bytes, index, value)
    local v = u32(value)
    bytes[index] = v & 0xFF
    bytes[index + 1] = (v >> 8) & 0xFF
    bytes[index + 2] = (v >> 16) & 0xFF
    bytes[index + 3] = (v >> 24) & 0xFF
end

local function bit_reverse(value)
    local left = 1 << 31
    local right = 1
    local result = 0

    for i = 31, 1, -2 do
        result = result | ((value & left) >> i)
        result = result | ((value & right) << i)
        left = left >> 1
        right = right << 1
    end

    return u32(result)
end

local function rotate_right(value, amount)
    local shift = amount & 31
    if shift == 0 then
        return u32(value)
    end

    return u32((value >> shift) | (value << (32 - shift)))
end

function SharedCrypto.RandomUpdateOld1(randValue, useOld)
    local v1 = u32(17 * randValue + 17)
    local updatedRandValue = v1

    if useOld then
        return updatedRandValue, u32(v1 ~ u32((v1 << 16) | (v1 >> 16)))
    end

    local reversed = bit_reverse(updatedRandValue)
    local reordered = u32(
        (reversed << 24)
        | ((reversed & 0x0000FF00) << 8)
        | (reversed >> 24)
        | ((reversed >> 8) & 0x0000FF00)
    )

    local shifted = u32(reordered << 8)
    shifted = u32(shifted + reordered)
    shifted = u32(shifted + 0x101)

    return updatedRandValue, u32(reordered ~ rotate_right(shifted, 16))
end

function SharedCrypto.GT4MC_swapPlace2(bytes, startIndex, size, count, offsetToSwapAt)
    if count == 0 then
        return
    end

    local startPos = startIndex or 1

    for i = 0, count - 1 do
        local aIndex = startPos + offsetToSwapAt + i
        local bIndex = startPos + i
        bytes[aIndex], bytes[bIndex] = bytes[bIndex], bytes[aIndex]
    end
end

function SharedCrypto.GT4MC_swapPlace(bytes, startIndex, size, count, mult)
    local mult32 = f32(mult)
    local offsetToSwapAt = math.floor(mult32 * (size - count))
    SharedCrypto.GT4MC_swapPlace2(bytes, startIndex, size, count, offsetToSwapAt)
    return offsetToSwapAt
end

function SharedCrypto.GT4MC_easyDecrypt(bytes, startIndex, len, rand, seed, useOld)
    local pos = 0
    local index = startIndex

    while pos + 4 <= len do
        local pseudoRandVal = rand:getInt32()
        local newSeed, updated = SharedCrypto.RandomUpdateOld1(seed, useOld)
        seed = newSeed

        local current = read_u32_le(bytes, index)
        local result = u32((current + updated) ~ pseudoRandVal)
        write_u32_le(bytes, index, result)

        pos = pos + 4
        index = index + 4
    end

    while pos < len do
        local pseudoRandVal = rand:getInt32()
        local newSeed, updated = SharedCrypto.RandomUpdateOld1(seed, useOld)
        seed = newSeed

        local result = u32((bytes[index] + updated) ~ pseudoRandVal)
        bytes[index] = result & 0xFF

        pos = pos + 1
        index = index + 1
    end

    return seed
end

function SharedCrypto.GT4MC_easyEncrypt(bytes, startIndex, len, rand, seed, useOld)
    local pos = 0
    local index = startIndex

    while pos + 4 <= len do
        local value = read_u32_le(bytes, index)
        local pseudoRandVal = rand:getInt32()
        local newSeed, updated = SharedCrypto.RandomUpdateOld1(seed, useOld)
        seed = newSeed

        local result = u32((value ~ pseudoRandVal) - updated)
        write_u32_le(bytes, index, result)

        pos = pos + 4
        index = index + 4
    end

    while pos < len do
        local value = bytes[index]
        local pseudoRandVal = rand:getInt32()
        local newSeed, updated = SharedCrypto.RandomUpdateOld1(seed, useOld)
        seed = newSeed

        local result = u32((value ~ pseudoRandVal) - updated)
        bytes[index] = result & 0xFF

        pos = pos + 1
        index = index + 1
    end

    return seed
end

function SharedCrypto.EncryptUnit_Decrypt(bytes, length, crcSeed, mult1, mult2, useMt, bigEndian, randomUpdateOld1_OldVersion)
    if bigEndian then
        return -1, "Big-endian decrypt is not implemented in this Lua port."
    end

    if length < 8 then
        return -1, "Buffer too small."
    end

    local actualDataSize = length - 8

    local swapOffset2 = SharedCrypto.GT4MC_swapPlace(bytes, 1, length, 4, mult2)

    if useMt then
        return -1, "MT pre-processing is not implemented in this decrypt path."
    end

    local swapOffset1 = SharedCrypto.GT4MC_swapPlace(bytes, 5, length - 4, 4, mult1)

    local cryptoRand = read_u32_le(bytes, 1)
    local dataCrc = read_u32_le(bytes, 5)
    local seed = u32(dataCrc + cryptoRand)
    local rand = MTRandom.new(seed)

    local startCipher = u32(dataCrc ~ cryptoRand)
    SharedCrypto.GT4MC_easyDecrypt(bytes, 9, actualDataSize, rand, startCipher, randomUpdateOld1_OldVersion)

    write_u32_le(bytes, 5, read_u32_le(bytes, 5) ~ (crcSeed or 0))

    local storedCrc = read_u32_le(bytes, 5)
    local calculatedCrc = CRC32.crc32_0x77073096(bytes, 9, actualDataSize)

    if storedCrc == calculatedCrc then
        return actualDataSize
    end

    return -1, string.format("[v5] CRC check failed. stored=%08X calculated=%08X rand=%08X dataCrc=%08X startCipher=%08X swap1=%d swap2=%d", storedCrc, calculatedCrc, cryptoRand, dataCrc, startCipher, swapOffset1 or -1, swapOffset2 or -1)
end

function SharedCrypto.EncryptUnit_Encrypt(bytes, length, crcSeed, mult1, mult2, useMt, bigEndian, randomUpdateOld1_OldVersion, randVal)
    if bigEndian then
        return false, "Big-endian encrypt is not implemented in this Lua port."
    end

    if length < 8 then
        return false, "Buffer too small."
    end

    if useMt then
        return false, "MT pre-processing is not implemented in this encrypt path."
    end

    local actualDataSize = length - 8
    local dataCrc = u32(CRC32.crc32_0x77073096(bytes, 9, actualDataSize) ~ (crcSeed or 0))
    local headerRand = u32(randVal or 0x12345678)

    write_u32_le(bytes, 1, headerRand)
    write_u32_le(bytes, 5, dataCrc)

    local rand = MTRandom.new(u32(dataCrc + headerRand))
    local startCipher = u32(dataCrc ~ headerRand)
    SharedCrypto.GT4MC_easyEncrypt(bytes, 9, actualDataSize, rand, startCipher, randomUpdateOld1_OldVersion)

    local swapOffset1 = SharedCrypto.GT4MC_swapPlace(bytes, 5, length - 4, 4, mult1)
    local swapOffset2 = SharedCrypto.GT4MC_swapPlace(bytes, 1, length, 4, mult2)

    return true, {
        rand = headerRand,
        dataCrc = dataCrc,
        startCipher = startCipher,
        swap1 = swapOffset1,
        swap2 = swapOffset2,
    }
end

return SharedCrypto
