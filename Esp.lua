-- Exact Player-Bound ESP for Roblox
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local ESP = {
    Enabled = true,
    ShowTeam = false,
    BoxColor = Color3.fromRGB(0, 255, 0),
    TracerColor = Color3.fromRGB(255, 0, 0),
    TextColor = Color3.fromRGB(255, 255, 255),
    TextSize = 14,
    TracerOrigin = "Bottom", -- "Bottom", "Middle", "Top"
    BoxThickness = 1,
    UseExactBounds = true, -- Toggle between exact bounds vs simple bounds
    UpdateFrequency = 1 -- Frames between bounding box recalculations (1 = every frame)
}

local ESPStore = {}
local connections = {}
local frameCounter = 0

-- Function to get precise bounding box corners in world space
local function getCharacterBoundingBox(character)
    if not character or not character:IsA("Model") then return nil end
    
    local success, boundingBox = pcall(function()
        return character:GetBoundingBox()
    end)
    
    if not success or not boundingBox then
        -- Fallback: Estimate from HumanoidRootPart
        local hrp = character:FindFirstChild("HumanoidRootPart")
        if hrp then
            local size = Vector3.new(4, 6, 2) -- Approximate human size
            local cf = hrp.CFrame
            local min = cf.Position - size/2
            local max = cf.Position + size/2
            return CFrame.new((min + max)/2), size
        end
        return nil
    end
    
    return boundingBox
end

-- Function to calculate 2D screen bounds from 3D bounding box
local function calculateExactScreenBounds(character)
    local bbox = getCharacterBoundingBox(character)
    if not bbox then return nil, false end
    
    local cf, size = bbox
    local halfSize = size / 2
    
    -- Define all 8 corners of the bounding box
    local corners = {
        cf * CFrame.new(-halfSize.X, -halfSize.Y, -halfSize.Z),
        cf * CFrame.new(halfSize.X, -halfSize.Y, -halfSize.Z),
        cf * CFrame.new(-halfSize.X, halfSize.Y, -halfSize.Z),
        cf * CFrame.new(halfSize.X, halfSize.Y, -halfSize.Z),
        cf * CFrame.new(-halfSize.X, -halfSize.Y, halfSize.Z),
        cf * CFrame.new(halfSize.X, -halfSize.Y, halfSize.Z),
        cf * CFrame.new(-halfSize.X, halfSize.Y, halfSize.Z),
        cf * CFrame.new(halfSize.X, halfSize.Y, halfSize.Z)
    }
    
    -- Project all corners to screen space
    local minX, maxX = math.huge, -math.huge
    local minY, maxY = math.huge, -math.huge
    local anyOnScreen = false
    
    for _, cornerCF in ipairs(corners) do
        local screenPos, onScreen = Camera:WorldToViewportPoint(cornerCF.Position)
        if onScreen then
            anyOnScreen = true
            minX = math.min(minX, screenPos.X)
            maxX = math.max(maxX, screenPos.X)
            minY = math.min(minY, screenPos.Y)
            maxY = math.max(maxY, screenPos.Y)
        end
    end
    
    if not anyOnScreen then
        return nil, false
    end
    
    -- Return the exact bounding rectangle
    return {
        TopLeft = Vector2.new(minX, minY),
        TopRight = Vector2.new(maxX, minY),
        BottomLeft = Vector2.new(minX, maxY),
        BottomRight = Vector2.new(maxX, maxY),
        Center = Vector2.new((minX + maxX) / 2, (minY + maxY) / 2),
        Width = maxX - minX,
        Height = maxY - minY
    }, true
end

-- Function to calculate simple screen bounds (faster, less accurate)
local function calculateSimpleScreenBounds(character)
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil, false end
    
    local screenPos, onScreen = Camera:WorldToViewportPoint(hrp.Position)
    if not onScreen then return nil, false end
    
    local distance = (Camera.CFrame.Position - hrp.Position).Magnitude
    local scale = math.clamp(100 / distance, 0.5, 2)
    
    -- Estimate character dimensions
    local width = 30 * scale
    local height = 60 * scale
    
    return {
        TopLeft = Vector2.new(screenPos.X - width/2, screenPos.Y - height/2),
        TopRight = Vector2.new(screenPos.X + width/2, screenPos.Y - height/2),
        BottomLeft = Vector2.new(screenPos.X - width/2, screenPos.Y + height/2),
        BottomRight = Vector2.new(screenPos.X + width/2, screenPos.Y + height/2),
        Center = Vector2.new(screenPos.X, screenPos.Y),
        Width = width,
        Height = height
    }, true
