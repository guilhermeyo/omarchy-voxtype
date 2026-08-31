// Catalog + parser for the voxtype polish pipeline switcher.
//
// The mode file holds a SPEC: an ORDERED list of steps joined by '+', with
// repeats allowed. It mirrors ~/.local/bin/voxtype-punct exactly — the two
// parsers have to agree byte for byte.
//
// Each token is [?]<stage>, stage in { sed, qwen, gemini }. The '?' prefix
// means FALLBACK OF THE PREVIOUS STEP: the step only runs when the step above
// it failed (produced nothing usable).
//
//   sed+qwen              DEFAULT — this is DEFAULT_MODE below, and DEFAULT_SPEC
//                         in bin/voxtype-punct. No cloud stage: see the comment
//                         on DEFAULT_MODE for why the failure fallback may not
//                         reach the network.
//   sed+qwen+?gemini+sed  the `auto` alias plus a second sed pass, which catches
//                         proper nouns (geminai/paracut) that the LLM faithfully
//                         carried through from the transcript. Opt-in.
//   sed+qwen+gemini       NO '?': gemini runs ON TOP of qwen's output, two LLM
//                         passes. Legitimate option now, not a bug.
//   sed+gemini+?qwen      cloud first, local as the reserve.
//   off                   raw transcript
//
// The five legacy words still parse as aliases, so an old mode file keeps working:
//   off = <none>  local = sed  3090 = sed+qwen
//   gemini = sed+gemini        auto = sed+qwen+?gemini
//
// Never falls back to "raw": an unparseable spec becomes DEFAULT_MODE, because
// silently dropping punctuation is worse than the opposite.
//
// Glyphs are Nerd Fonts 3.4.0 MDI, verified present in the font this bar
// resolves to (BerkeleyMono Nerd Font, MDI block U+F0001-U+F1AF0). Written as
// literal UTF-8: astral codepoints truncate in the 4-hex \u form.

// DEFAULT_MODE tem que ser IGUAL ao DEFAULT_SPEC do voxtype-punct: é o que os
// dois usam quando o polish-mode some, vem vazio ou vem quebrado. Se divergirem,
// o painel mostra uma pipeline e o ditado roda outra — e ninguém percebe, porque
// as duas parecem plausíveis. Por isso NÃO tem nuvem aqui: um arquivo truncado
// não pode virar "manda todo o ditado pro Google" sem ninguém escolher isso.
// O apelido "auto" (em ALIASES) continua sendo sed+qwen+?gemini — a nuvem de
// reserva é uma escolha explícita do usuário, nunca um fallback de falha.
var DEFAULT_MODE = "sed+qwen";

// Vocabulário de glyphs. Nomes conferidos contra a charset CFF da própria
// fonte — os comentários antigos deste arquivo e do Panel.qml estavam errados
// (U+F0143 é chevron_up, não arrow_up_thick).
var G = {
  identity: "󰍬",   // U+F036C md-microphone      — identidade do painel
  off:      "󰍭",   // U+F036D md-microphone_off  — mesma família do identity
  sed:      "󰑑",   // U+F0451 md-regex           — sed É substituição por regex
  qwen:     "󰢮",   // U+F08AE md-expansion_card  — a GPU
  gemini:   "󰅟",   // U+F015F md-cloud
  fallback: "󰲴",   // U+F0CB4 md-parachute       — reserva que só abre se falhar
  up:       "󰅃",   // U+F0143 md-chevron_up
  down:     "󰅀",   // U+F0140 md-chevron_down
  remove:   "󰅖",   // U+F0156 md-close
  add:      "󰐕"    // U+F0415 md-plus
};

// hint NÃO é renderizado em linha nenhuma — vira tooltip. O painel mostra só
// nome + ícone, como fazem 12 de 12 linhas de lista dos painéis nativos.
var STAGES = [
  { key: "sed",    label: "sed",    glyph: G.sed,    hint: "Correções fixas de transcrição. Offline, não pontua." },
  { key: "qwen",   label: "qwen",   glyph: G.qwen,   hint: "O seu endpoint de LLM (llm.conf). Local: ~250ms." },
  { key: "gemini", label: "gemini", glyph: G.gemini, hint: "Nuvem. Cobra por token e o texto sai da máquina." }
];

// O glyph de um preset é o do CAMINHO PRIMÁRIO — o estágio que roda de verdade
// quando nada falha. Antes o preset "auto" usava md-refresh só pra dizer "tem
// dois LLMs", anunciando um caminho (a nuvem) que com o '?' não acontece.
var MODES = [
  { code: "off",              label: "Off",      glyph: G.off,    hint: "Transcript cru" },
  { code: "sed",              label: "Local",    glyph: G.sed,    hint: "Só sed, nada sai da máquina" },
  { code: "sed+qwen",         label: "LLM",      glyph: G.qwen,   hint: "sed + o seu endpoint de LLM" },
  { code: "sed+gemini",       label: "Gemini",   glyph: G.gemini, hint: "sed + Gemini (nuvem)" },
  { code: "sed+qwen+?gemini", label: "Auto",     glyph: G.qwen,   hint: "sed + o seu LLM, nuvem de reserva" }
];

