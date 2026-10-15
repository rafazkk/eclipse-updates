EclipseLogin = {}

local screen

function EclipseLogin.toClientText(value)
  return (tostring(value or ''):gsub('[\194\195][\128-\191]', function(characters)
    return string.char((characters:byte(1) - 194) * 64 + characters:byte(2))
  end))
end

local metricProperties = {
  'size', 'width', 'height', 'margin', 'margin-top', 'margin-right', 'margin-bottom', 'margin-left',
  'padding', 'padding-top', 'padding-right', 'padding-bottom', 'padding-left', 'text-offset', 'ttf-font-size'
}

local function scaleWidget(widget, scale)
  if not widget.eclipseMetrics then widget.eclipseMetrics = widget:getStyle() or {} end
  if widget.eclipseScale ~= scale then
    local style = {}
    for _, name in ipairs(metricProperties) do
      local value = widget.eclipseMetrics[name]
      if type(value) == 'number' then
        style[name] = math.floor(value * scale + 0.5)
      elseif type(value) == 'string' then
        style[name] = value:gsub('%-?%d+', function(number)
          return tostring(math.floor(tonumber(number) * scale + 0.5))
        end)
      end
    end
    if widget.eclipseMetrics['ttf-font'] then style['ttf-font'] = widget.eclipseMetrics['ttf-font'] end
    widget.eclipseScale = scale
    widget:mergeStyle(style)
  end
  for _, child in ipairs(widget:getChildren()) do scaleWidget(child, scale) end
end

local linkLabels = {
  website = 'Website', createAccount = 'Criar conta', recoverAccount = 'Recuperar senha',
  discord = 'Discord', youtube = 'YouTube', cinematics = 'Cinemáticas', news = 'Notícias', premium = 'Premium'
}

local function configuredLink(name)
  local links = EclipseLoginConfig and EclipseLoginConfig.links or {}
  local value = links[name]
  if (not value or value == '') and Services then
    if name == 'website' or name == 'recoverAccount' then value = Services.websites end
    if name == 'premium' then value = Services.premium end
  end
  return value
end

local function safeLink(value)
  if type(value) ~= 'string' or value:find('[%s%c]') then return false end
  local scheme, authority = value:match('^(https?)://([^/]+)')
  if not authority or authority:find('@', 1, true) then return false end
  if scheme == 'https' then return true end
  return authority == '127.0.0.1' or authority == 'localhost'
    or authority:match('^127%.0%.0%.1:%d+$') ~= nil or authority:match('^localhost:%d+$') ~= nil
end

function EclipseLogin.openLink(name)
  local value = configuredLink(name)
  if not value or value == '' then
    displayInfoBox(linkLabels[name] or 'Eclipse', 'Este endereço ainda não foi configurado pelo servidor.')
    return
  end
  if not safeLink(value) then
    displayErrorBox('Eclipse', 'Endereço inválido. Use HTTPS, ou HTTP apenas para o teste em localhost.')
    return
  end
  g_platform.openUrl(value)
end

function EclipseLogin.createAccount()
  if Services and Services.createAccount and Services.createAccount ~= '' then
    if not safeLink(Services.createAccount) then
      displayErrorBox('Criar conta', 'O endereço do serviço de cadastro é inválido.')
      return
    end
    screen:getChildById('btnCreateNewAccount'):disable()
    createWidgetAccount()
    return
  end
  EclipseLogin.openLink('createAccount')
end

local function newsItems()
  local items = EclipseLoginConfig and EclipseLoginConfig.news
  if type(items) == 'table' and #items > 0 then return items end
  return {
    { title = 'BEM-VINDO AO ECLIPSE', description = 'Entre com o e-mail e a senha da conta.' },
    { title = 'NOTÍCIAS DO SERVIDOR', description = 'Nenhuma notícia publicada.' },
    { title = 'TESTE LOCAL', description = 'Ligue o servidor e o site para entrar.' }
  }
end

