local MTRandom = {}
MTRandom.__index = MTRandom

local N = 624
local M = 397
local MATRIX_A = 0x9908B0DF
local UPPER_MASK = 0x80000000
local LOWER_MASK = 0x7FFFFFFF

local function u32(value)
    return value & 0xFFFFFFFF
end

-- Portable 32-bit multiply modulo 2^32.
-- Avoids relying on large intermediate integer precision.
local function mul32(a, b)
    a = u32(a)
    b = u32(b)

    local aLo = a & 0xFFFF
    local aHi = (a >> 16) & 0xFFFF
    local bLo = b & 0xFFFF
    local bHi = (b >> 16) & 0xFFFF

    local low = aLo * bLo
    local mid = (aHi * bLo) + (aLo * bHi)

    return u32(low + ((mid & 0xFFFF) << 16))
end

function MTRandom.new(seed)
    local self = setmetatable({}, MTRandom)
    self.mt = {}
    self.seed = u32(seed or 0)

    self.mt[1] = self.seed
    self.mti = 2

    while self.mti <= N do
        local prev = self.mt[self.mti - 1]
        local mixed = u32(prev ~ (prev >> 30))
        self.mt[self.mti] = u32(mul32(1812433253, mixed) + (self.mti - 1))
        self.mti = self.mti + 1
    end

    return self
end

function MTRandom:shift()
    local mag01 = { 0x0, MATRIX_A }

    local kk = 1
    while kk <= N - M do
        local y = (self.mt[kk] & UPPER_MASK) | (self.mt[kk + 1] & LOWER_MASK)
        self.mt[kk] = u32(self.mt[kk + M] ~ (y >> 1) ~ mag01[(y & 0x1) + 1])
        kk = kk + 1
    end

    while kk <= N - 1 do
        local y = (self.mt[kk] & UPPER_MASK) | (self.mt[kk + 1] & LOWER_MASK)
        self.mt[kk] = u32(self.mt[kk - 227] ~ (y >> 1) ~ mag01[(y & 0x1) + 1])
        kk = kk + 1
    end

    local y = (self.mt[N] & UPPER_MASK) | (self.mt[1] & LOWER_MASK)
    self.mt[N] = u32(self.mt[M] ~ (y >> 1) ~ mag01[(y & 0x1) + 1])
    self.mti = 1
end

function MTRandom:getInt32()
    if self.mti > N then
        self:shift()
    end

    local y = self.mt[self.mti]
    self.mti = self.mti + 1

    y = u32(y ~ (y >> 11))
    y = u32(y ~ ((y << 7) & 0x9D2C5680))
    y = u32(y ~ ((y << 15) & 0xEFC60000))
    y = u32(y ~ (y >> 18))

    return y
end

function MTRandom:getFloat()
    return self:getInt32() * (1.0 / 0xFFFFFFFF)
end

return MTRandom
