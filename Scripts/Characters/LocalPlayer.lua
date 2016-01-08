include("Scripts/Characters/BasePlayer.lua")
include("Scripts/UI/SurvivalUIView.lua")
include("Scripts/Core/SurvivalInventoryController.lua")
include("Scripts/Mixins/ClientCraftingMixin.lua")
include("Scripts/Mixins/SurvivalPlacementInput.lua")
include("Scripts/Mixins/CreativePlacementInput.lua")
include("Scripts/Mixins/ChatCommandsInput.lua")

local NKPhysics = include("Scripts/Core/NKPhysics.lua")

LocalPlayer = BasePlayer.Subclass("LocalPlayer")

--[[										]]--
--[[	 Static variables (do not tweak!)	]]--
--[[										]]--
-- Camera mode enumeration
LocalPlayer.ECameraMode 			=
{
	First 	= 0,
	Third 	= 1,
	Free  	= 2
}

-- Visibility override mode enumeration
LocalPlayer.EVisibilitySettings		=
{
	Hands 	= 0,
	Body 	= 1,
	All		= 2
}

-- Gameobject to use when in first-person mode.
LocalPlayer.FirstPersonObjectName						= "Player Hand"
LocalPlayer.EquippedItemRendersLast						= false -- We start in first person.

-------------------------------------------------------------------------------
-- Visibility settings
LocalPlayer.m_baseVisibilitySettings 					= {}
LocalPlayer.m_baseVisibilitySettings.m_hands			= false
LocalPlayer.m_baseVisibilitySettings.m_body				= false
LocalPlayer.m_overrideVisibilitySettings 				= {}
LocalPlayer.m_overrideVisibilitySettings.m_hands		= false
LocalPlayer.m_overrideVisibilitySettings.m_body			= false
LocalPlayer.m_overrideVisibilitySettings.m_handsActive	= false
LocalPlayer.m_overrideVisibilitySettings.m_bodyActive	= false

-------------------------------------------------------------------------------
-- Speed Constants
LocalPlayer.NormalMoveSpeed 		= 5.5 	-- Walk speed of the player
LocalPlayer.SprintMoveSpeed			= 11.0 	-- Sprint speed of the player
LocalPlayer.SneakMoveSpeed			= 2.75	-- Sneak speed of the player
LocalPlayer.SneakFastMoveSpeed		= 4.675	-- Sneak fast speed of the player
LocalPlayer.FlyMoveSpeed			= 13.0	-- Flying and Wisp speed
LocalPlayer.ActionID 				= 0

LocalPlayer.WispFadeColor = "tl:FF000000 tr:FF000000 bl:FF000000 br:FF000000"

-------------------------------------------------------------------------------
-- <Private> ------------------------------------------------------------------

-------------------------------------------------------------------------------
-- Helper function for checking if a Query Hit matches the given Script Type
local function DidHitScriptOfType( queryHit, scriptType )
	if queryHit and queryHit.gameobject then
		local objScript = queryHit.gameobject
		if objScript and objScript:InstanceOf(scriptType) then
			return true
		end
	end
	return false
end

-------------------------------------------------------------------------------
-- Helper function for wrapping calls involved in making loot 'throw' outwards from a point
-- local function ThrowObjectAsLoot( obj )
-- 	if not obj then return end

-- 	local trueDir = Eternus.GameState.m_activeCamera:ForwardVector()
-- 	local throwDir = vec3(trueDir:x(), 0.0, trueDir:z())
-- 	throwDir = throwDir:normalize()
-- 	local pos = Eternus.GameState.player:GetEyePosition()

-- 	local lootHolder = Eternus.GameObjectSystem:NKCreateNetworkedGameObject("Loot Object", true)
-- 	--local loot = Eternus.GameObjectSystem:NKCreateNetworkedGameObject(EasyLootMain.LootObjectName, true)

-- 	obj:RaiseNetEvent("ClientEvent_SetShouldRender", {shouldRender = true, propogate = true})
-- 	lootHolder:SetLootObject(obj)

-- 	lootHolder:NKSetPosition(pos)
-- 	lootHolder:NKPlaceInWorld(false, false)

-- 	lootHolder:NKGetPhysics():NKSetLinearVelocity(throwDir:mul_scalar(8.5))
-- end
-- </Private> -----------------------------------------------------------------
-------------------------------------------------------------------------------



-------------------------------------------------------------------------------
function LocalPlayer:Constructor( args )
	self.m_doubleTapTimer = 0.0

	self.m_minimumFall 				= 10.0
	self.m_maximumFall 				= 30.0
	self.m_fallthreshold 			= -15.0
	self.m_isFalling 				= false
	self.m_cameraControl			= true
	self.m_jumpCooldown				= 0.0
	self.m_swingTimer				= 0.0

	self.m_primaryActionEnabled		= true
	self.m_secondaryActionEnabled 	= true

	self.m_primaryActionEngaged		= false
	self.m_secondaryActionEngaged 	= false
	self.m_inventoryToggleable		= true
	self.m_journalToggleable 		= true
	self.m_sprinting 				= false

	self.m_isHoldingCrouch			= false
	self.m_isRunning 				= false
	self.m_runPreventFlag			= false

	self.m_prevHitObj 				= nil
	self.m_prevHitCallback			= nil

	self.m_antiGravityTimer 		= -1

	self:Mixin(ClientCraftingMixin, args)
	if EternusEngine.GameMode:InstanceOf(Creative) then
		self:Mixin(CreativePlacementInput, args)
 	else
		self:Mixin(SurvivalPlacementInput, args)
 	end
	self:Mixin(ChatCommandsInput, args)
end

-------------------------------------------------------------------------------
function LocalPlayer:PostLoad()
	-- Create the hands
	local hands = Eternus.GameObjectSystem:NKCreateGameObject(self.FirstPersonObjectName, true)
	if hands then
		self.m_fpsHands = hands
	end

	-- Call super postload after hand creation because the super also triggers the morph target changes
	LocalPlayer.__super.PostLoad(self)

	self:SetCameraMode(LocalPlayer.ECameraMode.First)
end

-------------------------------------------------------------------------------
function LocalPlayer:Spawn()
	-- Call the super class function.
	LocalPlayer.__super.Spawn(self)
	if self.m_fpsHands then
		self.m_fpsHands:NKPlaceInWorld(false, true)
	end
	self:SetupInputContext()
	self.m_spawnedSignal:Fire()

	self:NKGetCharacterController():NKSetLayer(EternusEngine.Physics.Layers.PLAYER)
	self.m_targetQueryFlags:NKClearBit(EternusEngine.Physics.Layers.PLAYER)

	EternusEngine.Physics.StartTrackingObject(self)
end

-------------------------------------------------------------------------------
function LocalPlayer:SetupInputContext()

	self:NKGetCharacterController():NKSetMass(60.0)
	self:NKGetCharacterController():NKSetMaxPushForce(200.0)

	-- Grab the keybind mappings that the world is using and register commands
	self.m_defaultInputContext = InputMappingContext.new("Default")
	self.m_defaultInputContext:NKSetInputPropagation(false)

	self.m_defaultInputContext:NKRegisterNamedCommand("Chat Window"					, self, "ChatWindow"			, 0.67)
	self.m_defaultInputContext:NKRegisterNamedCommand("Toggle Mouse Show"			, self, "ToggleMouseShow"		, 0.67)
	self.m_defaultInputContext:NKRegisterNamedCommand("Toggle Mouse Hide"			, self, "ToggleMouseHide"		, 0.67)
	self.m_defaultInputContext:NKRegisterNamedCommand("Toggle Render Debug Text"	, self, "ToggleRenderDebugText"	, 0.67)

	self.m_defaultInputContext:NKRegisterNamedCommand("Move Forward"				, self, "MoveForward"			, KEY_FLOOD)
	self.m_defaultInputContext:NKRegisterNamedCommand("Move Backward"				, self, "MoveBackward"			, KEY_FLOOD)
	self.m_defaultInputContext:NKRegisterNamedCommand("Strafe Left"					, self, "StrafeLeft"			, KEY_FLOOD)
	self.m_defaultInputContext:NKRegisterNamedCommand("Strafe Right"				, self, "StrafeRight"			, KEY_FLOOD)
	self.m_defaultInputContext:NKRegisterNamedCommand("Jump"						, self, "Jump"					, KEY_FLOOD)
	self.m_defaultInputContext:NKRegisterNamedCommand("Crouch"						, self, "Crouch"				, KEY_FLOOD)
	self.m_defaultInputContext:NKRegisterNamedCommand("Sprint"						, self, "Sprint"				, KEY_FLOOD)

	self.m_defaultInputContext:NKRegisterNamedCommand("Craft"						, self, "BeginCraft"			, KEY_ONCE)
	self.m_defaultInputContext:NKRegisterNamedCommand("Use"							, self, "PrimaryAction"			, 0.67)
	self.m_defaultInputContext:NKRegisterNamedCommand("Place/Interact"				, self, "SecondaryAction"		, 1.0)
	self.m_defaultInputContext:NKRegisterNamedCommand("Inventory"					, self, "ToggleInventory"		, 1.0)
	self.m_defaultInputContext:NKRegisterNamedCommand("Journal"						, self, "ToggleJournal"			, 1.0)
	self.m_defaultInputContext:NKRegisterNamedCommand("Quickslot 1"					, self, "SwapHandSlot1"			, 0.67)
	self.m_defaultInputContext:NKRegisterNamedCommand("Quickslot 2"					, self, "SwapHandSlot2"			, 0.67)
	self.m_defaultInputContext:NKRegisterNamedCommand("Quickslot 3"					, self, "SwapHandSlot3"			, 0.67)
	self.m_defaultInputContext:NKRegisterNamedCommand("Quickslot 4"					, self, "SwapHandSlot4"			, 0.67)
	self.m_defaultInputContext:NKRegisterNamedCommand("Quickslot 5"					, self, "SwapHandSlot5"			, 0.67)
	self.m_defaultInputContext:NKRegisterNamedCommand("Quickslot 6"					, self, "SwapHandSlot6"			, 0.67)
	self.m_defaultInputContext:NKRegisterNamedCommand("Quickslot 7"					, self, "SwapHandSlot7"			, 0.67)
	self.m_defaultInputContext:NKRegisterNamedCommand("Quickslot 8"					, self, "SwapHandSlot8"			, 0.67)
	self.m_defaultInputContext:NKRegisterNamedCommand("Quickslot 9"					, self, "SwapHandSlot9"			, 0.67)
	self.m_defaultInputContext:NKRegisterNamedCommand("Quickslot 0"					, self, "SwapHandSlot10"		, 0.67)
	self.m_defaultInputContext:NKRegisterNamedCommand("Put Away Hand Item"			, self, "PutAwayHandItem"		, 0.67)
	self.m_defaultInputContext:NKRegisterNamedCommand("Show Players"				, self, "ShowPlayers"			, KEY_FLOOD)
	self.m_defaultInputContext:NKRegisterNamedCommand("Toggle Camera Mode"			, self, "ToggleCameraMode"		, KEY_ONCE)
	self.m_defaultInputContext:NKRegisterNamedCommand("Return to Menu"				, self, "GoToMenu"				, KEY_ONCE)
	self.m_defaultInputContext:NKRegisterNamedCommand("Toggle Stance"				, self, "ToggleHoldStance"		, KEY_ONCE)
	self.m_defaultInputContext:NKRegisterNamedCommand("Toggle UI"					, self, "ToggleUI"				, KEY_ONCE)
	self.m_defaultInputContext:NKRegisterNamedCommand("Toggle Hands"				, self, "ToggleHands"			, KEY_ONCE)
	--self.m_defaultInputContext:NKRegisterNamedCommand("Drop Item"					, self, "DropHandItem"			, KEY_ONCE)

	self.m_defaultInputContext:NKRegisterNamedCommand("Select Next Block Size"		, self, "SelectNextBlockBrush", KEY_ONCE)
	self.m_defaultInputContext:NKRegisterNamedCommand("Select Prev Block Size"		, self, "SelectPrevBlockBrush", KEY_ONCE)

	-- Test bindings for Loot Objects
	self.m_defaultInputContext:NKRegisterNamedCommand("Drop Item"					, self, "DropHandItemB"			, KEY_FLOOD)
	self.m_defaultInputContext:NKRegisterNamedCommand("Pickup"						, self, "PickupB"				, KEY_FLOOD)


	Eternus.InputSystem:NKPushInputContext(self.m_defaultInputContext)

	self.m_inventoryContext = nil

	-- Setup keybindings for thei game mode's placement
	self:SetupPlacementContext()