var ALIASES = {
  "off": "", "local": "sed", "3090": "sed+qwen",
  "gemini": "sed+gemini", "auto": "sed+qwen+?gemini"
};

function stageDef(key) {
  for (var i = 0; i < STAGES.length; i++) if (STAGES[i].key === key) return STAGES[i];
  return null;
}

// ---- spec <-> ordered step list ------------------------------------------
//
// Internal representation: ordered array of { key, fallback }. Order is
// execution order; `fallback` is the '?' prefix.

function mkStep(key, fallback) { return { key: key, fallback: !!fallback } }

// A '?' on the FIRST step is meaningless — there is no step above it to have
// failed — so it is dropped. Applied on both parse and serialize so an edit
// that drags a fallback step to the top cannot produce a bogus spec.
function dropLeadingFallback(list) {
  if (list.length) list[0].fallback = false;
  return list;
}

// Ordered, WITH repeats.
function stagesOf(spec) {
  var s = String(spec === undefined || spec === null ? "" : spec);
  // [ \t\n\r\f\v] explicitamente, NÃO \s: o \s do JS inclui NBSP (U+00A0) e o
  // [[:space:]] do glibc no bash NÃO. Com \s os dois parsers discordavam numa
  // spec que tivesse NBSP — o painel mostrava uma coisa e o ditado fazia outra.
  s = s.split("\n")[0].replace(/[ \t\n\r\f\v]+/g, "").toLowerCase();
  // "off" desliga explicitamente; "" é arquivo vazio/ilegível, que o wrapper
  // trata como default. Os dois não podem colapsar no mesmo caso.
  if (s === "off") return [];
  // hasOwnProperty, NÃO `in`: `in` percorre a cadeia de protótipos, então
  // "constructor" e "__proto__" (as únicas chaves de Object.prototype 100%
  // minúsculas, e a spec já veio minusculizada) casavam e `s` virava função —
  // `s.split` explodia e derrubava o parser do painel.
  if (Object.prototype.hasOwnProperty.call(ALIASES, s)) s = ALIASES[s];
  if (s === "") return stagesOf(DEFAULT_MODE);
  var parts = s.split("+"), out = [], ok = true;
  for (var i = 0; i < parts.length; i++) {
    var p = parts[i];
    if (p === "") continue;              // "+gemini" = spec explícita, não apelido
    var fb = false;
    if (p.charAt(0) === "?") { fb = true; p = p.substring(1) }
    if (p === "3090") p = "qwen";
    // Um "?" pelado não nomeia estágio nenhum: é token desconhecido, não token
    // vazio, então invalida a spec inteira (cai no default, nunca no cru).
    if (p !== "" && stageDef(p)) out.push(mkStep(p, fb)); else ok = false;
  }
  // Spec que só tem separador ("+", "++") sobrevive ao laço com out=[] e
  // ok=true, e [] é a representação de "off" — ou seja, uma spec sem sentido
  // DESLIGARIA o polimento em silêncio. Só "off" desliga. Espelha a guarda da
  // linha 70 do voxtype-punct.
  if (!out.length) return stagesOf(DEFAULT_MODE);
  return ok ? dropLeadingFallback(out) : stagesOf(DEFAULT_MODE);
}

// Nunca devolve "": o arquivo precisa dizer "off", senão o wrapper lê
// arquivo-vazio e cai no default. E "gemini" sozinho colidiria com o apelido
// legado (= sed+gemini), então recebe um '+' na frente.
function specOf(list) {
  if (!list.length) return "off";
  dropLeadingFallback(list);
  var parts = [];
  for (var i = 0; i < list.length; i++) {
    parts.push((list[i].fallback ? "?" : "") + list[i].key);
  }
  var s = parts.join("+");
  return s === "gemini" ? "+gemini" : s;
}

function parseMode(raw) { return specOf(stagesOf(raw)) }
function isValid() { return true }

// ---- edições da pipeline -------------------------------------------------

function removeAt(spec, i) {
  var l = stagesOf(spec);
  if (i < 0 || i >= l.length) return specOf(l);
  l.splice(i, 1);
  return specOf(l);
}

// A flag viaja junto com a linha; se ela parar no topo, specOf tira o '?'.
function moveAt(spec, i, delta) {
  var l = stagesOf(spec);
  var j = i + delta;
  if (i < 0 || i >= l.length || j < 0 || j >= l.length) return specOf(l);
  var tmp = l[i]; l[i] = l[j]; l[j] = tmp;
  return specOf(l);
}

function appendStage(spec, key) {
  if (!stageDef(key)) return specOf(stagesOf(spec));
  var l = stagesOf(spec);
  l.push(mkStep(key, false));            // entra como passo normal; '?' é um toggle
  return specOf(l);
}

function toggleFallback(spec, i) {
  var l = stagesOf(spec);
  if (i <= 0 || i >= l.length) return specOf(l);   // slot 0 não tem passo acima
  l[i].fallback = !l[i].fallback;
  return specOf(l);
}

