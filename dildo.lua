local DEFAULT_PROPS = {
	target = nil,
	color = Color3.fromRGB(255, 255, 255),
	transparency = 0,
}

local Highlight = {}

function Highlight.new(props)
	assert(type(props) == "table", "Highlight.new expects a table of props.")
	assert(props.target, "Highlight requires a target to be set!")
	assert(props.target:IsA("Model"), "Highlight requires target to be a Model!")

	local state = {
		target = props.target,
		color = props.color or DEFAULT_PROPS.color,
		transparency = props.transparency or DEFAULT_PROPS.transparency,
	}

	return setmetatable(state, Highlight)
end

function Highlight.fromTarget(target)
	assert(target and target:IsA("Model"), "Highlight.fromTarget requires a Model target to be set!")

	return Highlight.new({
		target = target,
	})
end

local Workspace = game:GetService("Workspace")

local ViewportFrame = {}
ViewportFrame.__index = ViewportFrame

function ViewportFrame.withReferences(objectRef)
	local state = {
		objectRef = objectRef,
		rbx = nil,
	}
	local self = setmetatable(state, ViewportFrame)

	local rbx = Instance.new("ViewportFrame")
	rbx.CurrentCamera = Workspace.CurrentCamera
	rbx.BackgroundTransparency = 1
	rbx.Size = UDim2.new(1, 0, 1, 0)
	self.rbx = rbx

	objectRef.rbx.Parent = self.rbx

	return self
end

function ViewportFrame:getReference()
	return self.objectRef
end

function ViewportFrame:requestParent(newParent)
	return pcall(function()
		self.rbx.Parent = newParent
	end)
end

function ViewportFrame:destruct()
	self.rbx:Destroy()
end

local createBasePartCopy = function(basePart)
	assert(basePart:IsA("BasePart"), "createBasePartCopy must only receive a basePart!")

	local result
	if basePart:IsA("MeshPart") or basePart:IsA("UnionOperation") then
		result = basePart:Clone()
	else
		-- TODO: Manually clone simple BaseParts
		result = basePart:Clone()
	end

	-- TODO: Consider whitelisting children applicable to rendering instead
	for _, object in pairs(result:GetDescendants()) do
		if object:IsA("BasePart") then
			object:Destroy()
		end
	end

	return result
end

local createInstanceCopy = function(instance)
	if instance:IsA("BasePart") then
		return createBasePartCopy(instance)
	elseif instance:IsA("Humanoid") then
		local humanoid = Instance.new("Humanoid")
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		return humanoid
	elseif instance:IsA("Shirt") or instance:IsA("Pants") or instance:IsA("CharacterMesh") then
		return instance:Clone()
	end
end

local DEFAULT_IMPLEMENTATION = function()
	local connections = {}

	return {
		onBeforeRender = function(_, _)
			return true
		end,

		onRender = function(_, worldPart, viewportPart, _)
			viewportPart.CFrame = worldPart.CFrame
		end,

		onAdded = function(worldPart, viewportPart, _)
			viewportPart.Color = worldPart.Color

			connections[worldPart] = worldPart:GetPropertyChangedSignal("Color"):Connect(function()
				viewportPart.Color = worldPart.Color
			end)
		end,

		onRemoved = function(worldPart, _, _)
			if connections[worldPart] then
				connections[worldPart]:Disconnect()
				connections[worldPart] = nil
			end
		end,
	}
end

local ObjectRefMap = {}

function ObjectRefMap.fromModel(model)
	local newModel = Instance.new("Model")

	local alreadyHasAHumanoid = false
	local clonedPrimaryPart
	local dataModel = {}
	local map = {}
	for _, object in ipairs(model:GetDescendants()) do
		local clone = createInstanceCopy(object)
		if clone then
			clone.Parent = newModel

			if clone:IsA("BasePart") then
				map[object] = clone
				if not clonedPrimaryPart and object == model.PrimaryPart then
					clonedPrimaryPart = clone
				end
			elseif object:IsA("Humanoid") then
				if alreadyHasAHumanoid then
					clone:Destroy()
				else
					alreadyHasAHumanoid = true
				end
			end
		end
	end
	newModel.PrimaryPart = clonedPrimaryPart

	dataModel.map = map
	dataModel.rbx = newModel
	dataModel.worldModel = model

	return dataModel
end

local Renderer = {}
Renderer.__index = Renderer

local function onAddedToStack(self, highlight)
	local objectRef = ObjectRefMap.fromModel(highlight.target)
	local viewport = ViewportFrame.withReferences(objectRef)

	if self.onAddedImpl then
		for worldPart, viewportPart in pairs(objectRef.map) do
			self.onAddedImpl(worldPart, viewportPart, highlight)
		end
	end

	viewport:requestParent(self.targetScreenGui)
	self._viewportMap[highlight] = viewport