end


LocalPlayer.DropAllTime = 0.4
function LocalPlayer:DropHandItemB( down )
	-------------
	if self.m_dropAllTimer == nil then self.m_dropAllTimer = 0 end
	if self.m_droppingStacks == nil then self.m_droppingStacks = false end
	-------------
	--NKInfo("[LocalPlayer:DropHandItemB]")

	if not self:GetEquippedItem() then return end

	if down then
		self.m_dropAllTimer = self.m_dropAllTimer + EternusEngine.DT
		if self.m_dropAllTimer >= LocalPlayer.DropAllTime then
			self.m_dropAllTimer = 0.0
			self.m_droppingStacks = true

			local pos = self:GetEyePosition()
			-- if self:IsCrouching() then
			-- 	pos = pos + vec3(0.0, 0.5, 0.0)
			-- end

			self:RaiseServerEvent("ServerEvent_DropHandItem", { quantity = 0, origin = pos, inDirection = Eternus.GameState.m_activeCamera:ForwardVector() })
		end
	else
		self.m_dropAllTimer = 0.0

		if not self.m_droppingStacks then
			local pos = self:GetEyePosition()
			if self:IsCrouching() then
				pos = pos + vec3(0.0, 0.5, 0.0)
			end

			self:RaiseServerEvent("ServerEvent_DropHandItem", { quantity = 1, origin = pos, inDirection = Eternus.GameState.m_activeCamera:ForwardVector() })
		else
			self.m_droppingStacks = false
		end
	end
end

LocalPlayer.PickupAllTime = 0.4
function LocalPlayer:PickupB( down )
	-------------
	if self.m_pickupAllTimer == nil then self.m_pickupAllTimer = 0 end
	if self.m_pickupTarget == nil then self.m_pickupTarget = nil end
	if self.m_pickupDelay == nil then self.m_pickupDelay = 0 end
	-------------

	if self.m_pickupTarget then
		if down then
			self.m_pickupAllTimer = self.m_pickupAllTimer + EternusEngine.DT

			self.m_playerUI:SetCraftingProgress(self.m_pickupAllTimer/self.m_pickupDelay)
			if self.m_pickupAllTimer >= self.m_pickupDelay then
				local dir = Eternus.GameState.m_activeCamera:ForwardVector()
				local pos = self:GetEyePosition()

				self:RaiseServerEvent("ServerEvent_PickupAction", { targetObj = self.m_pickupTarget:GetHighlightedObject() })
				self.m_playerUI:CraftingStopped(false)

				self.m_pickupAllTimer = 0.0
				self.m_pickupTarget = false
			end
		else
			self.m_pickupAllTimer = 0.0
			self.m_pickupTarget = nil
			self.m_playerUI:CraftingStopped(true)
		end
	elseif down then
		if self.m_pickupAllTimer == 0 then
			local dir = Eternus.GameState.m_activeCamera:ForwardVector()
			local pos = self:GetEyePosition()

			local rayHit = EternusEngine.Physics.RayCastCollect(pos, dir, self:GetMaxReachDistance(), nil, Eternus.LootQueryMask)

			if rayHit then
				rayHit.gameobject = rayHit.gameobject:GetHighlightedObject()
			end

			if DidHitScriptOfType(rayHit, Locked) and rayHit.gameobject:IsResource() then
				self.m_pickupDelay = rayHit.gameobject:GetPickupDelay()
				if self.m_pickupDelay <= 0 then
					self:RaiseServerEvent("ServerEvent_PickupAction", { targetObj = rayHit.gameobject:GetHighlightedObject() })
				elseif self.m_pickupTarget == nil then
					self.m_pickupTarget = rayHit.gameobject
					self.m_playerUI:CraftingStart("Picking up...", self.m_pickupTarget:NKGetName())
				end
			end
		end

		self.m_pickupAllTimer = self.m_pickupAllTimer + EternusEngine.DT

		if self.m_pickupAllTimer >= LocalPlayer.PickupAllTime then
			self.m_pickupAllTimer = 0.0
			self.m_pickupTarget = false

			self:RaiseServerEvent("ServerEvent_PlayTorsoAnimOnce", { animName = "Pickup", TimeIN = 0.1, TimeOUT = 0.1, loop = false, restart = true })

			local dir = Eternus.GameState.m_activeCamera:ForwardVector()
			local pos = self:GetEyePosition()

			local hits = EternusEngine.Physics.SphereSweepCollectAll(1.5, pos, dir, self:GetMaxReachDistance(), nil, Eternus.LootQueryMask)

			if hits then
				for k,v in pairs(hits) do
					if v.gameobject then
						if DidHitScriptOfType(v, LootObject) then
							self:RaiseServerEvent("Server_PickupLoot", { targetObj = v.gameobject })
						elseif DidHitScriptOfType(v, PlaceableObject) then
							if not v.gameobject:InstanceOf(Locked) then
								self:RaiseServerEvent("ServerEvent_PickupAction", { targetObj = v.gameobject:GetHighlightedObject() })
							end
						end
					end
				end
			end
		end
	else
		self.m_pickupAllTimer = 0.0
		self.m_pickupTarget = nil

		self:RaiseServerEvent("ServerEvent_PlayTorsoAnimOnce", { animName = "Pickup", TimeIN = 0.1, TimeOUT = 0.1, loop = false, restart = true })

		local dir = Eternus.GameState.m_activeCamera:ForwardVector()
		local pos = self:GetEyePosition()

		local rayHit = EternusEngine.Physics.RayCastCollect(pos, dir, self:GetMaxReachDistance(), nil, Eternus.LootQueryMask)

		-- Override any objects that was a leaf object to their root parent
		if rayHit and rayHit.gameobject and not DidHitScriptOfType(rayHit, LootObject) then
			rayHit.gameobject = rayHit.gameobject:GetHighlightedObject()
		end

		if EternusEngine.Debugging.Enabled then
			EternusEngine.Physics.ConsolePrintQueryHit(rayHit)
		end

		if DidHitScriptOfType(rayHit, LootObject) then
			self:RaiseServerEvent("Server_PickupLoot", { targetObj = rayHit.gameobject })
		elseif DidHitScriptOfType(rayHit, PlaceableObject) then

			if not rayHit.gameobject:InstanceOf(Locked) then
				self:RaiseServerEvent("ServerEvent_PickupAction", { targetObj = rayHit.gameobject:GetHighlightedObject() })
			end

		else
			local sphereHit = EternusEngine.Physics.SphereSweepCollect(0.5, pos, dir, self:GetMaxReachDistance(), nil, Eternus.LootQueryMask)

			if EternusEngine.Debugging.Enabled then
				EternusEngine.Physics.ConsolePrintQueryHit(sphereHit)
			end

			if DidHitScriptOfType(sphereHit, LootObject) then
				self:RaiseServerEvent("Server_PickupLoot", { targetObj = sphereHit.gameobject })
			elseif DidHitScriptOfType(sphereHit, PlaceableObject) then
				if not DidHitScriptOfType(sphereHit, Locked) or sphereHit.gameobject:GetPickupDelay() <= 0 then
					self:RaiseServerEvent("ServerEvent_PickupAction", { targetObj = sphereHit.gameobject:GetHighlightedObject() })
				end
			end
		end
	end

	-- Do a check to see if the pickup target can even fit in the inventory
	if self.m_pickupTarget and (not self.m_pickupTarget:InstanceOf(LootObject) and not self:TryPickup(self.m_pickupTarget)) then
		self:InterruptPickup()
	end
