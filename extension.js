// RubyNav Pro - Navegação AST por teclado (Ctrl+D / Ctrl+Shift+D)
// 100% estável no Linux/Wayland e sem mouse listeners.
// Lista referências e definições com PATH RELATIVO para máxima legibilidade.

const vscode = require("vscode");
const path = require("path");
const cp = require("child_process");

let serverProcess = null;
let statusBar = null;
let pending = {};
let fileWatcher = null;
let outputChannel = null;

function getOutputChannel() {
  if (!outputChannel) {
    // log: true integra com o sistema de níveis do VS Code (útil em "Output")
    outputChannel = vscode.window.createOutputChannel("RubyNav", { log: true });
  }
  return outputChannel;
}

function rubyNavDebugEnabled() {
  try {
    return !!vscode.workspace.getConfiguration("rubyNav").get("debug");
  } catch (_) {
    return false;
  }
}

function logRubyNav(line) {
  const text =
    typeof line === "string" ? line : JSON.stringify(line);
  getOutputChannel().appendLine(text);
}

/** Raiz do workspace para `cwd` do Ruby (`Dir.pwd` = ROOT do indexador). */
function workspaceRootForServer() {
  const folders = vscode.workspace.workspaceFolders;
  if (folders && folders.length > 0) {
    return folders[0].uri.fsPath;
  }
  return vscode.workspace.rootPath || undefined;
}

//
// -------------------------------
// Utils
// -------------------------------
//

function pathRelative(abs) {
  const ws = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
  if (!ws) return abs;
  if (!abs) return abs;

  const normalizedWs = ws.replace(/\\/g, "/");
  const normalizedAbs = abs.replace(/\\/g, "/");

  if (normalizedAbs.startsWith(normalizedWs)) {
    return normalizedAbs.substring(normalizedWs.length + 1);
  }

  return normalizedAbs;
}

function sendRequest(obj, timeout = 15000) {
  return new Promise((resolve) => {
    const id = Math.random().toString(36).slice(2);
    const command = obj.command;
    pending[id] = { resolve, command };
    obj.id = id;

    if (rubyNavDebugEnabled()) {
      logRubyNav(`→ ${JSON.stringify(obj)}`);
    }

    try {
      if (!serverProcess || !serverProcess.stdin) {
        if (rubyNavDebugEnabled()) {
          logRubyNav("(pedido ignorado: processo Ruby não está ativo)");
        }
        pending[id].resolve(null);
        delete pending[id];
        return;
      }
      serverProcess.stdin.write(JSON.stringify(obj) + "\n");

      setTimeout(() => {
        if (pending[id]) {
          if (rubyNavDebugEnabled()) {
            logRubyNav(`(timeout ${timeout} ms) command=${command}`);
          }
          pending[id].resolve(null);
          delete pending[id];
        }
      }, timeout);
    } catch (e) {
      if (rubyNavDebugEnabled()) {
        logRubyNav(`(erro ao enviar) ${e && e.message}`);
      }
      if (pending[id]) {
        pending[id].resolve(null);
        delete pending[id];
      }
    }
  });
}

function handleServerOutput(data) {
  const lines = data.toString().split(/\n+/).filter(Boolean);

  for (const l of lines) {
    let msg = null;
    try {
      msg = JSON.parse(l);
    } catch (_) {
      continue;
    }

    if (msg.event === "index_progress") {
      const pct = Math.floor((msg.done / Math.max(msg.total || 1, 1)) * 100);
      statusBar.text = `$(sync~spin) RubyNav: indexando... ${pct}%`;
      statusBar.show();
      continue;
    }

    if (msg.event === "index_done") {
      statusBar.text = "$(check) RubyNav pronto";
      setTimeout(() => statusBar.hide(), 4000);
      continue;
    }

    if (msg.reply && pending[msg.reply]) {
      const cmd = pending[msg.reply].command;
      if (rubyNavDebugEnabled() && cmd) {
        logRubyNav(`← ${cmd} ${JSON.stringify(msg.result)}`);
      }
      pending[msg.reply].resolve(msg.result);
      delete pending[msg.reply];
    }
  }
}

//
// -------------------------------
// Symbol extraction with receiver
// -------------------------------
//

/**
 * Com o cursor em `def` / `class` / `module`, o VS Code devolve a palavra-chave, não o nome definido.
 * Expandimos para o método ou constante (ex.: def load_object → load_object).
 */
