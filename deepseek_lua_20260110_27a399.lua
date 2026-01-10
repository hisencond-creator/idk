-- ESP Core Module for Roblox
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
    TracerOrigin = "Bottom" -- "Bottom", "Middle", "Top"
}

local ESPStore = {}
local connections = {}

local function createESP(player)
    if ESPStore[player] then return end
    
    local drawings = {
        boxTopLeft = Drawing.new("Line"),
        boxTopRight = Drawing.new("Line"),
        boxBottomLeft = Drawing.new("Line"),
        boxBottomRight = Drawing.new("Line"),
        tracer = Drawing.new("Line"),
        nameLabel = Drawing.new("Text"),
        distanceLabel = Drawing.new("Text")
    }
    
    -- Configure drawing objects
    for _, drawing in pairs(drawings) do
        if drawing.ClassName == "Line" then
            drawing.Thickness = 1
            drawing.ZIndex = 1
        elseif drawing.ClassName == "Text" then
            drawing.Size = ESP.TextSize
            drawing.Center = true
            drawing.Outline = true
            drawing.ZIndex = 1
        end
    end
    
    -- Set initial colors
    drawings.boxTopLeft.Color = ESP.BoxColor
    drawings.boxTopRight.Color = ESP.BoxColor
    drawings.boxBottomLeft.Color = ESP.BoxColor
    drawings.boxBottomRight.Color = ESP.BoxColor
    drawings.tracer.Color = ESP.TracerColor
    drawings.nameLabel.Color = ESP.TextColor
    drawings.distanceLabel.Color = ESP.TextColor
    
    ESPStore[player] = {
        drawings = drawings,
        character = nil,
        connection = nil
    }
    
    local function characterAdded(character)
        ESPStore[player].character = character
        local humanoidRootPart = character:WaitForChild("HumanoidRootPart", 5)
        local humanoid = character:WaitForChild("Humanoid", 5)
        
        if not humanoidRootPart or not humanoid then return end
        
        -- Update loop for this character
        ESPStore[player].connection = RunService.RenderStepped:Connect(function()
            if not ESP.Enabled or not Camera or not humanoidRootPart or humanoid.Health <= 0 then
                for _, drawing in pairs(drawings) do
                    drawing.Visible = false
                end
                return
            end
            
            -- Team check
            if not ESP.ShowTeam and player.Team == LocalPlayer.Team then
                for _, drawing in pairs(drawings) do
                    drawing.Visible = false
                end
                return
            end
            
            -- World to screen conversion
            local position, onScreen = Camera:WorldToViewportPoint(humanoidRootPart.Position)
            if not onScreen then
                for _, drawing in pairs(drawings) do
                    drawing.Visible = false
                end
                return
            end
            
            -- Calculate box dimensions based on distance
            local distance = (Camera.CFrame.Position - humanoidRootPart.Position).Magnitude
            local scaleFactor = math.clamp(1000 / distance, 0.5, 3)
            local boxWidth = 50 * scaleFactor
            local boxHeight = 80 * scaleFactor
            
            -- Box coordinates
            local topLeft = Vector2.new(position.X - boxWidth / 2, position.Y - boxHeight / 2)
            local topRight = Vector2.new(position.X + boxWidth / 2, position.Y - boxHeight / 2)
            local bottomLeft = Vector2.new(position.X - boxWidth / 2, position.Y + boxHeight / 2)
            local bottomRight = Vector2.new(position.X + boxWidth / 2, position.Y + boxHeight / 2)
            
            -- Update box lines
            drawings.boxTopLeft.From = topLeft
            drawings.boxTopLeft.To = topRight
            drawings.boxTopLeft.Visible = true
            
            drawings.boxTopRight.From = topRight
            drawings.boxTopRight.To = bottomRight
            drawings.boxTopRight.Visible = true
            
            drawings.boxBottomLeft.From = bottomLeft
            drawings.boxBottomLeft.To = bottomRight
            drawings.boxBottomLeft.Visible = true
            
            drawings.boxBottomRight.From = topLeft
            drawings.boxBottomRight.To = bottomLeft
            drawings.boxBottomRight.Visible = true
            
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
            drawings.tracer.To = Vector2.new(position.X, position.Y)
            drawings.tracer.Visible = true
            
            -- Update text labels
            drawings.nameLabel.Position = Vector2.new(position.X, position.Y - boxHeight / 2 - 20)
            drawings.nameLabel.Text = player.Name
            drawings.nameLabel.Visible = true
            
            drawings.distanceLabel.Position = Vector2.new(position.X, position.Y + boxHeight / 2 + 10)
            drawings.distanceLabel.Text = tostring(math.floor(distance)) .. " studs"
            drawings.distanceLabel.Visible = true
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
        end
    end))
end

local function removeESP(player)
    if not ESPStore[player] then return end
    
    if ESPStore[player].connection then
        ESPStore[player].connection:Disconnect()
    end
    
    for _, drawing in pairs(ESPStore[player].drawings) do
        drawing:Remove()
    end
    
    ESPStore[player] = nil
end

-- Initialization and control functions
local ESPModule = {}

function ESPModule:Toggle(state)
    ESP.Enabled = state
    if not state then
        for _, data in pairs(ESPStore) do
            for _, drawing in pairs(data.drawings) do
                drawing.Visible = false
            end
        end
    end
end

function ESPModule:SetTeamVisible(state)
    ESP.ShowTeam = state
end

function ESPModule:SetColors(boxColor, tracerColor, textColor)
    ESP.BoxColor = boxColor or ESP.BoxColor
    ESP.TracerColor = tracerColor or ESP.TracerColor
    ESP.TextColor = textColor or ESP.TextColor
    
    for _, data in pairs(ESPStore) do
        data.drawings.boxTopLeft.Color = ESP.BoxColor
        data.drawings.boxTopRight.Color = ESP.BoxColor
        data.drawings.boxBottomLeft.Color = ESP.BoxColor
        data.drawings.boxBottomRight.Color = ESP.BoxColor
        data.drawings.tracer.Color = ESP.TracerColor
        data.drawings.nameLabel.Color = ESP.TextColor
        data.drawings.distanceLabel.Color = ESP.TextColor
    end
end

function ESPModule:Cleanup()
    for _, connection in ipairs(connections) do
        connection:Disconnect()
    end
    
    for player, _ in pairs(ESPStore) do
        removeESP(player)
    end
    
    table.clear(ESPStore)
    table.clear(connections)
end

-- Auto-initialize for existing and new players
for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then
        createESP(player)
    end
end

table.insert(connections, Players.PlayerAdded:Connect(function(player)
    if player ~= LocalPlayer then
        createESP(player)
    end
end))

table.insert(connections, Players.PlayerRemoving:Connect(function(player)
    removeESP(player)
end))

-- Return the module for external control
return ESPModule