end

-------------------------------------------------------------------------------
function LocalPlayer:InterruptPickup()
	if self.m_pickupTarget then
		self.m_pickupAllTimer = 0.0
		self.m_pickupTarget = nil
		self.m_playerUI:CraftingStopped(true)
	end
end

-------------------------------------------------------------------------------
function LocalPlayer:CreateInventoryContext()
	self.m_inventoryContext = InputMappingContext.new("Inventory")
	self.m_inventoryContext:NKSetInputPropagation(false)
	self.m_inventoryContext:NKRegisterNamedCommand("Inventory"						, self, "ToggleInventory"			, KEY_ONCE)
	self.m_inventoryContext:NKRegisterNamedCommand("Journal"						, self, "ToggleJournal"				, KEY_ONCE)
	self.m_inventoryContext:NKRegisterNamedCommand("Chat Window"					, self, "ChatWindow"				, 0.67)
	self.m_inventoryContext:NKRegisterNamedCommand("Quickslot 1"					, self, "SwapHandSlot1"				, 0.67)
	self.m_inventoryContext:NKRegisterNamedCommand("Quickslot 2"					, self, "SwapHandSlot2"				, 0.67)
	self.m_inventoryContext:NKRegisterNamedCommand("Quickslot 3"					, self, "SwapHandSlot3"				, 0.67)
	self.m_inventoryContext:NKRegisterNamedCommand("Quickslot 4"					, self, "SwapHandSlot4"				, 0.67)
	self.m_inventoryContext:NKRegisterNamedCommand("Quickslot 5"					, self, "SwapHandSlot5"				, 0.67)
	self.m_inventoryContext:NKRegisterNamedCommand("Quickslot 6"					, self, "SwapHandSlot6"				, 0.67)
	self.m_inventoryContext:NKRegisterNamedCommand("Quickslot 7"					, self, "SwapHandSlot7"				, 0.67)
	self.m_inventoryContext:NKRegisterNamedCommand("Quickslot 8"					, self, "SwapHandSlot8"				, 0.67)
	self.m_inventoryContext:NKRegisterNamedCommand("Quickslot 9"					, self, "SwapHandSlot9"				, 0.67)
	self.m_inventoryContext:NKRegisterNamedCommand("Quickslot 0"					, self, "SwapHandSlot10"			, 0.67)
	self.m_inventoryContext:NKRegisterNamedCommand("Put Away Hand Item"				, self, "PutAwayHandItem"			, 0.67)
	self.m_inventoryContext:NKRegisterNamedCommand("Return to Menu"					, self, "ToggleInventoryOverride"	, KEY_ONCE)
end

-------------------------------------------------------------------------------
function LocalPlayer:SetupPlacementContext()
end

-------------------------------------------------------------------------------
function LocalPlayer:Sprint( down )
	self.m_sprinting = down
end

-------------------------------------------------------------------------------
function LocalPlayer:SetupUI( UIClass, layout )

	-- This UI is for the Local Player, The calss type and layout loaded are dependent on the game mode
	self.m_playerUI = UIClass.new(layout, "PlayerUI", self)

	-- This UI is for the Base Local Player
	self.m_gameModeUI = TUGGameModeUIView.new("TUGGameModeLayout.layout", "TUGGameModeUI", self)

	EternusEngine.UI.Layers.Gameplay:show()
	EternusEngine.UI.Layers.Gameplay:activate()
end

-------------------------------------------------------------------------------
function LocalPlayer:ChatWindow( down )

	if not down then
		return
	end

	NKToggleChatWindow(true)
end

-------------------------------------------------------------------------------
function LocalPlayer:ToggleMouseShow( down )

	if down then
		return
	end

	if Eternus.InputSystem:NKIsMouseHidden() then
		Eternus.InputSystem:NKShowMouse()
	end
end

-------------------------------------------------------------------------------
function LocalPlayer:ToggleMouseHide( down )

	if down then
		return
	end

	if not Eternus.InputSystem:NKIsMouseHidden() then
		Eternus.InputSystem:NKHideMouse()
	end
end

-------------------------------------------------------------------------------
function LocalPlayer:ToggleRenderDebugText( down )

	if down then
		return
	end

	NKToggleEngineOverlay()
end

-------------------------------------------------------------------------------
function LocalPlayer:ToggleUI( down )

	if not down then
		return
	end

	-- Hide all UI when toggled
	-- Gets the current state of the mouse so it can restore it when you show the UI again
	if EternusEngine.UI.Layers.Gameplay:isVisible() then
		EternusEngine.UI.Layers.Gameplay:hide()
		if Eternus.InputSystem:NKIsMouseHidden() then
			Eternus.InputSystem:NKHideMouse()
			self.m_restoreMouse = false
		else
			self.m_restoreMouse = true
		end
	else
		EternusEngine.UI.Layers.Gameplay:show()
		if self.m_restoreMouse then
			Eternus.InputSystem:NKShowMouse()
		end
	end
end

-------------------------------------------------------------------------------
function LocalPlayer:ToggleHands( down )
	if not down then
		return
	end

	if self.m_fpsHands then
		self.m_fpsHands:NKSetShouldRender(handsVisibility, not self.m_fpsHands:NKShouldRender())
	end

end

-------------------------------------------------------------------------------
function LocalPlayer:ShowPlayers( down )

	if not down then
		-- Turn off the players window
		self.m_gameModeUI.m_playersWindow:setVisible(false)
		self.m_gameModeUI.m_crosshair:setVisible(true)
		return
	end

	-- Turn on the players Window
	if not self.m_gameModeUI.m_playersWindow:isVisible() then
		self.m_gameModeUI.m_playersWindow:setVisible(true)
		self.m_gameModeUI.m_playersWindow:activate()
		self.m_gameModeUI.m_crosshair:setVisible(false)
	end
end

-------------------------------------------------------------------------------
function LocalPlayer:ToggleCameraMode( down )
	-- Wait for keyup
	if down then
		return
	end

	if self:IsDead() then
		return
	end

	-- Swap the m_activeCamera
	if Eternus.GameState.m_activeCamera ~= Eternus.GameState.m_fpcamera then
		Eternus.GameState.m_activeCamera = Eternus.GameState.m_fpcamera
		self:SetCameraMode(LocalPlayer.ECameraMode.First)
	else
		Eternus.GameState.m_activeCamera = Eternus.GameState.m_tpcamera
		self:SetCameraMode(LocalPlayer.ECameraMode.Third)
	end

	-- Inform the backing TUGGameMode
	NKSetActiveCamera(Eternus.GameState.m_activeCamera)
end

-------------------------------------------------------------------------------
function LocalPlayer:GoToMenu( down )
	if down then
		return
	end

	NKSwitchGameStateToMenu()
end

-------------------------------------------------------------------------------
function LocalPlayer:OnContactCreated(data)
	if self.m_isFalling then
		self.m_isFalling = false

		local diff = data.thisBody.position - self.m_initialFallLoc
		local distance = diff:NKLength()
		self.m_initialFallLoc = data.thisBody.position

		--NKPrint("In-Air Distance: " .. tostring(distance))
		self.m_triggerHurtEffects = true
		if distance > self.m_minimumFall then

			local falldamage = ((distance - self.m_minimumFall) / self.m_maximumFall) * self.MaxHealth
			--self:ApplyDamage({ damage = falldamage, category = "Undefined" })
			--NKPrint("Damage: " .. tostring(falldamage))
		end
	end
end

-------------------------------------------------------------------------------
function LocalPlayer:Update( dt )
	if self:NKGetCharacterController():NKGetState() == CharacterController.eInAirState and self:NKGetCharacterController():NKGetLinearVelocity():y() <= self.m_fallthreshold then
		if not self.m_isFalling then
			self.m_initialFallLoc = self:NKGetPosition()
		end
		self.m_isFalling = true
	else
		self.m_isFalling = false
	end


	-- Sync the players transform with the physics capsule.
	self:NKGetCharacterController():Step(dt)

	local cc = self:NKGetCharacterController()
	self.m_speed = cc:NKGetLinearVelocity():NKLength()
	self.m_moveDir = self:GetMovementDirection()
	self.m_onGround = cc:NKGetState() == CharacterController.eOnGroundState

	self:_UpdateState()

	LocalPlayer.__super.Update(self, dt)

	self.m_doubleTapTimer = self.m_doubleTapTimer + dt

	if self.m_jumpCooldown > 0.0 then
		self.m_jumpCooldown = self.m_jumpCooldown - dt
	end

	-- This needs to be flipped around to not always be decrementing this timer!!!!
	self.m_swingTimer = self.m_swingTimer - dt

	self:UpdateMovementSpeed()
	self:UpdateHands()
	self:UpdateHitObject()

	self:UpdateAntiGravTimer(dt)
	self.m_playerUI:Update(dt)
end

-------------------------------------------------------------------------------
function LocalPlayer:ResetAntiGravTimer()
	self.m_antiGravityTimer = 5.0

	-- Start floating.
	self:NKGetCharacterController():EnableFlying()
end

-------------------------------------------------------------------------------
-- Allows the player to float above the terrain while it's still generating beneath him.
function LocalPlayer:UpdateAntiGravTimer(dt)
	-- Are we in float mode?
	if self.m_antiGravityTimer > 0.0 then

		local result = EternusEngine.Physics.RayCastCheck(self:NKGetPosition() + vec3(0.0,1.0,0.0), vec3(0.0, -1.0, 0.0), 100.0, {self})

		if (result == true) then
			--Hit something
			self.m_antiGravityTimer = 0.0
			self:NKGetCharacterController():DisableFlying()
		end
		self.m_antiGravityTimer = self.m_antiGravityTimer - dt

		if (self.m_antiGravityTimer <= 0.0) then
			-- Timer finished, stop floating.
			self.m_antiGravityTimer = 0.0
			self:NKGetCharacterController():DisableFlying()
		end
	end
