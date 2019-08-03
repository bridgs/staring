local Controllers = require('src/Controller.lua')

-- Constants
local COLOR = {
  LIGHT_GREY = { 205 / 255, 205 / 255, 205 / 255 }, -- #cdcdcd
  DARK_GREY = { 78 / 255, 74 / 255, 73 / 255 }, -- #4e4a49
  WHITE = { 243 / 255, 241 / 255, 241 / 255 }, -- #f3f1f1
  PURE_WHITE = { 1, 1, 1 }, -- #ffffff
  DEBUG_GREEN = { 0, 1, 0 } -- #00ff00
}
local GAME_X = 27
local GAME_Y = 65
local GAME_WIDTH = 256
local GAME_HEIGHT = 105
local PLAYER_MOVE_SPEED = 60
local PLAYER_DASH_SPEED = 600
local PLAYER_DASH_FRICTION = 0.15
local PLAYER_DASH_DURATION = 0.25
local PLAYER_DASH_COOLDOWN = 0.10
local LASER_MARGIN = {
  TOP = 20,
  SIDE = 10,
  BOTTOM = 10
}

-- Assets
local spriteSheet

-- Input variables
local blankController
local mouseAndKeyboardController
local joystickControllers
local playerControllers

-- Entity groups
local players = {}
local obstacles = {}

-- Entity variables
local entities
local newEntities

