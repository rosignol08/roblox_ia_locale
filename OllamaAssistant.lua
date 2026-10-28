-- OllamaAssistant.lua
local HttpService = game:GetService("HttpService")
local ScriptEditorService = game:GetService("ScriptEditorService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Selection = game:GetService("Selection")

local AGENT_URL = "http://192.168.1.91:5000/api/agent"
local lastGeneratedCode = nil
local currentTaskId = nil
local isCancelled = false

local lastInjected = nil
local lastFullResponse = ""

-- Variables d'état pour le mode Agent Autonome
local planSteps = {}
local activeStepIndex = 0
local originalGlobalPrompt = ""

-- ======================================================
-- UI Setup
-- ======================================================
local toolbar = plugin:CreateToolbar("Ollama Assistant")
local button = toolbar:CreateButton("Ollama", "Assistant IA", "rbxassetid://4458901886")
button.ClickableWhenViewportHidden = true

local widget = plugin:CreateDockWidgetPluginGui(
	"OllamaAssistantWidget",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 420, 550, 300, 300)
)
widget.Title = "Ollama Agent"

local frame = Instance.new("Frame")
frame.Size = UDim2.fromScale(1, 1)
frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
frame.Parent = widget

local modelInput = Instance.new("TextBox", frame)
modelInput.Size, modelInput.Position = UDim2.new(0.5, -15, 0, 30), UDim2.new(0, 10, 0, 10)
modelInput.Text = "gemma4:26b"
modelInput.ClearTextOnFocus = false
modelInput.BackgroundColor3, modelInput.TextColor3 = Color3.fromRGB(45, 45, 45), Color3.fromRGB(230, 230, 230)

local modeButton = Instance.new("TextButton", frame)
modeButton.Size, modeButton.Position = UDim2.new(0.5, -15, 0, 30), UDim2.new(0.5, 5, 0, 10)
modeButton.BackgroundColor3, modeButton.TextColor3 = Color3.fromRGB(80, 80, 80), Color3.new(1, 1, 1)
modeButton.Font = Enum.Font.SourceSansBold

local modes = {"Assistant", "Constructeur", "Codeur Strict", "Débogueur", "Agent Autonome"}
local currentModeIndex = 1
modeButton.Text = "Mode: " .. modes[currentModeIndex]