end

-------------------------------------------------------------------------------
-- Called once a frame to update the players internal state variable (self.m_state).
function LocalPlayer:_UpdateState()

	local prevState = self.m_state
	local prevJumping = self.m_jumping

	-- Are we crouching?
	local isCrouching = self:IsCrouching()

	-- Are we moving?
	local isMoving = self:NKGetCharacterController():NKIsMoving()

	-- Are we on the ground?
	local onGround = self:NKGetCharacterController():NKOnGround()

	-- Update the state.
	if self:IsFlying() then
		self.m_state = BasePlayer.EState.eFlying
	elseif isMoving and onGround then
		-- Are we trying to run?
		local isRunning = (not self.m_runPreventFlag) and self.m_stamina > 0.0 and self.m_sprinting

		if isCrouching and isRunning then
			self.m_state = BasePlayer.EState.eSneakRun
		elseif isCrouching then
			self.m_state = BasePlayer.EState.eSneak
		elseif isRunning then
			self.m_state = BasePlayer.EState.eRunning
		else
			self.m_state = BasePlayer.EState.eWalking
		end
	elseif not isMoving then
		if isCrouching then
			self.m_state = BasePlayer.EState.eCrouch
		else
			self.m_state = BasePlayer.EState.eIdle
		end
	end

	if self:NKGetCharacterController():NKGetJumpFlag() then
		self:SetJumpFlag(true)
	elseif self.m_jumping and onGround then
		self:SetJumpFlag(false)
	end
end

-------------------------------------------------------------------------------
-- Called once a frame to update the first person hands position and orientation.
function LocalPlayer:UpdateHands()
	-- Don;'t bother unless we are in first person- the only state when hands are visible.
	if self.m_camMode ~= LocalPlayer.ECameraMode.First or not self.m_fpsHands then
		return
	end

	-- Update the hand's position based on the active camera.
	self.m_fpsHands:NKSetPosition(Eternus.GameState.m_activeCamera:NKGetLocation(true) + vec3.new(0.0, 0.0, 0.0), false)

	-- Update the hand's orientation.
	self.m_fpsHands:NKSetOrientation(Eternus.GameState.m_activeCamera:NKGetOrientation())
end

-------------------------------------------------------------------------------
function LocalPlayer:UpdateHitObject()
	local eyePosition = self:NKGetPosition() + vec3.new(0.0, self.m_cameraHeight, 0.0)
	local lookDirection = Eternus.GameState.m_activeCamera:ForwardVector()

	local layerMask = BitFlags32()
	layerMask:NKSetBit(EternusEngine.Physics.Layers.PLAYER)
	layerMask:NKInvert()

	local rayTraceHit = NKPhysics.RayCastCollect(eyePosition, lookDirection, self:GetMaxReachDistance(), {self.m_equippedItem}, layerMask)
	local hitObj = nil

	if rayTraceHit and rayTraceHit.gameobject then
		hitObj = rayTraceHit.gameobject:GetHighlightedObject()
	end

	if hitObj then
		-- If we hit something,
		if self.m_prevHitObj == nil then
			-- If our previous hit object was nil, fire m_targetAcquiredEvent
			self.m_targetAcquiredSignal:Fire(hitObj)
		else
			if self.m_prevHitObj ~= hitObj then
				-- If our previous hit object was not the same as our current hit object, fire m_targetAcquiredEvent
				self.m_targetAcquiredSignal:Fire(hitObj)

				-- Disable the highlighting of the previous object
				if self.m_prevHitObj then
					self.m_prevHitObj:SetHighlightedRender(false)
				end
			end
		end

		-- Always enable highlighting of whatever object was hit
		if hitObj then
			hitObj:SetHighlightedRender(true)
		end
	else
		-- If we hit nothing,
		if self.m_prevHitObj then
			-- If our previous hit object was not nil
			-- Set our previous hit object to nil, fire m_targetLostSignal
			self.m_targetLostSignal:Fire()

			-- Disable the highlighting of whatever object was being targeted
			if self.m_prevHitObj then
				self.m_prevHitObj:SetHighlightedRender(false)
			end
		end

		self:RenderVoxelSelectionBox(rayTraceHit)
	end

	if self.m_prevHitObj then
		self.m_prevHitObj.m_destroyedSignal:Remove(self.m_prevHitCallback)
	end
	-- Assign our previous hit object to the object we traced this frame
	self.m_prevHitObj = hitObj
	if self.m_prevHitObj then
		self.m_prevHitCallback = function()
			self.m_targetLostSignal:Fire()
			self.m_prevHitObj.m_destroyedSignal:Remove(self.m_prevHitCallback)
			self.m_prevHitObj = nil
			self.m_prevHitCallback = nil
		end
		self.m_prevHitObj.m_destroyedSignal:Add(self.m_prevHitCallback)
	end
	
end

-------------------------------------------------------------------------------
function LocalPlayer:GetActiveModel()
	if self.m_fpsHands and self.m_camMode == LocalPlayer.ECameraMode.First then
		return self.m_fpsHands
	elseif self.m_3pobject then
		return self.m_3pobject
	else
		return self
	end
end

-------------------------------------------------------------------------------
-- Returns true if this character is currently in a state where he should play a step sound.
-- Overridden from BasePlayer.
function LocalPlayer:ShouldPlayStepSounds()
	local cc = self:NKGetCharacterController()
	return self.m_camMode ~= LocalPlayer.ECameraMode.Free and cc:NKIsMoving() and cc:NKOnGround() and LocalPlayer.__super.ShouldPlayStepSounds(self)
end

-------------------------------------------------------------------------------
-- Provides different step sounds based on the aterial underfoot. This is currently done only for LocalPlayers.
-- Overridden from BasePlayer.
function LocalPlayer:GetCurrentStepSound()

	--check the voxel below us
	local result = EternusEngine.Physics.RayCastCollect(self:NKGetPosition() + vec3(0.0,1.0,0.0), vec3(0.0, -1.0, 0.0), 5.0, nil, EternusEngine.Physics.Layers.TERRAIN)

	if not result then
		return
	end

	local matObj = Eternus.GameObjectSystem:NKGetPlaceableMaterialByID(result.materialID)

	if matObj then
		local p = matObj:NKGetPlaceableMaterial()
		if p and p:NKGetStepSound() ~= "" then
			return p:NKGetStepSound()
		end
	end

	return self.DefaultStepSound
end

-------------------------------------------------------------------------------
-- Called once a frame to update the players current movement speed.
function LocalPlayer:UpdateMovementSpeed()
	-- Are we crouching?
	local isCrouching = self:IsCrouching()
	-- Are we trying to run?
	self.m_isRunning = (not self.m_runPreventFlag) and self.m_stamina > 0.0 and self.m_sprinting

	-- Update the speed.
	local speed = LocalPlayer.NormalMoveSpeed
	if self:InWispForm() then
		speed = LocalPlayer.FlyMoveSpeed
	elseif isCrouching and self.m_isRunning then
		speed = LocalPlayer.SneakFastMoveSpeed
	elseif isCrouching then
		speed = LocalPlayer.SneakMoveSpeed
	elseif self.m_isRunning and self:IsFlying() then
		speed = LocalPlayer.FlyMoveSpeed
	elseif self.m_isRunning then
		speed = LocalPlayer.SprintMoveSpeed
	elseif self:IsFlying() then
		speed = LocalPlayer.FlyMoveSpeed
	end

	--speed = speed * self.m_speedMultiplier
	local mul = 1.0
	local statMul = self:GetStat("SpeedMultiplier")
	if statMul then
		mul = statMul:Value()
	end
	speed = speed * mul

	-- Force the run key to be released for at least a frame after stamina bottoms out.
	if not self.m_sprinting then
		self.m_runPreventFlag = false
	end

	-- Actually set the move speed.
	self:NKGetCharacterController():NKSetMaxSpeed(100)
end

-------------------------------------------------------------------------------
function LocalPlayer:IsRunning()
	return self.m_isRunning
end

-------------------------------------------------------------------------------
function LocalPlayer:EquipItem( object )
	LocalPlayer.__super.EquipItem(self, object)

	self:ItemEquipped(self.m_equippedItem)
end

-------------------------------------------------------------------------------
function LocalPlayer:MoveForward(down)
	-- This is neccessary in the case where the server shuts down while a client is moving around
	if not self:NKGetCharacterController() then
		return
	end

	if down then
		if not self.m_movementLocked then
			self:NKGetCharacterController():MoveForward()
			self:InterruptPickup()
		end
	end
end

-------------------------------------------------------------------------------
function LocalPlayer:MoveBackward(down)
	-- This is neccessary in the case where the server shuts down while a client is moving around
	if not self:NKGetCharacterController() then
		return
	end

	if down then
		if not self.m_movementLocked then
			self:NKGetCharacterController():MoveBackward()
			self:InterruptPickup()
		end
	end
end

-------------------------------------------------------------------------------
function LocalPlayer:StrafeLeft(down)
	-- This is neccessary in the case where the server shuts down while a client is moving around
	if not self:NKGetCharacterController() then
		return
	end

	if down then
		if not self.m_movementLocked then
			self:NKGetCharacterController():MoveLeft()
			self:InterruptPickup()
		end
	end
end

-------------------------------------------------------------------------------
function LocalPlayer:StrafeRight(down)
	-- This is neccessary in the case where the server shuts down while a client is moving around
	if not self:NKGetCharacterController() then
		return
	end

	if down then
		if not self.m_movementLocked then
			self:NKGetCharacterController():MoveRight()
			self:InterruptPickup()
		end
	end
end