-- Entity classes
local ENTITY_CLASSES = {
  player = {
    groups = { players, obstacles },
    eyeRadius = 5,
    radius = 5,
    facingX = 1.0,
    facingY = 0.0,
    aimX = 1.0,
    aimY = 0.0,
    isDashing = false,
    dashDuration = 0.00,
    dashCooldown = 0.00,
    isAiming = false,
    target = nil,
    targetX = nil,
    targetY = nil,
    update = function(self, dt)
      local controller = self:getController()
      -- Calculate player facing
      local moveX, moveY, moveMagnitude = controller:getMoveDirection()
      if moveMagnitude >= 0.0 then
        self.facingX = moveX
        self.facingY = moveY
      end
      -- Handle dashes
      self.dashCooldown = math.max(0.00, self.dashCooldown - dt)
      if self.dashDuration > 0.00 then
        self.dashDuration = math.max(0.00, self.dashDuration - dt)
        if self.dashDuration <= 0.00 then
          self.isDashing = false
        end
      end
      if controller:justStartedDashing() and self.dashCooldown <= 0.00 then
        self.isAiming = false
        self.isDashing = true
        self.dashDuration = PLAYER_DASH_DURATION
        self.dashCooldown = PLAYER_DASH_DURATION + PLAYER_DASH_COOLDOWN
        self.vx = PLAYER_DASH_SPEED * self.facingX
        self.vy = PLAYER_DASH_SPEED * self.facingY
      end
      -- Determine whether the player is aiming
      self.isAiming = controller:isAiming() and not self.isDashing
      -- Move the player
      if self.isDashing then
        self.vx = self.vx * (1 - PLAYER_DASH_FRICTION)
        self.vy = self.vy * (1 - PLAYER_DASH_FRICTION)
      else
        local speed = self.isAiming and 0 or PLAYER_MOVE_SPEED
        self.vx = speed * moveX * moveMagnitude
        self.vy = speed * moveY * moveMagnitude
      end
      self:applyVelocity(dt)
      -- Check for collisions
      for _, obstacle in ipairs(obstacles) do
        if obstacle ~= self then
          handleCircleToCircleCollision(self, obstacle)
        end
      end
      -- Keep player in bounds
      self.x = math.min(math.max(self.radius, self.x), GAME_WIDTH - self.radius)
      self.y = math.min(math.max(self.radius, self.y), GAME_HEIGHT - self.radius)
      -- Figure out what the player is aiming at
      local aimX, aimY, aimMagnitude = controller:getAimDirection(self.x + GAME_X, self.y + GAME_Y)
      if aimMagnitude >= 0.0 then
        self.aimX = aimX
        self.aimY = aimY
      elseif moveMagnitude >= 0.0 then
        self.aimX = moveX
        self.aimY = moveY
      end
      if not self.isAiming then
        self.target = nil
        self.targetX = nil
        self.targetY = nil
      else
        self.target = nil
        self.targetX = self.x + 999 * self.aimX
        self.targetY = self.y + 999 * self.aimY
        -- See if the we're aiming at anything
        for _, obstacle in ipairs(obstacles) do
          if obstacle ~= self then
            local eyeX, eyeY = obstacle:getEyePosition()
            local isIntersecting, x, y = calcCircleLineIntersection(self.x, self.y, self.targetX, self.targetY, eyeX, eyeY, obstacle.eyeRadius)
            if isIntersecting then
              self.target = obstacle
              self.targetX = x
              self.targetY = y
            end
          end
        end
        -- Keep target in bounds
        if self.targetX < -LASER_MARGIN.SIDE then
          self.targetX = -LASER_MARGIN.SIDE
          self.targetY = self.y + self.aimY / self.aimX * (-LASER_MARGIN.SIDE - self.x)
        end
        if self.targetX > GAME_WIDTH + LASER_MARGIN.SIDE then
          self.targetX = GAME_WIDTH + LASER_MARGIN.SIDE
          self.targetY = self.y + self.aimY / self.aimX * (GAME_WIDTH + LASER_MARGIN.SIDE - self.x)
        end
        if self.targetY < -LASER_MARGIN.TOP then
          self.targetX = self.x + self.aimX / self.aimY * (-LASER_MARGIN.TOP - self.y)
          self.targetY = -LASER_MARGIN.TOP
        end
        if self.targetY > GAME_HEIGHT + LASER_MARGIN.BOTTOM then
          self.targetX = self.x + self.aimX / self.aimY * (GAME_HEIGHT + LASER_MARGIN.BOTTOM - self.y)
          self.targetY = GAME_HEIGHT + LASER_MARGIN.BOTTOM
        end
      end
    end,
    draw = function(self)
      love.graphics.setColor(COLOR.LIGHT_GREY)
      love.graphics.circle('fill', self.x, self.y, self.radius)
      if self.isAiming then
        love.graphics.setColor(COLOR.LIGHT_GREY)
        drawPixelatedLine(self.x, self.y, self.targetX, self.targetY)
      end
    end,
    getController = function(self)
      return playerControllers[self.playerNum] or blankController
    end,
    getEyePosition = function(self)
      return self.x, self.y
    end
  },
  baddie = {
    groups = { obstacles },
    radius = 7,
    eyeRadius = 5,
    eyeOffsetX = 0,
    eyeOffsetY = -15,
    eyeWhiteOffsetX = 0,
    eyeWhiteOffsetY = 0,
    timeUntilEyeWhiteUpdate = 0.00,
    pupilOffsetX = 0,
    pupilOffsetY = 0,
    timeUntilPupilUpdate = 0.00,
    isPushable = false,
    update = function(self, dt)
      -- Figure out which player is closest
      local closestPlayer
      local closestPlayerSquareDist
      for _, player in ipairs(players) do
        local dx = player.x - self.x
        local dy = player.y - self.y
        local squareDist = dx * dx + dy * dy
        if not closestPlayer or squareDist < closestPlayerSquareDist then
          closestPlayer = player
          closestPlayerSquareDist = squareDist
        end
      end
      -- Update eye
      if closestPlayer then
        local eyeX, eyeY = self:getEyePosition()
        local playerEyeX, playerEyeY = closestPlayer:getEyePosition()
        local dx = playerEyeX - eyeX
        local dy = playerEyeY - eyeY
        local dist = math.sqrt(dx * dx + dy * dy)
        local angle = math.atan2(dy, dx)
        local distMult = math.min(1.0, 0.35 + dist / 200)
        -- Update eye white offset
        self.timeUntilEyeWhiteUpdate = self.timeUntilEyeWhiteUpdate - dt
        if self.timeUntilEyeWhiteUpdate <= 0.00 then
          self.timeUntilEyeWhiteUpdate = 0.3 + 0.2 * math.random()
          local eyeWhiteDist = distMult * 2.0
          self.eyeWhiteOffsetX = eyeWhiteDist * math.cos(angle)
          self.eyeWhiteOffsetY = eyeWhiteDist * math.sin(angle)
        end
        -- Update pupil offset
        self.timeUntilPupilUpdate = self.timeUntilPupilUpdate - dt
        if self.timeUntilPupilUpdate <= 0.00 then
          self.timeUntilPupilUpdate = 0.1 + 0.2 * math.random()
          local angleMult = ((2 * angle / math.pi) + 1) % 2
          if angleMult > 1 then
            angleMult = 2 - angleMult
          end
          angleMult = math.max(0.2, angleMult)
          local pupilDist = distMult * (1.3 + 1.9 * angleMult)
          self.pupilOffsetX = pupilDist * math.cos(angle) + 0.5 * math.random() - 0.25
          self.pupilOffsetY = pupilDist * math.sin(angle) + 0.5 * math.random() - 0.25
        end
      end
    end,
    draw = function(self)
      -- Draw body
      drawSprite(0, 172, 21, 36, self.x - 10.5, self.y - 26)
      -- Draw eye white
      local eyeWhiteX, eyeWhiteY = self:getEyeWhitePosition()
      drawSprite(0, 209, 10, 7, eyeWhiteX - 5, eyeWhiteY - 3.5)
      -- Draw pupil
      local pupilX, pupilY = self:getPupilPosition()
      love.graphics.setColor(COLOR.DARK_GREY)
      love.graphics.rectangle('fill', pupilX - 0.5, pupilY - 0.5, 1, 1)
      -- love.graphics.setColor(COLOR.DEBUG_GREEN)
      -- love.graphics.circle('line', self.x, self.y, self.radius)
      -- local eyeX, eyeY = self:getEyePosition()
      -- love.graphics.circle('line', eyeX, eyeY, self.eyeRadius)
    end,
    getEyePosition = function(self)
      local x, y = self.x, self.y
      return x + self.eyeOffsetX, y + self.eyeOffsetY
    end,
    getEyeWhitePosition = function(self)
      local x, y = self:getEyePosition()
      return x + self.eyeWhiteOffsetX, y + self.eyeWhiteOffsetY
    end,
    getPupilPosition = function(self)
      local x, y = self:getEyeWhitePosition()
      return x + self.pupilOffsetX, y + self.pupilOffsetY
    end
  }
}

