EclipseCharacters = {}

local classes = {
  { id = 'guardian', name = 'GUARDIAN', role = 'TANK', color = '#96c6f0',
    quote = 'Proteger é o primeiro passo para a vitória.',
    description = 'Os Guardians são a linha de frente. Sua força, resistência e disciplina os tornam essenciais em qualquer batalha. Eles protegem seus aliados, controlam o campo de combate e mantêm o inimigo sob controle.',
    attributes = 'Vida · Defesa · Resistência', specializations = 'Bastion | Warlord' },
  { id = 'slayer', name = 'SLAYER', role = 'DPS FÍSICO', color = '#cf91ed',
    quote = 'Velocidade é a minha arma. O silêncio, minha vantagem.',
    description = 'Os Slayers são mestres da agilidade e da precisão. Eles atacam rapidamente, exploram brechas e eliminam alvos com golpes letais. Possuem alta mobilidade e são perfeitos tanto para o PvE quanto para o PvP.',
    attributes = 'Dano físico · Agilidade · Crítico', specializations = 'Assassin | Reaper' },
  { id = 'arcanist', name = 'ARCANIST', role = 'DPS MÁGICO', color = '#90b8ff',
    quote = 'O verdadeiro poder está no controle da energia.',
    description = 'Os Arcanists dominam os elementos e o poder arcano. Com suas magias de área e habilidades de controle, eles conseguem devastar grupos de inimigos e se destacar em qualquer situação.',
    attributes = 'Dano mágico · Mana · Controle', specializations = 'Elementalist | Voidcaller' },
  { id = 'mystic', name = 'MYSTIC', role = 'SUPORTE', color = '#badea0',
    quote = 'A vida é o maior dos poderes.',
    description = 'Os Mystics são a essência da cura e do equilíbrio. Eles mantêm o grupo vivo, oferecem buffs e dominam habilidades que garantem sobrevivência e vantagem em batalhas prolongadas.',
    attributes = 'Cura · Mana · Suporte', specializations = 'Oracle | Soulweaver' },
  { id = 'ranger', name = 'RANGER', role = 'DPS A DISTÂNCIA', color = '#c3df8d',
    quote = 'A natureza me guia. O meu alvo, meu destino.',
    description = 'Os Rangers são mestres do arco e da natureza. Eles atacam à distância, utilizam armadilhas, invocam aliados da floresta e possuem excelente mobilidade e controle de área.',
    attributes = 'Dano físico · Agilidade · Sobrevivência', specializations = 'Beastmaster | Pathfinder' }
}

local aliases = {
  knight = 'guardian', ['elite knight'] = 'guardian', bastion = 'guardian', warlord = 'guardian',
  assassin = 'slayer', reaper = 'slayer',
  sorcerer = 'arcanist', ['master sorcerer'] = 'arcanist', elementalist = 'arcanist', voidcaller = 'arcanist',
  druid = 'mystic', ['elder druid'] = 'mystic', oracle = 'mystic', soulweaver = 'mystic',
  paladin = 'ranger', ['royal paladin'] = 'ranger', beastmaster = 'ranger', pathfinder = 'ranger'
}

local function normalized(value)
  return tostring(value or ''):lower():match('^%s*(.-)%s*$')
end

function EclipseCharacters.presentation(character)
  local vocation = normalized(character.vocation)
  local vocationId = tonumber(character.vocationId or character.vocation)
  if vocationId == 5 or vocationId == 6 or vocation == 'god' or vocation == 'admin' or vocation == 'adm' then
    return 'god', 'GOD / ADM', '#ead093'
  end
  local id = vocation
  id = aliases[id] or id
  for _, class in ipairs(classes) do
    if class.id == id then return id, class.name, class.color end
  end
  return nil, '', '#b89acc'
end

function EclipseCharacters.apply(widget, character)
  local id, badge, color = EclipseCharacters.presentation(character)
  local art = widget:getChildById('heroArt')
  if not art then return end
  art:setVisible(id ~= nil)
  if id then
    art:setImageSource('/images/eclipse-selection/' .. id)
    art:mergeStyle({ size = id == 'god' and '152 228' or '86 228' })
  end
  widget:getChildById('presentationBadge'):setText(badge)
  widget:getChildById('presentationBadge'):setColor(color)
  local outfit = widget:getChildById('outfit')
  if not id then
    outfit:mergeStyle({ size = '142 186', ['margin-bottom'] = 46, ['margin-right'] = 76 })
    outfit.baseWidth = 142
    outfit:getChildById('outfitCreatureBox'):mergeStyle({ size = '132 176', ['fixed-creature-size'] = false })
  end
end

function EclipseCharacters.resize(window)
  if not window or window:isDestroyed() then return end
  local parent = window:getParent()
  if not parent then return end
  local scale = math.min(1, (parent:getWidth() - 20) / 1000, (parent:getHeight() - 20) / 660)
  EclipseLogin.scaleWidget(window, math.max(0.1, scale))
  for _, widget in ipairs(window:recursiveGetChildById('characters'):getChildren()) do
    local outfit = widget:getChildById('outfit')
    local checked = window:getChildById('showOutfitBox'):isChecked()
    outfit:setVisible(checked and g_game.getFeature(GameEnterGameShowAppearance))
  end
end

function EclipseCharacters.selectTab(window, tab)
  if not window:getChildById('lorePanel') then return end
  local lore = tab == 'lore'
  window:getChildById('charactersListFrame'):setVisible(not lore)
  window:getChildById('characterListScrollBar'):setVisible(not lore)
  window:getChildById('lorePanel'):setVisible(lore)
  window:getChildById('charactersTab'):setOn(not lore)
  window:getChildById('loreTab'):setOn(lore)
  window:getChildById('buttonOk'):setEnabled(not lore)
  window:getChildById('characterBoxBackground'):setVisible(not lore)
  window:getChildById('hiddenCharacterBox'):setVisible(not lore)
  window:getChildById('outfitBoxBackground'):setVisible(not lore)
  window:getChildById('showOutfitBox'):setVisible(not lore)
end

function EclipseCharacters.selectClass(window, id)
  if not window:getChildById('lorePanel') then return end
  for _, class in ipairs(classes) do
    window:getChildById('lorePanel'):getChildById(class.id .. 'Button'):setOn(class.id == id)
    if class.id == id then
      local panel = window:getChildById('lorePanel')
      panel:getChildById('loreArt'):setImageSource('/images/eclipse-selection/' .. id)
      for key, label in pairs({ name = 'loreName', role = 'loreRole', quote = 'loreQuote', description = 'loreDescription', attributes = 'loreAttributes', specializations = 'loreSpecializations' }) do
        panel:getChildById(label):setText(EclipseLogin.toClientText(class[key]))
      end
      panel:getChildById('loreName'):setColor(class.color)
    end
  end
end