-------------------------------------------------------------------------------
function LocalPlayer:Jump(down)
	-- This is neccessary in the case where the server shuts down while a client is moving around
	if not self:NKGetCharacterController() then
		return
	end

	if down then
		if self.m_movementLocked then
			return
		end

		self:InterruptPickup()

		if self:IsCrouching() then
			self:SetCrouching(false)
		end

		local doubleTap = (self.m_doubleTapTimer < 0.30)

		if not self.m_jumpHeld then
			self.m_doubleTapTimer = 0.0
			self.m_jumpHeld = true
		else
			--jump is already held
			doubleTap = false --Never double tap if we got here from a repeat.
		end

		if EternusEngine.Debugging.Enabled or Eternus.GlobalRules.FlyingEnabled > 0 then
			if self:IsFlying() then
				if doubleTap then
					self:SetFlying(false)
				else
					self:NKGetCharacterController():MoveUp()
				end
			else
				if doubleTap then
					self:SetFlying(true)
				elseif self.m_jumpCooldown <= 0.0 then
					self:NKGetCharacterController():Jump()
					self.m_jumpCooldown = 0.1
				end
			end
		else
			if self:IsFlying() then
				self:NKGetCharacterController():MoveUp()
			else
				if self.m_jumpCooldown <= 0.0 then
					self:NKGetCharacterController():Jump()
					self.m_jumpCooldown = 0.1
				end
			end
		end

	else
		self.m_jumpHeld = false
	end
end

-------------------------------------------------------------------------------
function LocalPlayer:Crouch(down)
	-- This is neccessary in the case where th server shuts down while a client is moving around
	if not self:NKGetCharacterController() then
		return
	end

	if down then
		if (self.m_movementLocked) then
			return
		end

		if self:IsFlying() then
			self:NKGetCharacterController():MoveDown()
		elseif not self.m_isHoldingCrouch then
			if not self:IsCrouching() then
				self:SetCrouching(true)
			else
				self:SetCrouching(false)
			end
		end
		self.m_isHoldingCrouch = true
	else
		self.m_isHoldingCrouch = false
	end
end

-- Visibility control.

-------------------------------------------------------------------------------
-- Sets visibility settings for the hands and body based on the given cam mode.
-- Automatically updates those objects ShouldRender flags.
function LocalPlayer:SetVisibilityForCamMode( camMode )
	if camMode == LocalPlayer.ECameraMode.First then
		self.m_baseVisibilitySettings.m_hands = true
		self.m_baseVisibilitySettings.m_body = false

	elseif camMode == LocalPlayer.ECameraMode.Third then
		self.m_baseVisibilitySettings.m_hands = false
		self.m_baseVisibilitySettings.m_body = true

	elseif camMode == LocalPlayer.ECameraMode.Free then
		self.m_baseVisibilitySettings.m_hands = false
		self.m_baseVisibilitySettings.m_body = true

	end

	self:UpdateVisibility()
end

-------------------------------------------------------------------------------
-- Sets override settings for hands and/or body visibility
-- Parameters:
-- part - The body part to be affected.  Should be one of LocalPlayer.EVisibilitySettings
-- activationFlag - Whether to turn the override on or off
-- visibilityFlag - Whether the model should render or not when the override is set.
function LocalPlayer:SetVisibilityOverride( part, activationFlag, visibilityFlag )
	if part == LocalPlayer.EVisibilitySettings.Hands then
		self.m_overrideVisibilitySettings.m_handsActive = activationFlag
		self.m_overrideVisibilitySettings.m_hands = visibilityFlag

	elseif part == LocalPlayer.EVisibilitySettings.Body then
		self.m_overrideVisibilitySettings.m_bodyActive = activationFlag
		self.m_overrideVisibilitySettings.m_body = visibilityFlag

	elseif part == LocalPlayer.EvisibilitySettings.All then
		self.m_overrideVisibilitySettings.m_handsActive = activationFlag
		self.m_overrideVisibilitySettings.m_hands = visibilityFlag

		self.m_overrideVisibilitySettings.m_bodyActive = activationFlag
		self.m_overrideVisibilitySettings.m_body = visibilityFlag

	end

	self:UpdateVisibility()
end

-------------------------------------------------------------------------------
-- Updates the visibility of the body and hands objects based on current
-- visibility settings.
function LocalPlayer:UpdateVisibility()
	local handsOR = self.m_overrideVisibilitySettings.m_handsActive
	local baseHands = self.m_baseVisibilitySettings.m_hands
	local overHands = self.m_overrideVisibilitySettings.m_hands
	local handsVisibility = (not handsOR and baseHands) or (handsOR and overHands)

	local bodyOR = self.m_overrideVisibilitySettings.m_bodyActive
	local baseBody = self.m_baseVisibilitySettings.m_body
	local overBody = self.m_overrideVisibilitySettings.m_body
	local bodyVisibility = (not bodyOR and baseBody) or (bodyOR and overBody)


	if self.m_fpsHands then
		self.m_fpsHands:NKSetShouldRender(handsVisibility, true)
	end

	if self.m_3pobject then
		self.m_3pobject:NKSetShouldRender(bodyVisibility, true)
	end
end

-------------------------------------------------------------------------------
-- Set the camera mode used by the player.
function LocalPlayer:SetCameraMode(mode)
	-- Save the current cam mode.
	self.m_camMode = mode

	-- In first person we show the hands and hide the seed. In third the opposite.
	if mode == LocalPlayer.ECameraMode.First and self.m_fpsHands then
		self.EquippedItemRendersLast = true
		if self:NKGetCharacterController() then
			self:NKGetCharacterController():NKSetAlignWithCamera(true)
		end
		if self.m_equippedItem and self.m_equippedItem:InstanceOf(Equipable) then
			self.m_equippedItem:SetShouldRenderLast(true)
			self.m_fpsHands:NKAddChildObject(self.m_equippedItem)
			local eqInst = self.m_equippedItem
			if (eqInst) then
				eqInst:AttachToBone("Bn_Tool01")
			else
				self.m_equippedItem:NKSetAttachBone("Bn_Tool01")
			end
		end
	else
		self.EquippedItemRendersLast = false
		if self:NKGetCharacterController() then
			self:NKGetCharacterController():NKSetAlignWithCamera(false)
		end
		if self.m_equippedItem and self.m_equippedItem:InstanceOf(Equipable) then
			self.m_equippedItem:SetShouldRenderLast(false)
			self.m_3pobject:NKAddChildObject(self.m_equippedItem)
			local eqInst = self.m_equippedItem
			if (eqInst) then
				eqInst:AttachToBone("Bn_Tool01")
			else
				self.m_equippedItem:NKSetAttachBone("Bn_Tool01")
			end
		end
	end

	self:SetVisibilityForCamMode(mode)
end

-------------------------------------------------------------------------------
-- Called when the player initates death.
-- Overridden from BasePlayer.
function LocalPlayer:Die(source)
	self:SetOverlayAlpha(0.85)
	self:PlayOverlayFlash(0.85, 0.0, 4.0, BasePlayer.HurtColor)

	local sound = Eternus.SoundSystem:NKGetAmbientSound("Death")
	if sound then
		sound:NKPlayAmbient(false)
	end

	self:SetCameraMode(LocalPlayer.ECameraMode.Third)
	Eternus.GameState:SyncCameraModeToPlayer()

	self:SetPlayerNotice("You have been killed!")
	self:PlayNotice(0.0, 1.0, 1.5)

	LocalPlayer.__super.Die(self, source)

	self:RaiseServerEvent("Server_DropAllItems", {})
end

-------------------------------------------------------------------------------
-- BasePlayer now binds the OnSwing animation callback.
function LocalPlayer:_SetThirdPersonGameObject( gameObjectName )
	LocalPlayer.__super._SetThirdPersonGameObject(self, gameObjectName)

	-- Setup the swing callback.
	if self.m_torsoAnimationSlot then
		self.m_gfx:NKRegisterAnimationEvent("OnThrow", LuaAnimationCallbackListener.new(self, "OnThrowAnimation"))
		self.m_gfx:NKRegisterAnimationEvent("OnShoot", LuaAnimationCallbackListener.new(self, "OnShootAnimation"))
		self.m_gfx:NKRegisterAnimationEvent("TransitionToDefault", LuaAnimationCallbackListener.new(self, "TransitionToDefault"))
		self.m_gfx:NKRegisterAnimationEvent("OnConsume", LuaAnimationCallbackListener.new(self, "OnConsume"))
	end
end

-------------------------------------------------------------------------------
-- Swap the 3P model (m_3pobject) out from a seedling to a wisp.
function LocalPlayer:SetModelWisp()
	-- Call the base player version.
	LocalPlayer.__super.SetModelWisp(self)

	-- Create a wisp and destroy the seed.
	if self:InstanceOf(LocalPlayer) then -- Belongs in LocalPlayer via virtual function.
		self:NKSetPosition(self:NKGetPosition() + vec3.new(0.0, 3.0, 0.0))
	end

	self:PlayNotice(1.0, 0.0, 5.0)

	-- Enable fly mode.
	self:NKGetCharacterController():EnableFlying()
	self:SetFlying(true)

	-- Set the base camera height to be at the center of the wisp's
	--	sphere like controller shape
	self:SetBaseCameraHeight(self.m_currentCapsule.WispRadius)
end

-------------------------------------------------------------------------------
function LocalPlayer:SetModelSeedling( growthState )
	LocalPlayer.__super.SetModelSeedling(self, growthState)

	self:SetCameraMode(LocalPlayer.ECameraMode.First)
	Eternus.GameState:SyncCameraModeToPlayer()
	self:NKSetOrientation(quat.new(0.0, 0.0, 1.0, 0.0))
	self.m_respawning = true
	self:SetFlying(false)

	if self:NKGetCharacterController() then
		self:NKGetCharacterController():DisableFlying() --Make sure we're not in fly mode! We should be if we came from a wisp.
		self:NKGetCharacterController():NKSetPhi(0.0)
		self:NKGetCharacterController():NKSetTheta(0.0)
	end
end

