EclipseLogin = {}

local screen
local linkLabels = {
  website = 'Website', createAccount = 'Criar conta', recoverAccount = 'Recuperar senha',
  discord = 'Discord', youtube = 'YouTube', cinematics = 'Cinemáticas', news = 'Notícias'
}

local function configuredLink(name)
  local links = EclipseLoginConfig and EclipseLoginConfig.links or {}
  local value = links[name]
  if (not value or value == '') and Services then
    if name == 'website' or name == 'recoverAccount' then value = Services.websites end
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

function EclipseLogin.resize()
  if not screen then return end
  local size = screen:getSize()
  local compact = size.width < 950
  screen:getChildById('loginFrame'):setMarginTop(size.height < 550 and 0 or math.min(55, math.floor(size.height * 0.075)))
  screen:getChildById('loginFrame'):setMarginLeft(size.width < 750 and -50 or 0)
  local news = screen:getChildById('newsFrame')
  news:setMarginLeft(compact and 16 or 45)
  news:setWidth(math.max(175, math.min(280, math.floor((size.width - 320) / 2 - 46))))
  news:setVisible(size.width >= 750 and size.height >= 550)
  local actions = screen:getChildById('actionsFrame')
  actions:setMarginRight(compact and 16 or 24)
  actions:setMarginTop(math.min(95, math.max(0, math.floor((size.height - 500) / 2))))
  local background = modules.client_background and modules.client_background.getBackground and modules.client_background.getBackground()
  if background and background.serverLogo then
    local logoHeight = math.min(240, math.floor(size.height * 0.3))
    background.serverLogo:setSize({ width = math.floor(logoHeight * 1.88), height = logoHeight })
    background.serverLogo:setMarginLeft(size.width < 750 and -50 or 0)
  end
end

function EclipseLogin.init(widget)
  screen = widget
  local actions = screen:getChildById('actionsFrame')
  for name, icon in pairs({ statusButton = 'user', optionsButton = 'options', cinematicsButton = 'cinematics', websiteButton = 'website', exitButton = 'exit' }) do
    actions:getChildById(name):getChildById('actionIcon'):setImageSource('/images/eclipse-login/' .. icon)
  end
  local icons = { 'news-welcome', 'news-battle', 'news-gift' }
  for i = 1, 3 do
    local row = screen:getChildById('newsFrame'):getChildById('news' .. i)
    local item = newsItems()[i]
    row:setVisible(type(item) == 'table')
    if type(item) == 'table' then
      row:getChildById('newsTitle'):setText(tostring(item.title or ''))
      row:getChildById('newsDate'):setText(tostring(item.date or ''))
      row:getChildById('newsDescription'):setText(tostring(item.description or ''))
      row:getChildById('newsIcon'):setImageSource('/images/eclipse-login/' .. icons[i])
    end
  end
  local _, config = next(Servers_init or {})
  if config and type(config.protocol) == 'number' then
    screen:getChildById('versionLabel'):setText(string.format('TIBIA %.2f\nOTCLIENT', config.protocol / 100))
  end
  connect(screen, { onGeometryChange = EclipseLogin.resize })
  EclipseLogin.resize()
end

function EclipseLogin.terminate()
  if screen then disconnect(screen, { onGeometryChange = EclipseLogin.resize }) end
  screen = nil
end
