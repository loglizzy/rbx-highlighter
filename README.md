#example
`i heavily recommend my library loader script, can be found at https://github.com/loglizzy/script-library-loader, or in the file 'best-way-to-load-it.lua'`
```lua
local ObjectHighlighter = loadstring(game:HttpGet('https://raw.githubusercontent.com/loglizzy/rbx-highlighter/main/dildo.lua'))()

local Players = game.Players
local RunService = game:GetService('RunService')
local ReplicatedStorage = game.ReplicatedStorage

local myScreenGui = Instance.new("ScreenGui")
myScreenGui.Name = "ObjectHighlighter"
myScreenGui.Parent = Players.LocalPlayer.PlayerGui

local myRenderer = ObjectHighlighter.createRenderer(myScreenGui)

local myHighlight = ObjectHighlighter.createFromTarget(Players.LocalPlayer.Character)

-- Apply our highlight object to our Renderer stack.
-- We can add as many highlight objects to a renderer as we need
myRenderer:addToStack(myHighlight)

RunService.RenderStepped:Connect(function(dt)
	-- Our renderer will not render until it steps
	myRenderer:step(dt)
end)
```
