--[[
  it uses my "library loader" script, that basicly saves any script to be used tomorrow (as result you never gonna need to wait for it download the library, until you delete the file in the workspace folder)
  
  remembering that file saving is a synapse x feature, if not using synapse, it will just make a http request for the library (the normal delay of a http request on github is 0.4 - 0.6 seconds, so its 10000x better when using synapse + my library loader)
]]

local FileName = 'rbx-highlighter.lua'
local LibLink = 'https://raw.githubusercontent.com/loglizzy/rbx-highlighter/main/dildo.lua'
local Library

local tick = time()
if syn then
    local success = pcall(function()
        if isfile(FileName) then
            local content = readfile(FileName)
            Library = loadstring(content)()
            Body = content
        else
            print('Creating cache in workspace for futher times...')
            local request = game:HttpGet(LibLink)
            writefile(FileName, request)
            Library = loadstring(readfile(FileName))()
            Body = request
            print('Successfully created cache and loaded the lib')
        end
    end)
    
    if not success then
        warn('Error while creating cache, using normal method')
        
        local sucess = pcall(function()
            Library = loadstring(game:HttpGet(LibLink))()
        end)
        
        if not sucess then
            warn('Cannot load the library, try again')
        end
    end
else
    local sucess = pcall(function()
        Library = loadstring(game:HttpGet(LibLink))()
    end)
    
    if not sucess then
        warn('Cannot load the library, try again')
    end
end


print('Loaded lib in', time()-tick, 'seconds') -- synapse: once one time downloaded, it always gonna load it instantly 
                                               -- (until you delete the file in the workspace folder)

local ObjectHighlighter = Library

local Players = game.Players
local RunService = game:GetService('RunService')
local ReplicatedStorage = game.ReplicatedStorage

local myScreenGui = Instance.new("ScreenGui")
myScreenGui.Name = "ObjectHighlighter"
myScreenGui.Parent = Players.LocalPlayer.PlayerGui

local myRenderer = ObjectHighlighter.createRenderer(myScreenGui)

local myHighlight = ObjectHighlighter.createFromTarget(Players.LocalPlayer.Character -- player character for example)

myRenderer:addToStack(myHighlight)

RunService.RenderStepped:Connect(function(dt)
	myRenderer:step(dt)
end)
