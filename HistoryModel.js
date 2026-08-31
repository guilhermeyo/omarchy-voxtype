// Parser + filtro do histórico de ditado.
//
// Fonte: ~/.local/state/voxtype/history.jsonl, escrito pelo wrapper
// ~/.local/bin/voxtype-punct — o único ponto do sistema que vê todo texto
// ditado (o voxtype não guarda histórico nativo; só meetings, em sqlite).
//
// Uma linha JSON por ditado:
//   {"t":"2026-07-31T00:02:41-03:00","spec":"sed+qwen+?gemini+sed",
//    "raw":"o que o Parakeet ouviu","text":"o que foi colado"}
//
// Estrutura copiada de plugins/clipboard/ClipboardHistory.js: JS puro, sem QML,
// e TOLERANTE A LIXO — linha malformada é pulada, exceção devolve lista vazia.
// Um painel que morre porque uma linha veio truncada seria pior que não ter
// painel nenhum.

// Mais novo primeiro. O arquivo é append-only, então a última linha é a última
// ditada — a lista é lida ao contrário.
function parseHistory(raw) {
  try {
    var lines = String(raw || "").split("\n");
    var out = [];
    for (var i = lines.length - 1; i >= 0; i--) {
      var line = lines[i];
      if (!line || !line.trim()) continue;
      var e = normalizeEntry(line);
      if (e) out.push(e);
    }
    return out;
  } catch (err) {
    return [];
  }
}

function normalizeEntry(line) {
  var o;
  try {
    o = JSON.parse(line);
  } catch (err) {
    return null;           // linha cortada no meio (append concorrente) — pula
  }
  if (!o || typeof o !== "object") return null;
  var text = String(o.text == null ? "" : o.text);
  if (!text.trim()) return null;
  return {
    text: text,
    raw: String(o.raw == null ? "" : o.raw),
    spec: String(o.spec == null ? "" : o.spec),
    when: shortTime(o.t),
    day: shortDay(o.t)
  };
}

// "2026-07-31T00:02:41-03:00" -> "00:02". Sem Date.parse: o offset com dois
// pontos (-03:00) quebra em alguns motores, e o formato aqui é fixo — quem
// escreve é `date -Is` no wrapper.
function shortTime(t) {
  var s = String(t || "");
  var m = s.match(/T(\d{2}):(\d{2})/);
  return m ? m[1] + ":" + m[2] : "";
}

function shortDay(t) {
  var s = String(t || "");
  var m = s.match(/^(\d{4})-(\d{2})-(\d{2})/);
  return m ? m[3] + "/" + m[2] : "";
}

// Preview de UMA linha: achata quebras de linha em espaço. Sem isto um ditado
// de 500 palavras com parágrafos viraria uma linha de altura variável e a
// ListView perde o alinhamento. Mesma decisão do clipboard nativo.
function previewOf(entry) {
  return String(entry && entry.text || "").replace(/\s+/g, " ");
}

// Filtro case-insensitive sobre o texto final E sobre o raw — procurar pelo que
// você FALOU acha mesmo quando o LLM reescreveu a frase.
function matches(entry, needle) {
  if (!needle) return true;
  var n = needle.toLowerCase();
  return String(entry.text || "").toLowerCase().indexOf(n) !== -1
      || String(entry.raw || "").toLowerCase().indexOf(n) !== -1;
}

// `index` é a posição no array ORIGINAL, não no filtrado. É o que permite
// copiar a entrada certa depois de digitar um filtro — no clipboard nativo esse
// campo existe pelo mesmo motivo.
function displayRows(history, filterText, limit) {
  var rows = [];
  var max = limit || 60;
  for (var i = 0; i < history.length && rows.length < max; i++) {
    var e = history[i];
    if (!matches(e, filterText)) continue;
    rows.push({
      index: i,
      when: e.when,
      day: e.day,
      spec: e.spec,
      previewText: previewOf(e),
      fullText: e.text,
      chars: e.text.length
    });
  }
  return rows;
}
