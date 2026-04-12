local SharedCrypto = dofile("GT4ReplayCrypto/sharedCrypto.lua")

local GT4ReplayCrypto = {}

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

local function read_i32_le(bytes, index)
    local value = read_u32_le(bytes, index)
    if value >= 0x80000000 then
        return value - 0x100000000
    end
    return value
end

local function read_u16_le(bytes, index)
    return (bytes[index] | (bytes[index + 1] << 8)) & 0xFFFF
end

local function bytes_from_string(input)
    local bytes = {}
    for i = 1, #input do
        bytes[i] = string.byte(input, i)
    end
    return bytes
end

local function string_from_bytes(bytes, startIndex)
    local startAt = startIndex or 1
    local parts = {}
    local chunkSize = 4096
    for chunkStart = startAt, #bytes, chunkSize do
        local chunk = {}
        local lastIndex = math.min(chunkStart + chunkSize - 1, #bytes)
        for i = chunkStart, lastIndex do
            chunk[#chunk + 1] = string.char(bytes[i])
        end
        parts[#parts + 1] = table.concat(chunk)
    end
    return table.concat(parts)
end

local function clone_bytes(bytes)
    local copy = {}
    for i = 1, #bytes do
        copy[i] = bytes[i]
    end
    return copy
end

local function u32_to_float(value)
    return string.unpack("<f", string.pack("<I4", u32(value)))
end

local function float_to_u32(value)
    return string.unpack("<I4", string.pack("<f", value))
end

GT4ReplayCrypto.Mult1 = f32(0.22973239)
GT4ReplayCrypto.Mult2 = f32(0.69584757)

GT4ReplayCrypto.FloatTable = {
    1.001955, 1.0058651, 1.0097752, 1.0136852, 1.0175953, 1.0215054,
    1.0254154, 1.0293255, 1.0332355, 1.0371456, 1.0410557, 1.0449657,
    1.0488758, 1.0527859, 1.0566959, 1.060606, 1.0645161, 1.0684261,
    1.0723362, 1.0762463, 1.0801563, 1.0840664, 1.0879765, 1.0918865,
    1.0957966, 1.0997066, 1.1036167, 1.1075268, 1.1114368, 1.1153469,
    1.119257, 1.123167, 1.1270772, 1.1309873, 1.1348974, 1.1388074,
    1.1427175, 1.1466275, 1.1505376, 1.1544477, 1.1583577, 1.1622678,
    1.1661779, 1.1700879, 1.173998, 1.1779081, 1.1818181, 1.1857282,
    1.1896383, 1.1935483, 1.1974584, 1.2013685, 1.2052785, 1.2091886,
    1.2130986, 1.2170087, 1.2209188, 1.2248288, 1.2287389, 1.232649,
    1.236559, 1.2404691, 1.2443792, 1.2482892, 1.2521994, 1.2561095,
    1.2600195, 1.2639296, 1.2678397, 1.2717497, 1.2756598, 1.2795699,
    1.2834799, 1.28739, 1.2913001, 1.2952101, 1.2991202, 1.3030303,
    1.3069403, 1.3108504, 1.3147604, 1.3186705, 1.3225806, 1.3264906,
    1.3304007, 1.3343108, 1.3382208, 1.3421309, 1.346041, 1.349951,
    1.3538611, 1.3577712, 1.3616812, 1.3655913, 1.3695014, 1.3734114,
    1.3773216, 1.3812317, 1.3851417, 1.3890518, 1.3929619, 1.3968719,
    1.400782, 1.4046921, 1.4086021, 1.4125122, 1.4164222, 1.4203323,
    1.4242424, 1.4281524, 1.4320625, 1.4359726, 1.4398826, 1.4437927,
    1.4477028, 1.4516128, 1.4555229, 1.459433, 1.463343, 1.4672531,
    1.4711632, 1.4750732, 1.4789833, 1.4828933, 1.4868034, 1.4907135,
    1.4946235, 1.4985336, 1.5024438, 1.5063539, 1.5102639, 1.514174,
    1.518084, 1.5219941, 1.5259042, 1.5298142, 1.5337243, 1.5376344,
    1.5415444, 1.5454545, 1.5493646, 1.5532746, 1.5571847, 1.5610948,
    1.5650048, 1.5689149, 1.572825, 1.576735, 1.5806451, 1.5845551,
    1.5884652, 1.5923753, 1.5962853, 1.6001954, 1.6041055, 1.6080155,
    1.6119256, 1.6158357, 1.6197457, 1.6236558, 1.627566, 1.631476,
    1.6353861, 1.6392962, 1.6432062, 1.6471163, 1.6510264, 1.6549364,
    1.6588465, 1.6627566, 1.6666666, 1.6705767, 1.6744868, 1.6783968,
    1.6823069, 1.686217, 1.690127, 1.6940371, 1.6979471, 1.7018572,
    1.7057673, 1.7096773, 1.7135874, 1.7174975, 1.7214075, 1.7253176,
    1.7292277, 1.7331377, 1.7370478, 1.7409579, 1.7448679, 1.748778,
    1.7526882, 1.7565982, 1.7605083, 1.7644184, 1.7683284, 1.7722385,
    1.7761486, 1.7800586, 1.7839687, 1.7878788, 1.7917888, 1.7956989,
    1.7996089, 1.803519, 1.8074291, 1.8113391, 1.8152492, 1.8191593,
    1.8230693, 1.8269794, 1.8308895, 1.8347995, 1.8387096, 1.8426197,
    1.8465297, 1.8504398, 1.8543499, 1.8582599, 1.86217, 1.86608,
    1.8699901, 1.8739002, 1.8778104, 1.8817204, 1.8856305, 1.8895406,
    1.8934506, 1.8973607, 1.9012707, 1.9051808, 1.9090909, 1.9130009,
    1.916911, 1.9208211, 1.9247311, 1.9286412, 1.9325513, 1.9364613,
    1.9403714, 1.9442815, 1.9481915, 1.9521016, 1.9560117, 1.9599217,
    1.9638318, 1.9677418, 1.9716519, 1.975562, 1.979472, 1.9833821,
    1.9872922, 1.9912022, 1.9951123, 1.9990224,
}

GT4ReplayCrypto.ShufTable = {
    0x00, 0x80, 0x40, 0xC0, 0x20, 0xA0, 0x60, 0xE0, 0x10, 0x90, 0x50, 0xD0,
    0x30, 0xB0, 0x70, 0xF0, 0x08, 0x88, 0x48, 0xC8, 0x28, 0xA8, 0x68, 0xE8,
    0x18, 0x98, 0x58, 0xD8, 0x38, 0xB8, 0x78, 0xF8, 0x04, 0x84, 0x44, 0xC4,
    0x24, 0xA4, 0x64, 0xE4, 0x14, 0x94, 0x54, 0xD4, 0x34, 0xB4, 0x74, 0xF4,
    0x0C, 0x8C, 0x4C, 0xCC, 0x2C, 0xAC, 0x6C, 0xEC, 0x1C, 0x9C, 0x5C, 0xDC,
    0x3C, 0xBC, 0x7C, 0xFC, 0x02, 0x82, 0x42, 0xC2, 0x22, 0xA2, 0x62, 0xE2,
    0x12, 0x92, 0x52, 0xD2, 0x32, 0xB2, 0x72, 0xF2, 0x0A, 0x8A, 0x4A, 0xCA,
    0x2A, 0xAA, 0x6A, 0xEA, 0x1A, 0x9A, 0x5A, 0xDA, 0x3A, 0xBA, 0x7A, 0xFA,
    0x06, 0x86, 0x46, 0xC6, 0x26, 0xA6, 0x66, 0xE6, 0x16, 0x96, 0x56, 0xD6,
    0x36, 0xB6, 0x76, 0xF6, 0x0E, 0x8E, 0x4E, 0xCE, 0x2E, 0xAE, 0x6E, 0xEE,
    0x1E, 0x9E, 0x5E, 0xDE, 0x3E, 0xBE, 0x7E, 0xFE, 0x01, 0x81, 0x41, 0xC1,
    0x21, 0xA1, 0x61, 0xE1, 0x11, 0x91, 0x51, 0xD1, 0x31, 0xB1, 0x71, 0xF1,
    0x09, 0x89, 0x49, 0xC9, 0x29, 0xA9, 0x69, 0xE9, 0x19, 0x99, 0x59, 0xD9,
    0x39, 0xB9, 0x79, 0xF9, 0x05, 0x85, 0x45, 0xC5, 0x25, 0xA5, 0x65, 0xE5,
    0x15, 0x95, 0x55, 0xD5, 0x35, 0xB5, 0x75, 0xF5, 0x0D, 0x8D, 0x4D, 0xCD,
    0x2D, 0xAD, 0x6D, 0xED, 0x1D, 0x9D, 0x5D, 0xDD, 0x3D, 0xBD, 0x7D, 0xFD,
    0x03, 0x83, 0x43, 0xC3, 0x23, 0xA3, 0x63, 0xE3, 0x13, 0x93, 0x53, 0xD3,
    0x33, 0xB3, 0x73, 0xF3, 0x0B, 0x8B, 0x4B, 0xCB, 0x2B, 0xAB, 0x6B, 0xEB,
    0x1B, 0x9B, 0x5B, 0xDB, 0x3B, 0xBB, 0x7B, 0xFB, 0x07, 0x87, 0x47, 0xC7,
    0x27, 0xA7, 0x67, 0xE7, 0x17, 0x97, 0x57, 0xD7, 0x37, 0xB7, 0x77, 0xF7,
    0x0F, 0x8F, 0x4F, 0xCF, 0x2F, 0xAF, 0x6F, 0xEF, 0x1F, 0x9F, 0x5F, 0xDF,
    0x3F, 0xBF, 0x7F, 0xFF,
}

function GT4ReplayCrypto.parseSerializeHeader(bytes, startIndex)
    local base = startIndex or 1
    if #bytes < base + 0x0F then
        return nil, "Replay is too small to contain the serialize header."
    end

    local headerSize = read_i32_le(bytes, base)
    local dataSize = read_u32_le(bytes, base + 0x04)
    local minorVersion = read_u16_le(bytes, base + 0x08)
    local majorVersion = read_u16_le(bytes, base + 0x0A)
    local encodeParam = read_u32_le(bytes, base + 0x0C)

    if headerSize < 0x10 then
        return nil, string.format("Invalid serialize header size: %d", headerSize)
    end

    local dataIndex = base + headerSize
    local dataEnd = dataIndex + dataSize - 1

    if dataIndex < 1 or dataIndex > (#bytes + 1) then
        return nil, "Serialize data start is out of bounds."
    end

    if dataSize > 0 and dataEnd > #bytes then
        return nil, "Serialize data length is out of bounds."
    end

    return {
        header_size = headerSize,
        data_size = dataSize,
        minor_version = minorVersion,
        major_version = majorVersion,
        encode_param = encodeParam,
        data_index = dataIndex,
        data_end = dataEnd,
        start_index = base,
    }
end

function GT4ReplayCrypto.hasSerializeHeader(bytes, startIndex)
    local info = GT4ReplayCrypto.parseSerializeHeader(bytes, startIndex)
    if not info then
        return false
    end

    if info.header_size ~= 0x40 then
        return false
    end

    if info.major_version ~= 4 and info.major_version ~= 5 then
        return false
    end

    return true
end

function GT4ReplayCrypto.inspectLayout(bytes)
    if GT4ReplayCrypto.hasSerializeHeader(bytes, 1) then
        return {
            layout = "serialize_only",
            serialize_index = 1,
            has_outer_header = false,
        }
    end

    if GT4ReplayCrypto.hasSerializeHeader(bytes, 9) then
        return {
            layout = "decrypted_wrapped",
            serialize_index = 9,
            has_outer_header = true,
        }
    end

    return {
        layout = "encrypted_wrapped",
        serialize_index = nil,
        has_outer_header = true,
    }
end

function GT4ReplayCrypto.CRC32_PS2_Float_Decrypt(bytes, startIndex, length, crc)
    local currentFloat = u32_to_float((crc & 0x00FFFFFF) | 0x3F000000)

    for i = 0, length - 1 do
        local currentVal = float_to_u32(currentFloat)
        local inByte = bytes[startIndex + i]

        bytes[startIndex + i] = (
            inByte
            ~ ((currentVal >> 16) & 0xFF)
            ~ ((currentVal >> 8) & 0xFF)
            ~ (currentVal & 0xFF)
        ) & 0xFF

        local denominatorBits = u32(
            (GT4ReplayCrypto.ShufTable[(currentVal & 0xFF) + 1] << 16)
            | (GT4ReplayCrypto.ShufTable[((currentVal >> 8) & 0xFF) + 1] << 8)
            | GT4ReplayCrypto.ShufTable[((currentVal >> 16) & 0xFF) + 1]
            | 0x3F000000
        )

        local numerator = f32(f32(GT4ReplayCrypto.FloatTable[inByte + 1]) * f32(currentFloat))
        currentFloat = f32(numerator / u32_to_float(denominatorBits))
    end
end

function GT4ReplayCrypto.CRC32_PS2_Float_Encrypt(bytes, startIndex, length, crc)
    local currentFloat = u32_to_float((crc & 0x00FFFFFF) | 0x3F000000)

    for i = 0, length - 1 do
        local currentVal = float_to_u32(currentFloat)
        local plainByte = bytes[startIndex + i]
        local outByte = (
            plainByte
            ~ ((currentVal >> 16) & 0xFF)
            ~ ((currentVal >> 8) & 0xFF)
            ~ (currentVal & 0xFF)
        ) & 0xFF

        bytes[startIndex + i] = outByte

        local denominatorBits = u32(
            (GT4ReplayCrypto.ShufTable[(currentVal & 0xFF) + 1] << 16)
            | (GT4ReplayCrypto.ShufTable[((currentVal >> 8) & 0xFF) + 1] << 8)
            | GT4ReplayCrypto.ShufTable[((currentVal >> 16) & 0xFF) + 1]
            | 0x3F000000
        )

        local numerator = f32(f32(GT4ReplayCrypto.FloatTable[outByte + 1]) * f32(currentFloat))
        currentFloat = f32(numerator / u32_to_float(denominatorBits))
    end
end

function GT4ReplayCrypto.decryptSerializeBytes(bytes, startIndex)
    local info, err = GT4ReplayCrypto.parseSerializeHeader(bytes, startIndex)
    if not info then
        return false, err
    end

    GT4ReplayCrypto.CRC32_PS2_Float_Decrypt(bytes, info.data_index, info.data_size, info.encode_param)
    return true, info
end

function GT4ReplayCrypto.encryptSerializeBytes(bytes, startIndex)
    local info, err = GT4ReplayCrypto.parseSerializeHeader(bytes, startIndex)
    if not info then
        return false, err
    end

    GT4ReplayCrypto.CRC32_PS2_Float_Encrypt(bytes, info.data_index, info.data_size, info.encode_param)
    return true, info
end

function GT4ReplayCrypto.decryptReplayBytesAuto(bytes)
    local initialLayout = GT4ReplayCrypto.inspectLayout(bytes)

    if initialLayout.layout == "serialize_only" then
        local ok, infoOrErr = GT4ReplayCrypto.decryptSerializeBytes(bytes, 1)
        if not ok then
            return false, infoOrErr
        end
        return true, {
            input_layout = initialLayout.layout,
            output_layout = "serialize_only",
            serialize = infoOrErr,
        }, bytes
    end

    if initialLayout.layout == "decrypted_wrapped" then
        local ok, infoOrErr = GT4ReplayCrypto.decryptSerializeBytes(bytes, 9)
        if not ok then
            return false, infoOrErr
        end
        return true, {
            input_layout = initialLayout.layout,
            output_layout = "decrypted_wrapped",
            serialize = infoOrErr,
        }, bytes
    end

    local result, err = SharedCrypto.EncryptUnit_Decrypt(
        bytes,
        #bytes,
        0,
        GT4ReplayCrypto.Mult1,
        GT4ReplayCrypto.Mult2,
        false,
        false,
        false
    )

    if result == -1 then
        return false, err or "EncryptUnit_Decrypt failed."
    end

    local postLayout = GT4ReplayCrypto.inspectLayout(bytes)
    if postLayout.layout ~= "decrypted_wrapped" then
        return false, "Replay decrypted but the serialize header was not found at offset 0x08."
    end

    local ok, infoOrErr = GT4ReplayCrypto.decryptSerializeBytes(bytes, 9)
    if not ok then
        return false, infoOrErr
    end

    return true, {
        input_layout = initialLayout.layout,
        output_layout = "decrypted_wrapped",
        serialize = infoOrErr,
    }, bytes
end

function GT4ReplayCrypto.encryptReplayBytesAuto(bytes, randVal)
    local layout = GT4ReplayCrypto.inspectLayout(bytes)
    local working = clone_bytes(bytes)

    if layout.layout == "serialize_only" then
        local ok, serializeInfoOrErr = GT4ReplayCrypto.encryptSerializeBytes(working, 1)
        if not ok then
            return false, serializeInfoOrErr
        end

        local wrapped = {}
        for i = 1, 8 do
            wrapped[i] = 0
        end
        for i = 1, #working do
            wrapped[8 + i] = working[i]
        end

        local cryptoOk, cryptoInfoOrErr = SharedCrypto.EncryptUnit_Encrypt(
            wrapped,
            #wrapped,
            0,
            GT4ReplayCrypto.Mult1,
            GT4ReplayCrypto.Mult2,
            false,
            false,
            false,
            randVal
        )

        if not cryptoOk then
            return false, cryptoInfoOrErr
        end

        return true, {
            input_layout = layout.layout,
            output_layout = "encrypted_wrapped",
            serialize = serializeInfoOrErr,
            crypto = cryptoInfoOrErr,
        }, wrapped
    end

    if layout.layout == "decrypted_wrapped" then
        local ok, serializeInfoOrErr = GT4ReplayCrypto.encryptSerializeBytes(working, 9)
        if not ok then
            return false, serializeInfoOrErr
        end

        local cryptoOk, cryptoInfoOrErr = SharedCrypto.EncryptUnit_Encrypt(
            working,
            #working,
            0,
            GT4ReplayCrypto.Mult1,
            GT4ReplayCrypto.Mult2,
            false,
            false,
            false,
            randVal
        )

        if not cryptoOk then
            return false, cryptoInfoOrErr
        end

        return true, {
            input_layout = layout.layout,
            output_layout = "encrypted_wrapped",
            serialize = serializeInfoOrErr,
            crypto = cryptoInfoOrErr,
        }, working
    end

    return false, "Input already looks like an encrypted wrapped replay. Use the decoder instead."
end

function GT4ReplayCrypto.decryptReplayString(inputData, outputMode)
    local bytes = bytes_from_string(inputData)
    local ok, infoOrErr, outputBytes = GT4ReplayCrypto.decryptReplayBytesAuto(bytes)
    if not ok then
        return nil, nil, infoOrErr
    end

    if outputMode == "payload_only" then
        local serializeIndex = 1
        if infoOrErr.output_layout == "decrypted_wrapped" then
            serializeIndex = 9
        end

        local serializeInfo, err = GT4ReplayCrypto.parseSerializeHeader(outputBytes, serializeIndex)
        if not serializeInfo then
            return nil, nil, err
        end

        return string_from_bytes(outputBytes, serializeInfo.data_index), {
            input_layout = infoOrErr.input_layout,
            output_layout = "payload_only",
            serialize = serializeInfo,
        }, nil
    end

    local startIndex = 1
    if outputMode == "serialize_only" and infoOrErr.output_layout == "decrypted_wrapped" then
        startIndex = 9
    end

    return string_from_bytes(outputBytes, startIndex), infoOrErr, nil
end


function GT4ReplayCrypto.makeDemoWrappedReplayBytes(bytes, randVal)
    local working = clone_bytes(bytes)

    local ok, encInfoOrErr, encryptedBytes = GT4ReplayCrypto.encryptReplayBytesAuto(working, randVal)
    if not ok then
        return false, encInfoOrErr
    end

    local ok2, decInfoOrErr, decryptedBytes = GT4ReplayCrypto.decryptReplayBytesAuto(clone_bytes(encryptedBytes))
    if not ok2 then
        return false, decInfoOrErr
    end

    return true, {
        input_layout = encInfoOrErr.input_layout,
        output_layout = "demo_wrapped",
        encrypted = encInfoOrErr,
        decrypted = decInfoOrErr,
        serialize = decInfoOrErr.serialize,
        crypto = encInfoOrErr.crypto,
    }, decryptedBytes
end

function GT4ReplayCrypto.makeDemoWrappedReplayString(inputData, randVal)
    local bytes = bytes_from_string(inputData)
    local ok, infoOrErr, wrapped = GT4ReplayCrypto.makeDemoWrappedReplayBytes(bytes, randVal)
    if not ok then
        return nil, nil, infoOrErr
    end

    return string_from_bytes(wrapped), infoOrErr, nil
end

function GT4ReplayCrypto.encryptDecryptedReplayString(inputData, randVal)
    local bytes = bytes_from_string(inputData)
    local ok, infoOrErr, wrapped = GT4ReplayCrypto.encryptReplayBytesAuto(bytes, randVal)
    if not ok then
        return nil, nil, infoOrErr
    end

    return string_from_bytes(wrapped), infoOrErr, nil
end


function GT4ReplayCrypto.makeReplayPayloadBytes(bytes)
    local layout = GT4ReplayCrypto.inspectLayout(bytes)
    local working = clone_bytes(bytes)

    if layout.layout == "serialize_only" then
        local ok, serializeInfoOrErr = GT4ReplayCrypto.encryptSerializeBytes(working, 1)
        if not ok then
            return false, serializeInfoOrErr
        end

        local payload = {}
        for i = serializeInfoOrErr.data_index, serializeInfoOrErr.data_end do
            payload[#payload + 1] = working[i]
        end

        return true, {
            input_layout = layout.layout,
            output_layout = "replay_payload",
            serialize = serializeInfoOrErr,
        }, payload
    end

    if layout.layout == "decrypted_wrapped" then
        local ok, serializeInfoOrErr = GT4ReplayCrypto.encryptSerializeBytes(working, 9)
        if not ok then
            return false, serializeInfoOrErr
        end

        local payload = {}
        for i = serializeInfoOrErr.data_index, serializeInfoOrErr.data_end do
            payload[#payload + 1] = working[i]
        end

        return true, {
            input_layout = layout.layout,
            output_layout = "replay_payload",
            serialize = serializeInfoOrErr,
        }, payload
    end

    return false, "Input looks like an encrypted wrapped replay. Decrypt it first, then build the replay payload."
end

function GT4ReplayCrypto.makeReplayPayloadString(inputData)
    local bytes = bytes_from_string(inputData)
    local ok, infoOrErr, outputBytes = GT4ReplayCrypto.makeReplayPayloadBytes(bytes)
    if not ok then
        return nil, nil, infoOrErr
    end

    return string_from_bytes(outputBytes), infoOrErr, nil
end


function GT4ReplayCrypto.makeDemoSerializeReplayBytes(bytes)
    local layout = GT4ReplayCrypto.inspectLayout(bytes)
    local working = clone_bytes(bytes)

    if layout.layout == "serialize_only" then
        local ok, serializeInfoOrErr = GT4ReplayCrypto.encryptSerializeBytes(working, 1)
        if not ok then
            return false, serializeInfoOrErr
        end

        return true, {
            input_layout = layout.layout,
            output_layout = "demo_serialize",
            serialize = serializeInfoOrErr,
        }, working
    end

    if layout.layout == "decrypted_wrapped" then
        local ok, serializeInfoOrErr = GT4ReplayCrypto.encryptSerializeBytes(working, 9)
        if not ok then
            return false, serializeInfoOrErr
        end

        local stripped = {}
        for i = 9, #working do
            stripped[#stripped + 1] = working[i]
        end

        return true, {
            input_layout = layout.layout,
            output_layout = "demo_serialize",
            serialize = serializeInfoOrErr,
        }, stripped
    end

    return false, "Input looks like an encrypted wrapped replay. Decrypt it first, then build the demo serialize replay."
end

function GT4ReplayCrypto.makeDemoSerializeReplayString(inputData)
    local bytes = bytes_from_string(inputData)
    local ok, infoOrErr, outputBytes = GT4ReplayCrypto.makeDemoSerializeReplayBytes(bytes)
    if not ok then
        return nil, nil, infoOrErr
    end

    return string_from_bytes(outputBytes), infoOrErr, nil
end

return GT4ReplayCrypto
