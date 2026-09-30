import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.babastardust.wow-addons"
  ipcTarget: "io.github.babastardust.wow-addons"
  manageIpc: false

  readonly property string helper: String(Qt.resolvedUrl("bin/wowaddons")).replace(/^file:\/\//, "")
  readonly property int updateCheckHours: Number(setting("updateCheckHours", 6))

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property string tab: "search"
  property var searchResult: ({ results: [], total: 0, mode: "", searchBlocked: false })
  property var installed: ({ addonsDir: "", installed: [], unmanaged: [] })
  property var updates: []
  readonly property var updateMap: Model.updateMap(updates)
  property var config: ({ config: {}, resolved: { addonsDir: "", source: "none" }, detectedRoots: [], flavors: [] })
  property string message: ""
  property bool messageIsError: false
  // Set when an install needs a manual download: { modId, fileId, url, fileName }.
  property var pendingImport: null
  // API key setup: the guide is open by default until a key exists.
  property bool keyHelpOpen: !hasKey
  property string keyMessage: ""
  property bool keyMessageIsError: false
  readonly property bool hasKey: config.hasKey !== false
  readonly property bool keyBusy: keyProc.running
  readonly property string consoleUrl: "https://console.curseforge.com/"

  readonly property bool busy: actionProc.running
  readonly property bool searching: searchProc.running
  readonly property bool hasAddonsDir: config.resolved.addonsDir !== ""
  readonly property int updateCount: updates.length

  readonly property var versionTypes: [
    { value: "88568", label: "Forever" },
    { value: "67408", label: "Classic" },
    { value: "517", label: "Retail" }
  ]
  readonly property var releaseTypes: [
    { value: "1", label: "Release" },
    { value: "2", label: "+ Beta" },
    { value: "3", label: "+ Alpha" }
  ]

  readonly property real resultRowHeight: bodyMetrics.height + captionMetrics.height + Style.space(1) + Style.spacing.rowPaddingX

  FontMetrics { id: bodyMetrics; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
  FontMetrics { id: captionMetrics; font.family: root.fontFamily; font.pixelSize: Style.font.caption }

  function setMessage(text, isError) {
    message = text
    messageIsError = isError === true
    messageTimer.restart()
  }

  function refresh() {
    start(listProc, ["list"])
    start(configProc, ["config"])
  }

  function checkUpdates() {
    start(updatesProc, ["updates"])
  }

  function start(proc, args) {
    if (proc.running) return
    proc.command = [helper].concat(args)
    proc.running = true
  }

  function search(query) {
    if (searchProc.running) searchProc.running = false
    searchProc.command = [helper, "search", String(query || "").trim()]
    searchProc.running = true
  }

  function run(args, label) {
    if (actionProc.running) return
    actionProc.label = label
    actionProc.command = [helper].concat(args)
    actionProc.running = true
    setMessage(label + "…", false)
  }

  function install(mod) {
    pendingImport = null
    run(["install", String(mod.id)], "Installing " + mod.name)
  }

  function update(modId, name) {
    pendingImport = null
    run(["update", String(modId)], "Updating " + name)
  }

  function openUrl(url) {
    if (url) Quickshell.execDetached(["xdg-open", url])
  }

  function saveKey(text) {
    var key = String(text || "").trim()
    if (key === "" || keyProc.running) return
    keyProc.secret = key
    keyProc.command = [helper, "key", "set"]
    keyMessage = "Checking key…"
    keyMessageIsError = false
    keyProc.running = true
  }

  function clearKey() {
    if (keyProc.running) return
    keyProc.secret = ""
    keyProc.command = [helper, "key", "clear"]
    keyProc.running = true
  }

  function setConfig(key, value, label) {
    run(["config", "set", key, String(value)], label)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    refresh()
    checkUpdates()
    if (searchResult.mode === "") search(searchField.text)
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Component.onCompleted: {
    start(configProc, ["config"])
    checkUpdates()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); root.checkUpdates(); return "ok" }
    function search(query: string): string { root.tab = "search"; searchField.text = query; root.search(query); return "ok" }
    function status(): string { return root.updateCount + " updates · " + root.installed.installed.length + " installed" }
  }

  Timer {
    id: updateTimer
    interval: Math.max(1, root.updateCheckHours) * 3600 * 1000
    running: root.updateCheckHours > 0
    repeat: true
    onTriggered: root.checkUpdates()
  }

  Timer {
    id: messageTimer
    interval: 8000
    onTriggered: root.message = ""
  }

  Process {
    id: searchProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var data = Model.parse(text, null)
        if (!data) return
        if (data.ok) root.searchResult = data
        // The setup card already explains a missing key.
        else if (data.code !== "no_key") root.setMessage(data.error, true)
      }
    }
  }

  Process {
    id: listProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var data = Model.parse(text, null)
        if (data && data.ok) root.installed = data
      }
    }
  }

  Process {
    id: updatesProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var data = Model.parse(text, null)
        // Without an AddOns folder there is nothing to check; stay quiet.
        root.updates = data && data.ok ? data.updates : []
      }
    }
  }

  Process {
    id: configProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var data = Model.parse(text, null)
        if (data && data.ok) root.config = data
      }
    }
  }

  // Saves the key via stdin so it never appears in the process list.
  Process {
    id: keyProc
    property string secret: ""
    stdinEnabled: secret !== ""
    stdout: StdioCollector { id: keyOut; waitForEnd: true }
    onStarted: if (secret !== "") {
      write(secret + "\n")
      secret = ""
    }
    onExited: {
      var data = Model.parse(keyOut.text, { ok: false, error: "no response" })
      if (data.ok) {
        keyMessage = data.saved ? "Key saved and accepted ✓" : (data.hasKey ? "" : "Key removed")
        keyMessageIsError = false
        keySetup.field.text = ""
        keyFieldSettings.text = ""
        root.keyHelpOpen = false
        root.checkUpdates()
        if (root.searchResult.mode === "" || data.saved) root.search(searchField.text)
      } else {
        keyMessage = data.error || "Could not save the key"
        keyMessageIsError = true
      }
      root.refresh()
    }
  }

  Process {
    id: actionProc
    property string label: ""
    stdout: StdioCollector { id: actionOut; waitForEnd: true }
    onExited: function(exitCode) {
      var data = Model.parse(actionOut.text, { ok: false, error: "no response" })
      if (data.ok) {
        var detail = data.version ? ": " + data.version : ""
        if (data.updated) detail = ": " + data.updated.length + " updated" + (data.skipped.length ? ", " + data.skipped.length + " manual only" : "")
        root.setMessage(label + detail + " ✓", false)
        if (data.fileId && root.pendingImport && root.pendingImport.fileId === data.fileId) root.pendingImport = null
      } else {
        if (data.code === "distribution_disabled") root.pendingImport = { modId: Number(command[2]), fileId: Number(String(data.url).split("/").pop()), url: data.url, fileName: data.fileName }
        root.setMessage(data.error || (label + " failed"), true)
      }
      root.refresh()
      root.checkUpdates()
      if (root.searchResult.mode !== "") root.search(searchField.text)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰊴"
    active: root.updateCount > 0
    activeColor: Color.accent
    tooltipText: "WoW Addons"
      + (root.updateCount > 0 ? "\n" + root.updateCount + (root.updateCount === 1 ? " update available" : " updates available") : "")
      + (root.config.hasKey === false ? "\nCurseForge API key missing – click to set up" : "")
      + (root.hasAddonsDir ? "" : "\nWoW folder not set up yet")
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.checkUpdates()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: searchField.activeFocus || keySetup.field.activeFocus || keyFieldSettings.activeFocus || rootField.fieldFocused || flavorField.fieldFocused || dirField.fieldFocused
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "/" || t === "s" || t === "S") { root.tab = "search"; searchField.forceActiveFocus() }
        else if (t === "i" || t === "I") root.tab = "installed"
        else if (t === "e" || t === "E") root.tab = "settings"
        else if (t === "r" || t === "R") { root.refresh(); root.checkUpdates() }
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            width: parent.width
            implicitHeight: Math.max(hero.implicitHeight, heroActions.implicitHeight)

            PanelHero {
              id: hero
              anchors.left: parent.left
              anchors.right: heroActions.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              title: "WoW Addons"
              meta: root.installed.installed.length + " installed"
                + (root.updateCount > 0 ? " · " + root.updateCount + " Updates" : "")
              detail: root.hasAddonsDir ? Model.shortPath(root.config.resolved.addonsDir) : "WoW folder missing → Settings"
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconComponent: Component {
                Text {
                  textFormat: Text.PlainText
                  text: "󰊴"
                  color: root.updateCount > 0 ? Color.accent : hero.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display * 1.6
                }
              }
            }

            Row {
              id: heroActions
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(4)

              PanelActionButton {
                iconText: "󰑐"
                tooltipText: "Reload and check for updates (r)"
                foreground: root.foreground
                fontFamily: root.fontFamily
                enabled: !root.busy
                onClicked: { root.refresh(); root.checkUpdates() }
              }
              PanelActionButton {
                iconText: "󰚰"
                tooltipText: "Install all updates"
                foreground: root.foreground
                fontFamily: root.fontFamily
                enabled: !root.busy && root.updateCount > 0
                opacity: enabled ? 1.0 : 0.4
                onClicked: root.run(["update-all"], "Updating all addons")
              }
              PanelActionButton {
                iconText: "󰉋"
                tooltipText: "Open AddOns folder"
                foreground: root.foreground
                fontFamily: root.fontFamily
                enabled: root.hasAddonsDir
                opacity: enabled ? 1.0 : 0.4
                onClicked: root.openUrl(root.config.resolved.addonsDir)
              }
            }
          }

          // ── API key setup (first run) ──────────────────────────────
          KeySetup {
            id: keySetup
            visible: !root.hasKey
            width: parent.width
          }

          ButtonGroup {
            visible: root.hasKey || root.tab === "settings"
            width: parent.width
            options: [
              { value: "search", label: "Search", icon: "󰍉" },
              { value: "installed", label: "Installed" + (root.updateCount > 0 ? " (" + root.updateCount + ")" : ""), icon: "󰏗" },
              { value: "settings", label: "Settings", icon: "󰒓" }
            ]
            value: root.tab
            foreground: root.foreground
            accent: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            focusable: false
            onChanged: function(v) { root.tab = v }
          }

          Text {
            textFormat: Text.PlainText
            visible: root.message !== ""
            width: parent.width
            text: root.message
            color: root.messageIsError ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          // Author opted out of third-party downloads: browser + import.
          RowLayout {
            visible: root.pendingImport !== null
            width: parent.width
            spacing: Style.space(6)
            Text {
              Layout.fillWidth: true
              textFormat: Text.PlainText
              text: root.pendingImport ? "1. Download  2. Import " + root.pendingImport.fileName + " from ~/Downloads" : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
            PanelActionButton {
              iconText: "󰖟"
              tooltipText: "Open file on CurseForge"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.openUrl(root.pendingImport.url)
            }
            PanelActionButton {
              iconText: "󰋺"
              tooltipText: "Import from ~/Downloads"
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: !root.busy
              onClicked: root.run(["import", String(root.pendingImport.modId), String(root.pendingImport.fileId)], "Import")
            }
            PanelActionButton {
              iconText: "󰅖"
              tooltipText: "Dismiss"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.pendingImport = null
            }
          }

          // ── Suchen ─────────────────────────────────────────────────
          Column {
            visible: root.tab === "search" && root.hasKey
            width: parent.width
            spacing: Style.space(6)

            TextField {
              id: searchField
              width: parent.width
              placeholderText: "Search addons or project ID · Enter"
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              foreground: root.foreground
              accent: root.foreground
              horizontalPadding: Style.spacing.controlGap
              verticalPadding: Style.spacing.controlPaddingY
              // Enter only: CurseForge throttles search hard, live search would burn it.
              onAccepted: root.search(text)
              Keys.onEscapePressed: keyCatcher.forceActiveFocus()
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              color: root.searchResult.searchBlocked ? root.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              text: {
                if (root.searching) return "Searching…"
                var r = root.searchResult
                if (r.mode === "") return ""
                if (r.searchBlocked) return "CurseForge is throttling search right now (HTTP 403) – press Enter again in a minute. Meanwhile: matching popular/new "
                  + root.versionLabel() + " addons. Project IDs always work."
                if (r.mode === "id") return r.total ? "Project " + r.query : "No addon with this ID for " + root.versionLabel()
                if (r.mode === "featured") return "Popular and recently updated · " + root.versionLabel()
                return Model.compactCount(r.total) + " results for “" + r.query + "”"
              }
            }

            ScrollList {
              visibleRows: 6
              rowHeight: root.resultRowHeight
              model: root.searchResult.results || []
              delegate: ResultRow {}
            }
          }

          // ── Installiert ────────────────────────────────────────────
          Column {
            visible: root.tab === "installed" && root.hasKey
            width: parent.width
            spacing: Style.space(6)

            Text {
              visible: root.installed.installed.length === 0
              width: parent.width
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              text: root.hasAddonsDir ? "Nothing installed through this plugin yet." : "Set the WoW folder under Settings first."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            ScrollList {
              visibleRows: 7
              rowHeight: root.resultRowHeight
              model: root.installed.installed || []
              delegate: InstalledRow {}
            }

            Text {
              visible: root.installed.unmanaged.length > 0
              width: parent.width
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              text: root.installed.unmanaged.length + " other folders not managed by this plugin: " + root.installed.unmanaged.join(", ")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              maximumLineCount: 3
              elide: Text.ElideRight
            }
          }

          // ── Einstellungen ──────────────────────────────────────────
          Column {
            visible: root.tab === "settings"
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader { text: "CURSEFORGE API KEY"; foreground: root.foreground; fontFamily: root.fontFamily }
            RowLayout {
              width: parent.width
              spacing: Style.space(6)
              TextField {
                id: keyFieldSettings
                Layout.fillWidth: true
                password: true
                placeholderText: root.hasKey ? "Key saved – paste a new one to replace it" : "Paste your API key · Enter"
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                foreground: root.foreground
                accent: root.foreground
                horizontalPadding: Style.spacing.controlGap
                verticalPadding: Style.spacing.controlPaddingY
                enabled: !root.keyBusy
                onAccepted: root.saveKey(text)
                Keys.onEscapePressed: keyCatcher.forceActiveFocus()
              }
              PanelActionButton {
                iconText: "󰄬"
                tooltipText: "Save and verify key"
                foreground: root.foreground
                fontFamily: root.fontFamily
                enabled: !root.keyBusy && keyFieldSettings.text.trim() !== ""
                opacity: enabled ? 1.0 : 0.4
                onClicked: root.saveKey(keyFieldSettings.text)
              }
              PanelActionButton {
                iconText: "󰋗"
                tooltipText: "How do I get a key?"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.keyHelpOpen = !root.keyHelpOpen
              }
              PanelActionButton {
                visible: root.hasKey
                iconText: "󰆴"
                tooltipText: "Remove saved key"
                foreground: root.foreground
                hoverColor: root.urgent
                fontFamily: root.fontFamily
                enabled: !root.keyBusy
                onClicked: root.clearKey()
              }
            }
            Text {
              visible: root.keyMessage !== ""
              width: parent.width
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              text: root.keyMessage
              color: root.keyMessageIsError ? root.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            KeyGuide {
              visible: root.keyHelpOpen && root.hasKey
              width: parent.width
            }

            PanelSectionHeader { text: "GAME VERSION"; foreground: root.foreground; fontFamily: root.fontFamily }
            ButtonGroup {
              width: parent.width
              options: root.versionTypes
              value: String(root.config.config.gameVersionTypeId || "")
              foreground: root.foreground
              accent: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              focusable: false
              enabled: !root.busy
              onChanged: function(v) { root.setConfig("gameVersionTypeId", v, "Game version: " + root.versionLabel(v)) }
            }
            ButtonGroup {
              width: parent.width
              options: root.releaseTypes
              value: String(root.config.config.releaseType || "")
              foreground: root.foreground
              accent: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              focusable: false
              enabled: !root.busy
              onChanged: function(v) { root.setConfig("releaseType", v, "Release channel") }
            }

            PanelSectionHeader { text: "WOW INSTALLATION"; foreground: root.foreground; fontFamily: root.fontFamily }
            SettingField {
              id: rootField
              label: "WoW folder"
              placeholder: root.config.detectedRoots.length ? root.config.detectedRoots[0] : "…/drive_c/Program Files (x86)/World of Warcraft"
              configKey: "wowRoot"
            }
            SettingField {
              id: flavorField
              label: "Flavor"
              placeholder: root.config.flavors.length ? root.config.flavors.join(", ") : "e.g. _classic_beta_"
              configKey: "flavor"
            }
            SettingField {
              id: dirField
              label: "AddOns folder"
              placeholder: "optional, overrides folder + flavor"
              configKey: "addonsDir"
            }
            Text {
              width: parent.width
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              color: root.hasAddonsDir ? root.dim : root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              text: {
                var r = root.config.resolved
                if (r.addonsDir) return "Target (" + ({ env: "environment", config: "manual", detected: "detected" }[r.source] || r.source) + "): " + r.addonsDir
                if (r.source === "no-flavor") return "WoW found, but no Forever flavor folder. Enter the flavor (found: " + (root.config.flavors.join(", ") || "none") + ")."
                return "No WoW installation found. Enter the WoW folder (Enter saves)."
              }
            }
            RowLayout {
              width: parent.width
              spacing: Style.space(6)
              Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: "Reset all settings to defaults (Forever)"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
              PanelActionButton {
                iconText: "󰦛"
                tooltipText: "Reset to defaults"
                foreground: root.foreground
                fontFamily: root.fontFamily
                enabled: !root.busy
                opacity: enabled ? 1.0 : 0.4
                onClicked: root.run(["config", "reset"], "Settings reset")
              }
            }
          }
        }
      }
    }
  }

  function versionLabel(value) {
    var v = String(value === undefined ? root.config.config.gameVersionTypeId : value)
    for (var i = 0; i < versionTypes.length; i++) if (versionTypes[i].value === v) return versionTypes[i].label
    return "Typ " + v
  }

  // Numbered how-to-get-a-key steps, shared by the setup card and Settings.
  component KeyGuide: Column {
    spacing: Style.space(4)
    Repeater {
      model: [
        "1. Open the CurseForge developer console (button below) and sign in – a free CurseForge account is enough.",
        "2. In the left menu choose “API keys” and create or view your key. Answer any short questions about how you will use it: personal use.",
        "3. Copy the whole key. It is a long text that starts with $2a$10$.",
        "4. Paste it here and press Enter. The plugin checks it right away and stores it privately on this computer (file mode 600)."
      ]
      Text {
        required property string modelData
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: modelData
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
    RowLayout {
      width: parent.width
      spacing: Style.space(6)
      Text {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: "The key is only used to talk to CurseForge. It is never shown again or sent anywhere else."
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
      PanelActionButton {
        iconText: "󰖟"
        tooltipText: "Open console.curseforge.com"
        foreground: Color.accent
        fontFamily: root.fontFamily
        onClicked: root.openUrl(root.consoleUrl)
      }
    }
  }

  // First-run card: shown instead of the tabs until a key is saved.
  component KeySetup: Column {
    property alias field: keyFieldSetup
    spacing: Style.space(6)

    PanelSectionHeader { text: "CONNECT TO CURSEFORGE"; foreground: root.foreground; fontFamily: root.fontFamily }
    Text {
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: "To search and install addons you need a free CurseForge API key."
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    RowLayout {
      width: parent.width
      spacing: Style.space(6)
      TextField {
        id: keyFieldSetup
        Layout.fillWidth: true
        password: true
        placeholderText: "Paste your API key · Enter"
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        foreground: root.foreground
        accent: root.foreground
        horizontalPadding: Style.spacing.controlGap
        verticalPadding: Style.spacing.controlPaddingY
        enabled: !root.keyBusy
        onAccepted: root.saveKey(text)
        Keys.onEscapePressed: keyCatcher.forceActiveFocus()
      }
      PanelActionButton {
        iconText: "󰄬"
        tooltipText: "Save and verify key"
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: !root.keyBusy && keyFieldSetup.text.trim() !== ""
        opacity: enabled ? 1.0 : 0.4
        onClicked: root.saveKey(keyFieldSetup.text)
      }
      PanelActionButton {
        iconText: "󰋗"
        tooltipText: "How do I get a key?"
        foreground: root.keyHelpOpen ? Color.accent : root.foreground
        fontFamily: root.fontFamily
        onClicked: root.keyHelpOpen = !root.keyHelpOpen
      }
    }
    Text {
      visible: root.keyMessage !== ""
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: root.keyMessage
      color: root.keyMessageIsError ? root.urgent : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
    KeyGuide {
      visible: root.keyHelpOpen
      width: parent.width
    }
    Text {
      visible: !root.keyHelpOpen
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: "No key yet? Click the ? button for a short guide."
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  component ScrollList: ListView {
    id: scrollList
    property int visibleRows: 2
    property real rowHeight: 0
    readonly property bool scrollable: count > visibleRows
    readonly property real rowWidth: width - (scrollable ? Style.space(12) : 0)

    width: parent.width
    height: Math.min(count, visibleRows) * (rowHeight + spacing) - (count > 0 ? spacing : 0)
    visible: count > 0
    spacing: Style.space(4)
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: scrollable
    ScrollBar.vertical: ScrollBar { policy: scrollList.scrollable ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff }
  }

  // Label + field; Enter stores the value, an empty field resets it.
  component SettingField: RowLayout {
    id: settingField
    property string label: ""
    property string placeholder: ""
    property string configKey: ""
    readonly property alias fieldFocused: field.activeFocus
    width: parent.width
    spacing: Style.space(6)
    Text {
      Layout.preferredWidth: Style.space(90)
      textFormat: Text.PlainText
      text: settingField.label
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
    TextField {
      id: field
      Layout.fillWidth: true
      text: String(root.config.config[settingField.configKey] || "")
      placeholderText: settingField.placeholder
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      foreground: root.foreground
      accent: root.foreground
      horizontalPadding: Style.spacing.controlGap
      verticalPadding: Style.spacing.controlPaddingY
      enabled: !root.busy
      onAccepted: root.setConfig(settingField.configKey, text.trim(), settingField.label + " saved")
      Keys.onEscapePressed: keyCatcher.forceActiveFocus()
    }
  }

  component ResultRow: CursorSurface {
    id: resultRow
    required property var modelData
    readonly property var upd: root.updateMap[String(modelData.id)]

    width: ListView.view.rowWidth
    height: root.resultRowHeight
    hasCursor: resultMouse.containsMouse
    foreground: root.foreground

    MouseArea {
      id: resultMouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }

    ColumnLayout {
      anchors.left: parent.left
      anchors.right: resultActions.left
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(1)

      Text {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        text: resultRow.modelData.name
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }
      Text {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        text: [resultRow.modelData.author, Model.compactCount(resultRow.modelData.downloads) + " ↓", resultRow.modelData.gameVersion, Model.releaseLabel(resultRow.modelData.releaseType)]
          .filter(function(s) { return s }).join(" · ")
          + (resultRow.modelData.distributable ? "" : " · manual only")
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    Row {
      id: resultActions
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      PanelActionButton {
        iconText: "󰖟"
        tooltipText: "View on CurseForge"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.openUrl(resultRow.modelData.url)
      }
      PanelActionButton {
        iconText: resultRow.upd ? "󰚰" : (resultRow.modelData.installed ? "󰄬" : "󰇚")
        tooltipText: resultRow.upd ? "Update" : (resultRow.modelData.installed ? "Installed – reinstall" : "Install")
        foreground: resultRow.upd ? Color.accent : root.foreground
        fontFamily: root.fontFamily
        enabled: !root.busy && root.hasAddonsDir && resultRow.modelData.latestFileId !== null
        opacity: enabled ? 1.0 : 0.4
        onClicked: root.install(resultRow.modelData)
      }
    }
  }

  component InstalledRow: CursorSurface {
    id: installedRow
    required property var modelData
    readonly property var upd: root.updateMap[String(modelData.modId)]

    width: ListView.view.rowWidth
    height: root.resultRowHeight
    hasCursor: installedMouse.containsMouse
    foreground: root.foreground

    MouseArea {
      id: installedMouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }

    ColumnLayout {
      anchors.left: parent.left
      anchors.right: installedActions.left
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(1)

      Text {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        text: installedRow.modelData.name
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }
      Text {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        text: installedRow.upd
          ? installedRow.modelData.versionString + "  →  " + installedRow.upd.latestFileName
          : installedRow.modelData.versionString + " · " + Model.shortDate(installedRow.modelData.installedAt)
        color: installedRow.upd ? Color.accent : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    Row {
      id: installedActions
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      PanelActionButton {
        visible: !!installedRow.upd
        iconText: "󰚰"
        tooltipText: installedRow.upd && !installedRow.upd.distributable ? "Update possible manually only" : "Update"
        foreground: Color.accent
        fontFamily: root.fontFamily
        enabled: !root.busy
        onClicked: root.update(installedRow.modelData.modId, installedRow.modelData.name)
      }
      PanelActionButton {
        iconText: "󰖟"
        tooltipText: "View on CurseForge"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.openUrl(installedRow.modelData.url)
      }
      PanelActionButton {
        iconText: "󰆴"
        tooltipText: "Remove (" + (installedRow.modelData.folders || []).join(", ") + ")"
        foreground: root.foreground
        hoverColor: root.urgent
        fontFamily: root.fontFamily
        enabled: !root.busy
        onClicked: root.run(["remove", String(installedRow.modelData.modId)], "Removing " + installedRow.modelData.name)
      }
    }
  }
}