function love.load()
  -- Set default filter to nearest to allow crisp pixel art
  love.graphics.setDefaultFilter('nearest', 'nearest')
  -- Load assets
  spriteSheet = love.graphics.newImage('img/sprite-sheet.png')
  -- Create controllers
  blankController = Controllers.BlankController:new()
  mouseAndKeyboardController = Controllers.MouseAndKeyboardController:new()
  joystickControllers = {}
  playerControllers = { mouseAndKeyboardController, nil }
  -- Spawn entities
  entities = {}
  newEntities = {}
  spawnEntity('player', {
    playerNum = 1,
    x = 150,
    y = 50
  })
  spawnEntity('player', {
    playerNum = 2,
    x = 100,
    y = 50
  })
  spawnEntity('baddie', {
    x = 200,
    y = 75
  })
  addNewEntitiesToGame()
end

function love.update(dt)
  -- Update entities
  for _, entity in ipairs(entities) do
    entity.framesAlive = entity.framesAlive + 1
    entity.timeAlive = entity.timeAlive + dt
    entity:update(dt)
  end
  -- Add newly spawned entities to the game
  addNewEntitiesToGame()
  -- Remove dead entities from the game
  removeDeadEntitiesFromGame()
  -- Update controllers
  mouseAndKeyboardController:update(dt)
  for i = #joystickControllers, 1, -1 do
    local controller = joystickControllers[i]
    if not controller:isActive() then
      table.remove(joystickControllers, i)
    else
      controller:update(dt)
    end
  end
  -- Try switching controllers after controller disconnects
  if playerControllers[1] and not playerControllers[1]:isActive() then
    if playerControllers[2] == mouseAndKeyboardController then
      playerControllers[2] = nil
    end
    playerControllers[1] = mouseAndKeyboardController
  end
  if playerControllers[2] and not playerControllers[2]:isActive() then
    if playerControllers[1] == mouseAndKeyboardController then
      playerControllers[2] = nil
    else
      playerControllers[2] = mouseAndKeyboardController
    end
  end
end

function love.draw()
  -- Clear the screen
  love.graphics.clear(COLOR.WHITE)
  -- Draw the background
  drawSprite(0, 0, 300, 163, 5, 21)
  -- Draw the game
  love.graphics.push()
  love.graphics.translate(GAME_X, GAME_Y)
  -- Draw entities
  for _, entity in ipairs(entities) do
    love.graphics.setColor(COLOR.PURE_WHITE)
    entity:draw()
  end
  love.graphics.pop()