function rubyKeywordExpandToDefinedName(document, position, word) {
  const line = document.lineAt(position.line).text;
  const s = line.replace(/^\s+/, "");

  if (word === "def") {
    let m = s.match(/^def\s+self\.([a-zA-Z_][\w]*[!?=]?)\b/);
    if (m) return m[1];
    m = s.match(/^def\s+([a-zA-Z_][\w]*[!?=]?)\b/);
    if (m) return m[1];
  }
  if (word === "defs") {
    const m = s.match(/^defs\s+[^:]+:\s*([a-zA-Z_][\w]*[!?=]?)\b/);
    if (m) return m[1];
  }
  if (word === "class") {
    if (/^\s*class\s*<<\s*/.test(line)) return word;
    const m = s.match(/^class\s+([A-Z][A-Za-z0-9_:]*)\b/);
    if (m) return m[1];
  }
  if (word === "module") {
    const m = s.match(/^module\s+([A-Z][A-Za-z0-9_:]*)\b/);
    if (m) return m[1];
  }
  return word;
}

function extractSymbolWithReceiver(doc, pos) {
  // 1. Pegar a palavra completa sob o cursor (ex: "call", "@origin", "valid?")
  const wordRange = doc.getWordRangeAtPosition(pos, /[@A-Za-z0-9_!?]+/);
  if (!wordRange) return { word: null, receiver: null };

  let word = doc.getText(wordRange);
  word = rubyKeywordExpandToDefinedName(doc, pos, word);

  // 2. Olhar o texto ANTES do início da palavra
  const lineText = doc.lineAt(pos.line).text;
  const textBeforeWord = lineText.substring(0, wordRange.start.character);

  // 3. Extrair receiver antes da palavra
  // Padrão: Foo::Bar::Baz.method ou Foo.method ou Foo::Bar::method
  // Aceita ponto (.) ou dois pontos (::) como separador final
  const receiverPattern = /([A-Z][A-Za-z0-9_]*(?:::[A-Z][A-Za-z0-9_]*)*)[\.\s:]*$/;
  const receiverMatch = receiverPattern.exec(textBeforeWord);

  let receiver = null;
  if (receiverMatch) {
    receiver = receiverMatch[1].trim();
  }

  return { word, receiver };
}

/** Monta o pedido `definition` ao servidor (ou null se não há símbolo). */
function buildDefinitionRequest(document, position) {
  const { word, receiver } = extractSymbolWithReceiver(document, position);
  if (!word) return null;
  return {
    command: "definition",
    word,
    receiver,
    file: document.uri.fsPath,
    line: position.line + 1,
    col: position.character,
  };
}

/** Palavra + receiver para `references` (com fallback de intervalo). */
function extractReferenceWord(document, position) {
  let { word, receiver } = extractSymbolWithReceiver(document, position);
  if (!word) {
    const range = document.getWordRangeAtPosition(
      position,
      /[A-Za-z0-9_:!?]+/
    );
    if (!range) return { word: null, receiver: null };
    word = document.getText(range);
    word = rubyKeywordExpandToDefinedName(document, position, word);
  }
  return { word, receiver };
}

function buildReferencesRequest(document, position) {
  const { word, receiver } = extractReferenceWord(document, position);
  if (!word) return null;
  return {
    command: "references",
    symbol: word,
    receiver,
    file: document.uri.fsPath,
    line: position.line + 1,
    col: position.character,
  };
}

/** Chave estável para o mesmo sítio físico (evita 5 itens para o mesmo `def`). */
function definitionResultSiteKey(r) {
  if (!r || typeof r.path !== "string") return null;
  const norm = r.path.replace(/\\/g, "/");
  return `${norm}\t${r.line ?? 1}\t${r.col ?? 0}`;
}

/** Mantém a primeira ocorrência por sítio (ordem do servidor = prioridade). */
function dedupeDefinitionResponses(resp) {
  if (resp == null) return null;
  const arr = Array.isArray(resp) ? resp : [resp];
  const map = new Map();
  for (const r of arr) {
    const k = definitionResultSiteKey(r);
    if (!k) continue;
    if (!map.has(k)) map.set(k, r);
  }
  return [...map.values()];
}