end

local function createESP(player)
    if ESPStore[player] then return end
    
    local drawings = {
        boxTop = Drawing.new("Line"),
        boxRight = Drawing.new("Line"),
        boxBottom = Drawing.new("Line"),
        boxLeft = Drawing.new("Line"),
        tracer = Drawing.new("Line"),
        nameLabel = Drawing.new("Text"),
        distanceLabel = Drawing.new("Text"),
        healthBarOutline = Drawing.new("Line"),
        healthBarFill = Drawing.new("Line")
    }
    
    -- Configure drawing objects
    for name, drawing in pairs(drawings) do
        if drawing.ClassName == "Line" then
            drawing.Thickness = ESP.BoxThickness
            drawing.ZIndex = name:find("health") and 2 or 1
        elseif drawing.ClassName == "Text" then
            drawing.Size = ESP.TextSize
            drawing.Center = true
            drawing.Outline = true
            drawing.ZIndex = 1
        end
    end
    
    -- Set initial colors
    for _, lineName in ipairs({"boxTop", "boxRight", "boxBottom", "boxLeft"}) do
        drawings[lineName].Color = ESP.BoxColor
    end
    drawings.tracer.Color = ESP.TracerColor
    drawings.nameLabel.Color = ESP.TextColor
    drawings.distanceLabel.Color = ESP.TextColor
    drawings.healthBarOutline.Color = Color3.fromRGB(0, 0, 0)
    
    ESPStore[player] = {
        drawings = drawings,
        character = nil,
        connection = nil,
        lastBounds = nil,
        updateFrame = 0
    }
    
    local function characterAdded(character)
        ESPStore[player].character = character
        local humanoid = character:WaitForChild("Humanoid", 5)
        
        if not humanoid then return end
        
        -- Update loop for this character
        ESPStore[player].connection = RunService.RenderStepped:Connect(function()
            frameCounter = frameCounter + 1
            
            if not ESP.Enabled or not Camera or not character.Parent then
                for _, drawing in pairs(drawings) do
                    drawing.Visible = false
                end
                return
            end
            
            -- Team check
            if not ESP.ShowTeam and player.Team and LocalPlayer.Team and player.Team == LocalPlayer.Team then
                for _, drawing in pairs(drawings) do
                    drawing.Visible = false
                end
                return
            end
            
            -- Health check
            if humanoid.Health <= 0 then
                for _, drawing in pairs(drawings) do
                    drawing.Visible = false
                end
                return
            end
            
            -- Calculate bounds (with frequency control)
            local bounds, onScreen
            local shouldRecalc = (frameCounter - ESPStore[player].updateFrame) >= ESP.UpdateFrequency
            
            if shouldRecalc then
                if ESP.UseExactBounds then
                    bounds, onScreen = calculateExactScreenBounds(character)
                else
                    bounds, onScreen = calculateSimpleScreenBounds(character)
                end
                ESPStore[player].lastBounds = bounds
                ESPStore[player].updateFrame = frameCounter
            else
                bounds = ESPStore[player].lastBounds
                onScreen = bounds ~= nil
            end
            
            if not onScreen then
                for _, drawing in pairs(drawings) do
                    drawing.Visible = false
                end
                return
            end
            
            -- Update box lines (exact bounds)
            drawings.boxTop.From = bounds.TopLeft
            drawings.boxTop.To = bounds.TopRight
            drawings.boxTop.Visible = true
            
            drawings.boxRight.From = bounds.TopRight
            drawings.boxRight.To = bounds.BottomRight
            drawings.boxRight.Visible = true
            
            drawings.boxBottom.From = bounds.BottomLeft
            drawings.boxBottom.To = bounds.BottomRight
            drawings.boxBottom.Visible = true
            
            drawings.boxLeft.From = bounds.TopLeft
            drawings.boxLeft.To = bounds.BottomLeft
            drawings.boxLeft.Visible = true
            
            -- Update tracer
            local tracerOriginY
            if ESP.TracerOrigin == "Top" then
                tracerOriginY = 0
            elseif ESP.TracerOrigin == "Middle" then
                tracerOriginY = Camera.ViewportSize.Y / 2
            else -- Bottom
                tracerOriginY = Camera.ViewportSize.Y
            end
            
            drawings.tracer.From = Vector2.new(Camera.ViewportSize.X / 2, tracerOriginY)
            drawings.tracer.To = bounds.Center
            drawings.tracer.Visible = true
            
            -- Update name label (above box)
            drawings.nameLabel.Position = Vector2.new(bounds.Center.X, bounds.TopLeft.Y - 20)
            drawings.nameLabel.Text = player.Name
            drawings.nameLabel.Visible = true
            
            -- Update distance label (below box)
            local distance = (Camera.CFrame.Position - character:GetPivot().Position).Magnitude
            drawings.distanceLabel.Position = Vector2.new(bounds.Center.X, bounds.BottomRight.Y + 10)
            drawings.distanceLabel.Text = tostring(math.floor(distance)) .. " studs"
            drawings.distanceLabel.Visible = true
            
            -- Update health bar (left of box)
            local healthPercent = humanoid.Health / humanoid.MaxHealth
            local barHeight = bounds.Height
            local barWidth = 4
            local barX = bounds.TopLeft.X - 10
            local barY = bounds.TopLeft.Y
            
            drawings.healthBarOutline.From = Vector2.new(barX, barY)
            drawings.healthBarOutline.To = Vector2.new(barX, barY + barHeight)
            drawings.healthBarOutline.Visible = true
            
            local fillHeight = barHeight * healthPercent
            local fillY = barY + (barHeight - fillHeight)
            drawings.healthBarFill.From = Vector2.new(barX, fillY)
            drawings.healthBarFill.To = Vector2.new(barX, barY + barHeight)
            
            -- Health color gradient (green to red)
            local healthColor = Color3.fromRGB(
                math.floor(255 * (1 - healthPercent)),
                math.floor(255 * healthPercent),
                0
            )
            drawings.healthBarFill.Color = healthColor
            drawings.healthBarFill.Thickness = barWidth
            drawings.healthBarFill.Visible = true
        end)
    end
    
    -- Character lifecycle
    if player.Character then
        characterAdded(player.Character)
    end
    
    table.insert(connections, player.CharacterAdded:Connect(characterAdded))
    table.insert(connections, player.CharacterRemoving:Connect(function()
        if ESPStore[player] and ESPStore[player].connection then
            ESPStore[player].connection:Disconnect()
            ESPStore[player].connection = nil
            ESPStore[player].lastBounds = nil
        end
    end))