end

-- Assign controllers as they're added
function love.joystickadded(joystick)
  local controller = Controllers.JoystickController:new(joystick)
  table.insert(joystickControllers, controller)
  if not playerControllers[1] or playerControllers[1] == mouseAndKeyboardController then
    playerControllers[1] = controller
    playerControllers[2] = mouseAndKeyboardController
  elseif not playerControllers[2] or playerControllers[2] == mouseAndKeyboardController then
    playerControllers[2] = controller
  end
end

-- Pass input callbacks to the controllers
function love.joystickpressed(...)
  for _, controller in ipairs(joystickControllers) do
    controller:joystickpressed(...)
  end
end
function love.mousepressed(...)
  mouseAndKeyboardController:mousepressed(...)
end
function love.keypressed(...)
  mouseAndKeyboardController:keypressed(...)
end

-- Spawns a new game entity
function spawnEntity(className, params)
  -- Create a default entity
  local entity = {
    type = className,
    isAlive = true,
    framesAlive = 0,
    timeAlive = 0.00,
    radius = 5,
    x = 0,
    y = 0,
    vx = 0,
    vy = 0,
    isPushable = true,
    init = function(self) end,
    update = function(self, dt)
      self:applyVelocity(dt)
    end,
    applyVelocity = function(self, dt)
      self.x = self.x + self.vx * dt
      self.y = self.y + self.vy * dt
    end,
    draw = function(self)
      love.graphics.setColor(COLOR.LIGHT_GREY)
      love.graphics.circle('fill', self.x, self.y, self.radius)
    end,
    addToGame = function(self)
      table.insert(entities, self)
      if self.groups then
        for _, group in ipairs(self.groups) do
          table.insert(group, self)
        end
      end
    end,
    removeFromGame = function(self)
      for i = 1, #entities do
        if entities[i] == self then
          table.remove(entities, i)
          break
        end
      end
      if self.groups then
        for _, group in ipairs(self.groups) do
          for i = 1, #group do
            if group[i] == self then
              table.remove(group, i)
              break
            end
          end
        end
      end
    end,
    destroy = function(self)
      self.isAlive = false
    end
  }
  -- Add properties from the class
  for k, v in pairs(ENTITY_CLASSES[className]) do
    entity[k] = v
  end
  -- Add properties that were passed into the method
  for k, v in pairs(params) do
    entity[k] = v
  end
  -- Add it to the list of entities to be added, initialize it, and return it
  table.insert(newEntities, entity)
  entity:init()
  return entity
end

-- Add any entities that were spawned this frame to the game
function addNewEntitiesToGame()
  for _, entity in ipairs(newEntities) do
    entity:addToGame()
  end
  newEntities = {}
end

-- Removes any entities that destroyed this frame from the game
function removeDeadEntitiesFromGame()
  for i = #entities, 1, -1 do
    if not entities[i].isAlive then
      entities[i]:removeFromGame()
    end
  end
end

-- Draw a sprite from the sprite sheet to the screen
function drawSprite(sx, sy, sw, sh, x, y, flipHorizontal, flipVertical, rotation)
  local width, height = spriteSheet:getDimensions()
  return love.graphics.draw(spriteSheet,
    love.graphics.newQuad(sx, sy, sw, sh, width, height),
    x + sw / 2, y + sh / 2,
    rotation or 0,
    flipHorizontal and -1 or 1, flipVertical and -1 or 1,
    sw / 2, sh / 2)
end

-- Moves two circular entities apart so they're not overlapping
function handleCircleToCircleCollision(entity1, entity2)
  -- Figure out how far apart the entities are
  local dx = entity2.x - entity1.x
  local dy = entity2.y - entity1.y
  if dx == 0 and dy == 0 then
    dy = 0.1
  end
  local squareDist = dx * dx + dy * dy
  local sumRadii = entity1.radius + entity2.radius
  -- If the entities are close enough, they're colliding
  if squareDist < sumRadii * sumRadii then
    local dist = math.sqrt(squareDist)
    local pushAmount = sumRadii - dist
    -- Push one away from the other
    if entity1.isPushable and not entity2.isPushable then
      entity1.x = entity1.x - pushAmount * dx / dist
      entity1.y = entity1.y - pushAmount * dy / dist
    elseif entity2.isPushable and not entity1.isPushable then
      entity2.x = entity2.x + pushAmount * dx / dist
      entity2.y = entity2.y + pushAmount * dy / dist
    -- Push them both away from each other
    else
      entity1.x = entity1.x - (pushAmount / 2) * dx / dist
      entity1.y = entity1.y - (pushAmount / 2) * dy / dist
      entity2.x = entity2.x + (pushAmount / 2) * dx / dist
      entity2.y = entity2.y + (pushAmount / 2) * dy / dist
    end
    return true
  -- If the entities are far from one another, they're not colliding
  else
    return false
  end