end

local function onRemovedFromStack(self, highlight)
	if self.onRemovedImpl then
		local viewport = self._viewportMap[highlight]
		local objectRef = viewport:getReference()
		for worldPart, viewportPart in pairs(objectRef.map) do
			self.onRemovedImpl(worldPart, viewportPart, highlight)
		end
	end

	local viewport = self._viewportMap[highlight]
	viewport:requestParent(nil)
	viewport:destruct()
	self._viewportMap[highlight] = nil
end

function Renderer.new(targetScreenGui)
	assert(targetScreenGui, "Renderer.new must be provided with a targetScreenGui.")

	local state = {
		_stack = {},
		_viewportMap = {},
		targetScreenGui = targetScreenGui,
	}
	setmetatable(state, Renderer)

	targetScreenGui.IgnoreGuiInset = true

	return state:withRenderImpl(DEFAULT_IMPLEMENTATION)
end

function Renderer:withRenderImpl(implementationFunc)
	local resultImpl = implementationFunc()

	self.onAddedImpl = resultImpl.onAdded
	self.onRemovedImpl = resultImpl.onRemoved
	self.onBeforeRenderImpl = resultImpl.onBeforeRender
	self.onRenderImpl = resultImpl.onRender

	return self
end

function Renderer:addToStack(highlight)
	if self._viewportMap[highlight] then
		return
	end

	table.insert(self._stack, highlight)
	onAddedToStack(self, highlight)
end

function Renderer:removeFromStack(highlight)
	local wasRemovedSuccessfully = false

	for index = #self._stack, 1, -1 do
		if highlight == self._stack[index] then
			table.remove(self._stack, index)
			wasRemovedSuccessfully = true
			break
		end
	end

	if wasRemovedSuccessfully then
		onRemovedFromStack(self, highlight)
	end
end

function Renderer:step(dt)
	if not self.onRenderImpl then
		return
	end

	for index = #self._stack, 1, -1 do
		local highlight = self._stack[index]
		local viewport = self._viewportMap[highlight]
		local objectRef = viewport:getReference()

		if self.onBeforeRenderImpl then
			local beforeRenderResult = self.onBeforeRenderImpl(dt, objectRef.worldModel)
			if beforeRenderResult == false then
				viewport.rbx.Visible = false
				return
			end
		end
		for worldPart, viewportPart in pairs(objectRef.map) do
			self.onRenderImpl(dt, worldPart, viewportPart, highlight)
		end
		viewport.rbx.Visible = true

	end
end

local ObjectHighlighter = {
	createFromTarget = function(targetModel)
	    return Highlight.fromTarget(targetModel)
    end,
	createRenderer = function(screenGui)
	    return Renderer.new(screenGui)
    end,
	Implementations = {
	    worldColor = function()
	local connections = {}

	return {
		onBeforeRender = function(_, _)
			return true
		end,

		onRender = function(_, worldPart, viewportPart, _)
			viewportPart.CFrame = worldPart.CFrame
		end,

		onAdded = function(worldPart, viewportPart, _)
			viewportPart.Color = worldPart.Color

			connections[worldPart] = worldPart:GetPropertyChangedSignal("Color"):Connect(function()
				viewportPart.Color = worldPart.Color
			end)
		end,

		onRemoved = function(worldPart, _, _)
			if connections[worldPart] then
				connections[worldPart]:Disconnect()
				connections[worldPart] = nil
			end
		end,
	}
end,
	    highlightColor = function()
	return {
		onBeforeRender = function(_, _)
			return true
		end,

		onRender = function(_, worldPart, viewportPart, highlight)
			viewportPart.CFrame = worldPart.CFrame
			viewportPart.Color = highlight.color
		end,

		onAdded = function(_, viewportPart, highlight)
			local function clearTextures(instance)
				if instance:IsA("MeshPart") then
					instance.TextureID = ""
				elseif instance:IsA("UnionOperation") then
					instance.UsePartColor = true
				elseif instance:IsA("SpecialMesh") then
					instance.TextureId = ""
				end
			end

			local function colorObject(instance)
				if instance:IsA("BasePart") then
					instance.Color = highlight.color
				end
			end

			for _, object in pairs(viewportPart:GetDescendants()) do
				clearTextures(object)
				colorObject(object)
			end
			clearTextures(viewportPart)
			colorObject(viewportPart)
		end,
	}
end,
    },
}

return ObjectHighlighter
