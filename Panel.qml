import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar widget + native picker for the voxtype dictation polish mode.
// Structure copied from ~/.config/omarchy/plugins/local.vpn/Panel.qml; the
// keyboard wiring follows plugins/panels/power/Panel.qml, which is the
// first-party example of a short fixed list (no filter TextField).
Panel {
  id: root
  moduleName: "local.voxtype"
  ipcTarget: "local.voxtype"   // gives `omarchy-shell local.voxtype toggle` for free

  // ---- cursor state (keyboard + mouse share one highlight) -----------------
  property int modeIndex: 0
  property bool cursorActive: false

  readonly property var rows: Model.rowsFor(svc.mode)

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Color.accent) : "transparent"

  // Colour for a mode, in the bar. Order: explicit shell.json override, then a
  // theme-derived default. `barForeground` (not `foreground`) is the one that
  // flips in transparent-bar mode, so bar paint must use it (Bar.qml:60-61).
  function barColorFor(code) {
    var override = svc.colorOverride(code)
    if (override !== "") return override
    if (code === "off") return Qt.darker(root.barForeground, 1.9)   // polish disabled -> recede
    if (code === "gemini") return root.bar ? root.bar.urgent : Color.urgent  // text leaves the machine
    return root.barForeground
  }
  // Same idea inside the panel, where `foreground` is the right base.
  function panelColorFor(code) {
    var override = svc.colorOverride(code)
    if (override !== "") return override
    if (code === "off") return root.dim
    if (code === "gemini") return root.urgent
    return root.foreground
  }

  function clampIndex() {
    if (modeIndex < 0) modeIndex = 0
    if (modeIndex > rows.length - 1) modeIndex = rows.length - 1
  }
  function moveCursor(dx, dy) {
    cursorActive = true
    var d = dy !== 0 ? dy : dx      // a vertical list, but accept left/right too
    modeIndex = modeIndex + (d > 0 ? 1 : -1)
    clampIndex()
  }
  function setCursor(i) { cursorActive = true; modeIndex = i; clampIndex() }
  // Editor de pipeline: o painel FICA ABERTO depois de cada edição, senão
  // montar "sed+qwen+sed" custaria três reaberturas. Fecha com Esc, clique
  // fora, ou clique no ícone da barra.
  //
  // Linha de estágio  -> clique remove (o ✕ à direita mostra isso)
  // Linha "+ estágio" -> clique acrescenta no fim
  // "fallback ⬆" na linha de estágio -> alterna "só roda se o de cima falhar"
  function applyRow(item) {
    if (!item) return
    if (item.kind === "add") svc.setMode(Model.appendStage(svc.mode, item.key))
    else                     svc.setMode(Model.removeAt(svc.mode, item.slot))
  }
  function moveRow(item, delta) {
    if (!item || item.kind !== "stage") return
    svc.setMode(Model.moveAt(svc.mode, item.slot, delta))
  }
  // canFallback é falso na primeira linha (não há passo acima pra ter falhado)
  // e em toda linha "+". Model.toggleFallback também se defende do slot 0, mas
  // a UI não deve nem oferecer o clique.
  function toggleFallbackRow(item) {
    if (!item || item.kind !== "stage" || !item.canFallback) return
    svc.setMode(Model.toggleFallback(svc.mode, item.slot))
  }
  function activateCursor() { clampIndex(); applyRow(rows[modeIndex]) }
  function selectByCode(key) {
    for (var i = 0; i < rows.length; i++)
      if (rows[i].kind === "add" && rows[i].key === key) { applyRow(rows[i]); return }
  }

  // The bar slot measures this item (Bar.qml:1409-1412), so the root must
  // publish implicits; BarIconButton already resolves them from Style.bar.
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    // Com toggles não existe "linha ativa" única. Parkeia no primeiro estágio;
    // Enter agora alterna, então nada é destrutivo por acidente.
    modeIndex = 0
    cursorActive = false
    svc.reload()
  }

  Service { id: svc; settings: root.settings }

  // Janela centralizada do histórico. Declarada aqui dentro de propósito:
  // acrescentar um kind "menu"/"overlay" ao manifest tiraria o plugin do
  // roteamento de bar-widget (shell.qml:426 isBarWidgetPanelPlugin) e mudaria
  // o dono deste painel.
  History {
    id: history
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // SÓ a pipeline. Antes era `label + " · " + hint`, e como o hint virou uma
    // frase explicando a notação, o tooltip da barra saía uma redação de ponta
    // a ponta da tela. O paraquedas no meio do rótulo já diz o que precisa; o
    // resto se lê no painel, sob demanda.
    tooltipText: "Voxtype · " + svc.label

    // iconComponent instead of `text:` because the glyph needs a per-mode
    // colour and BarIconButton's built-in painter only offers foreground vs
    // activeColor. OpticalGlyph is what `text:` would have used anyway
    // (BarIconButton.qml:28-38), so the optical centring that Nerd Font
    // glyphs need is preserved.
    iconComponent: Component {
      Item {
        OpticalGlyph {
          anchors.fill: parent
          text: svc.glyph
          fontFamily: root.fontFamily
          fontSize: Style.bar.iconFont
          color: root.barColorFor(svc.mode)
          Behavior on color { ColorAnimation { duration: 160 } }
        }
      }
    }

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) svc.cycle(1)        // next mode, no panel
      else if (buttonCode === Qt.MiddleButton) svc.reload()  // re-read the file
      else root.toggle()
    }
    onWheelMoved: function(delta) { svc.cycle(delta > 0 ? -1 : 1) }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(320))
    // Five fixed rows: no Flickable needed, so the card just fits its column
    // (same as plugins/panels/power/Panel.qml:269).
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      // Digits only. PanelKeyCatcher already claims h/j/k/l for movement and
      // x for delete (PanelKeyCatcher.qml:59-80), so letter shortcuts like
      // "l" for local would never reach onTextKey.
      onTextKey: function(t) {
        var n = parseInt(t, 10)
        // rowsFor emite `key`, nunca `code` — o atalho de dígito estava morto
        // desde sempre (rows[n-1].code === undefined). E como agora as linhas
        // são um editor, o dígito tem que agir na LINHA, não procurar um "+".
        if (isFinite(n) && n >= 1 && n <= root.rows.length) root.applyRow(root.rows[n - 1])
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        // `detail` fica VAZIO de propósito. PanelHero põe título e pill na mesma
        // Row (PanelHero.qml:46-84) e dá ao título
        // `min(implicitWidth, parent.width − pill)` — com a pill de 230px sobravam
        // 65.05px para os 67.16px de "Voxtype", que virava "Voxty…". Empilhar
        // desacopla: cada um ganha a largura inteira e nenhum elide, por mais
        // longa que a pipeline fique.
        //
        // O ícone é IDENTIDADE FIXA, não o modo. Antes era svc.glyph, então o
        // mesmo elemento tentava dizer "isto é o voxtype" e "o modo é auto" ao
        // mesmo tempo — e o glyph de "auto" era md-refresh, que quer dizer
        // "recarregar". O modo já está escrito no chip logo abaixo.
        PanelHero {
          width: parent.width
          title: "Voxtype"
          detail: ""
          meta: svc.fileReadable ? "" : "mode file missing — wrapper falls back to auto"
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconOpacity: svc.mode === "off" ? 0.5 : 1.0
          iconComponent: Component {
            Text {
              text: Model.G.identity
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
        }

        // A pipeline, em linha própria e largura inteira.
        BorderSurface {
          width: parent.width
          implicitHeight: pipeText.implicitHeight + Style.space(8)
          color: "transparent"
          borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
          radius: Style.cornerRadius

          Text {
            id: pipeText
            anchors.centerIn: parent
            width: parent.width - Style.space(16)
            text: svc.label
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }
        }

        PanelSeparator { foreground: root.foreground }

        // ── histórico ────────────────────────────────────────────────
        // Duas ações numa linha só: o histórico não é um estágio da pipeline,
        // então não entra na lista de baixo.
        Row {
          width: parent.width
          spacing: Style.space(10)

          Repeater {
            model: [
              { g: "󰋚", t: "histórico",      act: "open" },   // U+F02DA md-history
              { g: "󰆏", t: "copiar último", act: "last"  }    // U+F018F md-content_copy
            ]
            CursorSurface {
              required property var modelData
              width: (parent.width - Style.space(10)) / 2
              implicitHeight: Style.space(38)
              foreground: root.foreground
              fill: root.hoverFill
              hasCursor: actMa2.containsMouse

              Row {
                anchors.centerIn: parent
                spacing: Style.space(8)
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.g
                  color: actMa2.containsMouse ? root.foreground : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.icon
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.t
                  color: actMa2.containsMouse ? root.foreground : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
              }

              MouseArea {
                id: actMa2
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (modelData.act === "open") { root.close(); history.open() }
                  else { history.copyLatest(); root.close() }
                }
                PanelToolTip {
                  visible: actMa2.containsMouse
                  text: modelData.act === "open"
                        ? "Abre o histórico no meio da tela"
                        : "Copia o último ditado pro clipboard"
                }
              }
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        PanelSectionHeader {
          width: parent.width
          text: "POLISH MODE"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Column {
          id: modeColumn
          width: parent.width
          spacing: Style.space(6)

          Repeater {
            model: root.rows
            ModeRow {
              required property var modelData
              required property int index
              width: modeColumn.width
              item: modelData
              rowIndex: index
            }
          }
        }
      }
    }
  }

  component ModeRow: CursorSurface {
    id: modeRow
    property var item: null
    property int rowIndex: 0
    readonly property string code: item ? String(item.key) : ""
    // "stage" = está na pipeline; "add" = oferta pra acrescentar.
    readonly property bool isCurrent: item ? item.kind === "stage" : false
    // 0 nas linhas "+"; 1..N = posição na ordem de execução.
    readonly property int stageOrder: item ? Number(item.pos) : 0
    // '?' da spec: este passo só roda se o de cima tiver falhado.
    readonly property bool isFallback: item ? item.fallback === true : false
    readonly property bool canFallback: item ? item.canFallback === true : false

    // SEMPRE visíveis, esmaecidos — acendem no hover de cada um.
    //
    // Tentei revelar só na linha sob o cursor: fica mais limpo em repouso, mas
    // o painel passa a parecer que não tem controle nenhum, e o usuário abriu e
    // não achou nem as setas nem o paraquedas. Affordance escondida não é
    // affordance. O ruído dos ícones apagados é o preço de serem descobríveis.
    readonly property bool showControls: true

    // CursorSurface contract (CursorSurface.qml:4-13): never read containsMouse
    // for colour. Hover only moves the shared cursor; the paint derives from
    // hasCursor / current, which is what keeps a single highlight on screen.
    hasCursor: root.cursorActive && root.modeIndex === rowIndex
    current: isCurrent
    foreground: root.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    implicitHeight: rowInner.implicitHeight + Style.spacing.xl

    RowLayout {
      id: rowInner
      // ACIMA do MouseArea da linha, que é irmão deste RowLayout e declarado
      // depois — sem isto ele fica no topo da pilha e engole o clique das setas
      // antes delas verem qualquer coisa. z só ordena entre IRMÃOS, então pôr
      // z nos Text lá dentro não resolvia nada.
      // Text sem MouseArea não aceita evento, então o clique no vazio da linha
      // continua caindo no MouseArea de baixo, como antes.
      z: 5
      anchors.left: parent.left; anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10); anchors.rightMargin: Style.space(10)
      spacing: Style.space(10)

      // Ordem de execução: "1" "2" "3" nos estágios ligados, "·" nos desligados.
      Text {
        text: modeRow.stageOrder > 0 ? String(modeRow.stageOrder) : "·"
        color: modeRow.stageOrder > 0 ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        font.bold: modeRow.stageOrder > 0
        Layout.alignment: Qt.AlignVCenter
        Layout.preferredWidth: Style.space(14)
        horizontalAlignment: Text.AlignHCenter
      }

      Text {
        text: modeRow.item ? String(modeRow.item.glyph) : ""
        color: modeRow.isCurrent ? root.panelColorFor(modeRow.code) : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
        Layout.preferredWidth: Style.space(20)
        horizontalAlignment: Text.AlignHCenter
      }

      // UMA linha: só o nome. A segunda linha de descrição saiu — as 7 legendas
      // do painel elidiam TODAS em 320px, e legenda cortada não informa nada.
      // Censo dos painéis nativos do Omarchy: 0 de 12 linhas de lista carregam
      // descrição estática; as que têm segunda linha usam status ao vivo e
      // colapsam pra altura zero quando vazio. A descrição virou tooltip, que é
      // como a casa explica item (PanelToolTip, usado em bluetooth/dropbox).
      Text {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        text: modeRow.item ? String(modeRow.item.label) : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: modeRow.isCurrent
        elide: Text.ElideRight

        PanelToolTip {
          visible: rowMa.containsMouse && modeRow.item
          text: modeRow.item ? String(modeRow.item.hint) : ""
        }
      }

      // Liga/desliga "fallback do de cima" (o '?' da spec). Só aparece onde
      // faz sentido: a primeira linha não tem passo acima pra ter falhado, e
      // as linhas "+" nem estão na pipeline (canFallback vem falso nas duas).
      //
      // PARAQUEDAS, não seta. A seta circular anterior (md-arrow_up_circle)
      // dividia o EIXO DIRECIONAL com o chevron de mover, logo ao lado — as
      // duas apontavam pra cima e ela lia como um terceiro controle de
      // movimento. O paraquedas não tem eixo nenhum, tem silhueta de domo que
      // não se repete em lugar nenhum do painel, e a metáfora é exata: ninguém
      // abre paraquedas no caminho feliz.
      //
      // Visível quando a linha está sob o cursor OU quando está ligado — o
      // estado tem que se ler em repouso, senão o usuário não sabe qual passo
      // é reserva sem varrer o painel com o mouse.
      Text {
        visible: modeRow.canFallback && (modeRow.showControls || modeRow.isFallback)
        text: Model.G.fallback
        color: modeRow.isFallback || fbMa.containsMouse ? root.foreground : root.dim
        opacity: modeRow.isFallback ? 1.0 : (fbMa.containsMouse ? 1.0 : 0.65)
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        font.bold: modeRow.isFallback
        Layout.alignment: Qt.AlignVCenter
        MouseArea {
          id: fbMa
          anchors.fill: parent; anchors.margins: -Style.space(4)
          hoverEnabled: true; cursorShape: Qt.PointingHandCursor
          onClicked: root.toggleFallbackRow(modeRow.item)
          PanelToolTip {
            visible: fbMa.containsMouse
            text: modeRow.isFallback
                  ? "Passa a rodar sempre"
                  : "Só rodar se o passo anterior falhar"
          }
        }
      }

      // ▲▼ reordenam. z acima do MouseArea da linha, que cobre tudo e senão
      // engoliria estes cliques.
      // Hover por botão: apagado em repouso, aceso sob o mouse. O aviso do
      // CursorSurface sobre não ler containsMouse vale pra pintura da LINHA
      // (pra não ter dois destaques na tela) — um botão individual precisa
      // justamente do feedback próprio.
      Text {
        visible: modeRow.showControls && modeRow.item && modeRow.item.canUp
        text: Model.G.up
        color: upMa.containsMouse ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
        MouseArea {
          id: upMa
          anchors.fill: parent; anchors.margins: -Style.space(4)
          hoverEnabled: true; cursorShape: Qt.PointingHandCursor
          onClicked: root.moveRow(modeRow.item, -1)
          PanelToolTip { visible: upMa.containsMouse; text: "Subir um passo" }
        }
      }
      Text {
        visible: modeRow.showControls && modeRow.item && modeRow.item.canDown
        text: Model.G.down
        color: downMa.containsMouse ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
        MouseArea {
          id: downMa
          anchors.fill: parent; anchors.margins: -Style.space(4)
          hoverEnabled: true; cursorShape: Qt.PointingHandCursor
          onClicked: root.moveRow(modeRow.item, 1)
          PanelToolTip { visible: downMa.containsMouse; text: "Descer um passo" }
        }
      }

      // ✕ remove, + acrescenta. Tem MouseArea próprio: um ícone que parece
      // botão precisa funcionar como botão, não só decorar a linha.
      // O ✕ só na linha sob o cursor; o + da paleta fica sempre, porque ali é
      // a própria affordance da linha ("estes são os passos que dá pra somar").
      Text {
        visible: modeRow.isCurrent ? modeRow.showControls : true
        text: modeRow.isCurrent ? Model.G.remove : Model.G.add
        // vermelho no hover do ✕: a ação é destrutiva, o feedback avisa.
        color: actMa.containsMouse
               ? (modeRow.isCurrent ? root.urgent : root.foreground)
               : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
        MouseArea {
          id: actMa
          anchors.fill: parent; anchors.margins: -Style.space(4)
          hoverEnabled: true; cursorShape: Qt.PointingHandCursor
          onClicked: root.applyRow(modeRow.item)
          PanelToolTip {
            visible: actMa.containsMouse
            text: modeRow.isCurrent ? "Remover este passo" : "Acrescentar no fim"
          }
        }
      }
    }

    MouseArea {
      id: rowMa
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setCursor(modeRow.rowIndex)
      // applyRow, NÃO selectByCode: selectByCode procura a linha "+" com essa
      // key, então clicar numa linha de estágio ACRESCENTAVA outro em vez de
      // remover. Era o bug que enchia a spec de "sed".
      onClicked: root.applyRow(modeRow.item)
    }
  }
}