end

-- Draws a line by drawing little pixely squares
function drawPixelatedLine(x1, y1, x2, y2, thickness, gaps, dashes)
  thickness = thickness or 1
  gaps = gaps or 0
  dashes = dashes or (gaps == 0 and 1 or gaps)
  local dx, dy = math.abs(x2 - x1), math.abs(y2 - y1)
  if dx > dy then
    local i = x1 < x2 and 0 or dx
    local minX, maxX = math.floor(math.min(x1, x2) + 0.5), math.floor(math.max(x1, x2) + 0.5)
    for x = minX, maxX do
      if i % (gaps + dashes) < dashes then
        local y = math.floor(y1 + (y2 - y1) * (x - x1) /(x1 == x2 and 1 or x2 - x1) + 0.5)
        love.graphics.rectangle('fill', x - thickness / 2, y - thickness / 2, thickness, thickness)
      end
      i = i + (x1 < x2 and 1 or -1)
    end
  else
    local i = y1 < y2 and 0 or dy
    local minY, maxY = math.floor(math.min(y1, y2) + 0.5), math.floor(math.max(y1, y2) + 0.5)
    for y = minY, maxY do
      if i % (gaps + dashes) < dashes then
        local x = math.floor(x1 + (x2 - x1) * (y - y1) / (y1 == y2 and 1 or y2 - y1) + 0.5)
        love.graphics.rectangle('fill', x - thickness / 2, y - thickness / 2, thickness, thickness)
      end
      i = i + (y1 < y2 and 1 or -1)
    end
  end
end

-- Calculates the intersection between a line segment and a circle
function calcCircleLineIntersection(x1, y1, x2, y2, cx, cy, r)
  -- If the start point is within the circle, return the start point
  if (cx - x1) * (cx - x1) + (cy - y1) * (cy - y1) < r * r then
    return true, x1, y1, 0
  else
    local dx = x2 - x1
    local dy = y2 - y1
    local A = dx * dx + dy * dy
    local B = 2 * (dx * (x1 - cx) + dy * (y1 - cy))
    local C = (x1 - cx) * (x1 - cx) + (y1 - cy) * (y1 - cy) - r * r
    local det = B * B - 4 * A * C
    -- There are no valid intersections
    if det < 0 then
      return false
    else
      -- There is an intersection on the line, but maybe not on the line segment
      local rootDet = math.sqrt(det)
      local t1 = (-B + rootDet) / (2 * A)
      local t2 = (-B - rootDet) / (2 * A)
      local xIntersection1 = x1 + t1 * dx
      local yIntersection1 = y1 + t1 * dy
      local xIntersection2 = x1 + t2 * dx
      local yIntersection2 = y1 + t2 * dy
      local squareDist1 = (xIntersection1 - x1) * (xIntersection1 - x1) + (yIntersection1 - y1) * (yIntersection1 - y1)
      local squareDist2 = (xIntersection2 - x1) * (xIntersection2 - x1) + (yIntersection2 - y1) * (yIntersection2 - y1)
      local xMin = math.min(x1, x2)
      local xMax = math.max(x1, x2)
      local yMin = math.min(y1, y2)
      local yMax = math.max(y1, y2)
      -- There is an intersection on the line segment
      if squareDist1 < squareDist2 and xMin - 1 < xIntersection1 and xIntersection1 < xMax + 1 and yMin - 1 < yIntersection1 and yIntersection1 < yMax + 1 then
        return true, xIntersection1, yIntersection1, squareDist1
      elseif xMin - 1 < xIntersection2 and xIntersection2 < xMax + 1 and yMin - 1 < yIntersection2 and yIntersection2 < yMax + 1 then
        return true, xIntersection2, yIntersection2, squareDist2
      -- The intersection is not on the line segment
      else
        return false
      end
    end
  end
end