function EclipseLogin.showNews()
  if configuredLink('news') and configuredLink('news') ~= '' then
    EclipseLogin.openLink('news')
    return
  end
  local text = {}
  for i, item in ipairs(newsItems()) do
    if i > 30 then break end
    if type(item) == 'table' then
      text[#text + 1] = tostring(item.title or '') .. '\n' .. tostring(item.description or '')
    end
  end
  displayInfoBox('Notícias do Eclipse', table.concat(text, '\n\n'))
end

function EclipseLogin.showStatus()
  local host, config = next(Servers_init or {})
  displayInfoBox('Servidor de login', string.format('Endereço: %s\nPorta: %s\nProtocolo: %s\n\nO total de jogadores online ainda não foi informado por um serviço de status.',
    tostring(host or 'não configurado'), tostring(config and config.port or '-'), tostring(config and config.protocol or '-')))
end

function EclipseLogin.updatePasswordOption()
  if not screen then return end
  local email = screen:getChildById('rememberEmailBox')
  local password = screen:getChildById('rememberPasswordBox')
  password:setVisible(email:isChecked() or password:isChecked())
end

function EclipseLogin.resize()
  if not screen then return end
  local size = screen:getSize()
  local scale = math.max(0.8, math.min(1.6, size.width / 1124, size.height / 732))
  for _, child in ipairs(screen:getChildren()) do scaleWidget(child, scale) end
  local compact = size.width < 950 * scale
  local frame = screen:getChildById('loginFrame')
  frame:setMarginTop(math.floor(60 * scale))
  frame:setMarginLeft(size.width < 750 and math.floor(-50 * scale) or 0)
  local news = screen:getChildById('newsFrame')
  news:setMarginLeft(math.floor((compact and 16 or 57) * scale))
  news:setWidth(math.floor(math.min(263 * scale, (size.width - frame:getWidth()) / 2 - 64 * scale)))
  news:setVisible(size.width >= 750 and size.height >= 550)
  local actions = screen:getChildById('actionsFrame')
  actions:setMarginRight(math.floor((compact and 16 or 24) * scale))
  actions:setMarginTop(math.floor(95 * scale))
  local background = modules.client_background and modules.client_background.getBackground and modules.client_background.getBackground()
  if background and background.serverLogo then
    local frameTop = (size.height - frame:getHeight()) / 2 + frame:getMarginTop()
    local logoHeight = math.floor(math.min(200 * scale, frameTop - 18 * scale))
    background.serverLogo:setSize({ width = math.floor(logoHeight * 1.88), height = logoHeight })
    background.serverLogo:setMarginLeft(size.width < 750 and math.floor(-50 * scale) or 0)
  end
end

function EclipseLogin.init(widget)
  screen = widget
  for _, id in ipairs({ 'newsHeading', 'allNewsButton', 'eclipseTagline', 'onlinePlayersLabel' }) do
    local label = screen:recursiveGetChildById(id)
    label:setText(EclipseLogin.toClientText(label:getText()))
  end
  screen:getChildById('adventureTagline'):setText(EclipseLogin.toClientText('GRANDES AVENTURAS\nCOMEÇAM COM UM\nÚNICO PASSO...'))
  local actions = screen:getChildById('actionsFrame')
  for name, icon in pairs({ statusButton = 'user', optionsButton = 'options', cinematicsButton = 'cinematics', websiteButton = 'website', exitButton = 'exit' }) do
    local button = actions:getChildById(name)
    button:getChildById('actionIcon'):setImageSource('/images/eclipse-login/' .. icon)
    button:setText(EclipseLogin.toClientText(button:getText()))
  end
  local icons = { 'news-welcome', 'news-battle', 'news-gift' }
  for i = 1, 3 do
    local row = screen:getChildById('newsFrame'):getChildById('news' .. i)
    local item = newsItems()[i]
    row:setVisible(type(item) == 'table')
    if type(item) == 'table' then
      row:getChildById('newsTitle'):setText(EclipseLogin.toClientText(item.title))
      row:getChildById('newsDate'):setText(EclipseLogin.toClientText(item.date))
      row:getChildById('newsDescription'):setText(EclipseLogin.toClientText(item.description))
      row:getChildById('newsIcon'):setImageSource('/images/eclipse-login/' .. icons[i])
    end
  end
  EclipseLogin.updatePasswordOption()
  connect(screen, { onGeometryChange = EclipseLogin.resize })
  EclipseLogin.resize()
end

function EclipseLogin.terminate()
  if screen then disconnect(screen, { onGeometryChange = EclipseLogin.resize }) end
  screen = nil
end
