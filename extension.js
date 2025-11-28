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
    pending[id] = { resolve };
    obj.id = id;

    try {
      serverProcess.stdin.write(JSON.stringify(obj) + "\n");

      setTimeout(() => {
        if (pending[id]) {
          pending[id].resolve(null);
          delete pending[id];
        }
      }, timeout);
    } catch (e) {
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

function extractSymbolWithReceiver(doc, pos) {
  // 1. Pegar a palavra completa sob o cursor (ex: "call", "@origin", "valid?")
  const wordRange = doc.getWordRangeAtPosition(pos, /[@A-Za-z0-9_!?]+/);
  if (!wordRange) return { word: null, receiver: null };

  const word = doc.getText(wordRange);

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

  // Extrair símbolo completo com receiver (ex: Trips::CacheService.call)
  const { word, receiver } = extractSymbolWithReceiver(doc, pos);
  if (!word) return;

  const file = doc.uri.fsPath;

  const resp = await sendRequest({
    command: "definition",
    word,
    receiver, // Enviar receiver para contexto
    file,
    line: pos.line + 1,
    col: pos.character,
  });

  if (!resp) return;

  // 1 RESULTADO → abre direto
  if (Array.isArray(resp) && resp.length === 1) {
    const r = resp[0];
    const uri = vscode.Uri.file(r.path);
    const targetPos = new vscode.Position(
      (r.line || 1) - 1,
      r.col || 0
    );
    vscode.window.showTextDocument(uri, {
      selection: new vscode.Range(targetPos, targetPos),
    });
    return;
  }

  if (!Array.isArray(resp) && resp.path && typeof resp.path === "string") {
    const uri = vscode.Uri.file(resp.path);
    const targetPos = new vscode.Position(
      (resp.line || 1) - 1,
      resp.col || 0
    );
    vscode.window.showTextDocument(uri, {
      selection: new vscode.Range(targetPos, targetPos),
    });
    return;
  }

  // LISTA DE RESULTADOS
  if (Array.isArray(resp) && resp.length > 0) {
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

    const picks = resp.map((r) => ({
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

  // Extrair símbolo completo com receiver
  const symbolInfo = extractSymbolWithReceiver(doc, pos);
  let word = symbolInfo.word;
  const receiver = symbolInfo.receiver;

  // Se não conseguiu extrair com receiver, tentar com regex normal
  if (!word) {
    const range = doc.getWordRangeAtPosition(pos, /[A-Za-z0-9_:!?]+/);
    if (!range) return;
    word = doc.getText(range);
  }

  const resp = await sendRequest({
    command: "references",
    symbol: word,
    receiver: receiver, // Enviar receiver para contexto
    file: doc.uri.fsPath,
    line: pos.line + 1,
    col: pos.character,
  });

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
  try {
    serverProcess = cp.spawn("ruby", [serverPath, "--index"], {
      stdio: ["pipe", "pipe", "pipe"],
      cwd: vscode.workspace.rootPath || process.cwd(),
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
  serverProcess.stderr.on("data", (d) =>
    console.error("[ruby-nav-server]", d.toString())
  );
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

  // Configurar FileSystemWatcher para arquivos .rb
  const wsFolder = vscode.workspace.workspaceFolders?.[0];
  if (wsFolder) {
    // Pattern para arquivos .rb, excluindo vendor, node_modules, spec, test
    const pattern = new vscode.RelativePattern(wsFolder, "**/*.rb");
    fileWatcher = vscode.workspace.createFileSystemWatcher(pattern);

    // Debounce para evitar múltiplas re-indexações
    let reindexTimeout = null;
    const debouncedReindex = (uri) => {
      if (reindexTimeout) clearTimeout(reindexTimeout);
      reindexTimeout = setTimeout(() => {
        const filePath = uri.fsPath;
        // Ignorar arquivos de spec, test, vendor, node_modules
        if (
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
    statusBar
  );
}

function deactivate() {
  try {
    if (serverProcess) serverProcess.kill();
  } catch (_) { }
}

module.exports = { activate, deactivate };
