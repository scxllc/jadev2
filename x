

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local Mouse = nil
pcall(function() Mouse = LocalPlayer:GetMouse() end)

local _setrobloxinput = (type(setrobloxinput) == "function" and setrobloxinput) or function() end

Jade = {}
local UI = Jade
UI.Version = "1.0.0"
UI.Unloaded = false
UI.Loaded = false

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function lerpColor(a, b, t)
    return Color3.new(lerp(a.R, b.R, t), lerp(a.G, b.G, t), lerp(a.B, b.B, t))
end

local function rgbToHsv(c)
    local r, g, b = c.R, c.G, c.B
    local mx, mn = math.max(r, g, b), math.min(r, g, b)
    local d = mx - mn
    local h, s, v = 0, (mx == 0 and 0 or d / mx), mx
    if d ~= 0 then
        if mx == r then h = ((g - b) / d) % 6
        elseif mx == g then h = (b - r) / d + 2
        else h = (r - g) / d + 4 end
        h = h / 6
    end
    return h, s, v
end

local function eq(a, b)
    if a == b then return true end
    local ta = typeof(a)
    if ta ~= typeof(b) then return false end
    if ta == "Color3" then return a.R == b.R and a.G == b.G and a.B == b.B end
    if ta == "Vector2" then return a.X == b.X and a.Y == b.Y end
    return false
end