-------------------------------------------------------------------------------
function LocalPlayer:PlayTorsoAnimationOneShot( s_animationName, f_transitionInTime, f_transitionOutTime, loop, restart )
	-- Call super function (which plays it on the third person model)
	LocalPlayer.__super.PlayTorsoAnimationOneShot(self, s_animationName, f_transitionInTime, f_transitionOutTime, loop, restart)
	--Now tell the hands to do it.
	if self.m_fpsHands and self.m_fpsHands.PlayAnimationOneShot then
		self.m_fpsHands:PlayAnimationOneShot(s_animationName, f_transitionInTime, f_transitionOutTime, loop, restart)
	end
end

-------------------------------------------------------------------------------
function LocalPlayer:ClearTorsoAnimation()
	-- Call super function (which plays it on the third person model)
	LocalPlayer.__super.ClearTorsoAnimation(self)
	--Now tell the hands to do it.
	self.m_fpsHands:ClearTorsoAnimation()
end

-------------------------------------------------------------------------------
--  Called once a frame from BasePlayer to update the BlendInfo struct that drives the animated model.
--  Overridden from BasePlayer to handle First Person Hands blending as well.
function LocalPlayer:_UpdateAnimationBlending()
	-- Call the super function.
	LocalPlayer.__super._UpdateAnimationBlending(self)

	if self.m_fpsHands and self.m_fpsHands.u_gfx and self.m_gfx then
		-- Get the BlendInfo struct that was filled by the super call above.
		local blendInfo = self.m_gfx:GetBlendInfo()

		-- Copy the blending infomation from the third to first person model as well.
		local handsBlendInfo = self.m_fpsHands.u_gfx:GetBlendInfo()
		handsBlendInfo:NKCopy(blendInfo)

		-- We are crouching, the hands just play idle (we have no animations for this yet).
		-- Don't have crouching yet, ignore this till we do!
		if self:IsCrouching() then
			handsBlendInfo:NKSetState("PlayerState", BasePlayer.EState.eIdle)
		end
	end
end

-------------------------------------------------------------------------------
function LocalPlayer:IsActionLocked()
	return self.m_actionLocked or (not self:InDefaultStance() and not self.m_stance == BasePlayer.EStance.eHolding) or self:IsTransitioning()
end

-------------------------------------------------------------------------------
-- Logic should send an event to the server requesting a craft.
-- Server should send back an event telling it what to craft,
-- along with duration information.
function LocalPlayer:BeginCraft(down)
	if not down then
		return
	end

	if self.m_actionLocked then
		return
	end

	--NKPrint("Trying to craft.")

	local eyePosition = self:NKGetPosition() + vec3(0.0, self.m_cameraHeight, 0.0)
	local lookDirection = Eternus.GameState.m_activeCamera:ForwardVector()
	local result = NKPhysics.RayCastCollect(eyePosition, lookDirection, self:GetMaxReachDistance(), {self})

	local tracePos
	if result then
		tracePos = result.point
	else
		tracePos = eyePosition
		tracePos = tracePos + (lookDirection:mul_scalar(2.5))
	end

	self:RaiseServerEvent("ServerEvent_RequestCrafting", { at = tracePos})
end

-------------------------------------------------------------------------------
function LocalPlayer:SetOverlayAlpha( alpha )
	self.m_gameModeUI.m_backgroundFlash:setAlpha(0.85)
end

-------------------------------------------------------------------------------
function LocalPlayer:PlayOverlayFlash(startAlpha, endAlpha, duration, color)

	self.m_gameModeUI.m_backgroundFlash:setProperty("ImageColours", color)
	self.m_gameModeUI:FadeAlpha(self.m_gameModeUI.m_backgroundFlash, startAlpha, endAlpha, duration)
end

-------------------------------------------------------------------------------
function LocalPlayer:SetPlayerNotice( newText )
	self.m_gameModeUI:SetNoticeText(newText)
end

-------------------------------------------------------------------------------
function LocalPlayer:PlayNotice( startAlpha, endAlpha, duration, callback )
	self.m_gameModeUI:FadeAlpha(self.m_gameModeUI.m_deathNotice, startAlpha, endAlpha, duration, callback)
end

-------------------------------------------------------------------------------
-- Returns true if this player is ready to swing his weapon or hand (i.e. he has something to swing and is not already doing so).
function LocalPlayer:CanSwing( )
	-- Is another swing in progress?
	if self.m_swingTimer > 0 then
		return false
	end
	-- We can swing.
	return true
end

if Eternus.IsClient then
	-------------------------------------------------------------------------------
	-- Overridden from BasePlayer
	function LocalPlayer:ClientEvent_PlayTorsoAnimOnce( args )
		LocalPlayer.__super.ClientEvent_PlayTorsoAnimOnce( self, args )

		if args.animName then
			if self.m_torsoAnimationSlot then
				-- Set the swing timer so that it prevents other swings for the duration of this animation.
				local currentlyPlaying = self.m_torsoAnimationSlot:GetPlayingAnimation()
				if currentlyPlaying then
					self.m_swingTimer = currentlyPlaying:NKGetDuration();
				else
					self.m_swingTimer = 0.25
				end
			end
		end
	end
end -- Eternus.IsClient

-------------------------------------------------------------------------------
function LocalPlayer:SetBlockBrush( brushIdx, sizeIdx )

	self.m_currentBlockSizeIdx = sizeIdx
	self.m_currentBlockBrushIdx = brushIdx
	self.m_currentBlockBrush = self.BlockBrush[self.m_currentBlockBrushIdx]
	self.m_currentBlockBrush.Dimensions = self.m_currentBlockBrush[self.m_currentBlockSizeIdx]

	self:RaiseServerEvent("ServerEvent_SetBlockBrush", { brushIdx = self.m_currentBlockBrushIdx, sizeIdx = self.m_currentBlockSizeIdx })
end

-------------------------------------------------------------------------------
function LocalPlayer:PrimaryAction( down )
	if self:IsDead() or self.m_actionLocked then
		if (self.m_primaryActionEngaged) then
			self.m_primaryActionEngaged = false
		end
		return
	end
	-- no primary action while holding shield
	if self:InHoldingShieldStance() then
		return
	end

	if not down or not self:IsPrimaryActionEnabled() then
		self.m_primaryActionEngaged = false
		return
	end

	if not self.m_primaryActionEngaged then
		self.m_primaryActionEngaged = true
	else

	end

	-- If our inventory is open, CEGUI will handle all the input
	-- This is hacky and should be resolved when we get a new input system
	if self.m_showInventory then
		return
	end
	-- Make sure we can swing first
	if self:CanSwing() then
		--We need to go ahead and do this logic so we can determine if we need can pick something up
		-- as that is a priority over swinging

		-- Order of operations for primary action:
		-- 1. Pick up target.
		-- 2. Use currently held item(hand).
		local tempArgs = {}

		local clientCam = Eternus.GameState.m_activeCamera
		tempArgs.positionW = clientCam:NKGetLocation()
		tempArgs.direction = clientCam:ForwardVector()

		tempArgs.player = self
		self:AddTargetObject(tempArgs)

		-- tempArgs now contains
		-- targetObj
		-- targetPoint

		-- Decide to do new logic or old logic.
		if (self.m_equippedItem ~= nil and self.m_equippedItem.UseNewSwingLogic and self:InDefaultStance()) then
			if (self:IsTransitioning()) then
				return
			end

			local swingData = self.m_equippedItem:GetSwingAnimation()

			if (swingData and self:CanSwing()) then
				self:PlayHandlerSwingAnimation(swingData)
			end

			local currentlyPlaying = self.m_torsoAnimationSlot:GetPlayingAnimation()
			if currentlyPlaying then
				self.m_swingTimer = currentlyPlaying:NKGetDuration();
			end
		elseif self.m_equippedItem and self.m_equippedItem:InstanceOf(Equipable) then
			--Attempt to swing our weapon
			self:SwingEquippedItem()
		elseif self:InCastingStance( ) then
			self:RaiseServerEvent("ServerEvent_Cast", {})
		else
			--Attempt to punch
			--self:PlayTorsoAnimationOneShot("Place", BasePlayer.m_animationBlendTime, BasePlayer.m_animationBlendTime, false, true)
			self:RaiseServerEvent("ServerEvent_PlayTorsoAnimOnce", { animName = "Punch", TimeIN = 0.1, TimeOUT = 0.1, loop = false, restart = true })
		end
	end
end

-------------------------------------------------------------------------------
function LocalPlayer:PlayHandlerSwingAnimation( swingData )
	local swung = false
	if (swingData.type == "looping") then
		swung = self:TransitionStance(BasePlayer.EStanceTransitions.LookupByName[swingData.animation], false)
		self.m_clientLoopingAttacks = true
	elseif (swingData.type == "oneshot") then
		self:PlayTorsoAnimationOneShot(swingData.animation, self.DefaultAnimationBlendTime, self.DefaultAnimationBlendTime, false, true)
		self.m_clientLoopingAttacks = false
		swung = true
	else
		NKWarn("[LocalPlayer:PlayHandlerSwingAnimation] Unknown animation type: " .. tostring(swingData.type))
		return
	end

	--TODO: Move sound playing to when swing actually hits?
	if (swung) then
		self.ActionID = self.ActionID + 1
		self:NKGetSound():NKPlayLocalSound(self.m_equippedItem:GetSwingSound(), false)
		self:RaiseServerEvent("ServerEvent_BeginAttack",
			{
				animationName = swingData.animation,
				animationType = swingData.type,
				actionID = self.ActionID
			})
	end
end

