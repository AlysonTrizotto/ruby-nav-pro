// RubyNav Pro - Navegação AST por teclado (Ctrl+D / Ctrl+Shift+D)
// 100% estável no Linux/Wayland e sem mouse listeners.
// Lista referências e definições com PATH RELATIVO para máxima legibilidade.

const vscode = require("vscode");
const path = require("path");
const cp = require("child_process");

let serverProcess = null;
let statusBar = null;
let pending = {};

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
// Go to Definition (Ctrl+D)
// -------------------------------
//

async function goToDefinitionManual() {
  const editor = vscode.window.activeTextEditor;
  if (!editor) return;

  const pos = editor.selection.active;
  const doc = editor.document;
  const range = doc.getWordRangeAtPosition(pos);
  if (!range) return;

  const word = doc.getText(range);
  const file = doc.uri.fsPath;

  const resp = await sendRequest({
    command: "definition",
    word,
    file,
    line: pos.line + 1,
    col: pos.character,
  });

  if (!resp) return;

  // 1 RESULTADO → abre direto
  if (resp.path && typeof resp.path === "string") {
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
    const picks = resp.map((r) => ({
      label: r.fq || pathRelative(r.path),
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

  const range = doc.getWordRangeAtPosition(pos, /[A-Za-z0-9_:!?]+/);
  if (!range) return;

  const word = doc.getText(range);

  const resp = await sendRequest({
    command: "references",
    symbol: word,
  });

  if (!resp || resp.length === 0) {
    vscode.window.showInformationMessage(
      "Nenhuma referência encontrada para " + word
    );
    return;
  }

  const items = resp.map((r) => ({
    label: r.preview || r.label || pathRelative(r.path),
    description: `${pathRelative(r.path)}:${r.line}`,
    data: r,
  }));

  const pick = await vscode.window.showQuickPick(items, {
    placeHolder: `Referências para ${word}`,
  });

  if (!pick) return;

  const r = pick.data;
  const uri = vscode.Uri.file(r.path);
  const docTarget = await vscode.workspace.openTextDocument(uri);

  const targetPos = new vscode.Position(
    (r.line || 1) - 1,
    r.col || 0
  );

  vscode.window.showTextDocument(docTarget, {
    selection: new vscode.Range(targetPos, targetPos),
  });
}

//
// -------------------------------
// Server spawn
// -------------------------------
//

function spawnServer() {
  const serverPath = path.join(__dirname, "server", "server.rb");
  serverProcess = cp.spawn("ruby", [serverPath, "--index"], {
    stdio: ["pipe", "pipe", "pipe"],
    cwd: vscode.workspace.rootPath || process.cwd(),
  });

  serverProcess.stdout.on("data", handleServerOutput);
  serverProcess.stderr.on("data", (d) =>
    console.error("[ruby-nav-server]", d.toString())
  );
}

//
// -------------------------------
// Extension activation
// -------------------------------
//

function activate(context) {
  statusBar = vscode.window.createStatusBarItem(
    vscode.StatusBarAlignment.Left,
    100
  );
  statusBar.text = "$(sync~spin) RubyNav: indexando...";
  statusBar.show();

  spawnServer();

  context.subscriptions.push(
    vscode.commands.registerCommand(
      "rubyNav.goToDefinitionManual",
      goToDefinitionManual
    ),
    vscode.commands.registerCommand(
      "rubyNav.showReferences",
      showReferences
    ),
    statusBar
  );
}

function deactivate() {
  try {
    if (serverProcess) serverProcess.kill();
  } catch (_) {}
}

module.exports = { activate, deactivate };