local function safe(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, err = pcall(fn, ...)
    if not ok then warn("[Jade] Callback error: " .. tostring(err)) end
end

local function getViewport()
    local cam = workspace and workspace.CurrentCamera
    if cam and cam.ViewportSize then
        return cam.ViewportSize.X, cam.ViewportSize.Y
    end
    return 1920, 1080
end

local function textW(str, size)
    return #tostring(str or "") * (size or 13) * 0.48
end

local function trimText(str, maxW, size)
    str = tostring(str or "")
    local charW = (size or 13) * 0.48
    local maxC = math.max(0, math.floor(maxW / charW))
    if #str <= maxC then return str end
    if maxC <= 2 then return "" end
    return str:sub(1, maxC - 2) .. ".."
end

local function wrapText(str, maxW, size)
    str = tostring(str or "")
    local charW = (size or 13) * 0.48
    local maxC = math.max(1, math.floor(maxW / charW))
    local lines = {}
    local words = {}
    for w in str:gmatch("%S+") do words[#words + 1] = w end
    if #words == 0 then return {""} end
    local cur = ""
    for i = 1, #words do
        local candidate = cur == "" and words[i] or (cur .. " " .. words[i])
        if #candidate <= maxC then
            cur = candidate
        else
            if cur ~= "" then lines[#lines + 1] = cur end
            if #words[i] > maxC then
                local w = words[i]
                while #w > maxC do
                    lines[#lines + 1] = w:sub(1, maxC)
                    w = w:sub(maxC + 1)
                end
                cur = w
            else
                cur = words[i]
            end
        end
    end
    if cur ~= "" then lines[#lines + 1] = cur end
    return lines
end

-- ═══════════════════════════════════════════════════════
-- Section 2: Spring Animation System
-- ═══════════════════════════════════════════════════════

local function newSpring(initial, speed)
    return { v = initial or 0, goal = initial or 0, speed = speed or 12 }
end

local function springStep(spring, dt)
    spring.v = spring.v + (spring.goal - spring.v) * math.min(1, spring.speed * dt)
    return spring.v
end

-- ═══════════════════════════════════════════════════════
-- Section 3: Retained-Mode Drawing Cache
-- ═══════════════════════════════════════════════════════

local Cache = {}
local Visible = {}
local CurTick = 0

local function Draw(id, dtype, props)
    local c = Cache[id]
    if not c then
        local ok, obj = pcall(Drawing.new, dtype)
        if not ok or not obj then return nil end
        c = { Obj = obj, P = {} }
        Cache[id] = c
    end
    local obj, P = c.Obj, c.P
    local vis = props.Visible
    if vis == nil then vis = true end
    if P.Visible ~= vis then
        obj.Visible = vis
        P.Visible = vis
    end
    if vis then
        for k, v in pairs(props) do
            if k ~= "Visible" and not eq(P[k], v) then
                pcall(function() obj[k] = v; P[k] = v end)
            end
        end
        Visible[id] = true
    else
        Visible[id] = nil
    end
    c.Tick = CurTick
    return obj
end

local function cleanupDrawings()
    for id in pairs(Visible) do
        local c = Cache[id]
        if c and c.Tick ~= CurTick and c.P.Visible then
            c.Obj.Visible = false
            c.P.Visible = false
            Visible[id] = nil
        end
    end
end

local function removeAllDrawings()
    for _, c in pairs(Cache) do
        if c.Obj and c.Obj.Remove then
            pcall(function() c.Obj:Remove() end)
        end
    end
    Cache = {}
    Visible = {}
end

-- Drawing helpers
local function rect(id, x, y, w, h, color, op, z, corner)
    if w <= 0 or h <= 0 then return end
    Draw(id, "Square", {
        Filled = true, Color = color, Transparency = op or 1,
        ZIndex = z or 1, Position = Vector2.new(x, y),
        Size = Vector2.new(w, h), Corner = corner or 0,
    })
end

local function glow(id, x, y, w, h, color, op, z, corner, passes)
    if not State.GlowEnabled then
        passes = passes or 3
        for i = 1, passes do
            local c = Cache[id .. ".gl" .. i]
            if c and c.Obj then c.Obj.Visible = false end
        end
        return
    end
    passes = passes or 3
    local spread = 2
    local alphaDecay = op / passes
    for i = 1, passes do
        Draw(id .. ".gl" .. i, "Square", {
            Filled = true, Color = color, Transparency = alphaDecay * (passes - i + 1) * 0.5,
            ZIndex = z - 1, Position = Vector2.new(x - i * spread, y - i * spread),
            Size = Vector2.new(w + i * spread * 2, h + i * spread * 2), Corner = corner + i * spread,
        })
    end
end

local function outline(id, x, y, w, h, color, op, z, corner)
    if w <= 0 or h <= 0 then return end
    Draw(id, "Square", {
        Filled = false, Color = color, Transparency = op or 1,
        ZIndex = z or 1, Position = Vector2.new(x, y),
        Size = Vector2.new(w, h), Corner = corner or 0,
    })
end

local function text(id, str, x, y, size, color, z, centered, opacity)
    if not str or str == "" then return end
    str = tostring(str)
    Draw(id, "Text", {
        Text = str, Position = Vector2.new(x, y),
        Size = size or 13, Color = color, Font = Drawing.Fonts and Drawing.Fonts.SystemBold or 2,
        ZIndex = (z or 1) + 10, Center = centered == true,
        Outline = false, Transparency = opacity or 1,
    })
end

local function drawLine(id, x1, y1, x2, y2, color, op, z, thickness)
    Draw(id, "Line", {
        From = Vector2.new(x1, y1), To = Vector2.new(x2, y2),
        Color = color, Thickness = thickness or 1,
        Transparency = op or 1, ZIndex = z or 1,
    })
end

local function drawCircle(id, x, y, radius, color, op, z, filled, sides)
    Draw(id, "Circle", {
        Position = Vector2.new(x, y), Radius = radius,
        Color = color, Filled = filled ~= false,
        Thickness = 1, NumSides = sides or 32,
        Transparency = op or 1, ZIndex = z or 1,
    })
end

local function drawTriangle(id, ax, ay, bx, by, cx, cy, color, op, z, filled)
    Draw(id, "Triangle", {
        PointA = Vector2.new(ax, ay), PointB = Vector2.new(bx, by),
        PointC = Vector2.new(cx, cy), Color = color,
        Filled = filled ~= false, Thickness = 1,
        Transparency = op or 1, ZIndex = z or 1,
    })
end

local function image(id, data, x, y, w, h, op, z)
    local obj = Draw(id, "Image", {
        Position = Vector2.new(x, y), Size = Vector2.new(w, h),
        Transparency = op or 1, ZIndex = z or 0,
    })
    if obj then pcall(function() obj.Data = data end) end
end

-- ═══════════════════════════════════════════════════════
-- Section 4: Input System
-- ═══════════════════════════════════════════════════════

local Input = {
    mx = 0, my = 0,
    down = false, clicked = false, prevDown = false,
    scroll = 0,
}

local KeyName = {
    [0x41]="A",[0x42]="B",[0x43]="C",[0x44]="D",[0x45]="E",[0x46]="F",
    [0x47]="G",[0x48]="H",[0x49]="I",[0x4A]="J",[0x4B]="K",[0x4C]="L",
    [0x4D]="M",[0x4E]="N",[0x4F]="O",[0x50]="P",[0x51]="Q",[0x52]="R",
    [0x53]="S",[0x54]="T",[0x55]="U",[0x56]="V",[0x57]="W",[0x58]="X",
    [0x59]="Y",[0x5A]="Z",
    [0x30]="0",[0x31]="1",[0x32]="2",[0x33]="3",[0x34]="4",
    [0x35]="5",[0x36]="6",[0x37]="7",[0x38]="8",[0x39]="9",
    [0x70]="F1",[0x71]="F2",[0x72]="F3",[0x73]="F4",[0x74]="F5",[0x75]="F6",
    [0x76]="F7",[0x77]="F8",[0x78]="F9",[0x79]="F10",[0x7A]="F11",[0x7B]="F12",
    [0x10]="Shift",[0x11]="Ctrl",[0x12]="Alt",[0x20]="Space",[0x09]="Tab",
    [0x1B]="Esc",[0x0D]="Enter",[0x08]="Backspace",
    [0x23]="End",[0x24]="Home",[0x2D]="Insert",[0x2E]="Delete",
    [0x25]="Left",[0x26]="Up",[0x27]="Right",[0x28]="Down",
    [0x01]="MB1",[0x02]="MB2",[0x05]="Mouse4",[0x06]="Mouse5",
}

local KeyAlias = {
    LeftControl = 0x11, RightControl = 0x11, Control = 0x11, Ctrl = 0x11,
    LeftShift = 0x10, RightShift = 0x10, Shift = 0x10,
    LeftAlt = 0x12, RightAlt = 0x12, Alt = 0x12,
    MB1 = 0x01, MB2 = 0x02, Mouse1 = 0x01, Mouse2 = 0x02,
    Return = 0x0D, Enter = 0x0D, Escape = 0x1B, Backspace = 0x08, Spacebar = 0x20,
}

local function resolveKey(v)
    if type(v) == "number" then return v, KeyName[v] or tostring(v) end
    if type(v) == "string" then
        if KeyAlias[v] then return KeyAlias[v], KeyName[KeyAlias[v]] or v end
        for vk, name in pairs(KeyName) do
            if name == v then return vk, name end
        end
    end
    return nil, "None"
end

local ScanList = {}
for vk in pairs(KeyName) do ScanList[#ScanList + 1] = vk end

local CharMap = {}
for vk = 0x41, 0x5A do CharMap[vk] = { string.char(vk + 32), string.char(vk) } end
do
    local d = {
        [0x30]={"0",")"},[0x31]={"1","!"},[0x32]={"2","@"},[0x33]={"3","#"},
        [0x34]={"4","$"},[0x35]={"5","%"},[0x36]={"6","^"},[0x37]={"7","&"},
        [0x38]={"8","*"},[0x39]={"9","("},
    }
    for vk, m in pairs(d) do CharMap[vk] = m end
    CharMap[0x20] = {" "," "}
    CharMap[0xBA] = {";",":"}; CharMap[0xBB] = {"=","+"}
    CharMap[0xBC] = {",","<"}; CharMap[0xBD] = {"-","_"}
    CharMap[0xBE] = {".",">"}; CharMap[0xBF] = {"/","?"}
    CharMap[0xC0] = {"`","~"}; CharMap[0xDB] = {"[","{"}
    CharMap[0xDC] = {"\\","|"}; CharMap[0xDD] = {"]","}"}
    CharMap[0xDE] = {"'","\""}
end

local CharScanList = {}
for vk in pairs(CharMap) do CharScanList[#CharScanList + 1] = vk end

local _iskeypressed = iskeypressed or iskeydown or function() return false end
local _keyclick = keyclick or function() end
local _isrbxactive = isrbxactive or iswindowactive or function() return true end

local EdgeState = {}

local function keyEdge(vk)
    local pressed = _iskeypressed(vk)
    local was = EdgeState[vk]
    EdgeState[vk] = pressed
    return pressed and not was
end

local function pollInput()
    if not Mouse then
        pcall(function() Mouse = LocalPlayer:GetMouse() end)
    end
    if Mouse then
        Input.mx = Mouse.X
        Input.my = Mouse.Y
    end
    local down = _iskeypressed(0x01)
    Input.clicked = down and not Input.prevDown
    Input.down = down
    -- scroll is set via event connections, reset each frame in main loop
end

local function inBounds(x, y, w, h)
    return Input.mx >= x and Input.mx <= x + w and Input.my >= y and Input.my <= y + h
end

-- Mouse scroll via connections
pcall(function()
    if Mouse then
        Mouse.WheelForward:Connect(function() Input.scroll = Input.scroll + 1 end)
        Mouse.WheelBackward:Connect(function() Input.scroll = Input.scroll - 1 end)
    end
end)
pcall(function()
    UIS.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseWheel then
            Input.scroll = Input.scroll + (input.Position and input.Position.Z or 0)
        end
    end)
end)

-- ═══════════════════════════════════════════════════════
-- Section 5: Theme System
-- ═══════════════════════════════════════════════════════

local Theme = {
    Accent          = Color3.fromRGB(80, 200, 120),
    WindowBg        = Color3.fromRGB(22, 27, 30),
    WindowBorder    = Color3.fromRGB(0, 0, 0),
    TitleBarLine    = Color3.fromRGB(50, 60, 55),
    RailLine        = Color3.fromRGB(45, 55, 50),
    Title           = Color3.fromRGB(240, 245, 240),
    SubText         = Color3.fromRGB(130, 150, 140),
    TabText         = Color3.fromRGB(130, 145, 135),
    TabTextActive   = Color3.fromRGB(240, 245, 240),
    TabHighlight    = Color3.fromRGB(55, 70, 62),
    Element         = Color3.fromRGB(35, 42, 38),
    ElementBorder   = Color3.fromRGB(20, 25, 22),
    Text            = Color3.fromRGB(240, 245, 240),
    ToggleSlider    = Color3.fromRGB(100, 115, 108),
    ToggleKnobOn    = Color3.fromRGB(15, 18, 16),
    Control         = Color3.fromRGB(45, 55, 50),
    OverlayBg       = Color3.fromRGB(28, 34, 30),
    OverlayBorder   = Color3.fromRGB(18, 22, 20),
}

local OP = {
    Window = 0.99,
    Border = 0.40,
    Element = 0.16,
    ElementHover = 0.26,
    Rail = 0.5,
    TabActive = 0.16,
    TabHover = 0.09,
    Control = 0.85,
    Overlay = 0.99,
}

local Palettes = {
    ["Jade Dark"] = {
        Accent = Color3.fromRGB(80, 200, 120),
        WindowBg = Color3.fromRGB(22, 27, 30),
        WindowBorder = Color3.fromRGB(0, 0, 0),
        TitleBarLine = Color3.fromRGB(50, 60, 55),
        RailLine = Color3.fromRGB(45, 55, 50),
        Title = Color3.fromRGB(240, 245, 240),
        SubText = Color3.fromRGB(130, 150, 140),
        TabText = Color3.fromRGB(130, 145, 135),
        TabTextActive = Color3.fromRGB(240, 245, 240),
        TabHighlight = Color3.fromRGB(55, 70, 62),
        Element = Color3.fromRGB(35, 42, 38),
        ElementBorder = Color3.fromRGB(20, 25, 22),
        Text = Color3.fromRGB(240, 245, 240),
        ToggleSlider = Color3.fromRGB(100, 115, 108),
        ToggleKnobOn = Color3.fromRGB(15, 18, 16),
        Control = Color3.fromRGB(45, 55, 50),
        OverlayBg = Color3.fromRGB(28, 34, 30),
        OverlayBorder = Color3.fromRGB(18, 22, 20),
    },
    ["Jade Light"] = {
        Accent = Color3.fromRGB(60, 170, 100),
        WindowBg = Color3.fromRGB(242, 245, 240),
        WindowBorder = Color3.fromRGB(200, 210, 205),
        TitleBarLine = Color3.fromRGB(210, 218, 212),
        RailLine = Color3.fromRGB(215, 222, 218),
        Title = Color3.fromRGB(25, 35, 30),
        SubText = Color3.fromRGB(100, 120, 110),
        TabText = Color3.fromRGB(100, 115, 108),
        TabTextActive = Color3.fromRGB(25, 35, 30),
        TabHighlight = Color3.fromRGB(225, 232, 228),
        Element = Color3.fromRGB(255, 255, 255),
        ElementBorder = Color3.fromRGB(195, 205, 200),
        Text = Color3.fromRGB(25, 35, 30),
        ToggleSlider = Color3.fromRGB(140, 160, 150),
        ToggleKnobOn = Color3.fromRGB(255, 255, 255),
        Control = Color3.fromRGB(255, 255, 255),
        OverlayBg = Color3.fromRGB(248, 250, 248),
        OverlayBorder = Color3.fromRGB(190, 200, 195),
    },
    ["Jade Neon"] = {
        Accent = Color3.fromRGB(0, 255, 140),
        WindowBg = Color3.fromRGB(12, 14, 18),
        WindowBorder = Color3.fromRGB(0, 80, 45),
        TitleBarLine = Color3.fromRGB(0, 60, 35),
        RailLine = Color3.fromRGB(0, 50, 30),
        Title = Color3.fromRGB(220, 255, 235),
        SubText = Color3.fromRGB(80, 160, 120),
        TabText = Color3.fromRGB(80, 160, 120),
        TabTextActive = Color3.fromRGB(220, 255, 235),
        TabHighlight = Color3.fromRGB(0, 40, 25),
        Element = Color3.fromRGB(18, 22, 26),
        ElementBorder = Color3.fromRGB(0, 60, 35),
        Text = Color3.fromRGB(220, 255, 235),
        ToggleSlider = Color3.fromRGB(0, 120, 70),
        ToggleKnobOn = Color3.fromRGB(8, 10, 14),
        Control = Color3.fromRGB(18, 22, 26),
        OverlayBg = Color3.fromRGB(14, 18, 22),
        OverlayBorder = Color3.fromRGB(0, 60, 35),
    },
    ["Jade Rose"] = {
        Accent = Color3.fromRGB(255, 110, 150),
        WindowBg = Color3.fromRGB(28, 22, 26),
        WindowBorder = Color3.fromRGB(60, 30, 45),
        TitleBarLine = Color3.fromRGB(60, 35, 48),
        RailLine = Color3.fromRGB(55, 32, 44),
        Title = Color3.fromRGB(245, 235, 240),
        SubText = Color3.fromRGB(160, 130, 145),
        TabText = Color3.fromRGB(155, 125, 140),
        TabTextActive = Color3.fromRGB(245, 235, 240),
        TabHighlight = Color3.fromRGB(70, 42, 56),
        Element = Color3.fromRGB(40, 30, 36),
        ElementBorder = Color3.fromRGB(55, 25, 40),
        Text = Color3.fromRGB(245, 235, 240),
        ToggleSlider = Color3.fromRGB(180, 100, 130),
        ToggleKnobOn = Color3.fromRGB(28, 22, 26),
        Control = Color3.fromRGB(50, 35, 44),
        OverlayBg = Color3.fromRGB(34, 26, 32),
        OverlayBorder = Color3.fromRGB(55, 25, 40),
    },
    ["Jade Ocean"] = {
        Accent = Color3.fromRGB(70, 160, 255),
        WindowBg = Color3.fromRGB(18, 24, 34),
        WindowBorder = Color3.fromRGB(30, 50, 80),
        TitleBarLine = Color3.fromRGB(35, 55, 80),
        RailLine = Color3.fromRGB(30, 48, 72),
        Title = Color3.fromRGB(220, 235, 250),
        SubText = Color3.fromRGB(100, 130, 170),
        TabText = Color3.fromRGB(95, 125, 165),
        TabTextActive = Color3.fromRGB(220, 235, 250),
        TabHighlight = Color3.fromRGB(30, 55, 85),
        Element = Color3.fromRGB(24, 32, 46),
        ElementBorder = Color3.fromRGB(25, 42, 68),
        Text = Color3.fromRGB(220, 235, 250),
        ToggleSlider = Color3.fromRGB(70, 100, 145),
        ToggleKnobOn = Color3.fromRGB(14, 20, 30),
        Control = Color3.fromRGB(30, 40, 58),
        OverlayBg = Color3.fromRGB(20, 28, 40),
        OverlayBorder = Color3.fromRGB(25, 42, 68),
    },
    ["Jade Ember"] = {
        Accent = Color3.fromRGB(255, 140, 50),
        WindowBg = Color3.fromRGB(30, 22, 18),
        WindowBorder = Color3.fromRGB(70, 40, 20),
        TitleBarLine = Color3.fromRGB(65, 40, 25),
        RailLine = Color3.fromRGB(60, 38, 22),
        Title = Color3.fromRGB(250, 240, 230),
        SubText = Color3.fromRGB(170, 140, 115),
        TabText = Color3.fromRGB(165, 135, 110),
        TabTextActive = Color3.fromRGB(250, 240, 230),
        TabHighlight = Color3.fromRGB(75, 50, 32),
        Element = Color3.fromRGB(42, 32, 25),
        ElementBorder = Color3.fromRGB(60, 35, 18),
        Text = Color3.fromRGB(250, 240, 230),
        ToggleSlider = Color3.fromRGB(160, 110, 70),
        ToggleKnobOn = Color3.fromRGB(25, 18, 14),
        Control = Color3.fromRGB(55, 40, 30),
        OverlayBg = Color3.fromRGB(35, 26, 20),
        OverlayBorder = Color3.fromRGB(60, 35, 18),
    },
    -- Wabi Sabi themes ported
    Dark = {
        Accent = Color3.fromRGB(96, 205, 255), WindowBg = Color3.fromRGB(36, 36, 36),
        WindowBorder = Color3.fromRGB(0, 0, 0), TitleBarLine = Color3.fromRGB(75, 75, 75),
        RailLine = Color3.fromRGB(60, 60, 60), Title = Color3.fromRGB(240, 240, 240),
        SubText = Color3.fromRGB(170, 170, 170), TabText = Color3.fromRGB(150, 150, 150),
        TabTextActive = Color3.fromRGB(240, 240, 240), TabHighlight = Color3.fromRGB(130, 130, 130),
        Element = Color3.fromRGB(130, 130, 130), ElementBorder = Color3.fromRGB(20, 20, 20),
        Text = Color3.fromRGB(240, 240, 240), ToggleSlider = Color3.fromRGB(120, 120, 120),
        ToggleKnobOn = Color3.fromRGB(10, 10, 10), Control = Color3.fromRGB(66, 66, 66),
        OverlayBg = Color3.fromRGB(42, 42, 42), OverlayBorder = Color3.fromRGB(20, 20, 20),
    },
    Darker = {
        Accent = Color3.fromRGB(96, 205, 255), WindowBg = Color3.fromRGB(24, 24, 24),
        WindowBorder = Color3.fromRGB(0, 0, 0), TitleBarLine = Color3.fromRGB(75, 75, 75),
        RailLine = Color3.fromRGB(60, 60, 60), Title = Color3.fromRGB(240, 240, 240),
        SubText = Color3.fromRGB(170, 170, 170), TabText = Color3.fromRGB(150, 150, 150),
        TabTextActive = Color3.fromRGB(240, 240, 240), TabHighlight = Color3.fromRGB(130, 130, 130),
        Element = Color3.fromRGB(130, 130, 130), ElementBorder = Color3.fromRGB(20, 20, 20),
        Text = Color3.fromRGB(240, 240, 240), ToggleSlider = Color3.fromRGB(120, 120, 120),
        ToggleKnobOn = Color3.fromRGB(10, 10, 10), Control = Color3.fromRGB(50, 50, 50),
        OverlayBg = Color3.fromRGB(30, 30, 30), OverlayBorder = Color3.fromRGB(20, 20, 20),
    },
    Aqua = {
        Accent = Color3.fromRGB(38, 200, 200), WindowBg = Color3.fromRGB(36, 36, 36),
        WindowBorder = Color3.fromRGB(0, 0, 0), TitleBarLine = Color3.fromRGB(75, 75, 75),
        RailLine = Color3.fromRGB(60, 60, 60), Title = Color3.fromRGB(240, 240, 240),
        SubText = Color3.fromRGB(170, 170, 170), TabText = Color3.fromRGB(150, 150, 150),
        TabTextActive = Color3.fromRGB(240, 240, 240), TabHighlight = Color3.fromRGB(130, 130, 130),
        Element = Color3.fromRGB(130, 130, 130), ElementBorder = Color3.fromRGB(20, 20, 20),
        Text = Color3.fromRGB(240, 240, 240), ToggleSlider = Color3.fromRGB(120, 120, 120),
        ToggleKnobOn = Color3.fromRGB(10, 10, 10), Control = Color3.fromRGB(66, 66, 66),
        OverlayBg = Color3.fromRGB(42, 42, 42), OverlayBorder = Color3.fromRGB(20, 20, 20),
    },
    Amethyst = {
        Accent = Color3.fromRGB(170, 120, 255), WindowBg = Color3.fromRGB(36, 36, 36),
        WindowBorder = Color3.fromRGB(0, 0, 0), TitleBarLine = Color3.fromRGB(75, 75, 75),
        RailLine = Color3.fromRGB(60, 60, 60), Title = Color3.fromRGB(240, 240, 240),
        SubText = Color3.fromRGB(170, 170, 170), TabText = Color3.fromRGB(150, 150, 150),
        TabTextActive = Color3.fromRGB(240, 240, 240), TabHighlight = Color3.fromRGB(130, 130, 130),
        Element = Color3.fromRGB(130, 130, 130), ElementBorder = Color3.fromRGB(20, 20, 20),
        Text = Color3.fromRGB(240, 240, 240), ToggleSlider = Color3.fromRGB(120, 120, 120),
        ToggleKnobOn = Color3.fromRGB(10, 10, 10), Control = Color3.fromRGB(66, 66, 66),
        OverlayBg = Color3.fromRGB(42, 42, 42), OverlayBorder = Color3.fromRGB(20, 20, 20),
    },
    Rose = {
        Accent = Color3.fromRGB(255, 120, 165), WindowBg = Color3.fromRGB(36, 36, 36),
        WindowBorder = Color3.fromRGB(0, 0, 0), TitleBarLine = Color3.fromRGB(75, 75, 75),
        RailLine = Color3.fromRGB(60, 60, 60), Title = Color3.fromRGB(240, 240, 240),
        SubText = Color3.fromRGB(170, 170, 170), TabText = Color3.fromRGB(150, 150, 150),
        TabTextActive = Color3.fromRGB(240, 240, 240), TabHighlight = Color3.fromRGB(130, 130, 130),
        Element = Color3.fromRGB(130, 130, 130), ElementBorder = Color3.fromRGB(20, 20, 20),
        Text = Color3.fromRGB(240, 240, 240), ToggleSlider = Color3.fromRGB(120, 120, 120),
        ToggleKnobOn = Color3.fromRGB(10, 10, 10), Control = Color3.fromRGB(66, 66, 66),
        OverlayBg = Color3.fromRGB(42, 42, 42), OverlayBorder = Color3.fromRGB(20, 20, 20),
    },
    Ocean = {
        Accent = Color3.fromRGB(80, 150, 255), WindowBg = Color3.fromRGB(28, 32, 40),
        WindowBorder = Color3.fromRGB(0, 0, 0), TitleBarLine = Color3.fromRGB(75, 75, 75),
        RailLine = Color3.fromRGB(60, 60, 60), Title = Color3.fromRGB(240, 240, 240),
        SubText = Color3.fromRGB(170, 170, 170), TabText = Color3.fromRGB(150, 150, 150),
        TabTextActive = Color3.fromRGB(240, 240, 240), TabHighlight = Color3.fromRGB(130, 130, 130),
        Element = Color3.fromRGB(130, 130, 130), ElementBorder = Color3.fromRGB(20, 20, 20),
        Text = Color3.fromRGB(240, 240, 240), ToggleSlider = Color3.fromRGB(120, 120, 120),
        ToggleKnobOn = Color3.fromRGB(10, 10, 10), Control = Color3.fromRGB(66, 66, 66),
        OverlayBg = Color3.fromRGB(34, 39, 48), OverlayBorder = Color3.fromRGB(20, 20, 20),
    },
    ["Monokai"] = {
        Accent = Color3.fromRGB(249, 38, 114), WindowBg = Color3.fromRGB(39, 40, 34),
        WindowBorder = Color3.fromRGB(65, 67, 57), TitleBarLine = Color3.fromRGB(65, 67, 57),
        RailLine = Color3.fromRGB(65, 67, 57), Title = Color3.fromRGB(248, 248, 242),
        SubText = Color3.fromRGB(136, 132, 111), TabText = Color3.fromRGB(248, 248, 242),
        TabTextActive = Color3.fromRGB(248, 248, 242), TabHighlight = Color3.fromRGB(62, 61, 50),
        Element = Color3.fromRGB(65, 67, 57), ElementBorder = Color3.fromRGB(117, 113, 94),
        Text = Color3.fromRGB(248, 248, 242), ToggleSlider = Color3.fromRGB(249, 38, 114),
        ToggleKnobOn = Color3.fromRGB(65, 67, 57), Control = Color3.fromRGB(65, 67, 57),
        OverlayBg = Color3.fromRGB(30, 31, 28), OverlayBorder = Color3.fromRGB(117, 113, 94),
    },
    ["Monokai Vibrant"] = {
        Accent = Color3.fromRGB(82, 139, 255), WindowBg = Color3.fromRGB(22, 23, 29),
        WindowBorder = Color3.fromRGB(24, 26, 31), TitleBarLine = Color3.fromRGB(24, 26, 31),
        RailLine = Color3.fromRGB(24, 26, 31), Title = Color3.fromRGB(248, 248, 240),
        SubText = Color3.fromRGB(92, 99, 112), TabText = Color3.fromRGB(248, 248, 240),
        TabTextActive = Color3.fromRGB(248, 248, 240), TabHighlight = Color3.fromRGB(41, 45, 53),
        Element = Color3.fromRGB(29, 31, 35), ElementBorder = Color3.fromRGB(24, 26, 17),
        Text = Color3.fromRGB(248, 248, 240), ToggleSlider = Color3.fromRGB(82, 139, 255),
        ToggleKnobOn = Color3.fromRGB(22, 23, 29), Control = Color3.fromRGB(29, 31, 35),
        OverlayBg = Color3.fromRGB(33, 37, 43), OverlayBorder = Color3.fromRGB(24, 26, 17),
    },
    ["Solarized Dark"] = {
        Accent = Color3.fromRGB(42, 161, 152), WindowBg = Color3.fromRGB(0, 43, 54),
        WindowBorder = Color3.fromRGB(7, 54, 66), TitleBarLine = Color3.fromRGB(42, 161, 152),
        RailLine = Color3.fromRGB(42, 161, 152), Title = Color3.fromRGB(131, 148, 150),
        SubText = Color3.fromRGB(88, 110, 117), TabText = Color3.fromRGB(131, 148, 150),
        TabTextActive = Color3.fromRGB(131, 148, 150), TabHighlight = Color3.fromRGB(0, 68, 84),
        Element = Color3.fromRGB(0, 56, 71), ElementBorder = Color3.fromRGB(42, 161, 152),
        Text = Color3.fromRGB(131, 148, 150), ToggleSlider = Color3.fromRGB(42, 161, 152),
        ToggleKnobOn = Color3.fromRGB(0, 43, 54), Control = Color3.fromRGB(0, 33, 43),
        OverlayBg = Color3.fromRGB(0, 33, 43), OverlayBorder = Color3.fromRGB(42, 161, 152),
    },
    ["Solarized Light"] = {
        Accent = Color3.fromRGB(181, 137, 0), WindowBg = Color3.fromRGB(253, 246, 227),
        WindowBorder = Color3.fromRGB(221, 214, 193), TitleBarLine = Color3.fromRGB(221, 214, 193),
        RailLine = Color3.fromRGB(221, 214, 193), Title = Color3.fromRGB(101, 123, 131),
        SubText = Color3.fromRGB(147, 161, 161), TabText = Color3.fromRGB(101, 123, 131),
        TabTextActive = Color3.fromRGB(101, 123, 131), TabHighlight = Color3.fromRGB(223, 202, 136),
        Element = Color3.fromRGB(238, 232, 213), ElementBorder = Color3.fromRGB(211, 175, 134),
        Text = Color3.fromRGB(101, 123, 131), ToggleSlider = Color3.fromRGB(181, 137, 0),
        ToggleKnobOn = Color3.fromRGB(253, 246, 227), Control = Color3.fromRGB(238, 232, 213),
        OverlayBg = Color3.fromRGB(238, 232, 213), OverlayBorder = Color3.fromRGB(211, 175, 134),
    },
    ["GitHub Dark"] = {
        Accent = Color3.fromRGB(31, 111, 235), WindowBg = Color3.fromRGB(1, 4, 9),
        WindowBorder = Color3.fromRGB(48, 54, 61), TitleBarLine = Color3.fromRGB(48, 54, 61),
        RailLine = Color3.fromRGB(48, 54, 61), Title = Color3.fromRGB(230, 237, 243),
        SubText = Color3.fromRGB(125, 133, 144), TabText = Color3.fromRGB(230, 237, 243),
        TabTextActive = Color3.fromRGB(230, 237, 243), TabHighlight = Color3.fromRGB(110, 118, 129),
        Element = Color3.fromRGB(22, 27, 34), ElementBorder = Color3.fromRGB(48, 54, 61),
        Text = Color3.fromRGB(230, 237, 243), ToggleSlider = Color3.fromRGB(31, 111, 235),
        ToggleKnobOn = Color3.fromRGB(13, 17, 23), Control = Color3.fromRGB(22, 27, 34),
        OverlayBg = Color3.fromRGB(22, 27, 34), OverlayBorder = Color3.fromRGB(48, 54, 61),
    },
    ["VS Dark"] = {
        Accent = Color3.fromRGB(0, 122, 204), WindowBg = Color3.fromRGB(30, 30, 30),
        WindowBorder = Color3.fromRGB(48, 48, 49), TitleBarLine = Color3.fromRGB(48, 48, 49),
        RailLine = Color3.fromRGB(48, 48, 49), Title = Color3.fromRGB(212, 212, 212),
        SubText = Color3.fromRGB(187, 187, 187), TabText = Color3.fromRGB(255, 255, 255),
        TabTextActive = Color3.fromRGB(212, 212, 212), TabHighlight = Color3.fromRGB(56, 59, 61),
        Element = Color3.fromRGB(34, 34, 34), ElementBorder = Color3.fromRGB(107, 107, 107),
        Text = Color3.fromRGB(212, 212, 212), ToggleSlider = Color3.fromRGB(0, 122, 204),
        ToggleKnobOn = Color3.fromRGB(34, 34, 34), Control = Color3.fromRGB(37, 37, 38),
        OverlayBg = Color3.fromRGB(37, 37, 38), OverlayBorder = Color3.fromRGB(69, 69, 69),
    },
    ["Arc Dark"] = {
        Accent = Color3.fromRGB(82, 148, 226), WindowBg = Color3.fromRGB(56, 60, 74),
        WindowBorder = Color3.fromRGB(64, 79, 125), TitleBarLine = Color3.fromRGB(64, 79, 125),
        RailLine = Color3.fromRGB(64, 79, 125), Title = Color3.fromRGB(162, 162, 162),
        SubText = Color3.fromRGB(114, 133, 183), TabText = Color3.fromRGB(162, 162, 162),
        TabTextActive = Color3.fromRGB(162, 162, 162), TabHighlight = Color3.fromRGB(75, 81, 98),
        Element = Color3.fromRGB(75, 81, 98), ElementBorder = Color3.fromRGB(64, 79, 125),
        Text = Color3.fromRGB(162, 162, 162), ToggleSlider = Color3.fromRGB(82, 148, 226),
        ToggleKnobOn = Color3.fromRGB(56, 60, 74), Control = Color3.fromRGB(75, 81, 98),
        OverlayBg = Color3.fromRGB(75, 81, 98), OverlayBorder = Color3.fromRGB(64, 79, 125),
    },
    ["Amethyst Dark"] = {
        Accent = Color3.fromRGB(177, 51, 255), WindowBg = Color3.fromRGB(18, 0, 36),
        WindowBorder = Color3.fromRGB(77, 5, 123), TitleBarLine = Color3.fromRGB(77, 5, 123),
        RailLine = Color3.fromRGB(77, 5, 123), Title = Color3.fromRGB(233, 217, 242),
        SubText = Color3.fromRGB(158, 133, 173), TabText = Color3.fromRGB(233, 217, 242),
        TabTextActive = Color3.fromRGB(233, 217, 242), TabHighlight = Color3.fromRGB(77, 5, 123),
        Element = Color3.fromRGB(37, 1, 60), ElementBorder = Color3.fromRGB(77, 5, 123),
        Text = Color3.fromRGB(233, 217, 242), ToggleSlider = Color3.fromRGB(125, 22, 191),
        ToggleKnobOn = Color3.fromRGB(18, 0, 36), Control = Color3.fromRGB(37, 1, 60),
        OverlayBg = Color3.fromRGB(37, 1, 60), OverlayBorder = Color3.fromRGB(77, 5, 123),
    },
    ["DuoTone Dark Earth"] = {
        Accent = Color3.fromRGB(254, 203, 82), WindowBg = Color3.fromRGB(44, 40, 38),
        WindowBorder = Color3.fromRGB(72, 65, 61), TitleBarLine = Color3.fromRGB(72, 65, 61),
        RailLine = Color3.fromRGB(72, 65, 61), Title = Color3.fromRGB(189, 152, 127),
        SubText = Color3.fromRGB(86, 75, 67), TabText = Color3.fromRGB(189, 152, 127),
        TabTextActive = Color3.fromRGB(189, 152, 127), TabHighlight = Color3.fromRGB(77, 70, 66),
        Element = Color3.fromRGB(53, 48, 45), ElementBorder = Color3.fromRGB(72, 65, 61),
        Text = Color3.fromRGB(189, 152, 127), ToggleSlider = Color3.fromRGB(254, 203, 82),
        ToggleKnobOn = Color3.fromRGB(44, 40, 38), Control = Color3.fromRGB(53, 48, 45),
        OverlayBg = Color3.fromRGB(53, 48, 45), OverlayBorder = Color3.fromRGB(72, 65, 61),
    },
    ["DuoTone Dark Sea"] = {
        Accent = Color3.fromRGB(52, 254, 187), WindowBg = Color3.fromRGB(29, 38, 47),
        WindowBorder = Color3.fromRGB(48, 63, 79), TitleBarLine = Color3.fromRGB(48, 63, 79),
        RailLine = Color3.fromRGB(48, 63, 79), Title = Color3.fromRGB(136, 180, 231),
        SubText = Color3.fromRGB(68, 76, 85), TabText = Color3.fromRGB(136, 180, 231),
        TabTextActive = Color3.fromRGB(136, 180, 231), TabHighlight = Color3.fromRGB(53, 68, 84),
        Element = Color3.fromRGB(35, 45, 56), ElementBorder = Color3.fromRGB(48, 63, 79),
        Text = Color3.fromRGB(136, 180, 231), ToggleSlider = Color3.fromRGB(52, 254, 187),
        ToggleKnobOn = Color3.fromRGB(29, 38, 47), Control = Color3.fromRGB(35, 45, 56),
        OverlayBg = Color3.fromRGB(35, 45, 56), OverlayBorder = Color3.fromRGB(48, 63, 79),
    },
    ["DuoTone Dark Space"] = {
        Accent = Color3.fromRGB(254, 119, 52), WindowBg = Color3.fromRGB(36, 36, 46),
        WindowBorder = Color3.fromRGB(58, 58, 74), TitleBarLine = Color3.fromRGB(58, 58, 74),
        RailLine = Color3.fromRGB(58, 58, 74), Title = Color3.fromRGB(134, 134, 203),
        SubText = Color3.fromRGB(73, 73, 90), TabText = Color3.fromRGB(134, 134, 203),
        TabTextActive = Color3.fromRGB(134, 134, 203), TabHighlight = Color3.fromRGB(63, 63, 79),
        Element = Color3.fromRGB(43, 43, 54), ElementBorder = Color3.fromRGB(58, 58, 74),
        Text = Color3.fromRGB(134, 134, 203), ToggleSlider = Color3.fromRGB(254, 119, 52),
        ToggleKnobOn = Color3.fromRGB(36, 36, 46), Control = Color3.fromRGB(43, 43, 54),
        OverlayBg = Color3.fromRGB(43, 43, 54), OverlayBorder = Color3.fromRGB(58, 58, 74),
    },
    ["Tomorrow Night Blue"] = {
        Accent = Color3.fromRGB(187, 218, 255), WindowBg = Color3.fromRGB(0, 36, 81),
        WindowBorder = Color3.fromRGB(64, 79, 125), TitleBarLine = Color3.fromRGB(64, 79, 125),
        RailLine = Color3.fromRGB(64, 79, 125), Title = Color3.fromRGB(255, 255, 255),
        SubText = Color3.fromRGB(114, 133, 183), TabText = Color3.fromRGB(255, 255, 255),
        TabTextActive = Color3.fromRGB(255, 255, 255), TabHighlight = Color3.fromRGB(255, 255, 255),
        Element = Color3.fromRGB(0, 23, 51), ElementBorder = Color3.fromRGB(64, 79, 125),
        Text = Color3.fromRGB(255, 255, 255), ToggleSlider = Color3.fromRGB(187, 218, 255),
        ToggleKnobOn = Color3.fromRGB(0, 23, 51), Control = Color3.fromRGB(0, 23, 51),
        OverlayBg = Color3.fromRGB(0, 23, 51), OverlayBorder = Color3.fromRGB(64, 79, 125),
    },
    ["Yaru Dark"] = {
        Accent = Color3.fromRGB(233, 84, 32), WindowBg = Color3.fromRGB(56, 56, 56),
        WindowBorder = Color3.fromRGB(68, 68, 68), TitleBarLine = Color3.fromRGB(68, 68, 68),
        RailLine = Color3.fromRGB(68, 68, 68), Title = Color3.fromRGB(255, 255, 255),
        SubText = Color3.fromRGB(128, 128, 128), TabText = Color3.fromRGB(255, 255, 255),
        TabTextActive = Color3.fromRGB(255, 255, 255), TabHighlight = Color3.fromRGB(87, 87, 87),
        Element = Color3.fromRGB(72, 72, 72), ElementBorder = Color3.fromRGB(64, 64, 64),
        Text = Color3.fromRGB(255, 255, 255), ToggleSlider = Color3.fromRGB(233, 84, 32),
        ToggleKnobOn = Color3.fromRGB(47, 47, 47), Control = Color3.fromRGB(72, 72, 72),
        OverlayBg = Color3.fromRGB(72, 72, 72), OverlayBorder = Color3.fromRGB(64, 64, 64),
    },
    ["Kimbie Dark"] = {
        Accent = Color3.fromRGB(165, 122, 76), WindowBg = Color3.fromRGB(34, 26, 15),
        WindowBorder = Color3.fromRGB(94, 69, 43), TitleBarLine = Color3.fromRGB(81, 65, 44),
        RailLine = Color3.fromRGB(81, 65, 44), Title = Color3.fromRGB(211, 175, 134),
        SubText = Color3.fromRGB(165, 122, 76), TabText = Color3.fromRGB(211, 175, 134),
        TabTextActive = Color3.fromRGB(211, 175, 134), TabHighlight = Color3.fromRGB(124, 80, 33),
        Element = Color3.fromRGB(81, 65, 44), ElementBorder = Color3.fromRGB(94, 69, 43),
        Text = Color3.fromRGB(211, 175, 134), ToggleSlider = Color3.fromRGB(165, 122, 76),
        ToggleKnobOn = Color3.fromRGB(81, 65, 44), Control = Color3.fromRGB(81, 65, 44),
        OverlayBg = Color3.fromRGB(81, 65, 44), OverlayBorder = Color3.fromRGB(94, 69, 43),
    },
    ["VSC Dark Modern"] = {
        Accent = Color3.fromRGB(0, 120, 212), WindowBg = Color3.fromRGB(24, 24, 24),
        WindowBorder = Color3.fromRGB(43, 43, 43), TitleBarLine = Color3.fromRGB(43, 43, 43),
        RailLine = Color3.fromRGB(43, 43, 43), Title = Color3.fromRGB(204, 204, 204),
        SubText = Color3.fromRGB(157, 157, 157), TabText = Color3.fromRGB(255, 255, 255),
        TabTextActive = Color3.fromRGB(204, 204, 204), TabHighlight = Color3.fromRGB(60, 60, 60),
        Element = Color3.fromRGB(49, 49, 49), ElementBorder = Color3.fromRGB(60, 60, 60),
        Text = Color3.fromRGB(204, 204, 204), ToggleSlider = Color3.fromRGB(0, 120, 212),
        ToggleKnobOn = Color3.fromRGB(49, 49, 49), Control = Color3.fromRGB(49, 49, 49),
        OverlayBg = Color3.fromRGB(49, 49, 49), OverlayBorder = Color3.fromRGB(60, 60, 60),
    },
    ["United GNOME"] = {
        Accent = Color3.fromRGB(72, 178, 88), WindowBg = Color3.fromRGB(30, 30, 30),
        WindowBorder = Color3.fromRGB(68, 68, 68), TitleBarLine = Color3.fromRGB(68, 68, 68),
        RailLine = Color3.fromRGB(68, 68, 68), Title = Color3.fromRGB(221, 221, 221),
        SubText = Color3.fromRGB(128, 128, 128), TabText = Color3.fromRGB(221, 221, 221),
        TabTextActive = Color3.fromRGB(221, 221, 221), TabHighlight = Color3.fromRGB(42, 45, 46),
        Element = Color3.fromRGB(36, 36, 36), ElementBorder = Color3.fromRGB(64, 64, 64),
        Text = Color3.fromRGB(221, 221, 221), ToggleSlider = Color3.fromRGB(72, 178, 88),
        ToggleKnobOn = Color3.fromRGB(30, 30, 30), Control = Color3.fromRGB(36, 36, 36),
        OverlayBg = Color3.fromRGB(36, 36, 36), OverlayBorder = Color3.fromRGB(64, 64, 64),
    },
}

-- Build theme list
UI.Themes = {}
for k in pairs(Palettes) do UI.Themes[#UI.Themes + 1] = k end
table.sort(UI.Themes)

local function setTheme(name)
    local p = Palettes[name]
    if not p then return end
    for k, v in pairs(p) do Theme[k] = v end
end

-- ═══════════════════════════════════════════════════════
-- Section 6–18: Window, Tabs, Elements, Overlays, etc.
-- ═══════════════════════════════════════════════════════

local TITLE_H = 42
local RAIL_W = 160

local State = {
    Win = { x = 100, y = 80, w = 580, h = 460 },
    GlowEnabled = true,
    MinW = 470, MinH = 380,
    Minimized = false,
    Maximized = false,
    MaxPrev = nil,
    ActiveTab = 1,
    Running = false,
    Token = nil,
    LastTime = nil,
    Vw = 1920, Vh = 1080,
    Drag = false,
    DragOff = Vector2.new(0, 0),
    Resizing = false,
    BarDrag = false,
    Overlay = nil,
    Focused = nil,
    KBListening = nil,
    Dialog = nil,
    IndOff = newSpring(0, 14),
    IndInit = false,
    TabCurtain = newSpring(0, 8),
    BubblePos = { x = 20, y = 20 },
    BubbleDrag = false,
    BubbleMoved = false,
    BubbleOff = Vector2.new(0, 0),
    MenuKey = 0x23, -- End
    SpotlightActive = false,
    SpotlightSearch = "",
    SpotlightSelected = 1,
    SpotlightAnim = newSpring(0, 16),
    WatermarkEnabled = false,
    WatermarkText = "",
    TooltipText = nil,
    TooltipX = 0,
    TooltipY = 0,
    TooltipTimer = 0,
    TooltipHoverEl = nil,
    InStep = false,
    ConfigFolder = "Jade/configs",
    ThemeName = "Jade Dark",
}

local Tabs = {}
local AllKeybinds = {}
local AllElements = {}
local Notifs = {}
local NotifId = 0

-- ═══════════════════════════════════════════════════════
-- Section 7: Tab System
-- ═══════════════════════════════════════════════════════

local TabMT = {}
TabMT.__index = TabMT

function TabMT:AddSection(cfg)
    cfg = cfg or {}
    local section = {
        title = cfg.Title or nil,
        collapsed = false,
        collapseAnim = newSpring(1, 12),
        elements = {},
    }
    self.groups[#self.groups + 1] = section

    local SectionMT = {}
    SectionMT.__index = SectionMT

    -- Element adders will be attached below
    local sectionHandle = setmetatable({ _section = section, _tab = self }, SectionMT)

    -- Attach element creation methods
    local function addElement(el)
        section.elements[#section.elements + 1] = el
        AllElements[#AllElements + 1] = el
        return el
    end

    -- ═══════════════════════════════════════════════════
    -- Section 9: UI Elements
    -- ═══════════════════════════════════════════════════

    function sectionHandle:AddToggle(cfg)
        cfg = cfg or {}
        local el = {
            kind = "toggle", id = cfg.Id,
            title = cfg.Title or "Toggle",
            desc = cfg.Desc,
            tooltip = cfg.Tooltip,
            value = cfg.Default == true,
            callback = cfg.Callback,
            changed = cfg.Changed,
            anim = newSpring(cfg.Default and 1 or 0, 14),
            hover = newSpring(0, 18),
            keybind = nil,
            colorpicker = nil,
            dependsOn = nil,
            tabIndex = #Tabs,
            visible = true,
        }
        addElement(el)

        local handle = { _el = el }

        function handle:Set(value)
            local old = el.value
            el.value = value == true
            el.anim.goal = el.value and 1 or 0
            if el.value ~= old then safe(el.callback, el.value) end
            return self
        end

        function handle:GetValue()
            return el.value
        end

        function handle:DependsOn(parentHandle)
            el.dependsOn = parentHandle
            return self
        end

        function handle:AddKeybind(defaultKey, mode, callback)
            local vk, name = resolveKey(defaultKey)
            local kb = {
                key = vk, keyName = name,
                mode = mode or "Toggle",
                callback = callback,
                changedCallback = nil,
                changed = nil,
                owner = el,
            }
            el.keybind = kb
            AllKeybinds[#AllKeybinds + 1] = kb

            local kbHandle = {}
            function kbHandle:Set(newKey, newMode)
                local nvk, nname = resolveKey(newKey)
                kb.key = nvk; kb.keyName = nname
                if newMode then kb.mode = newMode end
                return self
            end
            function kbHandle:OnChanged(fn)
                kb.changed = fn
                return self
            end
            return kbHandle
        end

        function handle:AddColorpicker(cfg2)
            cfg2 = cfg2 or {}
            local h, s, v = rgbToHsv(cfg2.Default or Theme.Accent)
            local cp = {
                label = cfg2.Title or "Color",
                value = cfg2.Default or Theme.Accent,
                h = h, s = s, v = v,
                alpha = cfg2.Alpha or 1,
                hasAlpha = cfg2.Alpha ~= nil,
                callback = cfg2.Callback,
                changed = cfg2.Changed,
            }
            el.colorpicker = cp

            local cpHandle = {}
            function cpHandle:Set(newColor, newAlpha)
                cp.value = newColor
                if newAlpha then cp.alpha = newAlpha end
                cp.h, cp.s, cp.v = rgbToHsv(newColor)
                safe(cp.callback, newColor, cp.alpha)
                return self
            end
            return cpHandle
        end

        return handle
    end

    function sectionHandle:AddSlider(cfg)
        cfg = cfg or {}
        local el = {
            kind = "slider", id = cfg.Id,
            title = cfg.Title or "Slider",
            desc = cfg.Desc,
            tooltip = cfg.Tooltip,
            value = cfg.Default or cfg.Min or 0,
            min = cfg.Min or 0, max = cfg.Max or 100,
            rounding = cfg.Rounding or 0,
            step = cfg.Step,
            callback = cfg.Callback,
            changed = cfg.Changed,
            frac = newSpring(0, 14),
            hover = newSpring(0, 18),
            dragging = false,
            tabIndex = #Tabs,
            visible = true,
        }
        el.frac.v = (el.value - el.min) / math.max(1e-6, el.max - el.min)
        el.frac.goal = el.frac.v
        addElement(el)

        local handle = { _el = el }
        function handle:Set(value)
            value = tonumber(value) or el.min
            if el.rounding and el.rounding > 0 then
                value = tonumber(string.format("%." .. el.rounding .. "f", value)) or value
            else
                value = math.floor(value + 0.5)
            end
            value = clamp(value, el.min, el.max)
            el.value = value
            el.frac.goal = (value - el.min) / math.max(1e-6, el.max - el.min)
            safe(el.callback, value)
            return self
        end
        function handle:SetValue(v) return handle:Set(v) end
        function handle:GetValue() return el.value end
        return handle
    end

    function sectionHandle:AddDropdown(cfg)
        cfg = cfg or {}
        local multi = cfg.Multi == true
        local defaultVal
        if multi then
            defaultVal = {}
            if cfg.Default then
                if type(cfg.Default) == "table" then
                    for _, v in ipairs(cfg.Default) do defaultVal[v] = true end
                else
                    defaultVal[cfg.Default] = true
                end
            end
        else
            defaultVal = cfg.Default
        end
        local el = {
            kind = "dropdown", id = cfg.Id,
            title = cfg.Title or "Dropdown",
            desc = cfg.Desc,
            tooltip = cfg.Tooltip,
            options = cfg.Options or {},
            value = defaultVal,
            multi = multi,
            searchable = cfg.Searchable == true,
            searchPlaceholder = cfg.SearchPlaceholder or "Search...",
            searchText = "",
            scroll = 0,
            maxItems = cfg.MaxItems or 6,
            allowNull = cfg.AllowNull == true,
            displayer = cfg.Displayer,
            callback = cfg.Callback,
            changed = cfg.Changed,
            hover = newSpring(0, 18),
            tabIndex = #Tabs,
            visible = true,
        }
        addElement(el)

        local handle = { _el = el }
        function handle:Set(value)
            if multi then
                if type(value) == "table" then
                    el.value = value
                end
            else
                el.value = value
            end
            safe(el.callback, el.value)
            return self
        end
        function handle:UpdateOptions(opts)
            el.options = opts or {}
            return self
        end
        function handle:GetValue() return el.value end
        return handle
    end

    function sectionHandle:AddButton(cfg)
        cfg = cfg or {}
        local el = {
            kind = "button", id = cfg.Id,
            title = cfg.Title or "Button",
            desc = cfg.Desc,
            tooltip = cfg.Tooltip,
            callback = cfg.Callback,
            hover = newSpring(0, 18),
            tabIndex = #Tabs,
            visible = true,
        }
        addElement(el)
        local handle = { _el = el }
        return handle
    end

    function sectionHandle:AddInput(cfg)
        cfg = cfg or {}
        local el = {
            kind = "input", id = cfg.Id,
            title = cfg.Title or "Input",
            desc = cfg.Desc,
            tooltip = cfg.Tooltip,
            text = cfg.Default or "",
            placeholder = cfg.Placeholder or "",
            maxLength = cfg.MaxLength,
            numeric = cfg.Numeric == true,
            finished = cfg.Finished ~= false, -- true by default: fires on Enter
            clearOnFocusLost = cfg.ClearOnFocusLost == true,
            callback = cfg.Callback,
            changed = cfg.Changed,
            hover = newSpring(0, 18),
            tabIndex = #Tabs,
            visible = true,
        }
        addElement(el)
        local handle = { _el = el }
        function handle:Set(value)
            el.text = tostring(value or "")
            safe(el.callback, el.text)
            return self
        end
        function handle:GetValue() return el.text end
        return handle
    end

    function sectionHandle:AddColorpicker(cfg)
        cfg = cfg or {}
        local h, s, v = rgbToHsv(cfg.Default or Theme.Accent)
        local el = {
            kind = "colorpicker", id = cfg.Id,
            title = cfg.Title or "Color",
            desc = cfg.Desc,
            tooltip = cfg.Tooltip,
            value = cfg.Default or Theme.Accent,
            h = h, s = s, v = v,
            alpha = cfg.Alpha or 1,
            hasAlpha = cfg.Alpha ~= nil,
            callback = cfg.Callback,
            changed = cfg.Changed,
            hover = newSpring(0, 18),
            tabIndex = #Tabs,
            visible = true,
        }
        addElement(el)
        local handle = { _el = el }
        function handle:Set(color, alpha)
            el.value = color
            if alpha then el.alpha = alpha end
            el.h, el.s, el.v = rgbToHsv(color)
            safe(el.callback, color, el.alpha)
            return self
        end
        function handle:GetValue() return el.value, el.alpha end
        return handle
    end

    function sectionHandle:AddKeybind(cfg)
        cfg = cfg or {}
        local vk, name = resolveKey(cfg.Default)
        local el = {
            kind = "keybind", id = cfg.Id,
            title = cfg.Title or "Keybind",
            desc = cfg.Desc,
            tooltip = cfg.Tooltip,
            key = vk, keyName = name,
            mode = cfg.Mode or "Toggle",
            callback = cfg.Callback,
            changedCallback = cfg.OnChanged,
            changed = nil,
            hover = newSpring(0, 18),
            tabIndex = #Tabs,
            visible = true,
        }
        addElement(el)
        AllKeybinds[#AllKeybinds + 1] = el
        
        local handle = { _el = el }
        function handle:Set(newKey, newMode)
            local nvk, nname = resolveKey(newKey)
            el.key = nvk; el.keyName = nname
            if newMode then el.mode = newMode end
            return self
        end
        function handle:GetValue() return el.keyName end

        function handle:DoClick()
            if el.callback then
                safe(el.callback, el.keyName)
            end
        end

        el.DoClick = function()
            handle:DoClick()
        end

        return handle
    end

    function sectionHandle:AddParagraph(cfg)
        cfg = cfg or {}
        local lines = {}
        if cfg.Content then
            for ln in (tostring(cfg.Content) .. "\n"):gmatch("(.-)\n") do
                lines[#lines + 1] = ln
            end
            if #lines > 0 and lines[#lines] == "" then table.remove(lines) end
        end
        local el = {
            kind = "paragraph", id = cfg.Id,
            title = cfg.Title or "",
            lines = lines,
            titleAlign = cfg.TitleAlign or "left",
            contentAlign = cfg.ContentAlign or "left",
            hover = newSpring(0, 18),
            tabIndex = #Tabs,
            visible = true,
        }
        addElement(el)
        local handle = { _el = el }
        return handle
    end

    return sectionHandle
end

-- ═══════════════════════════════════════════════════════
-- Section 6: Window Management (CreateWindow)
-- ═══════════════════════════════════════════════════════

function UI:CreateWindow(cfg)
    cfg = cfg or {}
    UI.Title = cfg.Title or "Jade"
    UI.SubTitle = cfg.SubTitle or ""

    if cfg.Size then
        State.Win.w = cfg.Size.X or 580
        State.Win.h = cfg.Size.Y or 460
    end
    if cfg.MinSize then
        State.MinW = cfg.MinSize.X or 470
        State.MinH = cfg.MinSize.Y or 380
    end
    if cfg.Theme then
        setTheme(cfg.Theme)
        State.ThemeName = cfg.Theme
    end
    if cfg.MinimizeKey then
        local vk = resolveKey(cfg.MinimizeKey)
        if vk then State.MenuKey = vk end
    end
    if cfg.ConfigName then
        State.DefaultConfig = cfg.ConfigName
    end
    if cfg.Resize == true then
        -- auto-scale to viewport
        local vw, vh = getViewport()
        local sx = vw / 1920
        local sy = vh / 1080
        local s = math.min(sx, sy)
        if s ~= 1 then
            State.Win.w = math.floor(State.Win.w * s)
            State.Win.h = math.floor(State.Win.h * s)
            State.MinW = math.floor(State.MinW * s)
            State.MinH = math.floor(State.MinH * s)
        end
    end

    local Window = {}

    function Window:AddTab(tabCfg)
        tabCfg = tabCfg or {}
        local tab = setmetatable({
            name = tabCfg.Title or "Tab",
            icon = tabCfg.Icon,
            groups = {},
            scroll = 0,
        }, TabMT)
        Tabs[#Tabs + 1] = tab
        if #Tabs == 1 then State.ActiveTab = 1 end
        return tab
    end

    function Window:SelectTab(index)
        if index >= 1 and index <= #Tabs then
            State.ActiveTab = index
            State.Overlay = nil
            State.Focused = nil
            State.TabCurtain.v = 1
        end
    end

    function Window:Dialog(cfg2)
        cfg2 = cfg2 or {}
        local lines = {}
        if cfg2.Content then
            for ln in (tostring(cfg2.Content) .. "\n"):gmatch("(.-)\n") do
                lines[#lines + 1] = ln
            end
            if #lines > 0 and lines[#lines] == "" then table.remove(lines) end
        end
        State.Dialog = {
            title = cfg2.Title or "Dialog",
            lines = lines,
            buttons = cfg2.Buttons or {{ Title = "OK" }},
            anim = newSpring(0, 20),
            closing = false,
        }
    end

    -- Config system
    function Window:SaveConfig(name)
        name = name or State.DefaultConfig or "default"
        local data = {}
        for _, el in ipairs(AllElements) do
            if el.id then
                local entry = { kind = el.kind }
                if el.kind == "toggle" then
                    entry.value = el.value
                    if el.keybind then
                        entry.keybindKey = el.keybind.keyName
                        entry.keybindMode = el.keybind.mode
                    end
                    if el.colorpicker then
                        local c = el.colorpicker.value
                        entry.cpR = math.floor(c.R * 255 + 0.5)
                        entry.cpG = math.floor(c.G * 255 + 0.5)
                        entry.cpB = math.floor(c.B * 255 + 0.5)
                        entry.cpA = el.colorpicker.alpha
                    end
                elseif el.kind == "slider" then
                    entry.value = el.value
                elseif el.kind == "dropdown" then
                    if el.multi then
                        local sel = {}
                        for k, v in pairs(el.value) do
                            if v then sel[#sel + 1] = k end
                        end
                        entry.value = sel
                    else
                        entry.value = el.value
                    end
                elseif el.kind == "input" then
                    entry.value = el.text
                elseif el.kind == "colorpicker" then
                    local c = el.value
                    entry.r = math.floor(c.R * 255 + 0.5)
                    entry.g = math.floor(c.G * 255 + 0.5)
                    entry.b = math.floor(c.B * 255 + 0.5)
                    entry.a = el.alpha
                elseif el.kind == "keybind" then
                    entry.key = el.keyName
                    entry.mode = el.mode
                end
                data[el.id] = entry
            end
        end
        data._theme = State.ThemeName
        local json = game:GetService("HttpService"):JSONEncode(data)
        pcall(function()
            if not isfolder(State.ConfigFolder) then
                makefolder(State.ConfigFolder)
            end
            writefile(State.ConfigFolder .. "/" .. name .. ".json", json)
        end)
        UI:Notify({ Title = "Config Saved", Content = "Saved as '" .. name .. "'", Duration = 3 })
    end

    function Window:LoadConfig(name)
        name = name or State.DefaultConfig or "default"
        local ok, raw = pcall(function()
            return readfile(State.ConfigFolder .. "/" .. name .. ".json")
        end)
        if not ok or not raw then
            UI:Notify({ Title = "Error", Content = "Config '" .. name .. "' not found.", Duration = 3 })
            return
        end
        local ok2, data = pcall(function()
            return game:GetService("HttpService"):JSONDecode(raw)
        end)
        if not ok2 or type(data) ~= "table" then
            UI:Notify({ Title = "Error", Content = "Failed to parse config.", Duration = 3 })
            return
        end
        -- Apply theme
        if data._theme and Palettes[data._theme] then
            setTheme(data._theme)
            State.ThemeName = data._theme
        end
        -- Apply element values
        for _, el in ipairs(AllElements) do
            if el.id and data[el.id] then
                local entry = data[el.id]
                if el.kind == "toggle" and entry.value ~= nil then
                    el.value = entry.value == true
                    el.anim.goal = el.value and 1 or 0
                    safe(el.callback, el.value)
                    if el.keybind and entry.keybindKey then
                        local vk, nm = resolveKey(entry.keybindKey)
                        el.keybind.key = vk; el.keybind.keyName = nm
                        if entry.keybindMode then el.keybind.mode = entry.keybindMode end
                    end
                    if el.colorpicker and entry.cpR then
                        el.colorpicker.value = Color3.fromRGB(entry.cpR, entry.cpG, entry.cpB)
                        el.colorpicker.h, el.colorpicker.s, el.colorpicker.v = rgbToHsv(el.colorpicker.value)
                        if entry.cpA then el.colorpicker.alpha = entry.cpA end
                        safe(el.colorpicker.callback, el.colorpicker.value, el.colorpicker.alpha)
                    end
                elseif el.kind == "slider" and entry.value ~= nil then
                    local v = tonumber(entry.value) or el.min
                    v = clamp(v, el.min, el.max)
                    el.value = v
                    el.frac.goal = (v - el.min) / math.max(1e-6, el.max - el.min)
                    safe(el.callback, v)
                elseif el.kind == "dropdown" then
                    if el.multi and type(entry.value) == "table" then
                        el.value = {}
                        for _, k in ipairs(entry.value) do el.value[k] = true end
                    elseif not el.multi then
                        el.value = entry.value
                    end
                    safe(el.callback, el.value)
                elseif el.kind == "input" and entry.value ~= nil then
                    el.text = tostring(entry.value)
                    safe(el.callback, el.text)
                elseif el.kind == "colorpicker" and entry.r then
                    el.value = Color3.fromRGB(entry.r, entry.g, entry.b)
                    el.h, el.s, el.v = rgbToHsv(el.value)
                    if entry.a then el.alpha = entry.a end
                    safe(el.callback, el.value, el.alpha)
                elseif el.kind == "keybind" and entry.key then
                    local vk, nm = resolveKey(entry.key)
                    el.key = vk; el.keyName = nm
                    if entry.mode then el.mode = entry.mode end
                end
            end
        end
        UI:Notify({ Title = "Config Loaded", Content = "Loaded '" .. name .. "'", Duration = 3 })
    end

    function Window:ListConfigs()
        local list = {}
        pcall(function()
            if isfolder(State.ConfigFolder) then
                local files = listfiles(State.ConfigFolder)
                for _, f in ipairs(files) do
                    local name = f:match("([^/\\]+)%.json$")
                    if name then list[#list + 1] = name end
                end
            end
        end)
        return list
    end

    function Window:DeleteConfig(name)
        pcall(function()
            delfile(State.ConfigFolder .. "/" .. name .. ".json")
        end)
        UI:Notify({ Title = "Config Deleted", Content = "Deleted '" .. name .. "'", Duration = 3 })
    end

    -- Auto settings tab builders
    function Window:BuildConfigSection(tab)
        tab = tab or Window:AddTab({ Title = "Settings" })
        local cfgSection = tab:AddSection({ Title = "Configuration" })
        
        local configName = cfgSection:AddInput({
            Id = "_cfg_name",
            Title = "Config Name",
            Placeholder = "my_config",
            Default = State.DefaultConfig or "",
        })

        cfgSection:AddButton({
            Title = "Save Config",
            Desc = "Save current settings to file",
            Callback = function()
                local name = configName:GetValue()
                if name == "" then name = "default" end
                Window:SaveConfig(name)
            end,
        })

        cfgSection:AddButton({
            Title = "Load Config",
            Desc = "Load settings from file",
            Callback = function()
                local name = configName:GetValue()
                if name == "" then name = "default" end
                Window:LoadConfig(name)
            end,
        })

        cfgSection:AddButton({
            Title = "Delete Config",
            Callback = function()
                local name = configName:GetValue()
                if name ~= "" then Window:DeleteConfig(name) end
            end,
        })

        return tab
    end

    function Window:BuildInterfaceSection(tab)
        if not tab then
            -- Try to find existing Settings tab
            for _, t in ipairs(Tabs) do
                if t.name == "Settings" then tab = t; break end
            end
            if not tab then tab = Window:AddTab({ Title = "Settings" }) end
        end

        local ifaceSection = tab:AddSection({ Title = "Interface" })

        ifaceSection:AddDropdown({
            Id = "_theme",
            Title = "Theme",
            Options = UI.Themes,
            Default = State.ThemeName,
            Searchable = true,
            Callback = function(v)
                if v and Palettes[v] then
                    setTheme(v)
                    State.ThemeName = v
                end
            end,
        })

        ifaceSection:AddToggle({
            Id = "_glow",
            Title = "High Quality Glows",
            Desc = "Disabling improves FPS",
            Default = State.GlowEnabled,
            Callback = function(v)
                State.GlowEnabled = v
            end,
        })

        ifaceSection:AddKeybind({
            Id = "_minimize_key",
            Title = "Minimize Key",
            Default = KeyName[State.MenuKey],
            Callback = function() end,
            OnChanged = function(keyName)
                if keyName then
                    local vk = resolveKey(keyName)
                    if vk then State.MenuKey = vk end
                end
            end,
        })

        ifaceSection:AddToggle({
            Id = "_watermark",
            Title = "Watermark",
            Desc = "Show floating watermark",
            Default = State.WatermarkEnabled,
            Callback = function(v) State.WatermarkEnabled = v end,
        })

        return tab
    end

    State.Window = Window
    return Window
end

-- ═══════════════════════════════════════════════════════
-- Section 9 (continued): Element Rendering
-- ═══════════════════════════════════════════════════════

local function cardHeight(el)
    if el.kind == "paragraph" then
        return 32 + math.max(1, #el.lines) * 15 + 8
    end
    if el.desc then
        if el.kind == "slider" then return 58 end
        if el.kind == "dropdown" then return 64 end
        return 48
    end
    if el.kind == "slider" then return 42 end
    if el.kind == "dropdown" then return 54 end
    return 38
end

local function ddDisplay(el)
    if el.multi then
        local sel = {}
        for k, v in pairs(el.value) do
            if v then
                local d = el.displayer and tostring(el.displayer(k)) or tostring(k)
                sel[#sel + 1] = d
            end
        end
        if #sel == 0 then return "None" end
        return table.concat(sel, ", ")
    end
    if el.value == nil then return "None" end
    return el.displayer and tostring(el.displayer(el.value)) or tostring(el.value)
end

local function blurField()
    local f = State.Focused
    if f then
        if f.onCommit then f.onCommit(f.buf) end
        State.Focused = nil
    end
end

local function processEl(el, idp, x, y, w, h, dt, z, block)
    -- DependsOn check
    if el.dependsOn then
        local parent = el.dependsOn._el or el.dependsOn
        if parent and parent.value == false then
            el.visible = false
            return false -- hidden
        end
    end
    el.visible = true

    local hovered = not block and inBounds(x, y, w, h)
    local interactive = el.kind ~= "paragraph"

    if interactive then el.hover.goal = hovered and 1 or 0 end
    springStep(el.hover, dt)

    -- Tooltip tracking
    if hovered and el.tooltip and interactive then
        if State.TooltipHoverEl ~= el then
            State.TooltipHoverEl = el
            State.TooltipTimer = 0
        else
            State.TooltipTimer = State.TooltipTimer + dt
        end
        State.TooltipX = Input.mx + 14
        State.TooltipY = Input.my + 14
        State.TooltipText = el.tooltip
    end

    -- Background card
    if el.hover.v > 0.05 then
        glow(idp .. ".gl", x, y, w, h, Theme.Accent, el.hover.v * 0.15, z, 5, 2)
    end
    rect(idp .. ".bg", x, y, w, h, Theme.Element, lerp(OP.Element, OP.ElementHover, el.hover.v), z, 5)
    outline(idp .. ".bd", x, y, w, h, Theme.ElementBorder, OP.Border, z + 1, 5)

    if el.kind == "paragraph" then
        text(idp .. ".t", el.title, x + 14, y + 12, 13, Theme.Text, z + 2)
        local ly = y + 32
        for i, ln in ipairs(el.lines) do
            text(idp .. ".l" .. i, ln, x + 14, ly, 12, Theme.SubText, z + 2)
            ly = ly + 15
        end
        return true
    end

    local titleY = (el.desc or el.kind == "slider") and (y + 11) or (y + math.floor((h - 14) / 2))
    local titleX = x + 14
    text(idp .. ".t", el.title, titleX, titleY, 13, Theme.Text, z + 2)
    if el.desc then text(idp .. ".d", el.desc, titleX, titleY + 16, 12, Theme.SubText, z + 2) end

    if el.kind == "button" then
        if hovered and Input.clicked then safe(el.callback) end

    elseif el.kind == "toggle" then
        local pillW, pillH = 36, 18
        local px = x + w - 12 - pillW
        local py = y + math.floor((h - pillH) / 2)
        local chipHit = false

        -- Keybind chip
        if el.keybind then
            local kb = el.keybind
            local listening = (State.KBListening == kb)
            local chW, chH = 48, 20
            local chX = px - 10 - chW
            local chY = y + math.floor((h - chH) / 2)
            chipHit = not block and inBounds(chX, chY, chW, chH)
            rect(idp .. ".tkb", chX, chY, chW, chH, Theme.Control, chipHit and 0.95 or OP.Control, z + 2, 5)
            outline(idp .. ".tkbd", chX, chY, chW, chH, listening and Theme.Accent or Theme.ElementBorder, 0.6, z + 3, 5)
            local kt = listening and "..." or ("[" .. (kb.keyName or "None") .. "]")
            text(idp .. ".tkt", kt, chX + chW / 2, chY + chH / 2, 11, listening and Theme.Accent or Theme.Text, z + 3, true)
            if chipHit and Input.clicked then State.KBListening = kb end
        end

        -- Colorpicker swatch
        if el.colorpicker then
            local cp = el.colorpicker
            local sw, swh = 18, 18
            local cpX = (el.keybind and (px - 10 - 48 - 8 - sw)) or (px - 10 - sw)
            local cpY = y + math.floor((h - swh) / 2)
            local cpHover = not block and inBounds(cpX, cpY, sw, swh)
            rect(idp .. ".cps", cpX, cpY, sw, swh, cp.value, cp.alpha, z + 2, 4)
            outline(idp .. ".cpsd", cpX, cpY, sw, swh, cpHover and Theme.Accent or Theme.ElementBorder, 0.6, z + 3, 4)
            if cpHover and Input.clicked then
                State.Overlay = {
                    kind = "colorpicker", el = cp,
                    ax = cpX + sw, ay = cpY + swh + 4,
                    origH = cp.h, origS = cp.s, origV = cp.v, origAlpha = cp.alpha,
                }
            end
        end

        -- Toggle click
        if hovered and Input.clicked and not chipHit then
            el.value = not el.value
            el.anim.goal = el.value and 1 or 0
            safe(el.callback, el.value)
            safe(el.changed, el.value)
        end
        springStep(el.anim, dt)
        local t = el.anim.v
        rect(idp .. ".pill", px, py, pillW, pillH, Theme.Accent, t, z + 2, 9)
        outline(idp .. ".pilb", px, py, pillW, pillH, lerpColor(Theme.ToggleSlider, Theme.Accent, t), 0.55, z + 3, 9)
        drawCircle(idp .. ".knob", px + lerp(9, 27, t), py + pillH / 2, 6,
            lerpColor(Theme.ToggleSlider, Theme.ToggleKnobOn, t), lerp(0.6, 1, t), z + 4, true)

    elseif el.kind == "slider" then
        local tx, tw = x + 14, w - 28
        local ty = y + (el.desc and 50 or 34)
        local editing = State.Focused and State.Focused.owner == el

        local vs = (el.rounding and el.rounding > 0) and string.format("%." .. el.rounding .. "f", el.value)
            or tostring(math.floor(el.value + 0.5))
        local shownV = vs
        if editing then
            local caret = (math.floor(tick() * 2) % 2 == 0) and "|" or ""
            shownV = State.Focused.buf .. caret
        end
        local vwid = textW(shownV, 12)
        local vx = x + w - 14 - vwid
        local vHover = not block and inBounds(vx - 6, y + 8, vwid + 12, 18)
        text(idp .. ".v", shownV, vx, y + 11, 12, editing and Theme.Accent or Theme.SubText, z + 2)

        if not editing and Input.down and not block and (el.dragging or (Input.clicked and not vHover and inBounds(tx - 6, ty - 8, tw + 12, 18))) then
            el.dragging = true
            local f = clamp((Input.mx - tx) / tw, 0, 1)
            local raw = el.min + f * (el.max - el.min)
            local v = (el.rounding and el.rounding > 0) and tonumber(string.format("%." .. el.rounding .. "f", raw)) or math.floor(raw + 0.5)
            if v ~= el.value then
                local old = el.value
                el.value = v
                el.frac.goal = (el.value - el.min) / math.max(1e-6, el.max - el.min)
                safe(el.callback, v, old)
                safe(el.changed, v, old)
            end
        elseif not Input.down then
            el.dragging = false
        end
        if not editing and vHover and Input.clicked then
            State.KBListening = nil; State.Overlay = nil; el.dragging = false
            State.Focused = {
                owner = el, id = "value", buf = vs, numeric = true, live = false,
                onCommit = function(buf)
                    local n = tonumber(buf)
                    if n then
                        n = clamp(n, el.min, el.max)
                        if el.rounding and el.rounding > 0 then
                            n = tonumber(string.format("%." .. el.rounding .. "f", n))
                        else
                            n = math.floor(n + 0.5)
                        end
                        el.value = n
                        el.frac.goal = (n - el.min) / math.max(1e-6, el.max - el.min)
                        safe(el.callback, n)
                    end
                end,
            }
        elseif editing and Input.clicked and not vHover then
            blurField()
        end
        springStep(el.frac, dt)
        local f = clamp(el.frac.v, 0, 1)
        rect(idp .. ".trk", tx, ty, tw, 4, Theme.ToggleSlider, 0.30, z + 2, 2)
        rect(idp .. ".fil", tx, ty, math.max(0, tw * f), 4, Theme.Accent, 1, z + 3, 2)
        drawCircle(idp .. ".knb", tx + tw * f, ty + 2, 6, Theme.Text, 1, z + 4, true)

    elseif el.kind == "dropdown" then
        local boxH = 26
        local boxW = math.min(160, math.floor(w * 0.46))
        local bx = x + w - 12 - boxW
        local by = el.desc and (y + 28) or (y + math.floor((h - boxH) / 2))
        local bHover = not block and inBounds(bx, by, boxW, boxH)
        rect(idp .. ".db", bx, by, boxW, boxH, Theme.Control, bHover and 0.95 or OP.Control, z + 2, 5)
        outline(idp .. ".dbd", bx, by, boxW, boxH, Theme.ElementBorder, 0.5, z + 3, 5)
        local displayStr = trimText(ddDisplay(el), boxW - 24, 12)
        text(idp .. ".dt", displayStr, bx + 8, by + 6, 12, Theme.Text, z + 3)
        -- Chevron down
        drawTriangle(idp .. ".dc", bx + boxW - 14, by + 10, bx + boxW - 6, by + 10, bx + boxW - 10, by + 16,
            Theme.SubText, 1, z + 3, true)
        if bHover and Input.clicked then
            el.searchText = ""; el.scroll = 0
            State.Overlay = { kind = "dropdown", el = el, x = bx, y = by + boxH + 4, w = boxW }
        end

    elseif el.kind == "keybind" then
        local boxH, boxW = 26, 84
        local bx = x + w - 12 - boxW
        local by = y + math.floor((h - boxH) / 2)
        local listening = (State.KBListening == el)
        local bHover = not block and inBounds(bx, by, boxW, boxH)
        rect(idp .. ".kb", bx, by, boxW, boxH, Theme.Control, bHover and 0.95 or OP.Control, z + 2, 5)
        outline(idp .. ".kbd", bx, by, boxW, boxH, listening and Theme.Accent or Theme.ElementBorder, 0.6, z + 3, 5)
        local txt = listening and "..." or ("[" .. (el.keyName or "None") .. "]")
        text(idp .. ".kt", txt, bx + boxW / 2, by + boxH / 2, 12, listening and Theme.Accent or Theme.Text, z + 3, true)
        if bHover and Input.clicked then State.KBListening = el end

    elseif el.kind == "colorpicker" then
        local sw, swh = 32, 20
        local bx = x + w - 12 - sw
        local by = y + math.floor((h - swh) / 2)
        local bHover = not block and inBounds(bx, by, sw, swh)
        if el.hasAlpha then rect(idp .. ".cwbk", bx, by, sw, swh, Color3.fromRGB(55, 55, 55), 1, z + 2, 5) end
        rect(idp .. ".cw", bx, by, sw, swh, el.value, el.hasAlpha and el.alpha or 1, z + 3, 5)
        outline(idp .. ".cwd", bx, by, sw, swh, bHover and Theme.Accent or Theme.ElementBorder, 0.6, z + 4, 5)
        if bHover and Input.clicked then
            State.Overlay = {
                kind = "colorpicker", el = el,
                ax = bx + sw, ay = by + swh + 4,
                origH = el.h, origS = el.s, origV = el.v, origAlpha = el.alpha,
            }
        end

    elseif el.kind == "input" then
        local boxH = 26
        local boxW = math.min(170, math.floor(w * 0.5))
        local bx = x + w - 12 - boxW
        local by = y + math.floor((h - boxH) / 2)
        local focused = State.Focused and State.Focused.owner == el
        local bHover = not block and inBounds(bx, by, boxW, boxH)
        rect(idp .. ".ib", bx, by, boxW, boxH, Theme.Control, focused and 0.95 or OP.Control, z + 2, 5)
        outline(idp .. ".ibd", bx, by, boxW, boxH, focused and Theme.Accent or Theme.ElementBorder, 0.6, z + 3, 5)
        local raw = (focused and State.Focused.buf) or el.text or ""
        local maxc = math.max(1, math.floor((boxW - 18) / 6.5))
        local body = (#raw > maxc) and raw:sub(#raw - maxc + 1) or raw
        local caret = (focused and math.floor(tick() * 2) % 2 == 0) and "|" or ""
        local shown = (raw ~= "" and (body .. caret)) or (caret ~= "" and caret) or (el.placeholder or "")
        text(idp .. ".it", shown, bx + 8, by + 6, 12, raw ~= "" and Theme.Text or Theme.SubText, z + 3)
        if bHover and Input.clicked then
            State.KBListening = nil; State.Overlay = nil
            State.Focused = {
                owner = el, id = "text", buf = el.text or "", numeric = el.numeric,
                maxLength = el.maxLength, live = not el.finished,
                onType = function(buf)
                    el.text = buf; safe(el.callback, el.text); safe(el.changed, el.text)
                end,
                onCommit = function(buf)
                    if el.finished then el.text = buf; safe(el.callback, el.text); safe(el.changed, el.text)
                    else el.text = buf end
                    if el.clearOnFocusLost then el.text = "" end
                end,
            }
        elseif focused and Input.clicked and not bHover then
            blurField()
        end
    end

    return true
end

-- ═══════════════════════════════════════════════════════
-- Section 10: Overlay System
-- ═══════════════════════════════════════════════════════

local function renderOverlay(dt)
    local ov = State.Overlay
    if not ov then return false end
    local Z = 120

    if ov.kind == "dropdown" then
        local el = ov.el
        local function disp(v)
            if el.displayer then return tostring(el.displayer(v)) end
            return tostring(v)
        end
        local opts = el.options
        local filtered = opts
        if el.searchable and el.searchText ~= "" then
            filtered = {}
            local q = el.searchText:lower()
            for _, o in ipairs(opts) do
                if disp(o):lower():find(q, 1, true) then
                    filtered[#filtered + 1] = o
                end
            end
        end
        local rowH = 28
        local pad = 4
        local searchH = el.searchable and 28 or 0
        local visN = math.min(#filtered, el.maxItems or 6)
        local needBar = #filtered > visN
        local barW = needBar and 6 or 0
        local listH = math.max(rowH, visN * rowH)
        local panelW = ov.w
        local panelH = pad * 2 + searchH + listH
        local maxScroll = math.max(0, #filtered - visN)
        el.scroll = clamp(el.scroll or 0, 0, maxScroll)

        ov.anim = ov.anim or newSpring(0, 24)
        ov.rowHover = ov.rowHover or {}
        ov.anim.goal = ov.closing and 0 or 1
        local a = springStep(ov.anim, dt)
        if ov.closing and a < 0.04 then
            if State.Focused and State.Focused.owner == el then State.Focused = nil end
            State.Overlay = nil
            return true
        end

        rect("ov.bg", ov.x, ov.y, panelW, panelH, Theme.OverlayBg, OP.Overlay * a, Z, 5)
        outline("ov.bd", ov.x, ov.y, panelW, panelH, Theme.OverlayBorder, 0.7 * a, Z + 1, 5)

        if el.searchable then
            local sbx, sby, sbw, sbh = ov.x + 4, ov.y + 4, panelW - 8, 22
            local searching = State.Focused and State.Focused.owner == el
            rect("ov.sb", sbx, sby, sbw, sbh, Theme.Control, searching and 0.95 or OP.Control, Z + 2, 4)
            outline("ov.sbd", sbx, sby, sbw, sbh, searching and Theme.Accent or Theme.ElementBorder, 0.6 * a, Z + 3, 4)
            local stext = el.searchText
            local caret = (searching and math.floor(tick() * 2) % 2 == 0) and "|" or ""
            local shownS = (stext ~= "" and (stext .. caret)) or (caret ~= "" and caret) or el.searchPlaceholder
            text("ov.sbt", shownS, sbx + 8, sby + 4, 12, stext ~= "" and Theme.Text or Theme.SubText, Z + 4, false, a)
            if not ov.closing and Input.clicked and inBounds(sbx, sby, sbw, sbh) then
                State.Focused = {
                    owner = el, id = "search", buf = el.searchText, numeric = false, live = true,
                    onType = function(buf) el.searchText = buf; el.scroll = 0 end,
                    onCommit = function(buf) el.searchText = buf; el.scroll = 0 end,
                }
            end
        end

        -- Handle scroll
        if inBounds(ov.x, ov.y, panelW, panelH) and Input.scroll ~= 0 then
            el.scroll = clamp(el.scroll - Input.scroll, 0, maxScroll)
        end

        local listTop = ov.y + pad + searchH
        for i = 1, visN do
            local opt = filtered[i + el.scroll]
            if opt ~= nil then
                local ry = listTop + (i - 1) * rowH
                local rHover = inBounds(ov.x, ry, panelW - barW, rowH) and not ov.closing
                local selected = el.multi and el.value[opt] or (not el.multi and el.value == opt)
                ov.rowHover[i] = ov.rowHover[i] or newSpring(0, 18)
                ov.rowHover[i].goal = rHover and 1 or 0
                local rh = springStep(ov.rowHover[i], dt)
                rect("ov.r" .. i, ov.x + 2, ry, panelW - 4 - barW, rowH - 2, Theme.TabHighlight, 0.14 * rh * a, Z + 2, 4)
                text("ov.t" .. i, disp(opt), ov.x + 10, ry + 7, 12, selected and Theme.Accent or Theme.Text, Z + 3, false, a)
                if selected then
                    text("ov.m" .. i, "*", ov.x + panelW - barW - 16, ry + 6, 13, Theme.Accent, Z + 3, false, a)
                end
                if rHover and Input.clicked then
                    if el.multi then
                        el.value[opt] = (not el.value[opt]) or nil
                        safe(el.callback, el.value); safe(el.changed, el.value)
                    else
                        if el.allowNull and el.value == opt then el.value = nil else el.value = opt end
                        safe(el.callback, el.value); safe(el.changed, el.value)
                        ov.closing = true
                    end
                end
            end
        end
        if visN == 0 then
            text("ov.t1", "No results", ov.x + 10, listTop + 7, 12, Theme.SubText, Z + 3, false, a)
        end

        if needBar then
            local trackX = ov.x + panelW - barW
            local thumbH = math.max(20, listH * visN / #filtered)
            local thumbY = listTop + (el.scroll / math.max(1, maxScroll)) * (listH - thumbH)
            rect("ov.sbtk", trackX, listTop, barW, listH, Theme.OverlayBorder, 0.5 * a, Z + 2, 2)
            rect("ov.sbth", trackX, thumbY, barW, thumbH, Theme.TabHighlight, 0.6 * a, Z + 3, 2)
            if Input.down and (ov.dragBar or (Input.clicked and inBounds(trackX, listTop, barW, listH))) then
                ov.dragBar = true
                local f = clamp((Input.my - listTop - thumbH / 2) / math.max(1, listH - thumbH), 0, 1)
                el.scroll = math.floor(f * maxScroll + 0.5)
            elseif not Input.down then
                ov.dragBar = false
            end
        end

        if Input.clicked and not ov.closing and not inBounds(ov.x, ov.y, panelW, panelH) then
            ov.closing = true
        end
        return true

    elseif ov.kind == "colorpicker" then
        local el = ov.el
        local pad2, sv, hueW, svN = 10, 120, 14, 50
        local hasA = el.hasAlpha
        local alphaW = 14
        local fieldH = 22
        local panelW = pad2 + sv + 8 + hueW + (hasA and (8 + alphaW) or 0) + pad2
        local innerW = panelW - pad2 * 2
        local panelH = pad2 + sv + 8 + fieldH + 6 + fieldH + 8 + 26 + pad2
        local _, vh = getViewport()
        local win = State.Win
        local px = clamp(ov.ax - panelW, win.x + 4, win.x + win.w - panelW - 4)
        local py = clamp(ov.ay, 8, math.max(8, vh - panelH - 8))
        local svx, svy = px + pad2, py + pad2
        local hx = svx + sv + 8
        local axx = hx + hueW + 8
        local fieldsY = svy + sv + 8
        local rgbY = fieldsY + fieldH + 6
        local btnY = rgbY + fieldH + 8
        local Z2 = 140

        rect("ov.bg", px, py, panelW, panelH, Theme.OverlayBg, OP.Overlay, Z2, 5)
        outline("ov.bd", px, py, panelW, panelH, Theme.OverlayBorder, 0.7, Z2 + 1, 5)

        if Input.down then
            if Input.clicked and inBounds(svx, svy, sv, sv) then ov.drag = "sv"
            elseif Input.clicked and inBounds(hx, svy, hueW, sv) then ov.drag = "hue"
            elseif hasA and Input.clicked and inBounds(axx, svy, alphaW, sv) then ov.drag = "alpha" end
        else
            ov.drag = nil
        end
        if ov.drag and State.Focused and State.Focused.owner == el then State.Focused = nil end
        if ov.drag == "sv" then
            el.s = clamp((Input.mx - svx) / sv, 0, 1)
            el.v = 1 - clamp((Input.my - svy) / sv, 0, 1)
        elseif ov.drag == "hue" then
            el.h = 1 - clamp((Input.my - svy) / sv, 0, 1)
        elseif ov.drag == "alpha" then
            el.alpha = 1 - clamp((Input.my - svy) / sv, 0, 1)
        end
        if ov.drag then
            el.value = Color3.fromHSV(el.h, el.s, el.v)
            safe(el.callback, el.value); safe(el.changed, el.value)
        end

        -- SV grid
        local cell = sv / svN
        local k = 0
        for gx = 0, svN - 1 do
            for gy = 0, svN - 1 do
                k = k + 1
                rect("ov.sv" .. k, math.floor(svx + gx * cell), math.floor(svy + gy * cell),
                    math.ceil(cell), math.ceil(cell),
                    Color3.fromHSV(el.h, (gx + 0.5) / svN, 1 - (gy + 0.5) / svN), 1, Z2 + 2, 0)
            end
        end
        -- Hue bar
        local hcN = 100
        local hcell = sv / hcN
        for i = 0, hcN - 1 do
            rect("ov.hu" .. i, hx, math.floor(svy + i * hcell), hueW, math.ceil(hcell),
                Color3.fromHSV(1 - i / hcN, 1, 1), 1, Z2 + 2, 0)
        end
        -- SV cursor
        outline("ov.svc", svx + el.s * sv - 3, svy + (1 - el.v) * sv - 3, 6, 6,
            Color3.fromRGB(255, 255, 255), 1, Z2 + 3, 0)
        -- Hue cursor
        rect("ov.huc", hx - 2, svy + (1 - el.h) * sv - 1, hueW + 4, 2,
            Color3.fromRGB(255, 255, 255), 1, Z2 + 3, 0)
        -- Alpha bar
        if hasA then
            local aN = 100
            local acell = sv / aN
            local aBack = Color3.fromRGB(48, 48, 48)
            for i = 0, aN - 1 do
                local av = 1 - i / (aN - 1)
                rect("ov.a" .. i, axx, math.floor(svy + i * acell), alphaW, math.ceil(acell) + 1,
                    lerpColor(aBack, el.value, av), 1, Z2 + 2, 0)
            end
            rect("ov.ac", axx - 2, svy + (1 - el.alpha) * sv - 1, alphaW + 4, 2,
                Color3.fromRGB(255, 255, 255), 1, Z2 + 4, 0)
        end

        -- Fields
        local c = el.value
        local cr = math.floor(c.R * 255 + 0.5)
        local cg = math.floor(c.G * 255 + 0.5)
        local cb = math.floor(c.B * 255 + 0.5)
        local hexStr = string.format("#%02X%02X%02X", cr, cg, cb)

        local function fieldFocused(fid)
            return State.Focused and State.Focused.owner == el and State.Focused.id == fid
        end
        local function focusField(fid, seed, onCommit)
            if State.Focused and State.Focused.owner == el and State.Focused.onCommit then
                State.Focused.onCommit(State.Focused.buf)
            end
            State.Focused = {
                owner = el, id = fid, buf = seed,
                numeric = (fid ~= "hex"), live = false,
                onCommit = onCommit,
            }
        end
        local function drawField(fx, fy, fw, fid, valStr, onCommit)
            local foc = fieldFocused(fid)
            rect("ov.f_" .. fid, fx, fy, fw, fieldH, Theme.Control, foc and 0.95 or OP.Control, Z2 + 3, 4)
            outline("ov.fd_" .. fid, fx, fy, fw, fieldH, foc and Theme.Accent or Theme.ElementBorder, 0.6, Z2 + 4, 4)
            local shownF = valStr
            if foc then
                local caret = (math.floor(tick() * 2) % 2 == 0) and "|" or ""
                shownF = State.Focused.buf .. caret
            end
            text("ov.ft_" .. fid, shownF, fx + 6, fy + 4, 12, Theme.Text, Z2 + 5)
            if not foc and Input.clicked and inBounds(fx, fy, fw, fieldH) then
                focusField(fid, valStr, onCommit)
            end
        end

        drawField(px + pad2, fieldsY, innerW, "hex", hexStr, function(buf)
            local ok, col = pcall(Color3.fromHex, (buf:gsub("%s", "")))
            if ok and col then
                el.value = col; el.h, el.s, el.v = rgbToHsv(col)
                safe(el.callback, el.value); safe(el.changed, el.value)
            end
        end)
        local nF = hasA and 4 or 3
        local fw = math.floor((innerW - (nF - 1) * 6) / nF)
        local fx0 = px + pad2
        drawField(fx0, rgbY, fw, "r", tostring(cr), function(buf)
            local n = tonumber(buf)
            if n then
                n = clamp(math.floor(n), 0, 255)
                el.value = Color3.fromRGB(n, cg, cb); el.h, el.s, el.v = rgbToHsv(el.value)
                safe(el.callback, el.value); safe(el.changed, el.value)
            end
        end)
        drawField(fx0 + (fw + 6), rgbY, fw, "g", tostring(cg), function(buf)
            local n = tonumber(buf)
            if n then
                n = clamp(math.floor(n), 0, 255)
                el.value = Color3.fromRGB(cr, n, cb); el.h, el.s, el.v = rgbToHsv(el.value)
                safe(el.callback, el.value); safe(el.changed, el.value)
            end
        end)
        drawField(fx0 + (fw + 6) * 2, rgbY, fw, "b", tostring(cb), function(buf)
            local n = tonumber(buf)
            if n then
                n = clamp(math.floor(n), 0, 255)
                el.value = Color3.fromRGB(cr, cg, n); el.h, el.s, el.v = rgbToHsv(el.value)
                safe(el.callback, el.value); safe(el.changed, el.value)
            end
        end)
        if hasA then
            drawField(fx0 + (fw + 6) * 3, rgbY, fw, "a", tostring(math.floor(el.alpha * 100 + 0.5)), function(buf)
                local n = tonumber(buf)
                if n then el.alpha = clamp(n / 100, 0, 1) end
            end)
        end

        -- Cancel/Done buttons
        local function closePicker()
            if State.Focused and State.Focused.owner == el then State.Focused = nil end
            State.Overlay = nil
        end
        local halfW = math.floor((innerW - 8) / 2)
        local cancelHover = inBounds(px + pad2, btnY, halfW, 26)
        rect("ov.cancel", px + pad2, btnY, halfW, 26, Theme.Control, cancelHover and 0.95 or 0.9, Z2 + 3, 5)
        outline("ov.canceld", px + pad2, btnY, halfW, 26, Theme.OverlayBorder, 0.6, Z2 + 4, 5)
        text("ov.cancelt", "Cancel", px + pad2 + halfW / 2, btnY + 13, 12, Theme.Text, Z2 + 5, true)
        local doneX = px + pad2 + halfW + 8
        local doneHover = inBounds(doneX, btnY, halfW, 26)
        rect("ov.done", doneX, btnY, halfW, 26, Theme.Accent, 1, Z2 + 3, 5)
        outline("ov.doned", doneX, btnY, halfW, 26, Theme.Accent, 0.6, Z2 + 4, 5)
        text("ov.donet", "Done", doneX + halfW / 2, btnY + 13, 12, Color3.fromRGB(15, 15, 15), Z2 + 5, true)
        if Input.clicked then
            if cancelHover then
                el.h, el.s, el.v, el.alpha = ov.origH, ov.origS, ov.origV, ov.origAlpha
                el.value = Color3.fromHSV(el.h, el.s, el.v)
                safe(el.callback, el.value); safe(el.changed, el.value)
                closePicker()
                return true
            elseif doneHover then
                closePicker()
                return true
            end
        end
        if Input.clicked and not ov.drag and not inBounds(px, py, panelW, panelH) then closePicker() end
        return true
    end

    return false
end

-- ═══════════════════════════════════════════════════════
-- Section 11: Spotlight Search
-- ═══════════════════════════════════════════════════════

local function renderSpotlight(dt)
    if not State.SpotlightActive then
        State.SpotlightAnim.goal = 0
        springStep(State.SpotlightAnim, dt)
        return
    end
    State.SpotlightAnim.goal = 1
    local a = springStep(State.SpotlightAnim, dt)
    if a < 0.01 then return end

    local vw, vh = getViewport()
    local pw = 420
    local ph = 44
    local px = math.floor((vw - pw) / 2)
    local py = math.floor(vh * 0.25)
    local Z = 200

    -- Backdrop
    rect("sp.bk", 0, 0, vw, vh, Color3.fromRGB(0, 0, 0), 0.35 * a, Z - 1, 0)

    -- Search bar
    rect("sp.bg", px, py, pw, ph, Theme.OverlayBg, OP.Overlay * a, Z, 8)
    outline("sp.bd", px, py, pw, ph, Theme.Accent, 0.6 * a, Z + 1, 8)
    
    local query = State.SpotlightSearch
    local caret = (math.floor(tick() * 2) % 2 == 0) and "|" or ""
    local shown = query ~= "" and (query .. caret) or (caret ~= "" and caret or "Search elements...")
    text("sp.tx", shown, px + 16, py + 15, 14, query ~= "" and Theme.Text or Theme.SubText, Z + 2, false, a)

    -- Results
    local results = {}
    if query ~= "" then
        local q = query:lower()
        for _, el in ipairs(AllElements) do
            if el.title and el.title:lower():find(q, 1, true) then
                results[#results + 1] = el
                if #results >= 8 then break end
            end
        end
    end

    if #results > 0 then
        local rh = 32
        local resultsH = #results * rh + 8
        rect("sp.rbg", px, py + ph + 4, pw, resultsH, Theme.OverlayBg, OP.Overlay * a, Z, 6)
        outline("sp.rbd", px, py + ph + 4, pw, resultsH, Theme.OverlayBorder, 0.5 * a, Z + 1, 6)

        State.SpotlightSelected = clamp(State.SpotlightSelected, 1, #results)

        for i, el in ipairs(results) do
            local ry = py + ph + 4 + (i - 1) * rh + 4
            local selected = i == State.SpotlightSelected
            local hovered = inBounds(px, ry, pw, rh)
            if hovered then State.SpotlightSelected = i end
            
            if selected then
                rect("sp.sel" .. i, px + 4, ry, pw - 8, rh - 2, Theme.TabHighlight, 0.2 * a, Z + 2, 4)
            end
            -- Find tab name
            local tabName = ""
            for ti, tab in ipairs(Tabs) do
                for _, g in ipairs(tab.groups) do
                    for _, ge in ipairs(g.elements) do
                        if ge == el then tabName = tab.name; break end
                    end
                    if tabName ~= "" then break end
                end
                if tabName ~= "" then break end
            end
            text("sp.rn" .. i, el.title, px + 16, ry + 5, 13, selected and Theme.Accent or Theme.Text, Z + 3, false, a)
            text("sp.rt" .. i, tabName .. " > " .. el.kind, px + pw - 16 - textW(tabName .. " > " .. el.kind, 11), ry + 8, 11, Theme.SubText, Z + 3, false, a)

            if hovered and Input.clicked then
                -- Jump to element's tab
                for ti, tab in ipairs(Tabs) do
                    for _, g in ipairs(tab.groups) do
                        for _, ge in ipairs(g.elements) do
                            if ge == el then
                                State.ActiveTab = ti
                                State.TabCurtain.v = 1
                            end
                        end
                    end
                end
                State.SpotlightActive = false
                State.SpotlightSearch = ""
            end
        end
    end

    -- Handle click outside to close
    if Input.clicked and not inBounds(px, py, pw, ph + (#results > 0 and (#results * 32 + 12) or 0)) then
        State.SpotlightActive = false
        State.SpotlightSearch = ""
    end
end

-- ═══════════════════════════════════════════════════════
-- Section 12: Notification System
-- ═══════════════════════════════════════════════════════

function UI:Notify(cfg)
    cfg = cfg or {}
    NotifId = NotifId + 1
    local lines = {}
    for ln in (tostring(cfg.Content or "") .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = ln
    end
    if #lines > 0 and lines[#lines] == "" then table.remove(lines) end
    Notifs[#Notifs + 1] = {
        id = NotifId, title = cfg.Title or "Notification",
        lines = lines, sub = cfg.SubContent,
        duration = cfg.Duration or 5, born = tick(),
        slide = newSpring(1, 13), alpha = newSpring(0, 13),
        dying = false,
    }
end

local function renderNotifs(dt)
    if #Notifs == 0 then return end
    local vw, vh = getViewport()
    local margin, w, Z = 16, 300, 200
    local now = tick()
    local y = vh - margin
    for idx = #Notifs, 1, -1 do
        local n = Notifs[idx]
        if n.duration and not n.dying and (now - n.born) > n.duration then
            n.dying = true; n.diedAt = now; n.slide.goal = 1; n.alpha.goal = 0
        end
        if n.dying and (now - (n.diedAt or now)) > 0.4 then
            table.remove(Notifs, idx)
        else
            springStep(n.slide, dt); springStep(n.alpha, dt)
            local hh = 14 + 18 + #n.lines * 15 + (n.sub and 16 or 0) + 12
            y = y - hh
            local nx = vw - margin - w + n.slide.v * (w + margin + 8)
            local a = n.alpha.v
            rect("nf.bg" .. n.id, nx, y, w, hh, Theme.OverlayBg, OP.Overlay * a, Z, 6)
            outline("nf.bd" .. n.id, nx, y, w, hh, Theme.Accent, 0.5 * a, Z + 1, 6)
            text("nf.t" .. n.id, n.title, nx + 14, y + 12, 13, Theme.Text, Z + 2, false, a)
            -- Close X
            local cx = nx + w - 22
            text("nf.x" .. n.id, "x", cx, y + 11, 14, Theme.SubText, Z + 3, false, a)
            if not n.dying and Input.clicked and inBounds(cx - 5, y + 8, 20, 20) then
                n.dying = true; n.diedAt = now; n.slide.goal = 1; n.alpha.goal = 0
            end
            local ly = y + 32
            for li, ln in ipairs(n.lines) do
                text("nf.c" .. n.id .. "_" .. li, ln, nx + 14, ly, 12, Theme.SubText, Z + 2, false, a)
                ly = ly + 15
            end
            if n.sub then
                text("nf.s" .. n.id, n.sub, nx + 14, ly, 11, Color3.fromRGB(120, 120, 120), Z + 2, false, a)
            end
            y = y - 10
        end
    end
end

-- ═══════════════════════════════════════════════════════
-- Section 13: Dialog System
-- ═══════════════════════════════════════════════════════

local function renderDialog(dt)
    local d = State.Dialog
    if not d then return end
    local vw, vh = getViewport()
    d.anim = d.anim or newSpring(0, 20)
    d.anim.goal = d.closing and 0 or 1
    local a = springStep(d.anim, dt)
    if d.closing and a < 0.04 then State.Dialog = nil; return end
    rect("dlg.bk", 0, 0, vw, vh, Color3.fromRGB(0, 0, 0), 0.5 * a, 145, 0)
    local bw = 340
    local bh = 16 + 24 + #d.lines * 16 + 18 + 36
    local bx = math.floor((vw - bw) / 2)
    local by = math.floor((vh - bh) / 2) + math.floor((1 - a) * 12)
    rect("dlg.bg", bx, by, bw, bh, Theme.OverlayBg, a, 150, 8)
    outline("dlg.bd", bx, by, bw, bh, Theme.OverlayBorder, 0.8 * a, 151, 8)
    text("dlg.t", d.title, bx + 18, by + 15, 15, Theme.Text, 152, false, a)
    local ly = by + 44
    for li, ln in ipairs(d.lines) do
        text("dlg.c" .. li, ln, bx + 18, ly, 12, Theme.SubText, 152, false, a)
        ly = ly + 16
    end
    local nb = #d.buttons
    local padD = 18
    local btnW = math.floor((bw - padD * 2 - (nb - 1) * 10) / math.max(1, nb))
    local btnYd = by + bh - padD - 28
    for i, b in ipairs(d.buttons) do
        local btnX = bx + padD + (i - 1) * (btnW + 10)
        local accent = (i == 1)
        local bHover = inBounds(btnX, btnYd, btnW, 28)
        rect("dlg.btn" .. i, btnX, btnYd, btnW, 28, accent and Theme.Accent or Theme.Control,
            (accent and 1 or (bHover and 0.95 or 0.9)) * a, 152, 5)
        outline("dlg.btb" .. i, btnX, btnYd, btnW, 28, accent and Theme.Accent or Theme.OverlayBorder, 0.6 * a, 153, 5)
        local label = b.Title or "OK"
        text("dlg.btx" .. i, label, btnX + btnW / 2, btnYd + 14, 12,
            accent and Color3.fromRGB(15, 15, 15) or Theme.Text, 153, true, a)
        if bHover and Input.clicked and not d.closing then
            d.closing = true
            safe(b.Callback)
        end
    end
end

-- ═══════════════════════════════════════════════════════
-- Section 14: Watermark
-- ═══════════════════════════════════════════════════════

local function renderWatermark(dt)
    if not State.WatermarkEnabled then return end
    local label = UI.Title or "Jade"
    if UI.SubTitle and UI.SubTitle ~= "" then label = label .. " | " .. UI.SubTitle end
    -- Add FPS
    local fps = math.floor(1 / math.max(0.001, dt) + 0.5)
    label = label .. " | " .. fps .. " FPS"

    local pw = math.floor(28 + textW(label, 12))
    local ph = 26
    local Z = 250
    local bp = State.WatermarkPos or { x = 10, y = 10 }
    State.WatermarkPos = bp

    if Input.down and not State.Drag and not State.Resizing then
        if not State.WatermarkDrag and Input.clicked and inBounds(bp.x, bp.y, pw, ph) then
            State.WatermarkDrag = true
            State.WatermarkOff = Vector2.new(Input.mx - bp.x, Input.my - bp.y)
        end
        if State.WatermarkDrag then
            bp.x = Input.mx - State.WatermarkOff.X
            bp.y = Input.my - State.WatermarkOff.Y
        end
    else
        State.WatermarkDrag = false
    end

    rect("wm.bg", bp.x, bp.y, pw, ph, Theme.WindowBg, OP.Window, Z, 6)
    outline("wm.bd", bp.x, bp.y, pw, ph, Theme.Accent, 0.5, Z + 1, 6)
    text("wm.tx", label, bp.x + 14, bp.y + 7, 12, Theme.Title, Z + 2)
end

-- ═══════════════════════════════════════════════════════
-- Section 15: Tooltip System
-- ═══════════════════════════════════════════════════════

local function renderTooltip(dt)
    if not State.TooltipText or State.TooltipTimer < 0.5 then
        -- fade out
        return
    end
    local tip = State.TooltipText
    local lines = wrapText(tip, 200, 11)
    local tw = 0
    for _, ln in ipairs(lines) do
        tw = math.max(tw, textW(ln, 11))
    end
    local pw = tw + 16
    local ph = #lines * 14 + 10
    local tx, ty = State.TooltipX, State.TooltipY
    local vw, vh = getViewport()
    if tx + pw > vw - 8 then tx = vw - pw - 8 end
    if ty + ph > vh - 8 then ty = ty - ph - 28 end
    local Z = 180

    rect("tip.bg", tx, ty, pw, ph, Theme.OverlayBg, 0.95, Z, 5)
    outline("tip.bd", tx, ty, pw, ph, Theme.OverlayBorder, 0.6, Z + 1, 5)
    for i, ln in ipairs(lines) do
        text("tip.l" .. i, ln, tx + 8, ty + 5 + (i - 1) * 14, 11, Theme.Text, Z + 2)
    end
end

-- ═══════════════════════════════════════════════════════
-- Section 16-17: (Config & Settings already built above)
-- ═══════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════
-- Section 18: Main Loop + API
-- ═══════════════════════════════════════════════════════

local function pollKeybinds(ck)
    if State.KBListening then
        local el = State.KBListening
        for _, vk in ipairs(ScanList) do
            if vk ~= 0x01 and ck(vk) then
                if vk == 0x1B then
                    State.KBListening = nil
                elseif vk == 0x2E then
                    -- Delete = unbind
                    el.key = nil; el.keyName = "None"; State.KBListening = nil
                    if el.changedCallback then el.changedCallback(nil) end
                    if el.changed then el.changed("None") end
                else
                    el.key = vk; el.keyName = KeyName[vk] or tostring(vk)
                    State.KBListening = nil
                    if el.changedCallback then el.changedCallback(el.keyName) end
                    if el.changed then el.changed(el.keyName) end
                end
                break
            end
        end
        return
    end
    for _, kb in ipairs(AllKeybinds) do
        local key = kb.key
        if not key and kb.owner then
            -- keybind on toggle
        end
        if key and ck(key) then
            if kb.owner then
                -- Toggle keybind on a toggle element
                local el = kb.owner
                el.value = not el.value
                el.anim.goal = el.value and 1 or 0
                safe(el.callback, el.value)
            elseif kb.DoClick then
                kb.DoClick()
            end
        end
    end
end

local function pollTextInput(ck)
    local f = State.Focused
    if not f then return end
    if ck(0x0D) then
        if f.onCommit then f.onCommit(f.buf) end
        State.Focused = nil
        return
    end
    if ck(0x1B) then State.Focused = nil; return end
    local changed = false
    if ck(0x08) then
        if #f.buf > 0 then f.buf = f.buf:sub(1, -2); changed = true end
    end
    local shift = _iskeypressed(0x10) or _iskeypressed(0xA0) or _iskeypressed(0xA1)
    for _, vk in ipairs(CharScanList) do
        if ck(vk) then
            local m = CharMap[vk]
            local chr = m and (shift and m[2] or m[1])
            if chr and (not f.numeric or chr:match("[%d%.%-]")) then
                if not f.maxLength or #f.buf < f.maxLength then
                    f.buf = f.buf .. chr
                    changed = true
                end
            end
        end
    end
    if changed and f.live and f.onType then f.onType(f.buf) end
end

local function pollSpotlightInput(ck)
    if not State.SpotlightActive then return end
    -- Spotlight text input
    if ck(0x1B) then
        State.SpotlightActive = false
        State.SpotlightSearch = ""
        return
    end
    if ck(0x0D) then
        -- Select current result
        local results = {}
        if State.SpotlightSearch ~= "" then
            local q = State.SpotlightSearch:lower()
            for _, el in ipairs(AllElements) do
                if el.title and el.title:lower():find(q, 1, true) then
                    results[#results + 1] = el
                    if #results >= 8 then break end
                end
            end
        end
        local sel = results[State.SpotlightSelected]
        if sel then
            for ti, tab in ipairs(Tabs) do
                for _, g in ipairs(tab.groups) do
                    for _, ge in ipairs(g.elements) do
                        if ge == sel then
                            State.ActiveTab = ti
                            State.TabCurtain.v = 1
                        end
                    end
                end
            end
        end
        State.SpotlightActive = false
        State.SpotlightSearch = ""
        return
    end
    if ck(0x26) then -- Up
        State.SpotlightSelected = math.max(1, State.SpotlightSelected - 1)
        return
    end
    if ck(0x28) then -- Down
        State.SpotlightSelected = State.SpotlightSelected + 1
        return
    end
    if ck(0x08) then
        if #State.SpotlightSearch > 0 then
            State.SpotlightSearch = State.SpotlightSearch:sub(1, -2)
            State.SpotlightSelected = 1
        end
        return
    end
    local shift = _iskeypressed(0x10)
    for _, vk in ipairs(CharScanList) do
        if ck(vk) then
            local m = CharMap[vk]
            local chr = m and (shift and m[2] or m[1])
            if chr then
                State.SpotlightSearch = State.SpotlightSearch .. chr
                State.SpotlightSelected = 1
            end
        end
    end
end

local function renderBubble(dt)
    local bp = State.BubblePos
    local label = UI.Title or "Jade"
    if UI.SubTitle and UI.SubTitle ~= "" then label = label .. "  " .. UI.SubTitle end
    local pw = math.floor(46 + textW(label, 13))
    local ph = 32
    local hovered = inBounds(bp.x, bp.y, pw, ph)
    if Input.down then
        if not State.BubbleDrag and hovered then
            State.BubbleDrag = true; State.BubbleMoved = false
            State.BubbleOff = Vector2.new(Input.mx - bp.x, Input.my - bp.y)
        end
        if State.BubbleDrag then
            local nx = math.floor(Input.mx - State.BubbleOff.X)
            local ny = math.floor(Input.my - State.BubbleOff.Y)
            if math.abs(nx - bp.x) > 2 or math.abs(ny - bp.y) > 2 then State.BubbleMoved = true end
            bp.x, bp.y = nx, ny
        end
    else
        if State.BubbleDrag and not State.BubbleMoved then UI:Minimize() end
        State.BubbleDrag = false
    end
    rect("bub.bg", bp.x, bp.y, pw, ph, Theme.WindowBg, OP.Window, 120, 9)
    outline("bub.bd", bp.x, bp.y, pw, ph, hovered and Theme.Accent or Theme.WindowBorder,
        hovered and 0.7 or OP.Border, 121, 9)
    drawCircle("bub.dot", bp.x + 18, bp.y + ph / 2, 5, Theme.Accent, 1, 122, true)
    text("bub.tx", label, bp.x + 32, bp.y + 9, 13, Theme.Title, 122)
end

local function renderWindow(dt)
    local win = State.Win

    -- Resize grip
    local gripN = 14
    local gx, gy = win.x + win.w - gripN, win.y + win.h - gripN
    if Input.down then
        if not State.Drag and not State.Resizing and not State.Overlay then
            if inBounds(gx, gy, gripN, gripN) then
                State.Resizing = true
            elseif inBounds(win.x, win.y, win.w - 84, TITLE_H) then
                if State.Maximized then UI:Maximize(false) end
                State.Drag = true
                State.DragOff = Vector2.new(clamp(Input.mx - win.x, 0, win.w - 40), Input.my - win.y)
            end
        end
    else
        State.Drag = false
        State.Resizing = false
    end
    if State.Drag then
        win.x = math.floor(Input.mx - State.DragOff.X)
        win.y = math.floor(Input.my - State.DragOff.Y)
    elseif State.Resizing then
        local vw, vh = getViewport()
        win.w = clamp(math.floor(Input.mx - win.x), State.MinW, vw - win.x - 4)
        win.h = clamp(math.floor(Input.my - win.y), State.MinH, vh - win.y - 4)
        gx, gy = win.x + win.w - gripN, win.y + win.h - gripN
    end
    local gripHover = State.Resizing or inBounds(gx, gy, gripN, gripN)
    drawLine("win.grip1", gx + 5, win.y + win.h - 3, win.x + win.w - 3, gy + 5, Theme.SubText, gripHover and 0.9 or 0.45, 62)
    drawLine("win.grip2", gx + 9, win.y + win.h - 3, win.x + win.w - 3, gy + 9, Theme.SubText, gripHover and 0.9 or 0.45, 62)

    -- Window bg
    outline("win.bd", win.x - 1, win.y - 1, win.w + 2, win.h + 2, Theme.WindowBorder, OP.Border, 10, 9)
    rect("win.bg", win.x, win.y, win.w, win.h, Theme.WindowBg, OP.Window, 11, 8)

    local block = renderOverlay(dt)
    if State.Dialog then block = true end

    -- Content area
    local cvy = win.y + TITLE_H + 1
    local cvh = win.h - TITLE_H - 1
    local viewBottom = cvy + cvh
    local tab = Tabs[State.ActiveTab]
    if tab then
        local topPad, gap = 14, 8
        local totalH = topPad * 2
        for _, g in ipairs(tab.groups) do
            if g.title then totalH = totalH + 30 + gap end
            for _, el in ipairs(g.elements) do
                if el.visible ~= false then
                    totalH = totalH + cardHeight(el) + gap
                end
            end
        end
        totalH = totalH - gap
        local maxScroll = math.max(0, totalH - cvh)

        -- Scroll with mouse wheel
        if inBounds(win.x + RAIL_W, cvy, win.w - RAIL_W, cvh) and Input.scroll ~= 0 and not State.Overlay then
            tab.scroll = clamp((tab.scroll or 0) - Input.scroll * 28, 0, maxScroll)
        end
        tab.scroll = clamp(tab.scroll or 0, 0, maxScroll)

        -- Scrollbar
        local barW = 0
        if maxScroll > 0 then
            barW = 6
            local barX = win.x + win.w - 8
            local trackY, trackH = cvy + 4, cvh - 8
            local thumbH = math.max(24, trackH * cvh / totalH)
            if Input.down and not block and not State.Resizing and (State.BarDrag or (Input.clicked and inBounds(barX - 3, cvy, 14, cvh))) then
                State.BarDrag = true
                local f = clamp((Input.my - trackY - thumbH / 2) / math.max(1, trackH - thumbH), 0, 1)
                tab.scroll = f * maxScroll
            elseif not Input.down then
                State.BarDrag = false
            end
            tab.scroll = clamp(tab.scroll, 0, maxScroll)
            local thumbY = trackY + (tab.scroll / maxScroll) * (trackH - thumbH)
            rect("win.sbtk", barX, trackY, barW, trackH, Theme.OverlayBorder, 0.4, 20, 2)
            rect("win.sbth", barX, thumbY, barW, thumbH, Theme.TabHighlight, 0.5, 21, 2)
        end

        -- Render elements
        local cx = win.x + RAIL_W + 14
        local cw = win.w - RAIL_W - 28 - (barW > 0 and 8 or 0)
        local cy = cvy + topPad - tab.scroll
        local mouseInView = Input.mx > win.x + RAIL_W and Input.my > cvy and Input.my < viewBottom
        local idx = 0
        for _, g in ipairs(tab.groups) do
            if g.title then
                idx = idx + 1
                local hh = 30
                if cy + hh > cvy and cy < viewBottom then
                    -- Section header
                    text("t" .. State.ActiveTab .. "g" .. idx, g.title, cx + 2, cy + 10, 15, Theme.Text, 22)
                    -- Collapse toggle
                    local colX = cx + cw - 14
                    local colHover = mouseInView and inBounds(colX - 6, cy + 4, 20, 20)
                    if g.collapsed then
                        drawTriangle("t" .. State.ActiveTab .. "gc" .. idx,
                            colX, cy + 8, colX, cy + 20, colX + 7, cy + 14,
                            colHover and Theme.Accent or Theme.SubText, 1, 23, true)
                    else
                        drawTriangle("t" .. State.ActiveTab .. "gc" .. idx,
                            colX - 3, cy + 10, colX + 7, cy + 10, colX + 2, cy + 18,
                            colHover and Theme.Accent or Theme.SubText, 1, 23, true)
                    end
                    if colHover and Input.clicked then
                        g.collapsed = not g.collapsed
                    end
                end
                cy = cy + hh + gap
            end
            if not g.collapsed then
                for _, el in ipairs(g.elements) do
                    -- Check dependency
                    if el.dependsOn then
                        local parent = el.dependsOn._el or el.dependsOn
                        if parent and parent.value == false then
                            el.visible = false
                            -- skip rendering
                        else
                            el.visible = true
                        end
                    end
                    if el.visible ~= false then
                        idx = idx + 1
                        local hh = cardHeight(el)
                        local top, bot = cy, cy + hh
                        if top >= cvy - 5 and bot <= viewBottom + 5 then
                            processEl(el, "t" .. State.ActiveTab .. "e" .. idx, cx, cy, cw, hh, dt, 20, block or not mouseInView)
                        else
                            -- Hide elements outside bounds to prevent bleeding
                            local c1 = Cache["t" .. State.ActiveTab .. "e" .. idx .. ".bg"]
                            if c1 and c1.Obj then c1.Obj.Visible = false end
                        end
                        cy = cy + hh + gap
                    end
                end
            end
        end
    end

    -- Tab curtain transition
    springStep(State.TabCurtain, dt)
    if State.TabCurtain.v > 0.01 then
        rect("win.curtain", win.x + RAIL_W + 1, cvy, win.w - RAIL_W - 1, cvh,
            Theme.WindowBg, math.min(1, State.TabCurtain.v), 50, 0)
    end

    -- Window Glow & Accent Line
    glow("win.glow", win.x, win.y, win.w, win.h, Color3.new(0,0,0), 0.4, 57, 8, 4)
    rect("win.accent", win.x + RAIL_W, win.y + TITLE_H - 1, win.w - RAIL_W, 1, Theme.Accent, 1, 60, 0)

    -- Title bar (drawn on top of content)
    rect("win.tbmask", win.x, win.y, win.w, TITLE_H, Theme.WindowBg, OP.Window, 58, 8)
    text("win.title", UI.Title or "Jade", win.x + 18, win.y + 13, 18, Theme.Title, 62)
    if UI.SubTitle and UI.SubTitle ~= "" then
        text("win.sub", UI.SubTitle, win.x + 18 + textW(UI.Title or "Jade", 18) + 10, win.y + 18, 13, Theme.SubText, 62)
    end

    -- Minimize button
    local mbW, mbH = 28, 22
    local mbX = win.x + win.w - 16 - mbW
    local mbY = win.y + 11
    local mbHover = not block and inBounds(mbX, mbY, mbW, mbH)
    rect("win.minbg", mbX, mbY, mbW, mbH, Theme.Control, mbHover and 0.6 or 0, 60, 5)
    drawLine("win.min", mbX + 9, mbY + math.floor(mbH / 2), mbX + mbW - 9, mbY + math.floor(mbH / 2), Theme.Text, 0.9, 61)
    if mbHover and Input.clicked then UI:Minimize() end

    -- Maximize button
    local mxW = 28
    local mxX = mbX - 6 - mxW
    local mxY = win.y + 11
    local mxHover = not block and inBounds(mxX, mxY, mxW, mbH)
    rect("win.maxbg", mxX, mxY, mxW, mbH, Theme.Control, mxHover and 0.6 or 0, 60, 5)
    outline("win.max", mxX + 9, mxY + 6, mxW - 18, mbH - 12, Theme.Text, 0.9, 61, 2)
    if mxHover and Input.clicked then UI:Maximize() end

    -- Title bar line + rail line
    drawLine("win.tline", win.x, win.y + TITLE_H, win.x + win.w, win.y + TITLE_H, Theme.TitleBarLine, 0.5, 59)
    drawLine("win.rline", win.x + RAIL_W, win.y + TITLE_H, win.x + RAIL_W, win.y + win.h, Theme.RailLine, OP.Rail, 59)

    -- Tab list
    local tabY0 = win.y + TITLE_H + 10
    for i, t in ipairs(Tabs) do
        local ty = tabY0 + (i - 1) * 36
        local tx = win.x + 8
        local tw = RAIL_W - 16
        local active = (i == State.ActiveTab)
        local hovered = inBounds(tx, ty, tw, 30) and not block
        if hovered and Input.clicked and not active then
            State.ActiveTab = i; State.Overlay = nil; State.Focused = nil
            State.TabCurtain.v = 1
        end
        rect("tab.hl" .. i, tx, ty, tw, 30, Theme.TabHighlight,
            active and OP.TabActive or (hovered and OP.TabHover or 0), 60, 6)
        text("tab.tx" .. i, t.name, tx + 14, ty + 8, 13,
            active and Theme.TabTextActive or Theme.TabText, 61)
    end

    -- Active tab indicator
    State.IndOff.goal = (State.ActiveTab - 1) * 36
    if not State.IndInit then State.IndOff.v = State.IndOff.goal; State.IndInit = true end
    springStep(State.IndOff, dt)
    rect("tab.ind", win.x + 8, tabY0 + State.IndOff.v + 7, 3, 16, Theme.Accent, 1, 61, 2)
end

function UI:Minimize()
    State.Minimized = not State.Minimized
    State.Overlay = nil; State.Focused = nil; State.KBListening = nil
    _setrobloxinput(State.Minimized)
end

function UI:Maximize(toggle)
    if toggle == false or State.Maximized then
        if State.MaxPrev then
            State.Win.x = State.MaxPrev.x
            State.Win.y = State.MaxPrev.y
            State.Win.w = State.MaxPrev.w
            State.Win.h = State.MaxPrev.h
        end
        State.Maximized = false
    else
        State.MaxPrev = { x = State.Win.x, y = State.Win.y, w = State.Win.w, h = State.Win.h }
        local vw, vh = getViewport()
        State.Win.x = 4; State.Win.y = 4
        State.Win.w = vw - 8; State.Win.h = vh - 8
        State.Maximized = true
    end
end

-- Main step function
local function step()
    if not _isrbxactive() then return end
    State.InStep = true
    CurTick = CurTick + 1
    local now = tick()
    local dt = State.LastTime and (now - State.LastTime) or 0.016
    if dt > 0.1 then dt = 0.1 elseif dt < 0 then dt = 0.016 end
    State.LastTime = now
    State.Vw, State.Vh = getViewport()

    pollInput()
    local clicks = {}
    local function ck(vk)
        local c = clicks[vk]
        if c == nil then c = keyEdge(vk); clicks[vk] = c end
        return c
    end

    -- Reset tooltip
    State.TooltipText = nil
    local prevHover = State.TooltipHoverEl
    State.TooltipHoverEl = nil

    local busy = State.KBListening ~= nil or State.Focused ~= nil or State.SpotlightActive

    -- Spotlight toggle: Ctrl+Space
    if not State.KBListening and not State.Focused then
        if (_iskeypressed(0x11) or _iskeypressed(0xA2) or _iskeypressed(0xA3)) and ck(0x20) then
            State.SpotlightActive = not State.SpotlightActive
            State.SpotlightSearch = ""
            State.SpotlightSelected = 1
        end
    end

    if State.SpotlightActive then
        pollSpotlightInput(ck)
    else
        pollKeybinds(ck)
        pollTextInput(ck)
        if not busy and ck(State.MenuKey) then UI:Minimize() end
    end

    -- Render
    if State.Minimized then
        renderBubble(dt)
    else
        renderWindow(dt)
    end
    renderSpotlight(dt)
    renderDialog(dt)
    renderNotifs(dt)
    renderWatermark(dt)

    -- Tooltip (only if hovered same el as before)
    if State.TooltipHoverEl and State.TooltipHoverEl == prevHover then
        -- timer continues
    else
        State.TooltipTimer = 0
    end
    renderTooltip(dt)

    cleanupDrawings()
    State.InStep = false
end

function UI:Start()
    local prev = _G.__Jade
    if prev and prev ~= UI and prev._RemoveAll then
        pcall(function() prev:_RemoveAll() end)
    end
    _G.__Jade = UI
    if State.Running then
        _G.__JadeToken = State.Token
        return
    end
    local token = {}
    _G.__JadeToken = token; State.Token = token; State.Running = true
    UI.Loaded = true; UI.Unloaded = false
    task.spawn(function()
        while _G.__JadeToken == token do
            local ok, err = pcall(step)
            if not ok then warn("[Jade] " .. tostring(err)) end
            State.InStep = false
            Input.prevDown = Input.down
            Input.scroll = 0
            task.wait()
        end
        State.Running = false
        UI.Loaded = false
        pcall(function() UI:_RemoveAll() end)
    end)
end

function UI:Stop()
    if _G.__JadeToken == State.Token then _G.__JadeToken = nil end
    State.Running = false
    removeAllDrawings()
end

function UI:Destroy()
    UI.Unloaded = true
    UI.Loaded = false
    UI:Stop()
end

function UI:_RemoveAll()
    removeAllDrawings()
end

function UI:SetTheme(name)
    if Palettes[name] then
        setTheme(name)
        State.ThemeName = name
    end
end

-- Auto-start if AutoStep not disabled
-- (Caller controls when to call Jade:Start())
-- Global 'Jade' is already set, no return needed for loadstring usage