-------------------------------------------------------------------------------
function LocalPlayer:SecondaryAction( down )
	if self:IsDead() or self.m_actionLocked then
		return
	end

	if not down or not self:IsSecondaryActionEnabled() then
		self.m_secondaryActionEngaged = false
		return
	end

	if self:IsPrimaryActionEngaged() then
		return
	end

	local pressed = false

	if not self.m_secondaryActionEngaged then
		self.m_secondaryActionEngaged = true
		if (down) then
			pressed = true
		end
	end

	-- Play test safety code (slingshot)
	if self.m_stance.id == BasePlayer.EStance.eSlingshotHolding.id or self.m_stance.id == BasePlayer.EStance.eSlingshotHolding2.id then
		return
	end

	-- Play test safety code (shield)
	if self:InHoldingShieldStance() then
		return
	end

	-- Play test safety code (casting)
	if self.m_stance.id == BasePlayer.EStance.eCasting.id or self.m_stance.id == BasePlayer.EStance.eCasting2.id then
		return
	end

	-- Play test safety code
	if self.m_stance.id == BasePlayer.EStance.eHolding.id or self:IsTransitioning() then
		return
	end

	-- Temp bail to fix right clicking stuff out of your inventory.
	if self.m_showInventory then
		return
	end

	-- Grab the current client camera and pack the:
	--	origin(vec3) : World Position
	--	direction(vec3) : Normalized direction
	local clientCam = Eternus.GameState.m_activeCamera

	self:RaiseServerEvent("ServerEvent_SecondaryAction", { positionW = clientCam:NKGetLocation(), direction = clientCam:ForwardVector(), pressed = pressed })
end

-------------------------------------------------------------------------------
function LocalPlayer:InventoryToggleable( activated )
	self.m_inventoryToggleable = activated
end

-------------------------------------------------------------------------------
function LocalPlayer:JournalToggleable( activated )
	self.m_journalToggleable = activated
end

-------------------------------------------------------------------------------
function LocalPlayer:ClientEvent_ToggleInventory( args )
	self:ToggleInventory(args.down)
end

-------------------------------------------------------------------------------
function LocalPlayer:ToggleInventoryOverride( down )

	if down then
		return
	end
	self.m_inventoryToggleable = true
	self:ToggleInventory(false)
end

-------------------------------------------------------------------------------
function LocalPlayer:ToggleJournal( down )
	if down then
		return
	end

	if not self.m_journalToggleable then
		return
	end

	self.m_showJournal = not self.m_showJournal

	if self.m_showInventory then
		self.m_playerUI:ToggleJournal(self.m_showJournal)
	else
		self:ToggleInventory(false)
		self.m_playerUI:ToggleJournal(self.m_showJournal)
	end
end

-------------------------------------------------------------------------------
function LocalPlayer:ToggleInventory( down )

	if down then
		return
	end

	if self:IsDead() then
		return
	end

	if not self.m_inventoryToggleable then
		return
	end

	self.m_showInventory = not self.m_showInventory
	self.m_toggleInventorySignal:Fire(self.m_showInventory)

	if self.m_showInventory then
		-- Show the Inventory
		-- Push the inventory input context
		self:CreateInventoryContext()
		Eternus.InputSystem:NKPushInputContext(self.m_inventoryContext)
		self.m_gameModeUI.m_crosshair:hide()
		self.m_playerUI:ToggleInventory(true)
		Eternus.InputSystem:NKShowMouse()
		Eternus.InputSystem:NKCenterMouse()
	else
		-- Hide the Inventory
		-- Pop the inventory input context
		Eternus.InputSystem:NKRemoveInputContext(self.m_inventoryContext)
		self.m_gameModeUI.m_crosshair:show()
		self.m_playerUI:ToggleInventory(false)
		if self.m_showJournal then
			self.m_showJournal = not self.m_showJournal
			self.m_playerUI:ToggleJournal(self.m_showJournal)
		end
		Eternus.InputSystem:NKHideMouse()
		self:CloseContainer(self.m_inventoryContainers[5])
	end

end

-------------------------------------------------------------------------------
-- Overridden from BasePlayer.TransitionStance to also transition the first person hands.
-- sendEvent defaults to true.
function LocalPlayer:TransitionStance( stanceTransition, sendEvent )
	local success = LocalPlayer.__super.TransitionStance(self, stanceTransition)

	if success then
		if (sendEvent == nil or sendEvent == true) then
			self:RaiseServerEvent("SharedEvent_TransitionStance", { transitionID = stanceTransition.id })
		end

		self.m_fpsHands.m_stanceGraph:NKFinishTransition()
		success = self.m_fpsHands.m_stanceGraph:NKTriggerTransition(stanceTransition.name)
	end

	return success
end

-------------------------------------------------------------------------------
-- Overridden from BasePlayer.TransitionShield to also transition the first person hands.
function LocalPlayer:TransitionShield( stanceTransition, targetStance )
	local success = LocalPlayer.__super.TransitionShield(self, stanceTransition, targetStance)

	if (success and self.m_fpsHands.m_shieldGraph:NKGetActiveTransition() ~= stanceTransition.name) then
		self.m_fpsHands.m_shieldGraph:NKFinishTransition()
		success = self.m_fpsHands.m_shieldGraph:NKTriggerTransition(stanceTransition.name)
		if success then
			--NKPrint("FPS Shield Transitioning to '" .. stanceTransition.name .. "'...")
		else
			--NKPrint("FPS Shield Failed to transition to '" .. stanceTransition.name .. "'...")
			if targetStance then
				local result = self.m_fpsHands.m_shieldGraph:NKSetStateEx(targetStance.name)

				if result == BlendByGraph.SUCCESS then
					self.m_shieldStance = targetStance
					success = true
				else
					success = false
					NKPrint("FPS Shield Failed set stance to '" .. targetStance.name .. "'...")
				end
			end
		end
	end

	return success
end

-------------------------------------------------------------------------------
-- Overridden from BasePlayer.SetStance to also set the state of the first person hands.
function LocalPlayer:SetStance( stance )
	local result = self.m_fpsHands.m_stanceGraph:NKSetStateEx(stance.name)
	return LocalPlayer.__super.SetStance(self, stance)
end

-------------------------------------------------------------------------------
function LocalPlayer:ToggleHoldStance(down)
	if not down then
		return
	end

	if self.m_equippedItem then

		-- Specialized Logic --
		if self.m_equippedItem:InstanceOf(RangedWeapon) then
			if self:InDefaultStance() then
				self.m_equippedItem:Aim(self)
			else
				self:TransitionStance(BasePlayer.EStanceTransitions.eCancel)
			end
		else
		-- /Specialized Logic --

			if self.m_equippedItem.holdAnimationName and self:InDefaultStance() and self:CanSwing() then
				self:TransitionStance(BasePlayer.EStanceTransitions.LookupByName[self.m_equippedItem.holdAnimationName])
			else
				self:TransitionStance(BasePlayer.EStanceTransitions.eCancel)
			end
		end
	else
		self:RaiseServerEvent("ServerEvent_ToggleHoldStance", {})
	end
end

-------------------------------------------------------------------------------
-- Test code for throwing an equipped object
-- For now, it's easier to create a new object that
-- is copied from the held item and deleting the item
-- currently being held in the hand
function LocalPlayer:OnThrowAnimation(slot, animation)
	-- Only works if there's an item in the hand
	if not self.m_equippedItem then return end

	local clientCam = Eternus.GameState.m_activeCamera
	if self.m_equippedItem.ClientThrow then
		self.m_equippedItem:ClientThrow({ positionW = clientCam:NKGetLocation(), direction = clientCam:ForwardVector(), rightVector = clientCam:RightVector() })
	end
	self:RaiseServerEvent("ServerEvent_PrimaryAction", { positionW = clientCam:NKGetLocation(), direction = clientCam:ForwardVector(), rightVector = clientCam:RightVector() })
end

-------------------------------------------------------------------------------
function LocalPlayer:OnShootAnimation(slot, animation)
	-- Only works if there's an item in the hand
	if not self.m_equippedItem and not self:InCastingStance() then
		return
	end
	local clientCam = Eternus.GameState.m_activeCamera

	self:RaiseServerEvent("ServerEvent_PrimaryAction", { positionW = clientCam:NKGetLocation(), direction = clientCam:ForwardVector(), rightVector = clientCam:RightVector() })
end

-------------------------------------------------------------------------------
-- Have the player perform the Place action.
function LocalPlayer:Place()
	-- Play the animation.
	self:PlayTorsoAnimationOneShot("Place", BasePlayer.DefaultAnimationBlendTime, BasePlayer.DefaultAnimationBlendTime, false, true)
end

