// Dev-Boost — browse, search and install dev-boost stacks and modules from the desktop.
//
// Organised by PROFILE, not by module, because that is the unit people actually think in:
// "set up Laravel", not "install ddev, then ddev-remote, then laravel-lsp". It is also the
// unit dev-boost installs in — `devboost install laravel` is a real command — so grouping
// and action agree. Profiles start collapsed (~19 rows instead of ~84); expand one to pick
// individual modules out of it.
//
// The catalogue comes from `devboost list --json --status`, which reports the PLAN for
// this host: modules scoped to another OS are absent, and ones the platform already
// provides carry a skip reason. So the list only offers what is actually installable here,
// and says why when something is not.
//
// Installs are NOT run inside the shell. They need sudo, they take minutes, and they print
// things worth reading — so Enter hands the work to a terminal via `omarchy-launch-tui`
// and closes the overlay. A progress bar in a popup would hide a password prompt and give
// you nowhere to answer it.

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property bool loading: false
  property string loadError: ""
  //: true when devboost itself is absent, which turns the empty state into an offer
  //: to install it rather than a dead end.
  property bool missingBinary: false
  property var modules: []
  property var profiles: []
  property var expanded: ({})
  property var picked: ({})
  property int pickedCount: 0

  // Share the [menu] surface tokens, so any theme that styles the Omarchy menu styles
  // this too — no separate palette to keep in sync.
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText

  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int titleHeight: Math.max(Style.space(30), Style.font.title + Style.space(6))
  property int searchHeight: Math.max(Style.space(26), Style.font.heading + Style.space(6))
  property int footerHeight: Math.max(Style.space(22), Style.font.caption + Style.space(8))
  property int contentSpacing: Style.spacing.md
  property int cardWidth: Math.min(Style.space(900), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(640), panel.height - Style.gapsOut * 2)
  property int rowHeight: Math.max(Style.space(46), Style.font.body + Style.font.caption + Style.spacing.rowPaddingX * 2)

  // Profile ids are lowercase slugs; these are the ones whose natural spelling a
  // title-case fallback would get wrong.
  readonly property var profileLabels: ({
    "cli": "CLI",
    "dotnet": ".NET + Aspire",
    "devops": "DevOps",
    "react-native": "React Native",
    "dev-hygiene": "Dev hygiene",
    "brain-host": "Brain host",
    "brain-tools": "Brain tools",
    "omarchy": "Omarchy integration",
    "apps": "Desktop apps",
    "data": "Data services",
    "web": "Web / Node",
    "base": "Base system",
    "laravel": "Laravel"
  })

  readonly property var profileBlurbs: ({
    "laravel": "ddev-based PHP/Laravel stack",
    "dotnet": ".NET SDK, Aspire CLI and C# language servers",
    "python": "uv plus Python language servers",
    "web": "node, pnpm and bun via mise, with TS/ESLint servers",
    "react-native": "Android SDK, JDK and Expo",
    "data": "containerised postgres, valkey and dbgate",
    "devops": "OpenTofu, kubectl, helm and k9s",
    "editors": "the fresh editor, VS Code and base language servers",
    "apps": "Obsidian, Bitwarden, Bruno and friends",
    "shell": "prompt, dotfiles and terminal configuration",
    "cli": "the everyday command-line tools",
    "base": "compilers, docker, mise and credentials",
    "system": "backups, firmware and disk health",
    "remote": "Tailscale and Mosh"
  })

  // --- summon contract -------------------------------------------------------------

  function open(payloadJson) {
    root.opened = true
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    root.expanded = ({})
    root.clearPicks()
    root.reload()
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  // --- data ------------------------------------------------------------------------

  function reload() {
    root.loading = true
    root.loadError = ""
    listProc.buffer = ""
    loadWatchdog.restart()
    listProc.running = true
  }

  function fail(message, missing) {
    root.loading = false
    root.modules = []
    root.profiles = []
    root.rebuild()
    root.loadError = message
    root.missingBinary = missing === true
  }

  // dev-boost is a hard dependency: without it this panel has nothing to show and nothing
  // to do. `omarchy plugin add` cannot install it — plugin install only clones, validates
  // and enables, and never executes anything from the plugin (a security property, not an
  // oversight). So the panel offers the install itself, one keypress, in a terminal where
  // you can see it work and answer for sudo.
  function installDevboost() {
    root.runInTerminal(
      "curl -fsSL https://raw.githubusercontent.com/adams100111/dev-boost/main/scripts/get.sh | bash",
      "install dev-boost")
  }

  function labelFor(profile) {
    if (root.profileLabels[profile]) return root.profileLabels[profile]
    var words = String(profile).split("-")
    return words[0].charAt(0).toUpperCase() + words[0].slice(1)
           + (words.length > 1 ? " " + words.slice(1).join(" ") : "")
  }

  function applyCatalogue(text) {
    root.loading = false
    root.missingBinary = false
    var parsed = []
    try {
      parsed = JSON.parse(text)
    } catch (e) {
      root.fail("Could not read the module list from devboost.", false)
      return
    }

    // Bucket modules by the profile(s) they declare. A module listed under two profiles
    // (web-runtimes is in both `web` and `react-native`) genuinely belongs to both:
    // installing either profile brings it in, so showing it twice is accurate.
    var buckets = ({})
    for (var i = 0; i < parsed.length; i++) {
      var m = parsed[i]
      var names = (m.profiles && m.profiles.length) ? m.profiles : ["other"]
      for (var j = 0; j < names.length; j++) {
        var key = String(names[j])
        if (!buckets[key]) buckets[key] = []
        buckets[key].push(m)
      }
    }

    var built = []
    for (var key2 in buckets) {
      var rows = buckets[key2]
      rows.sort(function (a, b) { return String(a.name) < String(b.name) ? -1 : 1 })
      var installed = 0, provided = 0
      for (var k = 0; k < rows.length; k++) {
        if (rows[k].skip_reason) provided += 1
        else if (rows[k].installed === true) installed += 1
      }
      built.push({
        id: key2,
        label: root.labelFor(key2),
        blurb: root.profileBlurbs[key2] || "",
        members: rows,
        installed: installed,
        provided: provided,
        actionable: rows.length - provided
      })
    }
    built.sort(function (a, b) { return a.label < b.label ? -1 : 1 })

    root.modules = parsed
    root.profiles = built
    root.rebuild()
  }

  function stateOf(entry) {
    if (entry.skip_reason) return "provided"
    if (entry.installed === true) return "installed"
    return "available"
  }

  function matches(entry, needle) {
    if (!needle) return true
    var hay = (String(entry.name) + " " + String(entry.category || "") + " "
               + String(entry.description || "")).toLowerCase()
    // Every whitespace-separated term must appear, so "python lsp" narrows rather than
    // widening the way a single substring match would.
    var terms = needle.toLowerCase().split(/\s+/)
    for (var i = 0; i < terms.length; i++) {
      if (terms[i] && hay.indexOf(terms[i]) === -1) return false
    }
    return true
  }

  function profileMatches(profile, needle) {
    if (!needle) return true
    var hay = (profile.id + " " + profile.label + " " + profile.blurb).toLowerCase()
    var terms = needle.toLowerCase().split(/\s+/)
    for (var i = 0; i < terms.length; i++) {
      if (terms[i] && hay.indexOf(terms[i]) === -1) return false
    }
    return true
  }

  function rebuild() {
    displayModel.clear()
    var needle = root.filterText
    for (var i = 0; i < root.profiles.length; i++) {
      var p = root.profiles[i]
      var wholeProfileMatched = root.profileMatches(p, needle)
      var hits = []
      for (var j = 0; j < p.members.length; j++) {
        if (wholeProfileMatched || root.matches(p.members[j], needle)) hits.push(p.members[j])
      }
      if (hits.length === 0) continue

      displayModel.append({
        kind: "profile",
        key: p.id,
        title: p.label,
        subtitle: p.blurb,
        state: p.actionable > 0 && p.installed >= p.actionable ? "installed" : "available",
        count: p.members.length,
        installedCount: p.installed,
        actionable: p.actionable,
        skipReason: ""
      })

      // While searching, show the matches without making people expand every group.
      var showMembers = root.expanded[p.id] === true || (needle !== "" && !wholeProfileMatched)
      if (!showMembers) continue
      for (var k = 0; k < hits.length; k++) {
        var m = hits[k]
        displayModel.append({
          kind: "module",
          key: String(m.name),
          title: String(m.name),
          subtitle: String(m.description || ""),
          state: root.stateOf(m),
          count: 0,
          installedCount: 0,
          actionable: 0,
          skipReason: String(m.skip_reason || "")
        })
      }
    }
    if (root.selectedIndex >= displayModel.count) root.selectedIndex = Math.max(0, displayModel.count - 1)
    if (displayModel.count > 0) resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function setFilter(text) {
    root.filterText = text
    root.selectedIndex = 0
    root.rebuild()
  }

  function toggleExpand(index) {
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    if (row.kind !== "profile") return
    var next = ({})
    for (var key in root.expanded) next[key] = root.expanded[key]
    if (next[row.key]) delete next[row.key]
    else next[row.key] = true
    root.expanded = next
    root.rebuild()
  }

  // --- selection --------------------------------------------------------------------

  function clearPicks() {
    root.picked = ({})
    root.pickedCount = 0
  }

  function togglePick(index) {
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    if (row.state === "provided") return  // nothing to install; the platform supplies it
    var next = ({})
    for (var key in root.picked) next[key] = root.picked[key]
    if (next[row.key]) delete next[row.key]
    else next[row.key] = true
    root.picked = next
    var n = 0
    for (var k in next) n++
    root.pickedCount = n
  }

  function pendingTargets() {
    var names = []
    for (var key in root.picked) names.push(key)
    if (names.length > 0) return names.sort()
    if (root.selectedIndex >= 0 && root.selectedIndex < displayModel.count) {
      var row = displayModel.get(root.selectedIndex)
      if (row.state !== "provided") return [row.key]
    }
    return []
  }

  // --- actions ----------------------------------------------------------------------

  // Quote for the shell: these strings end up inside a bash -c, and a profile or module
  // name is not guaranteed to stay [a-z-] forever.
  function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  function runInTerminal(command, title) {
    // `read` keeps the window open on the summary — a terminal that vanishes takes the
    // error message with it.
    var script = command
                 + "; printf '\\n%s\\n' " + root.shellQuote("— " + title + " finished —")
                 + "; read -n 1 -s -r -p 'Press any key to close…'"
    termProc.command = ["omarchy-launch-tui", "bash", "-lc", script]
    termProc.running = true
    root.close()
  }

  // `devboost install` takes profiles and modules interchangeably, so one code path
  // covers "install the whole Laravel stack" and "install just ddev".
  function installPending() {
    var targets = root.pendingTargets()
    if (targets.length === 0) return
    var quoted = []
    for (var i = 0; i < targets.length; i++) quoted.push(root.shellQuote(targets[i]))
    root.runInTerminal("devboost install " + quoted.join(" "), "install " + targets.join(", "))
  }

  function updateTools() {
    root.runInTerminal("devboost install --update", "update dev-boost tooling")
  }

  function upgradeSystem() {
    // The OS is Omarchy's to update — it snapshots first, runs migrations, then AUR and
    // mise. dev-boost's own post-update hook rides along.
    root.runInTerminal("omarchy update", "system update")
  }

  function verifyAll() {
    root.runInTerminal("devboost verify", "verify")
  }

  function moveCursor(delta) {
    var next = root.selectedIndex + delta
    if (next < 0) next = 0
    if (next > displayModel.count - 1) next = displayModel.count - 1
    root.selectedIndex = next
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  ListModel { id: displayModel }

  Process {
    id: listProc
    property string buffer: ""
    // Run through a LOGIN shell, for two reasons that both bit in testing:
    //   1. Quickshell's Process does not emit `exited` when the binary itself cannot be
    //      found — it only logs a warning — so onExited never fires and the panel sits on
    //      "loading…" forever. bash always exists, so the process always starts and always
    //      exits, returning 127 when devboost is missing. The error path becomes reachable.
    //   2. The shell is started by the session, not by your terminal, so it does not
    //      inherit a PATH built by ~/.bashrc. `-l` sources the profile, which is how a
    //      devboost installed into ~/.local/bin or a uv tool dir gets found at all.
    command: ["bash", "-lc", "command -v devboost >/dev/null 2>&1 || exit 127; exec devboost list --json --status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: listProc.buffer = text
    }
    onExited: function (code) {
      loadWatchdog.stop()
      if (code === 0 && listProc.buffer) {
        root.applyCatalogue(listProc.buffer)
      } else {
        var missing = code === 127 || code < 0
        root.fail(missing
                  ? "dev-boost is not installed.\n\nPress enter to install it — "
                    + "it opens a terminal so you can watch it and answer for sudo.\n"
                    + "Press ^r to re-check once it is done."
                  : "devboost could not list modules (exit " + code + ").",
                  missing)
      }
    }
  }

  // A command that cannot be spawned at all may never report an exit, which would leave
  // the panel saying "loading…" forever — the least useful thing it could say. Time the
  // probe out and explain instead. --status runs a verify per module, so the budget is
  // generous rather than snappy.
  Timer {
    id: loadWatchdog
    interval: 20000
    repeat: false
    onTriggered: {
      if (!root.loading) return
      listProc.running = false
      root.fail("devboost did not respond. Is it installed and on PATH?", true)
    }
  }

  Process { id: termProc }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "devboost"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      // Kept EMPTY and a sibling of the content, exactly as the built-in overlays do it:
      // a focusable child (a ListView is one) would otherwise take focus and swallow the
      // keystrokes that drive the filter.
      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function (event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.close()
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.missingBinary) root.installDevboost()
            else root.installPending()
            event.accepted = true
          } else if (event.key === Qt.Key_Right) {
            root.toggleExpand(root.selectedIndex)
            event.accepted = true
          } else if (event.key === Qt.Key_Left) {
            root.toggleExpand(root.selectedIndex)
            event.accepted = true
          } else if (event.key === Qt.Key_Tab) {
            root.togglePick(root.selectedIndex)
            root.moveCursor(1)
            event.accepted = true
          } else if (event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier)) {
            root.updateTools()
            event.accepted = true
          } else if (event.key === Qt.Key_G && (event.modifiers & Qt.ControlModifier)) {
            root.upgradeSystem()
            event.accepted = true
          } else if (event.key === Qt.Key_L && (event.modifiers & Qt.ControlModifier)) {
            root.verifyAll()
            event.accepted = true
          } else if (event.key === Qt.Key_R && (event.modifiers & Qt.ControlModifier)) {
            root.reload()
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.moveCursor(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.moveCursor(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.moveCursor(-8)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.moveCursor(8)
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            // Deletion keys only (Backspace / Ctrl+Backspace / Ctrl+U) — Util deliberately
            // does not handle typing, so the printable branch below is not optional.
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.text && event.text.length === 1
                     && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127
                     && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        // --- title + search --------------------------------------------------------
        // The panel says what it IS before it says what you can type into it. Without the
        // title the first thing you read is a placeholder, which makes an app you opened
        // deliberately look like a search box that appeared at you.
        Column {
          id: headerBlock
          width: parent.width
          spacing: Style.space(3)

          Item {
            width: parent.width
            height: root.titleHeight

            Text {
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.right: countLabel.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              text: "Dev Boost"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              id: countLabel
              textFormat: Text.PlainText
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: root.loading
                    ? "loading…"
                    : (root.pickedCount > 0
                       ? root.pickedCount + " selected"
                       : root.profiles.length + " stacks · " + root.modules.length + " modules")
              color: root.foreground
              opacity: 0.55
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Text {
            width: parent.width
            height: root.searchHeight
            textFormat: Text.PlainText
            text: root.filterText || "Search stacks and modules…"
            color: root.foreground
            opacity: root.filterText ? 1 : 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
          }
        }

        // --- list ------------------------------------------------------------------
        Item {
          width: parent.width
          height: parent.height - headerBlock.height - root.footerHeight - root.contentSpacing * 2

          Text {
            anchors.centerIn: parent
            visible: root.loadError !== "" || (!root.loading && displayModel.count === 0)
            textFormat: Text.PlainText
            width: parent.width - Style.space(40)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            lineHeight: 1.35
            text: root.loadError !== ""
                  ? root.loadError
                  : (root.filterText ? "Nothing matches “" + root.filterText + "”"
                                     : "No modules to show.")
            color: root.foreground
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          ListView {
            id: resultList
            anchors.fill: parent
            model: displayModel
            clip: true
            visible: displayModel.count > 0
            spacing: Style.space(2)
            boundsBehavior: Flickable.StopAtBounds
            // Never take focus: the key-catcher above owns every keystroke.
            focus: false

            delegate: Rectangle {
              id: row
              required property int index
              required property string kind
              required property string key
              required property string title
              required property string subtitle
              required property string state
              required property string skipReason
              required property int count
              required property int installedCount
              required property int actionable

              readonly property bool isProfile: kind === "profile"
              readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex
              readonly property bool isPicked: root.picked[key] === true
              readonly property bool isOpen: root.expanded[key] === true

              width: ListView.view.width
              height: root.rowHeight
              radius: root.cornerRadius
              color: hasCursor ? root.selectedBackground : "transparent"

              Row {
                anchors.fill: parent
                anchors.leftMargin: row.isProfile ? Style.space(12) : Style.space(30)
                anchors.rightMargin: Style.space(12)
                spacing: Style.space(10)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(16)
                  textFormat: Text.PlainText
                  // A stack shows its open/closed state; a module shows install state.
                  text: row.isProfile
                        ? (row.isPicked ? "+" : (row.isOpen ? "▾" : "▸"))
                        : (row.state === "installed" ? "✓"
                           : (row.isPicked ? "+" : (row.state === "provided" ? "–" : "·")))
                  color: row.hasCursor ? root.selectedText : root.foreground
                  opacity: row.state === "provided" ? 0.4 : (row.isPicked ? 1 : 0.7)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                Column {
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - Style.space(46) - tally.width
                  spacing: Style.space(1)

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: row.title
                    color: row.hasCursor ? root.selectedText : root.foreground
                    opacity: row.state === "provided" ? 0.5 : 1
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: row.isProfile
                    elide: Text.ElideRight
                  }

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: row.skipReason !== ""
                          ? "already provided by the system (" + row.skipReason + ")"
                          : row.subtitle
                    color: row.hasCursor ? root.selectedText : root.foreground
                    opacity: 0.55
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                    visible: text !== ""
                  }
                }

                // Roll-up, so a stack says how much of it is already on the box.
                Text {
                  id: tally
                  anchors.verticalCenter: parent.verticalCenter
                  visible: row.isProfile
                  textFormat: Text.PlainText
                  text: !row.isProfile ? ""
                        : (row.actionable === 0
                           ? "provided"
                           : (row.installedCount >= row.actionable
                              ? "installed"
                              : row.installedCount + "/" + row.actionable))
                  color: row.hasCursor ? root.selectedText : root.foreground
                  opacity: 0.5
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              MouseArea {
                anchors.fill: parent
                onClicked: {
                  root.selectedIndex = row.index
                  if (row.isProfile) root.toggleExpand(row.index)
                  else root.togglePick(row.index)
                }
                onDoubleClicked: {
                  root.selectedIndex = row.index
                  root.installPending()
                }
              }
            }
          }
        }

        // --- key hints -------------------------------------------------------------
        Text {
          width: parent.width
          height: root.footerHeight
          textFormat: Text.PlainText
          text: "type to search   → expand   enter install   tab select   ^u update   ^g system update   ^l verify   ^r reload"
          color: root.foreground
          opacity: 0.4
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          verticalAlignment: Text.AlignVCenter
        }
      }
    }
  }
}