/** Converte resposta do servidor em `vscode.Location[]` (range mínimo na coluna). */
function definitionResultToLocations(result, wordLength) {
  if (!result) return [];
  const list = Array.isArray(result) ? result : [result];
  const len = Math.max(1, wordLength || 1);
  return list
    .filter((r) => r && typeof r.path === "string")
    .map((r) => {
      const line = (r.line || 1) - 1;
      const col = r.col || 0;
      return new vscode.Location(
        vscode.Uri.file(r.path),
        new vscode.Range(line, col, line, col + len)
      );
    });
}

function referenceResultToLocations(rows, wordLength) {
  if (!rows || !rows.length) return [];
  const len = Math.max(1, wordLength || 1);
  return rows
    .filter((r) => r && typeof r.path === "string")
    .map((r) => {
      const line = (r.line || 1) - 1;
      const col = r.col || 0;
      return new vscode.Location(
        vscode.Uri.file(r.path),
        new vscode.Range(line, col, line, col + len)
      );
    });
}

async function requestDefinition(document, position) {
  const payload = buildDefinitionRequest(document, position);
  if (!payload) return null;
  return sendRequest(payload);
}

/** Abre editor / QuickPick a partir da resposta bruta do servidor (comandos manuais). */
async function navigateToDefinitionResponse(resp) {
  if (!resp) return;

  const uniq = dedupeDefinitionResponses(resp);
  if (!uniq || uniq.length === 0) return;

  // 1 sítio físico → abre direto (vários aliases no índice colapsam aqui)
  if (uniq.length === 1) {
    const r = uniq[0];
    const uri = vscode.Uri.file(r.path);
    const targetPos = new vscode.Position((r.line || 1) - 1, r.col || 0);
    vscode.window.showTextDocument(uri, {
      selection: new vscode.Range(targetPos, targetPos),
    });
    return;
  }

  // Vários sítios distintos → QuickPick (lista já deduplicada)
  if (uniq.length > 1) {
    const formatLabel = (r) => {
      if (r && r.fq && r.type === "method") {
        const parts = r.fq.split("::");
        if (parts.length > 1) {
          const methodName = parts.pop();
          return `${parts.join("::")}#${methodName}`;
        }
      }
      return r.fq || pathRelative(r.path);
    };

    const picks = uniq.map((r) => ({
      label: formatLabel(r),
      description: `${pathRelative(r.path)}:${r.line}`,
      data: r,
    }));

    const pick = await vscode.window.showQuickPick(picks, {
      placeHolder: "Selecione a definição",
    });

    if (!pick) return;

    const r = pick.data;
    const uri = vscode.Uri.file(r.path);
    const goto = new vscode.Position((r.line || 1) - 1, r.col || 0);

    vscode.window.showTextDocument(uri, {
      selection: new vscode.Range(goto, goto),
    });
  }
}

async function provideRubyNavDefinition(document, position, _token) {
  if (!serverProcess) return null;
  const { word } = extractSymbolWithReceiver(document, position);
  const resp = await requestDefinition(document, position);
  if (!resp) return null;
  const uniq = dedupeDefinitionResponses(resp);
  const locs = definitionResultToLocations(uniq, word ? word.length : 1);
  return locs.length === 0 ? null : locs.length === 1 ? locs[0] : locs;
}

//
// -------------------------------
// Go to Definition (Ctrl+D)
// -------------------------------
//

async function goToDefinitionManual() {
  const editor = vscode.window.activeTextEditor;
  if (!editor) return;

  const pos = editor.selection.active;
  const doc = editor.document;

  const resp = await requestDefinition(doc, pos);
  await navigateToDefinitionResponse(resp);
}

//
// -------------------------------
// Show References (Ctrl+Shift+D)
// -------------------------------
//

async function provideRubyNavReferences(document, position, _context, _token) {
  if (!serverProcess) return null;
  const { word } = extractReferenceWord(document, position);
  const payload = buildReferencesRequest(document, position);
  if (!payload) return null;
  const resp = await sendRequest(payload);
  if (!resp || !resp.length) return null;
  return referenceResultToLocations(resp, word ? word.length : 1);
}

//
// -------------------------------
// Show References (Ctrl+Shift+D)
// -------------------------------
//