// ---- linhas do painel ----------------------------------------------------

// Uma lista só, pro Repeater: primeiro a pipeline atual (ordenada, com
// repetições), depois os estágios disponíveis para acrescentar no fim.
function rowsFor(spec) {
  var l = stagesOf(spec), rows = [], i;
  for (i = 0; i < l.length; i++) {
    var d = stageDef(l[i].key);
    rows.push({
      kind: "stage", key: l[i].key, slot: i, pos: i + 1,
      label: d.label, glyph: d.glyph,
      // hint agora é TOOLTIP, não segunda linha. Toda legenda deste painel
      // elidia em 320px — 7 de 7 — e legenda cortada não informa nada.
      hint: l[i].fallback ? d.hint + "  ·  só roda se o passo anterior falhar" : d.hint,
      fallback: l[i].fallback,
      canFallback: i > 0,              // primeira linha não tem passo acima
      canUp: i > 0, canDown: i < l.length - 1
    });
  }
  for (i = 0; i < STAGES.length; i++) {
    rows.push({
      kind: "add", key: STAGES[i].key, slot: -1, pos: 0,
      label: "+ " + STAGES[i].label, glyph: STAGES[i].glyph,
      hint: "acrescenta no fim · " + STAGES[i].hint,
      fallback: false, canFallback: false, canUp: false, canDown: false
    });
  }
  return rows;
}

// ---- ícone da barra ------------------------------------------------------

function indexOfMode(code) {
  var c = parseMode(code);
  for (var i = 0; i < MODES.length; i++) if (MODES[i].code === c) return i;
  return -1;
}

function hasStage(list, key) {
  for (var i = 0; i < list.length; i++) if (list[i].key === key) return true;
  return false;
}

function entryFor(code) {
  var i = indexOfMode(code);
  if (i !== -1) return MODES[i];
  var on = stagesOf(code);
  var hasFb = false;
  for (i = 0; i < on.length; i++) if (on[i].fallback) hasFb = true;
  return {
    code: parseMode(code),
    label: pipelineLabel(on),
    hint: !on.length ? "sem polimento"
        : hasFb ? "o passo após " + G.fallback + " só roda se o anterior falhar"
        : "pipeline personalizada",
    glyph: primaryGlyph(on)
  };
}

// Rótulo da pipeline. O '?' saiu: a relação "só se o anterior falhar" é ENTRE
// dois passos, então mora no CONECTOR, não colada no nome do passo. Mesmo
// símbolo que o toggle da linha usa, então a notação se explica sozinha.
// Espaço duplo em volta do glyph porque o avanço da Nerd Font é apertado e
// sem folga ele encosta no texto.
function pipelineLabel(list) {
  if (!list.length) return "Off";
  var out = "";
  for (var i = 0; i < list.length; i++) {
    if (i > 0) out += list[i].fallback ? "  " + G.fallback + "  " : " → ";
    out += list[i].key;
  }
  return out;
}

// Glyph da BARRA: o estágio que roda no caminho feliz. Um passo marcado como
// fallback não representa a pipeline — ele é a exceção, não a regra.
function primaryGlyph(list) {
  var i;
  // A nuvem SEM '?' ganha de tudo: significa que o ditado sai da máquina em
  // toda ditada. Esse é o sinal que o usuário precisa ver de relance na barra,
  // acima de qual LLM entrega o texto final.
  for (i = 0; i < list.length; i++)
    if (!list[i].fallback && list[i].key === "gemini") return G.gemini;
  for (i = 0; i < list.length; i++)
    if (!list[i].fallback && list[i].key === "qwen") return G.qwen;
  for (i = 0; i < list.length; i++)          // pipeline só de fallbacks
    if (list[i].key === "qwen" || list[i].key === "gemini") return G[list[i].key];
  return list.length ? G.sed : G.off;
}

function labelFor(code) { return entryFor(code).label }
function glyphFor(code) { return entryFor(code).glyph }
function hintFor(code)  { return entryFor(code).hint }

// Botão direito / scroll continuam ciclando os 5 presets — volta rápida a uma
// combinação conhecida sem abrir o painel.
// A âncora de uma spec que não é preset é o FIM da lista, não o DEFAULT_MODE:
// assim um scroll pra frente cai em MODES[0] (Off, offline), que é o destino
// seguro. Ancorar no DEFAULT_MODE amarrava o ciclo à posição desse preset na
// lista, então mudar o default movia silenciosamente onde o scroll aterrissa —
// e com sed+qwen na posição 2 um scroll pra frente cairia em sed+gemini, ou
// seja, mandaria o ditado pra nuvem por causa de um giro de dedo.
function nextMode(code, step) {
  var n = MODES.length;
  var d = (step === undefined || step === null || !isFinite(step)) ? 1 : Math.round(step);
  var i = indexOfMode(code);
  if (i === -1) i = n - 1;
  return MODES[((i + d) % n + n) % n].code;
}