-------------------------------------------------------------------------------
-- Callback from the animation system when playing upper torso animations (occurs at LocalPlayer.SwingDamageApplyTime).
function LocalPlayer:OnSwingAnimation( animation )
	LocalPlayer.__super.OnSwingAnimation(self, animation)

	if (self.m_equippedItem ~= nil and self.m_equippedItem.UseNewSwingLogic and self:InDefaultStance()) then
		local hits = self.m_equippedItem:CollectHits(self)
		if (hits == nil) then
			return false
		end

		if (#hits ~= 0) then
			for k, hit in pairs(hits) do
				hit:SerializeHit(self, self.ActionID)
			end

			self:RaiseServerEvent("ServerEvent_FinalizeHits", { actionID = self.ActionID })
		end
	else
		-- Modify our stamina due to the swing.
		--self:_ModifyStamina(-LocalPlayer.m_staminaDrainSwinging)
		local clientCam = Eternus.GameState.m_activeCamera
		self:RaiseServerEvent("ServerEvent_PrimaryAction", { positionW = clientCam:NKGetLocation(), direction = clientCam:ForwardVector(), rightVector = clientCam:RightVector() })
		return false
	end
end

-------------------------------------------------------------------------------
function LocalPlayer:_SetStamina( amount )
	LocalPlayer.__super._SetStamina(self, amount)

	if self.m_stamina <= 0.0 then
		self.m_runPreventFlag = true
	end
end

-------------------------------------------------------------------------------
function LocalPlayer:SharedEvent_SetStance( args )
end

-------------------------------------------------------------------------------
function LocalPlayer:ClientEvent_TakeDamage( args )
	LocalPlayer.__super.ClientEvent_TakeDamage( self, args )

	self:SetOverlayAlpha(0.85)
	self:PlayOverlayFlash(0.5, 0.0, 1.0, BasePlayer.HurtColor)
end

-------------------------------------------------------------------------------
function LocalPlayer:ClientEvent_NetEventFailure( args )
	self:NetEventFailure(args, "[LocalPlayer] ")
end

-------------------------------------------------------------------------------
function LocalPlayer:ClientEvent_SetStance(args)
	if args.stanceID then
		self:SetStance(BasePlayer.EStance.Lookup[args.stanceID])
	end
end

-------------------------------------------------------------------------------
function LocalPlayer:HandleMouse()
	if not self:HasCameraControl() then return end
end

-------------------------------------------------------------------------------
function LocalPlayer:SetCameraControl(to)
	self.m_cameraControl = to
end

-------------------------------------------------------------------------------
function LocalPlayer:HasCameraControl()
	return self.m_cameraControl
end

-------------------------------------------------------------------------------
function LocalPlayer:SetSecondaryActionEnabled(to)
	self.m_secondaryActionEnabled = to
end

-------------------------------------------------------------------------------
function LocalPlayer:SetPrimaryActionEnabled(to)
	self.m_primaryActionEnabled = to
end

-------------------------------------------------------------------------------
function LocalPlayer:IsSecondaryActionEnabled()
	return self.m_secondaryActionEnabled
end

-------------------------------------------------------------------------------
function LocalPlayer:IsPrimaryActionEnabled()
	return self.m_primaryActionEnabled
end

-------------------------------------------------------------------------------
function LocalPlayer:IsPrimaryActionEngaged()
	return self.m_primaryActionEngaged
end

-------------------------------------------------------------------------------
function LocalPlayer:IsSecondaryActionEngaged()
	return self.m_secondaryActionEngaged
end

-------------------------------------------------------------------------------
function LocalPlayer:HasActionsEngaged()
	return self.m_primaryActionEngaged or self.m_secondaryActionEngaged
end

-------------------------------------------------------------------------------
function LocalPlayer:OnGearEquipped( slotId, gearGameObject, playEffect )
	LocalPlayer.__super.OnGearEquipped(self, slotId, gearGameObject, playEffect)

	if not self.m_fpsHands then return end
	if not gearGameObject:InstanceOf( EquipableGear ) or not gearGameObject:AltersAppearance() then
		self.m_fpsHands:ClearSlotAppearanceRules( slotId )
	else
		self.m_fpsHands:SetSlotAppearanceRules( slotId, gearGameObject:GetAppearanceRules() )
	end
end

-------------------------------------------------------------------------------
function LocalPlayer:OnGearRemoved( slotId )
	LocalPlayer.__super.OnGearRemoved(self, slotId)

	if not self.m_fpsHands then return end
	self.m_fpsHands:ClearSlotAppearanceRules( slotId )
end

-------------------------------------------------------------------------------
function LocalPlayer:_UpdateGearVisuals( obesity, age, hairIdx )
	LocalPlayer.__super._UpdateGearVisuals( self, obesity, age, hairIdx )

	obesity = obesity or self.m_obesity
	age = age or 0.0
	hairIdx = hairIdx or self.m_hairIdx
	if self.m_fpsHands then
		self.m_fpsHands:SetDefaultAppearance(obesity, age, hairIdx)
	end
end

-- Experience asthetics functions that are client side only.
if Eternus.IsClient then
	-------------------------------------------------------------------------------
	-- Overrides BasePlayer._ApplyGrowthState to also apply camera effects for localplayers.
	function LocalPlayer:_ApplyGrowthState( growthState, stateName )
		self.m_fpsHands:SetGrowthState( stateName )
		LocalPlayer.__super._ApplyGrowthState( self, growthState, stateName )
	end
end -- Eternus.IsClient

-------------------------------------------------------------------------------
function LocalPlayer:SharedEvent_Revive( args )
	LocalPlayer.__super.SharedEvent_Revive(self, args)
	-- unlock the player
	self:SetActionLock(false)
	self:SetMovementLock(false)
end

-------------------------------------------------------------------------------
-- Plays a swing animation and starts swing audio
function LocalPlayer:SwingEquippedItem( )
	if self:InDefaultStance() and not self:IsTransitioning() then

		if self.m_equippedItem and self.m_equippedItem:InstanceOf(Equipable) then

			local swingTransitionName = self.m_equippedItem:GetSwingTransition()
			local playSwingSound = false

			if not swingTransitionName then
				-- Get the swing animation from the weapon.
				local animationName = self.m_equippedItem:GetRandSwingAnimationName()
				if animationName then
					playSwingSound = true
					self:RaiseServerEvent("ServerEvent_PlayTorsoAnimOnce", { animName = animationName, TimeIN = self.DefaultAnimationBlendTime, TimeOUT = self.DefaultAnimationBlendTime, loop = false, restart = true })
				end
			else
				playSwingSound = true
				self:TransitionStance(BasePlayer.EStanceTransitions.LookupByName[swingTransitionName])
			end

			-- Play the swing noise.
			if (playSwingSound) then
				self:NKGetSound():NKPlayLocalSound(self.m_equippedItem:GetSwingSound(), false)
			end
		end
	elseif self:InHoldingStance() then
		self:TransitionStance(BasePlayer.EStanceTransitions.eThrow)

		--[[
	elseif self.m_stance == BasePlayer.EStance.eHolding then
		if self.m_equippedItem and self.m_equippedItem:InstanceOf(Projectile) then
			self:TransitionStance(BasePlayer.EStanceTransitions.eThrow)
		end
	elseif self.m_stance == BasePlayer.EStance.eHoldingPotion then
		NKInfo("[LocalPlayer] SwingEquippedItem")
		if self.m_equippedItem and self.m_equippedItem:InstanceOf(ThrowablePotion) then
			self:TransitionStance(BasePlayer.EStanceTransitions.eThrow)
		end
		--]]

	elseif self:InSlingshotHoldingStance( ) then
		if self.m_equippedItem and self.m_equippedItem:InstanceOf(RangedWeapon) then
			self.m_equippedItem:Shoot(self)
		end
	elseif self:InCastingStance( ) then
		local handsEq = self.m_inventoryContainers[SurvivalInventoryController.Containers.eGearSlots]:GetItemAt(CharacterGear.ESlotsLUT["Hands"]) -- "Hands"

		if not self.m_equippedItem and handsEq and handsEq:GetItem() and handsEq:GetItem():InstanceOf(Gauntlet) then
			handsEq:GetItem():Shoot(self)
		else
			self:ResetStance()
		end
	end
end

-------------------------------------------------------------------------------
-- Transitions back to the default stance playing the appropriate transition out animation.
-- This function is hooked up to animation events.
function LocalPlayer:TransitionToDefault( )
	if not self.m_equippedItem or not self.m_primaryActionEngaged then
		self:TransitionStance(BasePlayer.EStanceTransitions.eBackToDefault)
	end
end
------------------------------------------------------------------------
function LocalPlayer:SetTrapped( lockFlag )
	LocalPlayer.__super.SetTrapped(self, lockFlag)

	self:TransitionStance(BasePlayer.EStanceTransitions.eBackToDefault)
end

------------------------------------------------------------------------
-- Fetch the currently traced object.
function LocalPlayer:GetHitObject()
	return self.m_prevHitObj
end

-------------------------------------------------------------------------------
function LocalPlayer:RegisterDeathSignals()
	LocalPlayer.__super.RegisterDeathSignals(self)

	---------------------------------------------
	-- [Dying] state entry signals
	local dyingPhase = self.DeathPhases["Dying"]
	if (dyingPhase == nil) then
		NKError("[RegisterDeathSignals] Dying phase has not been registered.")
		return
	end

	dyingPhase.enterSignal:Add(function()
			self:SetActionLock(true)
			self:SetMovementLock(true)
		end)

	dyingPhase.exitSignal:Add(function()
			self:SetActionLock(false)
			self:SetMovementLock(false)
		end)

	---------------------------------------------
	-- [Wisp] state entry signals
	local wispPhase = self.DeathPhases["Wisp"]
	if (wispPhase == nil) then
		NKError("[RegisterDeathSignals] Wisp phase has not been registered.")
		return
	end

	-- No enter functions for wispPhase

	-- No exit functions for wispPhase

	---------------------------------------------
	-- [WispFade] state entry signals
	local wispFadePhase = self.DeathPhases["WispFade"]
	if (wispFadePhase == nil) then
		NKError("[RegisterDeathSignals] WispFade phase has not been registered.")
		return
	end

	wispFadePhase.enterSignal:Add(function()
			self:PlayOverlayFlash(0.0, 1.0, wispFadePhase.duration, self.WispFadeColor)
		end)

	-- No exit functions for wispFadePhase

	---------------------------------------------
	-- [Removed] state entry signals
	local removedPhase = self.DeathPhases["Removed"]
	if (removedPhase == nil) then
		NKError("[RegisterDeathSignals] Removed phase has not been registered.")
		return
	end

	removedPhase.enterSignal:Add(function()
			self:SetActionLock(true)
			self:SetMovementLock(true)
		end)

	removedPhase.exitSignal:Add(function()
			self:SetActionLock(false)
			self:SetMovementLock(false)
		end)

	---------------------------------------------
	-- [Reviving] state entry signals
	local revivingPhase = self.DeathPhases["Reviving"]
	if (revivingPhase == nil) then
		NKError("[RegisterDeathSignals] Alive phase has not been registered.")
		return
	end

	revivingPhase.enterSignal:Add(function()
			self:PlayOverlayFlash(1.0, 0.0, revivingPhase.duration, self.WispFadeColor)
		end)

	-- No exit functions for revivingPhase

	---------------------------------------------
	-- [Alive] state entry signals
	local alivePhase = self.DeathPhases["Alive"]
	if (alivePhase == nil) then
		NKError("[RegisterDeathSignals] Alive phase has not been registered.")
		return
	end

	-- No enter functions for alivePhase

	alivePhase.exitSignal:Add(function()
			self:SetCrouching(false)
			if (self.m_showInventory) then
				self:ToggleInventory(false)
			end

			if self.m_showJournal then
				self:ToggleJournal(false)
			end
		end)
end

EntityFramework:RegisterGameObject(LocalPlayer)