end

-- (Remaining functions: removeESP, ESPModule controls, initialization identical to previous implementation)
-- [Include the exact same cleanup, control functions, and auto-initialization code from previous response]

-- Return module for external control
local ESPModule = {
    Toggle = function(state) ESP.Enabled = state end,
    SetTeamVisible = function(state) ESP.ShowTeam = state end,
    SetColors = function(boxColor, tracerColor, textColor)
        ESP.BoxColor = boxColor or ESP.BoxColor
        ESP.TracerColor = tracerColor or ESP.TracerColor
        ESP.TextColor = textColor or ESP.TextColor
    end,
    SetExactBounds = function(state) ESP.UseExactBounds = state end,
    SetUpdateFrequency = function(freq) ESP.UpdateFrequency = math.max(1, math.floor(freq)) end,
    Cleanup = function() -- Cleanup implementation from previous response
        for _, conn in ipairs(connections) do conn:Disconnect() end
        for player, _ in pairs(ESPStore) do
            if ESPStore[player].connection then ESPStore[player].connection:Disconnect() end
            for _, drawing in pairs(ESPStore[player].drawings) do drawing:Remove() end
        end
        table.clear(ESPStore)
        table.clear(connections)
    end
}

-- Auto-initialize
for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then createESP(player) end
end

table.insert(connections, Players.PlayerAdded:Connect(function(player)
    if player ~= LocalPlayer then createESP(player) end
end))

table.insert(connections, Players.PlayerRemoving:Connect(function(player)
    if ESPStore[player] then
        if ESPStore[player].connection then ESPStore[player].connection:Disconnect() end
        for _, drawing in pairs(ESPStore[player].drawings) do drawing:Remove() end
        ESPStore[player] = nil
    end
end))

return ESPModule