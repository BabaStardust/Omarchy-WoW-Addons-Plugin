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
  // Installs/updates run as parallel background jobs, keyed by modId:
  // { key, modId, name, args, status, seq, url, downloadUrl, fileId, error, code, finishedAt }
  // status: queued → downloading | waiting (browser) → installing → done | failed
  property var jobs: ({})
  property var jobProcs: ({})
  property int jobSeq: 0
  readonly property int maxParallel: 4
  readonly property var jobList: Object.keys(jobs).map(function(k) { return jobs[k] }).sort(function(a, b) { return a.seq - b.seq })
  readonly property int jobsRunning: jobList.filter(function(j) { return j.status !== "done" && j.status !== "failed" }).length
  readonly property int jobsWaiting: jobList.filter(function(j) { return j.status === "waiting" }).length
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

  // --browser: addons that block third-party downloads open their CurseForge
  // download page and are installed as soon as the zip lands in ~/Downloads.
  function install(mod) {
    startJob(mod.id, mod.name, ["install", String(mod.id), "--browser"])
  }

  function update(modId, name) {
    startJob(modId, name, ["update", String(modId), "--browser"])
  }

  function updateAll() {
    for (var i = 0; i < updates.length; i++) update(updates[i].modId, updates[i].name)
  }

  function importDownload(job) {
    startJob(job.modId, job.name, ["import", String(job.modId), String(job.fileId)])
  }

  function jobFor(modId) {
    return jobs[String(modId)] || null
  }

  function jobActive(modId) {
    var j = jobFor(modId)
    return j !== null && j.status !== "done" && j.status !== "failed"
  }

  function setJob(key, patch) {
    var all = Object.assign({}, jobs)
    if (patch === null) delete all[key]
    else all[key] = Object.assign({}, all[key] || {}, patch)
    jobs = all
  }

  function startJob(modId, name, args) {
    var key = String(modId)
    if (jobActive(modId) || !hasAddonsDir) return
    jobSeq += 1
    setJob(key, { key: key, modId: Number(modId), name: name, args: args, status: "queued", seq: jobSeq, error: "", code: "", url: "", downloadUrl: "", fileId: 0, finishedAt: 0 })
    pumpJobs()
  }

  // Jobs waiting for the browser do not take a slot.
  function pumpJobs() {
    var list = jobList
    var active = list.filter(function(j) { return j.status === "starting" || j.status === "downloading" || j.status === "installing" }).length
    for (var i = 0; i < list.length && active < maxParallel; i++) {
      var j = list[i]
      if (j.status !== "queued") continue
      var proc = jobComponent.createObject(root, { jobKey: j.key, command: [helper].concat(j.args) })
      var procs = Object.assign({}, jobProcs)
      procs[j.key] = proc
      jobProcs = procs
      setJob(j.key, { status: "starting" })
      proc.running = true
      active += 1
    }
  }

  function cancelJob(key) {
    var proc = jobProcs[key]
    if (proc) proc.running = false
    else setJob(key, null)
  }

  function dismissJob(key) {
    if (!jobActive(Number(key))) setJob(key, null)
  }

  function jobStatusText(j) {
    switch (j.status) {
    case "queued": return "Queued"
    case "starting": return "Starting…"
    case "downloading": return "Downloading…"
    case "installing": return "Installing…"
    case "waiting": return "Waiting for the browser download in ~/Downloads…"
    case "done": return "Done" + (j.version ? ": " + j.version : "") + " ✓"
    case "failed": return j.error || "Failed"
    }
    return j.status
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
    function tab(name: string): string {
      if (["search", "installed", "settings"].indexOf(name) < 0) return "unknown tab"
      root.tab = name
      return "ok"
    }
    function search(query: string): string { root.tab = "search"; searchField.text = query; root.search(query); return "ok" }
    function updateAll(): string { root.updateAll(); return "ok" }
    function status(): string { return root.updateCount + " updates · " + root.installed.installed.length + " installed" }
  }

  Timer {
    id: updateTimer
    interval: Math.max(1, root.updateCheckHours) * 3600 * 1000
    running: root.updateCheckHours > 0
    repeat: true
    onTriggered: root.checkUpdates()
  }

  // Coalesces the refresh after several jobs finish close together.
  Timer {
    id: refreshTimer
    interval: 400
    onTriggered: {
      if (listProc.running || updatesProc.running || configProc.running) { restart(); return }
      root.refresh()
      root.checkUpdates()
      if (root.searchResult.mode !== "") root.search(searchField.text)
    }
  }

  // Finished jobs stay visible for a moment; failed ones until dismissed.
  Timer {
    interval: 2000
    repeat: true
    running: root.jobList.some(function(j) { return j.status === "done" })
    onTriggered: {
      var now = Date.now()
      root.jobList.forEach(function(j) { if (j.status === "done" && now - j.finishedAt > 6000) root.setJob(j.key, null) })
    }
  }

  Component {
    id: jobComponent
    Process {
      id: jobProc
      property string jobKey: ""
      // Progress events, one JSON object per line on stderr.
      stderr: SplitParser {
        onRead: function(data) {
          var ev = Model.parse(data, null)
          if (!ev || !ev.event) return
          var patch = { status: ev.event }
          if (ev.url) patch.url = ev.url
          if (ev.downloadUrl) patch.downloadUrl = ev.downloadUrl
          root.setJob(jobProc.jobKey, patch)
          if (ev.event === "waiting") root.pumpJobs()
        }
      }
      stdout: StdioCollector { id: jobOut; waitForEnd: true }
      onExited: function(exitCode) {
        var data = Model.parse(jobOut.text, null)
        var key = jobProc.jobKey
        if (data && data.ok) {
          root.setJob(key, { status: "done", version: data.version || "", finishedAt: Date.now() })
        } else if (!data) {
          // Cancelled (or crashed) without a result.
          root.setJob(key, null)
        } else {
          root.setJob(key, {
            status: "failed",
            error: data.error || "Failed",
            code: data.code || "",
            url: data.url || root.jobFor(key).url || "",
            downloadUrl: data.downloadUrl || root.jobFor(key).downloadUrl || "",
            fileId: Number(data.fileId || 0)
          })
        }
        var procs = Object.assign({}, root.jobProcs)
        delete procs[key]
        root.jobProcs = procs
        root.pumpJobs()
        refreshTimer.restart()
        jobProc.destroy()
      }
    }
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
      } else {
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
    active: root.updateCount > 0 || root.jobsRunning > 0
    activeColor: Color.accent
    tooltipText: "WoW Addons"
      + (root.updateCount > 0 ? "\n" + root.updateCount + (root.updateCount === 1 ? " update available" : " updates available") : "")
      + (root.jobsRunning > 0 ? "\n" + root.jobsRunning + " running" + (root.jobsWaiting > 0 ? " (" + root.jobsWaiting + " waiting for browser download)" : "") : "")
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
        else if (t === "u" || t === "U") root.updateAll()
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
                + (root.jobsRunning > 0 ? " · " + root.jobsRunning + " running" : "")
                + (root.hasAddonsDir ? "" : " · WoW folder missing → Settings")
              // The hero's detail pill never elides, so keep it short: the
              // flavor ("forever"), not the full AddOns path.
              detail: root.hasAddonsDir ? Model.flavorLabel(root.config.resolved.flavor, root.config.resolved.addonsDir) : ""
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
                tooltipText: "Install all updates in parallel (u)"
                foreground: root.foreground
                fontFamily: root.fontFamily
                enabled: root.updates.some(function(u) { return !root.jobActive(u.modId) })
                opacity: enabled ? 1.0 : 0.4
                onClicked: root.updateAll()
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

          // ── Running installs/updates ───────────────────────────────
          Column {
            visible: root.jobList.length > 0
            width: parent.width
            spacing: Style.space(4)

            PanelSectionHeader {
              text: root.jobsWaiting > 0 ? "JOBS · DOWNLOAD IN THE BROWSER, THE REST HAPPENS HERE" : "JOBS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }
            ScrollList {
              visibleRows: 4
              rowHeight: root.resultRowHeight
              model: root.jobList
              delegate: JobRow {}
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

            RowLayout {
              visible: root.updateCount > 0
              width: parent.width
              spacing: Style.space(6)

              Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                elide: Text.ElideRight
                text: root.updateCount + (root.updateCount === 1 ? " update available" : " updates available")
                color: Color.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
              Button {
                iconText: "󰚰"
                text: "Update all (" + root.updateCount + ")"
                tooltipText: "Install all updates in parallel (u)"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                enabled: root.updates.some(function(u) { return !root.jobActive(u.modId) })
                opacity: enabled ? 1.0 : 0.4
                onClicked: root.updateAll()
              }
            }

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
              placeholder: root.config.flavors.length ? root.config.flavors.join(", ") : "e.g. _forever_"
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
        tooltipText: (resultRow.upd ? "Update" : (resultRow.modelData.installed ? "Installed – reinstall" : "Install"))
          + (resultRow.modelData.distributable ? "" : " (opens the download in the browser)")
        foreground: resultRow.upd ? Color.accent : root.foreground
        fontFamily: root.fontFamily
        enabled: !root.jobActive(resultRow.modelData.id) && root.hasAddonsDir && resultRow.modelData.latestFileId !== null
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
        tooltipText: installedRow.upd && !installedRow.upd.distributable ? "Update (opens the download in the browser)" : "Update"
        foreground: Color.accent
        fontFamily: root.fontFamily
        enabled: !root.jobActive(installedRow.modelData.modId)
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
        enabled: !root.busy && !root.jobActive(installedRow.modelData.modId)
        onClicked: root.run(["remove", String(installedRow.modelData.modId)], "Removing " + installedRow.modelData.name)
      }
    }
  }

  component JobRow: CursorSurface {
    id: jobRow
    required property var modelData
    readonly property bool failed: modelData.status === "failed"
    readonly property bool manual: modelData.code === "distribution_disabled" || modelData.code === "download_timeout"

    width: ListView.view.rowWidth
    height: root.resultRowHeight
    hasCursor: jobMouse.containsMouse
    foreground: root.foreground

    MouseArea {
      id: jobMouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }

    ColumnLayout {
      anchors.left: parent.left
      anchors.right: jobActions.left
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(1)

      Text {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        text: jobRow.modelData.name
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }
      Text {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        text: root.jobStatusText(jobRow.modelData)
        color: jobRow.failed ? root.urgent : (jobRow.modelData.status === "waiting" || jobRow.modelData.status === "done" ? Color.accent : root.dim)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        // Long errors: full text on hover.
        ToolTip.visible: jobRow.failed && jobMouse.containsMouse
        ToolTip.text: jobRow.modelData.error || ""
      }
    }

    Row {
      id: jobActions
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      PanelActionButton {
        visible: jobRow.modelData.status === "waiting" || jobRow.manual
        iconText: "󰖟"
        tooltipText: "Open the download on CurseForge again"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.openUrl(jobRow.modelData.downloadUrl || jobRow.modelData.url)
      }
      PanelActionButton {
        visible: jobRow.failed && jobRow.manual && jobRow.modelData.fileId > 0
        iconText: "󰋺"
        tooltipText: "Import from ~/Downloads"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.importDownload(jobRow.modelData)
      }
      PanelActionButton {
        visible: jobRow.failed && !jobRow.manual
        iconText: "󰑐"
        tooltipText: "Retry"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.startJob(jobRow.modelData.modId, jobRow.modelData.name, jobRow.modelData.args)
      }
      PanelActionButton {
        visible: jobRow.modelData.status === "queued" || jobRow.modelData.status === "waiting" || jobRow.failed || jobRow.modelData.status === "done"
        iconText: "󰅖"
        tooltipText: jobRow.failed || jobRow.modelData.status === "done" ? "Dismiss" : "Cancel"
        foreground: root.foreground
        hoverColor: root.urgent
        fontFamily: root.fontFamily
        onClicked: jobRow.failed || jobRow.modelData.status === "done" ? root.dismissJob(jobRow.modelData.key) : root.cancelJob(jobRow.modelData.key)
      }
    }
  }
}