async function showReferences() {
  const editor = vscode.window.activeTextEditor;
  if (!editor) return;

  const pos = editor.selection.active;
  const doc = editor.document;

  const { word } = extractReferenceWord(doc, pos);
  if (!word) return;

  const payload = buildReferencesRequest(doc, pos);
  if (!payload) return;

  const resp = await sendRequest(payload);

  if (!resp || resp.length === 0) {
    vscode.window.showInformationMessage(
      "Nenhuma referência encontrada para " + word
    );
    return;
  }

  // Agrupar referências por arquivo e, dentro do arquivo, por "classe/método"
  const grouped = new Map();

  for (const r of resp) {
    const fileKey = pathRelative(r.path || "(desconhecido)");
    if (!grouped.has(fileKey)) grouped.set(fileKey, []);
    grouped.get(fileKey).push(r);
  }

  const items = [];

  const classify = (r) => {
    if (r.fq) return r.fq;
    if (r.receiver && r.method) return `${r.receiver}#${r.method}`;
    if (r.type === "route") return "Rotas";
    return "Uso";
  };

  for (const [fileKey, refs] of grouped.entries()) {
    // Cabeçalho do arquivo: "### caminho/relativo"
    items.push({
      label: `### ${fileKey}`,
      description: "",
      data: null,
    });

    const byClass = new Map();
    for (const r of refs) {
      const key = classify(r);
      if (!byClass.has(key)) byClass.set(key, []);
      byClass.get(key).push(r);
    }

    for (const [clsKey, clsRefs] of byClass.entries()) {
      // Cabeçalho de classe/método: "# Classe - Método"
      const headerLabel = clsKey.includes("#")
        ? `# ${clsKey.replace("#", " - ")}`
        : `# ${clsKey}`;

      items.push({
        label: headerLabel,
        description: "",
        data: null,
      });

      for (const r of clsRefs) {
        items.push({
          label: `- ${r.preview || r.label || "(sem preview)"}`,
          description: `${pathRelative(r.path)}:${r.line || 1}`,
          data: r,
        });
      }
    }
  }

  // Usar QuickPick com "grupos" visuais via separadores
  const qpItems = [];
  for (const it of items) {
    if (it.data === null) {
      // Cabeçalhos viram separadores
      qpItems.push({
        label: it.label.replace(/^#+\s*/, ""),
        kind: vscode.QuickPickItemKind.Separator,
      });
    } else {
      qpItems.push(it);
    }
  }

  const qp = vscode.window.createQuickPick();
  qp.items = qpItems;
  qp.matchOnDescription = true;
  qp.placeholder = `Referências para ${word}`;

  qp.onDidChangeSelection(async (selection) => {
    const picked = selection[0];
    if (!picked || !picked.data) return;

    const r = picked.data;
    const uri = vscode.Uri.file(r.path);
    const docTarget = await vscode.workspace.openTextDocument(uri);

    const targetPos = new vscode.Position(
      (r.line || 1) - 1,
      r.col || 0
    );

    vscode.window.showTextDocument(docTarget, {
      selection: new vscode.Range(targetPos, targetPos),
    });

    qp.hide();
  });

  qp.show();
  return;
  // (código de navegação foi movido para o handler do QuickPick acima)
}

//
// -------------------------------
// Server spawn
// -------------------------------
//

function spawnServer() {
  console.log("[ruby-nav] spawnServer called");

  const serverPath = path.join(__dirname, "server", "server.rb");
  const cwd = workspaceRootForServer();
  const debug = rubyNavDebugEnabled();

  if (debug) {
    logRubyNav(
      `Iniciar servidor Ruby: cwd=${cwd || "(indefinido — abre uma pasta de workspace)"}`
    );
  }

  try {
    serverProcess = cp.spawn("ruby", [serverPath, "--index"], {
      stdio: ["pipe", "pipe", "pipe"],
      cwd: cwd || undefined,
      env: { ...process.env, RUBYNAV_DEBUG: debug ? "1" : "0" },
    });
  } catch (e) {
    console.error("[ruby-nav] spawn error (sync)", e);
    return;
  }

  serverProcess.on("error", (err) => {
    console.error("[ruby-nav] spawn error", err);
  });

  serverProcess.on("exit", (code, signal) => {
    console.error(
      "[ruby-nav] server exited",
      "code=",
      code,
      "signal=",
      signal
    );
  });

  serverProcess.stdout.on("data", handleServerOutput);
  serverProcess.stderr.on("data", (d) => {
    const s = d.toString();
    console.error("[ruby-nav-server]", s);
    if (rubyNavDebugEnabled()) {
      logRubyNav(`[stderr] ${s.replace(/\s+$/u, "")}`);
    }
  });
}

//
// -------------------------------
// Re-indexing functions
// -------------------------------
//

async function reindexFile(filePath) {
  if (!serverProcess) return;

  try {
    await sendRequest({
      command: "reindex_file",
      file: filePath,
    });
  } catch (e) {
    console.error("[ruby-nav] reindex_file error", e);
  }
}

async function reindexWorkspace() {
  if (!serverProcess) return;

  statusBar.text = "$(sync~spin) RubyNav: re-indexando...";
  statusBar.show();

  try {
    await sendRequest({
      command: "reindex_workspace",
    });
  } catch (e) {
    console.error("[ruby-nav] reindex_workspace error", e);
  }
}

//
// -------------------------------
// Extension activation
// -------------------------------
//

function activate(context) {
  console.log("[ruby-nav] activate called");

  statusBar = vscode.window.createStatusBarItem(
    vscode.StatusBarAlignment.Left,
    100
  );
  statusBar.text = "$(sync~spin) RubyNav: indexando...";
  statusBar.show();

  spawnServer();

  logRubyNav(
    '[RubyNav] Registo: View → Output → escolher o canal "RubyNav" (não aparece em "Developer: Show Logs"). Paleta: escrever "RubyNav log". Tráfego JSON: settings rubyNav.debug = true + Reload Window.'
  );

  if (rubyNavDebugEnabled()) {
    getOutputChannel().show(true);
    logRubyNav(
      "rubyNav.debug=true — pedidos/respostas e stderr Ruby. Para logs no servidor após mudar a opção, recarrega a janela (Developer: Reload Window)."
    );
  }

  // Configurar FileSystemWatcher para .rb e .erb
  const wsFolder = vscode.workspace.workspaceFolders?.[0];
  if (wsFolder) {
    const pattern = new vscode.RelativePattern(wsFolder, "**/*.{rb,erb}");
    fileWatcher = vscode.workspace.createFileSystemWatcher(pattern);

    // Debounce para evitar múltiplas re-indexações
    let reindexTimeout = null;
    const debouncedReindex = (uri) => {
      if (reindexTimeout) clearTimeout(reindexTimeout);
      reindexTimeout = setTimeout(() => {
        const filePath = uri.fsPath;
        // Ignorar arquivos de spec, test, vendor, node_modules
        if (
          (/\.(rb|erb)$/i.test(filePath)) &&
          !filePath.includes("/spec/") &&
          !filePath.includes("/test/") &&
          !filePath.includes("/vendor/") &&
          !filePath.includes("/node_modules/")
        ) {
          console.log("[ruby-nav] Re-indexing file:", filePath);
          reindexFile(filePath);
        }
      }, 500); // 500ms de debounce
    };

    fileWatcher.onDidCreate(debouncedReindex);
    fileWatcher.onDidChange(debouncedReindex);
    fileWatcher.onDidDelete((uri) => {
      const filePath = uri.fsPath;
      if (
        !/\.(rb|erb)$/i.test(filePath) ||
        filePath.includes("/spec/") ||
        filePath.includes("/test/") ||
        filePath.includes("/vendor/") ||
        filePath.includes("/node_modules/")
      ) {
        return;
      }
      console.log("[ruby-nav] File deleted:", filePath);
      reindexFile(filePath);
    });

    context.subscriptions.push(fileWatcher);
  }

  context.subscriptions.push(
    vscode.commands.registerCommand(
      "rubyNav.goToDefinitionManual",
      goToDefinitionManual
    ),
    vscode.commands.registerCommand(
      "rubyNav.showReferences",
      showReferences
    ),
    vscode.commands.registerCommand(
      "rubyNav.reindexWorkspace",
      reindexWorkspace
    ),
    vscode.commands.registerCommand("rubyNav.showOutput", () => {
      getOutputChannel().show(true);
    }),
    vscode.languages.registerDefinitionProvider(
      [
        { language: "ruby", scheme: "file" },
        { language: "erb", scheme: "file" },
      ],
      { provideDefinition: provideRubyNavDefinition }
    ),
    vscode.languages.registerReferenceProvider(
      [
        { language: "ruby", scheme: "file" },
        { language: "erb", scheme: "file" },
      ],
      { provideReferences: provideRubyNavReferences }
    ),
    statusBar
  );
}

function deactivate() {
  try {
    if (serverProcess) serverProcess.kill();
  } catch (_) { }
}

module.exports = { activate, deactivate };
