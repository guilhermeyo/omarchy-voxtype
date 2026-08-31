import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "HistoryModel.js" as History

// Janela CENTRALIZADA com o histórico de ditado. Clicar (ou Enter) copia.
//
// A receita de centralização é a mesma dos três overlays nativos (clipboard,
// emojis e o menu do SUPER+SPACE): a janela é a tela INTEIRA e quem centraliza
// é o `anchors.centerIn: parent` do card. Não há cálculo de x/y — e é isso que
// faz ela abrir no monitor com foco, ao contrário do painel de pipeline, que é
// ancorado na barra e sempre cai no HDMI-A-1.
//
// Por que NÃO virei um plugin de kind "menu" como o omarchy.menu: shell.qml:426
// (`isBarWidgetPanelPlugin`) devolve false pra qualquer plugin que declare
// panel/overlay/menu, tirando o local.voxtype do roteamento de bar-widget e
// mudando o dono do painel de pipeline que já funciona. O omarchy.menu escapa
// disso separando em dois arquivos, com um BarWidget.qml que só dispara IPC.
// Um PanelWindow pode ser declarado aqui dentro sem tocar no manifest.
Item {
  id: root

  property bool opened: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  readonly property color dim: Qt.darker(foreground, 1.5)

  property string historyPath: Quickshell.env("HOME") + "/.local/state/voxtype/history.jsonl"

  property var entries: []
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false

  signal copied(string text)

  function open() {
    filterText = ""
    selectedIndex = 0
    cursorActive = false
    // Recarrega ao ABRIR em vez de confiar só no watcher: o histórico só
    // precisa estar fresco no momento em que você olha pra ele.
    historyFile.reload()
    opened = true
  }
  function close() { opened = false }

  function rebuild() {
    var rows = History.displayRows(root.entries, root.filterText, 60)
    listModel.clear()
    for (var i = 0; i < rows.length; i++) listModel.append(rows[i])
    if (selectedIndex >= listModel.count) selectedIndex = Math.max(0, listModel.count - 1)
  }
  function setFilter(v) { root.filterText = String(v || ""); rebuild() }

  function select(delta) {
    if (listModel.count === 0) return
    cursorActive = true
    selectedIndex = Math.max(0, Math.min(listModel.count - 1, selectedIndex + delta))
  }

  // wl-copy, NÃO Quickshell.clipboardText. A API nativa existe e é gravável,
  // mas o próprio header do Quickshell avisa: "under wayland the clipboard will
  // be empty unless a quickshell window is focused" — é wl_data_device, que
  // exige serial de input recente numa surface com foco. O omarchy copia em 5
  // lugares e nunca usa clipboardText (zero hits no grep). Util.shellQuote
  // protege aspas, newline e $ no texto ditado.
  function copyText(text) {
    var s = String(text || "")
    if (s === "") return
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(s) + " | wl-copy"])
    root.copied(s)
  }

  function copyIndex(i) {
    if (i < 0 || i >= listModel.count) return
    copyText(listModel.get(i).fullText)
    close()
  }

  // Usado pelo botão "copiar último" do painel de pipeline, sem abrir nada.
  function copyLatest() {
    if (root.entries.length === 0) { historyFile.reload(); return false }
    copyText(root.entries[0].text)
    return true
  }

  // Alvo IPC próprio, no mesmo formato que o omarchy.menu usa pro SUPER+SPACE.
  // Serve pra amarrar numa tecla no bindings.lua:
  //   o.bind("SUPER + SHIFT + V", "Histórico do ditado",
  //          "omarchy-shell voxtype-history toggle")
  IpcHandler {
    target: "voxtype-history"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.opened ? root.close() : root.open() }
    function copyLast(): void { root.copyLatest() }
  }

  ListModel { id: listModel }

  FileView {
    id: historyFile
    path: root.historyPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { root.entries = History.parseHistory(text()); root.rebuild() }
    onLoadFailed: { root.entries = []; root.rebuild() }
  }

  PanelWindow {
    id: win
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "voxtype-history"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.45) }
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    BorderSurface {
      id: card
      width: Math.min(Style.space(900), win.width - Style.gapsOut * 2)
      height: Math.min(Style.space(560), win.height - Style.gapsOut * 2)
      anchors.centerIn: parent
      radius: Style.cornerRadius
      color: Color.background
      borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
      padding: Style.spacing.popupPadding

      MouseArea { anchors.fill: parent; onClicked: {} }   // não fecha ao clicar dentro

      Item {
        id: keys
        anchors.fill: parent
        // Margem explícita: o `padding` do BorderSurface não insetou os filhos
        // ancorados, e o cabeçalho e o rodapé estavam sangrando pra fora do
        // card — "digite para filtrar…" cortava na borda direita. O respiro é
        // maior que o popupPadding de propósito: título, lista e rodapé
        // ficavam colados na borda do card.
        anchors.margins: Style.space(24)
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter(""); else root.close()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText)); event.accepted = true
          } else if (event.key === Qt.Key_Up)   { root.select(-1); event.accepted = true }
          else if (event.key === Qt.Key_Down)   { root.select(1);  event.accepted = true }
          else if (event.key === Qt.Key_PageUp) { root.select(-6); event.accepted = true }
          else if (event.key === Qt.Key_PageDown){ root.select(6); event.accepted = true }
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (listModel.count > 0) root.copyIndex(root.selectedIndex)
            event.accepted = true
          } else if (event.text && event.text.length === 1
                     && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text); event.accepted = true
          }
        }

        // Cabeçalho ancorado no topo, rodapé no fundo, conteúdo no meio. Antes
        // era uma Column com altura calculada na mão, e a conta errava por
        // alguns px — o rodapé saía cortado embaixo.
        Item {
          id: header
          anchors { top: parent.top; left: parent.left; right: parent.right }
          height: hdrIcon.implicitHeight

          Item {
            anchors.fill: parent

            Text {
              id: hdrIcon
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "󰋚"                     // U+F02DA md-history
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
            }
            Text {
              anchors.left: hdrIcon.right
              anchors.leftMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              text: "Histórico do ditado"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
            // Campo de busca falso: um Text alimentado pelas teclas cruas, como
            // o clipboard nativo faz. Sem TextField, sem foco pra disputar.
            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: root.filterText || "digite para filtrar…"
              color: root.filterText ? root.foreground : root.dim
              opacity: root.filterText ? 1 : 0.6
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }

        }

        PanelSeparator {
          id: sep
          anchors { top: header.bottom; topMargin: Style.space(10); left: parent.left; right: parent.right }
          foreground: root.foreground
        }

        // ── lista à esquerda · texto inteiro à direita ──────────────
        Item {
            anchors {
              top: sep.bottom; topMargin: Style.space(10)
              left: parent.left; right: parent.right
              bottom: footer.top; bottomMargin: Style.space(10)
            }

            Item {
              id: leftPane
              width: parent.width * 0.42
              height: parent.height
              clip: true

              ListView {
                id: list
                anchors.fill: parent
                anchors.rightMargin: Style.space(10)
                model: listModel
                clip: true
                spacing: Style.space(2)
                boundsBehavior: Flickable.StopAtBounds
                currentIndex: root.selectedIndex
                highlightMoveDuration: 0
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

                delegate: CursorSurface {
                  required property int index
                  required property string when
                  required property string day
                  required property string previewText
                  width: list.width
                  // Altura FIXA. Preview de uma linha e altura fixa é o que
                  // segura a lista com ditado de 500 palavras.
                  implicitHeight: Style.space(44)
                  hasCursor: root.cursorActive && root.selectedIndex === index
                  current: root.selectedIndex === index
                  foreground: root.foreground

                  Column {
                    anchors.fill: parent
                    anchors.margins: Style.space(8)
                    spacing: Style.space(1)

                    Text {
                      width: parent.width
                      text: day + "  " + when
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                    Text {
                      width: parent.width
                      text: previewText
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                      wrapMode: Text.NoWrap
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: { root.cursorActive = true; root.selectedIndex = index }
                    onClicked: root.copyIndex(index)
                  }
                }
              }

              Text {
                anchors.centerIn: parent
                visible: listModel.count === 0
                text: root.entries.length === 0
                      ? "Nenhum ditado ainda"
                      : "Nada para “" + root.filterText + "”"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }

            Item {
              anchors.left: leftPane.right
              anchors.leftMargin: Style.space(14)
              anchors.right: parent.right
              height: parent.height
              clip: true

              property var row: listModel.count > 0 && root.selectedIndex >= 0
                                && root.selectedIndex < listModel.count
                                ? listModel.get(root.selectedIndex) : null

              Text {
                anchors.fill: parent
                text: parent.row ? parent.row.fullText : ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                // Text.Wrap, NÃO WrapAnywhere. O clipboard nativo usa
                // WrapAnywhere porque o conteúdo dele costuma ser URL/base64,
                // que não tem espaço pra quebrar. Ditado é prosa: WrapAnywhere
                // partia palavra no meio ("t elefone", "Entã o", "Preci so").
                // Text.Wrap quebra em espaço e só recorre ao meio da palavra
                // quando um token sozinho não cabe.
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                verticalAlignment: Text.AlignTop
              }
            }
        }

        Text {
          id: footer
          anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
          text: "Enter ou clique copia  ·  Esc fecha  ·  " + listModel.count + " de " + root.entries.length
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