modeButton.MouseButton1Click:Connect(function()
	currentModeIndex = (currentModeIndex % #modes) + 1
	modeButton.Text = "Mode: " .. modes[currentModeIndex]
end)

local inputBox = Instance.new("TextBox", frame)
inputBox.Size, inputBox.Position = UDim2.new(1, -20, 0, 80), UDim2.new(0, 10, 0, 50)
inputBox.MultiLine, inputBox.TextWrapped = true, true
inputBox.PlaceholderText = "Ex: Crée des flaques d'eau qui font glisser le joueur..."
inputBox.ClearTextOnFocus = false
inputBox.BackgroundColor3, inputBox.TextColor3 = Color3.fromRGB(45, 45, 45), Color3.fromRGB(230, 230, 230)
inputBox.TextXAlignment, inputBox.TextYAlignment = Enum.TextXAlignment.Left, Enum.TextYAlignment.Top

local sendButton = Instance.new("TextButton", frame)
sendButton.Size, sendButton.Position = UDim2.new(1, -20, 0, 32), UDim2.new(0, 10, 0, 140)
sendButton.Text = "Envoyer / Créer un Plan"
sendButton.BackgroundColor3, sendButton.TextColor3 = Color3.fromRGB(60, 100, 220), Color3.new(1, 1, 1)

local stopButton = Instance.new("TextButton", frame)
stopButton.Size, stopButton.Position = UDim2.new(1, -20, 0, 32), UDim2.new(0, 10, 0, 140)
stopButton.Text = "🛑 Arrêter la réflexion"
stopButton.BackgroundColor3, stopButton.TextColor3 = Color3.fromRGB(200, 50, 50), Color3.new(1, 1, 1)
stopButton.Font = Enum.Font.SourceSansBold
stopButton.Visible = false

-- Ligne d'actions Y=177
local executeButton = Instance.new("TextButton", frame)
executeButton.Size, executeButton.Position = UDim2.new(0.65, -15, 0, 32), UDim2.new(0, 10, 0, 177)
executeButton.Text = "▶️ Exécuter le code"
executeButton.BackgroundColor3, executeButton.TextColor3 = Color3.fromRGB(40, 160, 80), Color3.new(1, 1, 1)
executeButton.Font = Enum.Font.SourceSansBold
executeButton.Visible = false

local btnNextStep = Instance.new("TextButton", frame)
btnNextStep.Size, btnNextStep.Position = UDim2.new(0.40, -5, 0, 32), UDim2.new(0, 10, 0, 177)
btnNextStep.Text = "▶️ Étape Suivante"
btnNextStep.BackgroundColor3, btnNextStep.TextColor3 = Color3.fromRGB(40, 120, 200), Color3.new(1, 1, 1)
btnNextStep.Font = Enum.Font.SourceSansBold
btnNextStep.Visible = false

local btnRetryStep = Instance.new("TextButton", frame)
btnRetryStep.Size, btnRetryStep.Position = UDim2.new(0.25, -10, 0, 32), UDim2.new(0.40, 10, 0, 177)
btnRetryStep.Text = "🔄 Refaire"
btnRetryStep.BackgroundColor3, btnRetryStep.TextColor3 = Color3.fromRGB(200, 160, 40), Color3.new(1, 1, 1)
btnRetryStep.Font = Enum.Font.SourceSansBold
btnRetryStep.Visible = false

local undoButton = Instance.new("TextButton", frame)
undoButton.Size, undoButton.Position = UDim2.new(0.35, -10, 0, 32), UDim2.new(0.65, 10, 0, 177)
undoButton.Text = "↩️ Annuler"
undoButton.BackgroundColor3, undoButton.TextColor3 = Color3.fromRGB(200, 100, 40), Color3.new(1, 1, 1)
undoButton.Font = Enum.Font.SourceSansBold
undoButton.Visible = false

local provideContextButton = Instance.new("TextButton", frame)
provideContextButton.Size, provideContextButton.Position = UDim2.new(1, -20, 0, 32), UDim2.new(0, 10, 0, 105)
provideContextButton.BackgroundColor3, provideContextButton.TextColor3 = Color3.fromRGB(150, 80, 200), Color3.new(1, 1, 1)
provideContextButton.Font = Enum.Font.SourceSansBold
provideContextButton.Visible = false
local fileToFetch = "" -- Stockera le chemin du fichier demandé

local statusLabel = Instance.new("TextLabel", frame)
statusLabel.Size, statusLabel.Position = UDim2.new(1, -20, 0, 20), UDim2.new(0, 10, 0, 215)
statusLabel.BackgroundTransparency, statusLabel.TextColor3 = 1, Color3.fromRGB(150, 150, 150)
statusLabel.Text = "Prêt."

local outputScroll = Instance.new("ScrollingFrame", frame)
outputScroll.Size, outputScroll.Position = UDim2.new(1, -20, 1, -245), UDim2.new(0, 10, 0, 235)
outputScroll.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
outputScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
outputScroll.CanvasSize = UDim2.new(0, 0, 0, 0)

local MAX_CHUNK = 8000      -- bien sous la limite de ~16 000 caractères
local PREVIEW_LINES = 30

-- Découpe une réponse en segments texte / code (gère aussi un ``` jamais fermé)
local function splitSegments(text)
	local segments = {}
	local pos = 1
	while true do
		local s, e = string.find(text, "```[%w_]*[ \t]*\r?\n", pos)
		if not s then break end
		if s > pos then
			table.insert(segments, {kind = "text", body = string.sub(text, pos, s - 1)})
		end
		local closeS, closeE = string.find(text, "```", e + 1, true)
		if closeS then
			table.insert(segments, {kind = "code", body = string.sub(text, e + 1, closeS - 1)})
			pos = closeE + 1
		else
			table.insert(segments, {kind = "code", body = string.sub(text, e + 1), truncated = true})
			pos = #text + 1
			break
		end
	end
	if pos <= #text then
		table.insert(segments, {kind = "text", body = string.sub(text, pos)})
	end
	return segments
end

local boxOrder = 0
local function addBox(text, isCode)
	boxOrder += 1
	local tb = Instance.new("TextBox")
	tb.Size = UDim2.new(1, -10, 0, 0)
	tb.AutomaticSize = Enum.AutomaticSize.Y
	tb.BackgroundTransparency = isCode and 0 or 1
	tb.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
	tb.TextColor3 = isCode and Color3.fromRGB(180, 230, 180) or Color3.fromRGB(210, 210, 210)
	tb.Font = isCode and Enum.Font.Code or Enum.Font.SourceSans
	tb.TextSize = 14
	tb.TextWrapped = true
	tb.MultiLine = true
	tb.TextEditable = false
	tb.ClearTextOnFocus = false
	tb.TextXAlignment = Enum.TextXAlignment.Left
	tb.TextYAlignment = Enum.TextYAlignment.Top
	tb.Text = text
	tb.LayoutOrder = boxOrder
	tb.Parent = outputScroll
end

-- Texte long : plusieurs boîtes, découpées aux sauts de ligne
local function addTextChunked(text, isCode)
	local buffer = ""
	for line in string.gmatch(text .. "\n", "(.-)\r?\n") do
		if #buffer + #line + 1 > MAX_CHUNK and buffer ~= "" then
			addBox(buffer, isCode)
			buffer = ""
		end
		-- ligne gigantesque : on la coupe
		while #line > MAX_CHUNK do
			addBox(string.sub(line, 1, MAX_CHUNK), isCode)
			line = string.sub(line, MAX_CHUNK + 1)
		end
		buffer ..= line .. "\n"
	end
	if buffer ~= "" then addBox(buffer, isCode) end
end

local function afficherReponse(texte)
	for _, child in ipairs(outputScroll:GetChildren()) do
		if child:IsA("GuiObject") then child:Destroy() end
	end
	boxOrder = 0
	if not texte or texte == "" then return end

	for _, seg in ipairs(splitSegments(texte)) do
		if seg.kind == "text" then
			if string.match(seg.body, "%S") then addTextChunked(seg.body, false) end
		else
			-- Aperçu du code seulement : le code COMPLET est injecté via le bouton
			local lines = string.split(seg.body, "\n")
			local preview = {}
			for i = 1, math.min(#lines, PREVIEW_LINES) do
				table.insert(preview, string.sub(lines[i], 1, 200))
			end
			local msg = table.concat(preview, "\n")
			if #lines > PREVIEW_LINES then
				msg ..= "\n… (" .. #lines .. " lignes, " .. #seg.body .. " caractères au total)"
			end
			if seg.truncated then
				msg ..= "\n⚠️ Réponse coupée par le modèle : le code est peut-être incomplet."
			end
			addBox(msg, true)
		end
	end
end

-- 2. Création du bouton de copie (placé juste au-dessus de la zone de texte, à droite)
local copyButton = Instance.new("TextButton", frame)
copyButton.Size, copyButton.Position = UDim2.new(0, 130, 0, 25), UDim2.new(1, -140, 0, 205) 
copyButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
copyButton.TextColor3 = Color3.new(1, 1, 1)
copyButton.Font = Enum.Font.SourceSansBold
copyButton.Text = "📋 Copier la réponse"
copyButton.Visible = true

-- 3. Action du bouton : copie dans le presse-papier de ton ordinateur
copyButton.Text = "📂 Ouvrir le script"

copyButton.MouseButton1Click:Connect(function()
	if lastInjected and lastInjected.Parent then
		task.spawn(function()
			pcall(function() ScriptEditorService:OpenScriptDocumentAsync(lastInjected) end)
		end)
	else
		statusLabel.Text = "Aucun script injecté pour l'instant."
	end
end)
-- Création de l'indicateur visuel
local contextIndicator = Instance.new("TextLabel", frame)
contextIndicator.Size = UDim2.new(1, -20, 0, 20)
contextIndicator.Position = UDim2.new(0, 10, 0, 85) -- Ajuste la position Y selon ton interface
contextIndicator.BackgroundTransparency = 1
contextIndicator.TextColor3 = Color3.fromRGB(150, 150, 255) -- Bleu clair pour se démarquer
contextIndicator.TextXAlignment = Enum.TextXAlignment.Left
contextIndicator.Font = Enum.Font.SourceSansItalic
contextIndicator.Text = "📎 Contexte : Aucun script sélectionné"
contextIndicator.TextTruncate = Enum.TextTruncate.AtEnd

-- Mise à jour automatique à chaque clic dans l'explorateur
game:GetService("Selection").SelectionChanged:Connect(function()
	local selected = game:GetService("Selection"):Get()
	if #selected == 0 then
		contextIndicator.Text = "📎 Contexte : Automatique (Carte du projet)"
	else
		local names = {}
		for _, item in ipairs(selected) do
			table.insert(names, item.Name)
		end
		contextIndicator.Text = "📎 Contexte actif : " .. table.concat(names, ", ")
	end
end)

-- ======================================================
-- NOUVEAU : Exécution non bloquante + tracking des nouvelles instances
-- ======================================================
-- Au bout de RUN_TIMEOUT_SECONDS, si le code tourne encore (boucle infinie,
-- task.wait long...), le plugin arrête d'attendre et rend la main. Le code
-- continue de s'exécuter tout seul en arrière-plan ; on ne peut pas le "tuer"
-- depuis un plugin, seulement arrêter d'attendre dessus.
local RUN_TIMEOUT_SECONDS = 5
local POLL_INTERVAL = 0.1

-- callback(success: bool, errMsg: string?, newInstances: {Instance}, timedOut: bool)
local function executeGeneratedCode(code, callback)
	local func, compileErr = loadstring(code)
	if not func then
		callback(false, "Erreur de syntaxe : " .. tostring(compileErr), {}, false)
		return
	end

	-- Tracking des objets créés pendant l'exécution
	local newInstances = {}
	local seen = {}
	local trackingConn
	trackingConn = game.DescendantAdded:Connect(function(inst)
		if not seen[inst] then
			seen[inst] = true
			table.insert(newInstances, inst)
		end
	end)

	ChangeHistoryService:SetWaypoint("Avant Execution IA")

	local finished = false
	local runSuccess, runErr = true, nil

	-- Thread séparé : une boucle infinie ou un task.wait() dans le code généré
	-- ne bloque plus l'interface du plugin.
	task.spawn(function()
		local ok, err = pcall(func)
		runSuccess, runErr = ok, err
		finished = true
	end)

	local elapsed = 0
	while not finished and elapsed < RUN_TIMEOUT_SECONDS do
		task.wait(POLL_INTERVAL)
		elapsed += POLL_INTERVAL
	end

	-- On arrête le tracking ici : les objets créés après ce point (dans un code
	-- qui tourne toujours en arrière-plan après le timeout) ne seront pas
	-- remontés, pour éviter de laisser le listener connecté indéfiniment.
	trackingConn:Disconnect()

	if finished then
		if runSuccess then
			ChangeHistoryService:SetWaypoint("Apres Execution IA")
			callback(true, nil, newInstances, false)
		else
			callback(false, tostring(runErr), newInstances, false)
		end
	else
		-- Timeout : on considère que le lancement a réussi (le code continue
		-- de tourner tout seul), mais on prévient l'utilisateur.
		ChangeHistoryService:SetWaypoint("Apres Execution IA (arrière-plan)")
		callback(true, "timeout_background", newInstances, true)
	end
end


local function getObjectFromPath(path)
	-- Nettoie le "game." au début si l'IA l'a mis
	local cleanPath = string.gsub(path, "^game%.", "")
	local parts = string.split(cleanPath, ".")
	
	local current = game
	for _, partName in ipairs(parts) do
		-- Cherche l'enfant à chaque étape du chemin
		current = current:FindFirstChild(partName)
		if not current then return nil end
	end
	return current
end

-- Sélectionne dans l'explorateur les instances passées, en filtrant celles
-- qui auraient déjà été détruites entre temps.
local function highlightInstances(instances)
	local valid = {}
	for _, inst in ipairs(instances) do
		if inst and inst.Parent ~= nil then
			table.insert(valid, inst)
		end
	end
	if #valid > 0 then
		Selection:Set(valid)
	end
end

local function writeSource(inst, code)
	local ok = pcall(function()
		ScriptEditorService:UpdateSourceAsync(inst, function() return code end)
	end)
	if not ok then inst.Source = code end
end

-- Détermine où le code va aller
local function resolveTargets()
	local targets = {}
	local selected = Selection:Get()
	if #selected == 0 then
		table.insert(targets, {parent = workspace, name = "OllamaGeneratedScript"})
		return targets
	end
	for _, item in ipairs(selected) do
		if item:IsA("LuaSourceContainer") then
			table.insert(targets, {existing = item})
		else
			local found = {}
			for _, d in ipairs(item:GetDescendants()) do
				if d:IsA("LuaSourceContainer") then table.insert(found, d) end
			end
			if #found == 1 then
				table.insert(targets, {existing = found[1]})   -- le script de l'archer
			else
				table.insert(targets, {parent = item, name = "Ollama_Script"})
			end
		end
	end
	return targets
end

local function describeTargets()
	local t = resolveTargets()[1]
	if t.existing then return "remplacer " .. t.existing.Name end
	return "nouveau script dans " .. t.parent.Name
end

local function injectCode(code)
	local touched = {}
	ChangeHistoryService:SetWaypoint("Avant Injection Code Ollama")

	for _, t in ipairs(resolveTargets()) do
		if t.existing then
			writeSource(t.existing, code)
			table.insert(touched, t.existing)
		else
			local s = Instance.new("Script")
			s.Name = t.name
			s.Source = code
			s.Parent = t.parent
			table.insert(touched, s)
		end
	end

	Selection:Set(touched)
	lastInjected = touched[1]
	ChangeHistoryService:SetWaypoint("Apres Injection Code Ollama")
	return touched
end

-- ======================================================
-- Exécution Simple et Annulation (Modes classiques)
-- ======================================================
--executeButton.MouseButton1Click:Connect(function()
--	if not lastGeneratedCode or lastGeneratedCode == "" then return end
--	
--	local selectedItems = game:GetService("Selection"):Get()
--	local instancesToSelect = {} -- Pour mémoriser les scripts modifiés
--	
--	ChangeHistoryService:SetWaypoint("Avant Injection Code Ollama")
--	
--	if #selectedItems > 0 then
--		for _, item in ipairs(selectedItems) do
--			if item:IsA("LuaSourceContainer") then
--				-- CAS 1 : Tu as sélectionné un script directement
--				item.Source = lastGeneratedCode
--				table.insert(instancesToSelect, item)
--			else
--				-- CAS 2 : Tu as sélectionné le NPC/Modèle
--				-- On cherche s'il y a DÉJÀ des scripts dedans
--				local existingScripts = {}
--				for _, child in ipairs(item:GetChildren()) do
--					if child:IsA("LuaSourceContainer") then
--						table.insert(existingScripts, child)
--					end
--				end
--				
--				if #existingScripts == 1 then
--					-- S'il n'y a qu'un seul script dans le NPC, on écrase celui-là !
--					existingScripts[1].Source = lastGeneratedCode
--					table.insert(instancesToSelect, existingScripts[1])
--				else
--					-- S'il n'y en a pas (ou plusieurs), on en crée un nouveau proprement
--					local newScript = Instance.new("Script")
--					newScript.Name = "Ollama_ArcherAI" -- Un nom plus clair
--					newScript.Source = lastGeneratedCode
--					newScript.Parent = item
--					table.insert(instancesToSelect, newScript)
--				end
--			end
--		end
--		statusLabel.Text = "✅ Code injecté !"
--	else
--		-- CAS 3 : Rien n'est sélectionné
--		local newScript = Instance.new("Script")
--		newScript.Name = "OllamaGeneratedScript"
--		newScript.Source = lastGeneratedCode
--		newScript.Parent = game.Workspace
--		table.insert(instancesToSelect, newScript)
--		statusLabel.Text = "✅ Nouveau script créé dans Workspace !"
--	end
--	
--	-- LA MAGIE : On force l'explorateur à sélectionner et surligner le(s) script(s) modifié(s) !
--	game:GetService("Selection"):Set(instancesToSelect)
--	
--	ChangeHistoryService:SetWaypoint("Apres Injection Code Ollama")
--	executeButton.Visible = false
--end)

executeButton.TextTruncate = Enum.TextTruncate.AtEnd

executeButton.MouseButton1Click:Connect(function()
	if not lastGeneratedCode or lastGeneratedCode == "" then return end
	local touched = injectCode(lastGeneratedCode)
	statusLabel.Text = "✅ Code injecté dans " .. #touched .. " script(s) !"
	executeButton.Visible = false
	undoButton.Visible = true
	copyButton.Text = "📂 Ouvrir le script"
end)

undoButton.MouseButton1Click:Connect(function()
	ChangeHistoryService:Undo()
	statusLabel.Text = "↩️ Changements annulés."
	undoButton.Visible = false
end)

stopButton.MouseButton1Click:Connect(function()
	isCancelled = true
	if currentTaskId then
		pcall(function()
			HttpService:RequestAsync({Url = string.gsub(AGENT_URL, "/agent", "/cancel/") .. currentTaskId, Method = "POST"})
		end)
	end
	statusLabel.Text = "🛑 Demande arrêtée."
	stopButton.Visible = false
	sendButton.Visible = true
end)

provideContextButton.MouseButton1Click:Connect(function()
	provideContextButton.Visible = false
	statusLabel.Text = "Recherche du fichier..."
	
	local targetScript = getObjectFromPath(fileToFetch)
	
	if targetScript and targetScript:IsA("LuaSourceContainer") then
		
		if targetScript:IsA("BaseScript") and not targetScript.Enabled then
			statusLabel.Text = "❌ Ce script est désactivé (ignoré)."
			return
		end

		local ok, source = pcall(function() return targetScript.Source end)
		if ok then
			local newContext = "\n\n--- CONTENU DE " .. fileToFetch .. " ---\n```lua\n" .. source .. "\n```\n"
			
			inputBox.Text = inputBox.Text .. newContext
			statusLabel.Text = "✅ Fichier ajouté ! Tu peux renvoyer."
		else
			statusLabel.Text = "❌ Impossible de lire la source."
		end
	else
		statusLabel.Text = "❌ Fichier introuvable."
	end
end)

-- ======================================================
-- Fonctions Utilitaires Agent
-- ======================================================
local function extractCode(text)
	local best, bestTruncated
	for _, seg in ipairs(splitSegments(text)) do
		if seg.kind == "code" and (not best or #seg.body > #best) then
			best, bestTruncated = seg.body, seg.truncated
		end
	end
	-- Pas de balises du tout mais ça ressemble à du Luau : on prend tout
	if not best and (string.find(text, "game:GetService") or string.find(text, "local %w+ =")) then
		best = text
	end
	return best, bestTruncated
end

local function getSelectedScriptSource()
	local ok, doc = pcall(function() return ScriptEditorService:GetScriptDocuments()[1] end)
	if ok and doc then
		local okText, text = pcall(function() return doc:GetText() end)
		if okText then return text end
	end
	return nil
end

local function getSelectionContext()
	local selectedItems = Selection:Get()
	if #selectedItems == 0 then return "" end

	local contextString = "Éléments actuellement sélectionnés :\n"
	for _, item in ipairs(selectedItems) do
		contextString = contextString .. "👉 Chemin exact : 'game." .. item:GetFullName() .. "' (Type: " .. item.ClassName .. ")\n"

		if item:IsA("LuaSourceContainer") then
			local ok, source = pcall(function() return item.Source end)
			if ok and source ~= "" then
				contextString = contextString .. "   Code actuel de ce script :\n```lua\n" .. source .. "\n```\n"
			end
		else
			local children = item:GetChildren()
			if #children > 0 then
				contextString = contextString .. "   Enfants directs :\n"
				for _, child in ipairs(children) do
					contextString = contextString .. "   - game." .. child:GetFullName() .. " (" .. child.ClassName .. ")\n"

					if child:IsA("LuaSourceContainer") then
						local ok, source = pcall(function() return child.Source end)
						if ok and source ~= "" then
							contextString = contextString .. "     Code inclus :\n```lua\n" .. source .. "\n```\n"
						end
					end
				end
			end
		end
	end
	return contextString
end

local function getProjectMap()
	-- On cible uniquement les endroits où l'on range du code normalement
	local servicesToScan = {
		game:GetService("ServerScriptService"),
		game:GetService("ReplicatedStorage"),
		game:GetService("StarterPlayerScripts"),
		game:GetService("StarterCharacterScripts")
	}
	
	local mapString = "--- ARCHITECTURE GLOBALE DU JEU ---\n(Voici la liste des scripts existants dans le jeu. Tu peux demander à l'utilisateur de sélectionner l'un d'eux si tu as besoin de voir ou modifier son code précis.)\n"
	local scriptCount = 0

	for _, service in ipairs(servicesToScan) do
		local ok, descendants = pcall(function() return service:GetDescendants() end)
		if ok then
			for _, obj in ipairs(descendants) do
				-- Si c'est un script, un LocalScript ou un ModuleScript
				if obj:IsA("LuaSourceContainer") then
					-- Si c'est un script classique, on vérifie qu'il est bien activé
					local isActive = true
					if obj:IsA("BaseScript") then
						isActive = obj.Enabled
					end
					
					if isActive then
						mapString = mapString .. "📄 game." .. obj:GetFullName() .. "\n"
						scriptCount = scriptCount + 1
					end
				end
			end
		end
	end

	if scriptCount == 0 then return "" end
	return mapString .. "-----------------------------------\n\n"
end

-- ======================================================
-- Fonction askAgent (Anti-Cache et Sécurisée)
-- ======================================================
local function askAgent(userPrompt, modelName, modeName)
	local contextScript = getSelectedScriptSource()
	local selectionContext = getSelectionContext()
	
	local hasScriptInContext = (contextScript and #contextScript > 0) or (selectionContext ~= "" and string.find(selectionContext, "```lua"))
	
	local projectMap = ""
	
	-- NOUVEAU : On ne charge la carte QUE si on n'a pas de script ET qu'on n'est PAS en mode "Constructeur" (Étape de code)
	if not hasScriptInContext and modeName ~= "Constructeur" then
		projectMap = getProjectMap()
	end
	
	local fullPrompt = userPrompt
	if selectionContext ~= "" then
		fullPrompt = selectionContext .. "\nDemande : " .. fullPrompt
	end
	if contextScript and #contextScript > 0 then
		fullPrompt = "Voici le script ouvert :\n```lua\n" .. contextScript .. "\n```\n\nDemande : " .. userPrompt
	end
	if projectMap ~= "" then
		local instructionFichier = "\n\nREGLE ABSOLUE : Si tu as besoin de lire le code d'un des scripts listés ci-dessus pour comprendre ou répondre, TU NE DOIS PAS FAIRE DE PHRASE. Réponds UNIQUEMENT avec ce format exact et rien d'autre : [LIRE_FICHIER: game.Chemin.Exact.Du.Script]\n\n"
		fullPrompt = projectMap .. instructionFichier .. fullPrompt
	end

	local body = HttpService:JSONEncode({ prompt = fullPrompt, model = modelName, mode = modeName })
	local success, response = pcall(function()
		return HttpService:RequestAsync({
			Url = AGENT_URL, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = body,
		})
	end)

	if not success or not response.Success then return false, "Impossible de joindre Python." end

	local okDecode, startData = pcall(function() return HttpService:JSONDecode(response.Body) end)
	if not okDecode or not startData.task_id then return false, "Erreur de lecture du ticket." end

	currentTaskId = startData.task_id
	isCancelled = false

	local STATUS_URL = string.gsub(AGENT_URL, "/agent", "/status/") .. currentTaskId
	local secondesEcoulees = 0

	while true do
		if isCancelled then return false, "Annulé." end
		task.wait(2)
		if isCancelled then return false, "Annulé." end

		secondesEcoulees = secondesEcoulees + 2
		statusLabel.Text = "Agent réfléchit... (" .. secondesEcoulees .. "s)"

		local noCacheUrl = STATUS_URL .. "?nocache=" .. tostring(os.clock())

		local chkSuccess, chkResponse = pcall(function()
			return HttpService:RequestAsync({Url = noCacheUrl, Method = "GET"})
		end)

		if chkSuccess and chkResponse.Success then
			local okJson, chkData = pcall(function() return HttpService:JSONDecode(chkResponse.Body) end)
			if okJson then
				if chkData.statut == "termine" then return true, chkData.reponse
				elseif chkData.statut == "erreur" then return false, "Erreur IA : " .. tostring(chkData.reponse)
				elseif chkData.statut == "annule" then return false, "Annulé serveur." end
			end
		elseif chkSuccess and not chkResponse.Success then
			return false, "Erreur HTTP Serveur : " .. tostring(chkResponse.StatusCode)
		end

		if secondesEcoulees >= 300 then return false, "Timeout (5 min)." end
	end
end

-- ======================================================
-- Phase 2 : Exécution d'une sous-étape (utilise maintenant executeGeneratedCode)
-- ======================================================
local function runStep(stepIndex)
	local stepDescription = planSteps[stepIndex]
	if not stepDescription then return end

	btnNextStep.Visible = false
	btnRetryStep.Visible = false
	undoButton.Visible = false
	stopButton.Visible = true

	afficherReponse("Préparation de l'Étape " .. stepIndex .. "...")

	task.spawn(function()
		local maxEssais = 3
		local actionReussie = false
		local model = modelInput.Text

		local basePrompt = "Objectif final du jeu : " .. originalGlobalPrompt .. "\n\nTA TÂCHE ACTUELLE (Étape " .. stepIndex .. "/" .. #planSteps .. ") : " .. stepDescription .. "\n\nÉcris UNIQUEMENT le script Luau exécutable pour réaliser cette tâche. RÈGLES ABSOLUES :\n1. Pour MODIFIER un script existant (présent dans le contexte), NE crée PAS de nouvel objet. Remplace son code en utilisant son chemin exact et les crochets, par exemple : `game.Workspace.MonObjet.MonScript.Source = [[nouveau code]]`.\n2. Pour CRÉER un tout nouveau comportement, utilise `Instance.new('Script')`, mets le code dans sa propriété `.Source` et parente-le.\nNe donne AUCUNE explication."
		if lastGeneratedCode then
			basePrompt = basePrompt .. "\n\n(Contexte : voici le code généré à l'étape précédente auquel tu peux te lier si besoin) :\n```lua\n" .. lastGeneratedCode .. "\n```"
		end

		local currentPrompt = basePrompt

		for essai = 1, maxEssais do
			if isCancelled then break end
			statusLabel.Text = "Code Étape " .. stepIndex .. " (Essai " .. essai .. "/" .. maxEssais .. ")..."

			local ok, textRes = askAgent(currentPrompt, model, "Constructeur")
			if isCancelled then break end
			
			local demandedFile = string.match(textRes, "%[LIRE_FICHIER:%s*(.-)%]")

			if demandedFile then
				-- CAS 1 : L'IA veut lire un script
				afficherReponse("L'IA a besoin de lire :\n" .. demandedFile)
				statusLabel.Text = "Action requise."
				fileToFetch = demandedFile
				provideContextButton.Text = "Fournir " .. demandedFile:match("([^%.]+)$") .. " et relancer"
				provideContextButton.Visible = true
				executeButton.Visible = false

				-- On sort de la boucle d'essais pour te laisser le temps de cliquer sur le bouton
				break 

			elseif ok then
				lastFullResponse = textRes
				local code = extractCode(textRes)
				if code then
					afficherReponse("Code de l'Étape " .. stepIndex .. " (Essai " .. essai .. "):\n```lua\n" .. code .. "\n```")

					local execSuccess, execErr, execInstances, execTimedOut
					if string.find(code, "%.Source%s*=") then
						executeGeneratedCode(code, function(success, errMsg, newInstances, timedOut)
							execSuccess, execErr, execInstances, execTimedOut = success, errMsg, newInstances, timedOut
						end)
					else
						execInstances = injectCode(code)
						execSuccess, execErr, execTimedOut = true, nil, false
					end
					if execSuccess then
						statusLabel.Text = execTimedOut
							and ("⏱️ Étape " .. stepIndex .. " lancée (continue en arrière-plan).")
							or ("✅ Étape " .. stepIndex .. " réussie !")
						lastGeneratedCode = code
						actionReussie = true
						highlightInstances(execInstances)
						break
					else
						warn("Erreur exécution Agent :", execErr)
						currentPrompt = basePrompt .. "\n\n⚠️ Ton code précédent a échoué avec l'erreur : " .. tostring(execErr) .. "\nCorrige-le."
					end
				else
					currentPrompt = basePrompt .. "\n\n⚠️ Tu as oublié les balises ```lua. Renvoie UNIQUEMENT le code."
				end
			else
				statusLabel.Text = "Échec connexion."
				break
			end
			if essai < maxEssais then task.wait(1) end
		end

		if not actionReussie and not isCancelled then
			statusLabel.Text = "❌ Étape " .. stepIndex .. " échouée."
		end

		stopButton.Visible = false
		btnRetryStep.Visible = true
		undoButton.Visible = true

		if actionReussie and stepIndex < #planSteps then
			activeStepIndex = stepIndex + 1
			btnNextStep.Text = "▶️ Lancer Étape " .. activeStepIndex
			btnNextStep.Visible = true
		elseif actionReussie then
			statusLabel.Text = "🎉 Plan complet terminé !"
		end
	end)
end

-- ======================================================
-- Phase 1 : Bouton Principal (Planification ou Code Simple)
-- ======================================================
sendButton.MouseButton1Click:Connect(function()
	local prompt, model, mode = inputBox.Text, modelInput.Text, modes[currentModeIndex]
	if prompt == "" then return end

	sendButton.Visible = false
	stopButton.Visible = true
	executeButton.Visible = false
	undoButton.Visible = false
	btnNextStep.Visible = false
	btnRetryStep.Visible = false
	afficherReponse("")

	task.spawn(function()
		if mode == "Agent Autonome" then
			originalGlobalPrompt = prompt
			statusLabel.Text = "L'Agent génère un plan..."

			local planPrompt = "Tu es un architecte Roblox. L'utilisateur veut ceci : '" .. prompt .. "'. Divise cet objectif en 2 à 4 étapes simples et chronologiques. Chaque étape doit pouvoir être codée par un seul script Luau. NE DONNE PAS DE CODE. Fais uniquement une liste numérotée stricte (1. ... 2. ...)."

			local ok, textRes = askAgent(planPrompt, model, "Assistant")

			if ok and not isCancelled then
				
				afficherReponse("📋 PLAN D'ACTION :\n\n" .. textRes)
				statusLabel.Text = "Plan prêt ! Validez pour commencer."

				planSteps = {}
				for stepText in string.gmatch(textRes, "%d+%.%s*([^\n]+)") do
					table.insert(planSteps, stepText)
				end
				if #planSteps == 0 then
					for line in string.gmatch(textRes, "[^\r\n]+") do
						if #line > 10 then table.insert(planSteps, line) end
					end
				end

				if #planSteps > 0 then
					activeStepIndex = 1
					btnNextStep.Text = "▶️ Démarrer Étape 1"
					btnNextStep.Visible = true
				else
					statusLabel.Text = "Erreur : Plan illisible."
				end
			end
		else
            -- MODE CLASSIQUE (Assistant, Débogueur, Codeur)
            local ok, textRes = askAgent(prompt, model, mode)
            
            if ok and not isCancelled then
                -- On cherche la balise spéciale
                local demandedFile = string.match(textRes, "%[LIRE_FICHIER:%s*(.-)%]")
                
                if demandedFile then
                    -- L'IA demande un fichier
                    afficherReponse("L'IA a besoin de lire :\n" .. demandedFile)
                    statusLabel.Text = "Action requise."
                    fileToFetch = demandedFile
                    provideContextButton.Text = "Fournir " .. demandedFile:match("([^%.]+)$") .. " et relancer"
                    provideContextButton.Visible = true
                    executeButton.Visible = false
                else
					-- Réponse classique (Ni erreur, ni demande de fichier)
					lastFullResponse = textRes
					afficherReponse(textRes)
					statusLabel.Text = "Réponse reçue."
					local code, truncated = extractCode(textRes)
					if code then
						lastGeneratedCode = code
						executeButton.Text = "⬇️ Injecter : " .. describeTargets()
						executeButton.Visible = true
						if truncated then
							statusLabel.Text = "⚠️ Réponse coupée : le code est peut-être incomplet."
						end
					end
				end
            elseif not ok and not isCancelled then
                -- Affichage des erreurs réseau/Python
                afficherReponse("Erreur :\n" .. tostring(textRes))
                statusLabel.Text = "Échec."
            end
        end

        sendButton.Visible = true
        stopButton.Visible = false
        currentTaskId = nil
    end)
end)

btnNextStep.MouseButton1Click:Connect(function() runStep(activeStepIndex) end)
btnRetryStep.MouseButton1Click:Connect(function()
	local stepToRetry = activeStepIndex
	if activeStepIndex > 1 and not btnNextStep.Visible then stepToRetry = activeStepIndex - 1 end
	runStep(stepToRetry)
end)

button.Click:Connect(function() widget.Enabled = not widget.Enabled end)