// Drives one language server over stdio and checks that it answers.
// Node standard library only: Content-Length framing, JSON-RPC 2.0.
//
// usage: node lsp-probe.mjs --root <dir> --file <rel> --def <line:char>
//          --expect <rel>:<line> [--language <id>] [--timeout <seconds>]
//          -- <server> [args...]
//
// 1. initialize, initialized, textDocument/didOpen of --file.
// 2. Waits for a publishDiagnostics for that file with an error (severity 1).
// 3. textDocument/definition at --def (0-based line:char) must land on
//    --expect (file relative to --root, 0-based line).
// 4. shutdown, exit. Exit 0 when all of it held, 1 on a miss, 2 on bad usage.
import { spawn } from "node:child_process";
import { readFileSync } from "node:fs";
import { resolve, join } from "node:path";
import { pathToFileURL, fileURLToPath } from "node:url";

function usage() {
  console.error(
    "usage: lsp-probe.mjs --root <dir> --file <rel> --def <line:char> --expect <rel>:<line> [--language <id>] [--timeout <s>] -- <server> [args...]",
  );
  process.exit(2);
}

const argv = process.argv.slice(2);
const dash = argv.indexOf("--");
if (dash < 0 || dash === argv.length - 1) usage();
const opts = {};
for (let i = 0; i < dash; i += 2) {
  if (!argv[i].startsWith("--") || i + 1 >= dash) usage();
  opts[argv[i].slice(2)] = argv[i + 1];
}
const cmd = argv.slice(dash + 1);
for (const k of ["root", "file", "def", "expect"]) if (!opts[k]) usage();

const root = resolve(opts.root);
const rootUri = pathToFileURL(root).href;
const fileUri = pathToFileURL(join(root, opts.file)).href;
const [defLine, defChar] = opts.def.split(":").map(Number);
const expectAt = opts.expect.lastIndexOf(":");
const expectFile = join(root, opts.expect.slice(0, expectAt));
const expectLine = Number(opts.expect.slice(expectAt + 1));
const timeoutMs = Number(opts.timeout ?? 60) * 1000;

const server = spawn(cmd[0], cmd.slice(1), { cwd: root, stdio: ["pipe", "pipe", "inherit"] });
let nextId = 1;
const pending = new Map();
let errorSeen;
const errorPromise = new Promise((res) => (errorSeen = res));
let buf = Buffer.alloc(0);
let exited = false;

function send(msg) {
  const body = Buffer.from(JSON.stringify({ jsonrpc: "2.0", ...msg }));
  server.stdin.write(`Content-Length: ${body.length}\r\n\r\n`);
  server.stdin.write(body);
}
function request(method, params) {
  const id = nextId++;
  return new Promise((res, rej) => {
    pending.set(id, { res, rej });
    send({ id, method, params });
  });
}
const notify = (method, params) => send({ method, params });

function onMessage(m) {
  if (m.id !== undefined && m.method === undefined) {
    const p = pending.get(m.id);
    if (!p) return;
    pending.delete(m.id);
    if (m.error) p.rej(new Error(`${m.error.code} ${m.error.message}`));
    else p.res(m.result);
  } else if (m.id !== undefined) {
    // A request from the server: answer the ones servers commonly send.
    let result = null;
    if (m.method === "workspace/configuration") result = (m.params.items ?? []).map(() => null);
    if (m.method === "workspace/workspaceFolders") result = [{ uri: rootUri, name: "root" }];
    send({ id: m.id, result });
  } else if (m.method === "textDocument/publishDiagnostics" && m.params.uri === fileUri) {
    if ((m.params.diagnostics ?? []).some((d) => d.severity === 1)) errorSeen(m.params.diagnostics);
  }
}
server.stdout.on("data", (chunk) => {
  buf = Buffer.concat([buf, chunk]);
  for (;;) {
    const end = buf.indexOf("\r\n\r\n");
    if (end < 0) return;
    const m = /content-length:\s*(\d+)/i.exec(buf.subarray(0, end).toString("latin1"));
    if (!m) fail("frame without Content-Length");
    const len = Number(m[1]);
    if (buf.length < end + 4 + len) return;
    const body = buf.subarray(end + 4, end + 4 + len).toString("utf8");
    buf = buf.subarray(end + 4 + len);
    onMessage(JSON.parse(body));
  }
});
server.stdin.on("error", () => {});
server.on("exit", (code, sig) => {
  exited = true;
  for (const p of pending.values()) p.rej(new Error(`server exited (${code ?? sig})`));
});
server.on("error", (e) => fail(`cannot start ${cmd[0]}: ${e.message}`));

function fail(msg) {
  console.error(`probe: ${msg}`);
  server.kill("SIGKILL");
  process.exit(1);
}
function within(ms, p, what) {
  let t;
  return Promise.race([
    p,
    new Promise((_, rej) => (t = setTimeout(() => rej(new Error(`timeout after ${ms / 1000}s: ${what}`)), ms))),
  ]).finally(() => clearTimeout(t));
}

try {
  const init = await within(
    timeoutMs,
    request("initialize", {
      processId: process.pid,
      clientInfo: { name: "lsp-probe" },
      rootUri,
      workspaceFolders: [{ uri: rootUri, name: "root" }],
      capabilities: {
        workspace: { configuration: true, workspaceFolders: true },
        window: { workDoneProgress: true },
        textDocument: {
          publishDiagnostics: {},
          definition: { linkSupport: true },
          synchronization: { didSave: false },
        },
      },
    }),
    "initialize",
  );
  if (!init?.capabilities) fail("initialize returned no capabilities");
  notify("initialized", {});
  notify("textDocument/didOpen", {
    textDocument: {
      uri: fileUri,
      languageId: opts.language ?? "plaintext",
      version: 1,
      text: readFileSync(fileURLToPath(fileUri), "utf8"),
    },
  });
  const diags = await within(timeoutMs, errorPromise, `an error diagnostic for ${opts.file}`);
  console.log(`diagnostic: ${diags.find((d) => d.severity === 1).message.split("\n")[0]}`);

  // A server may answer with nothing while it is still loading: ask again.
  const deadline = Date.now() + timeoutMs;
  let loc;
  for (;;) {
    const r = await within(
      Math.max(1000, deadline - Date.now()),
      request("textDocument/definition", {
        textDocument: { uri: fileUri },
        position: { line: defLine, character: defChar },
      }),
      "definition",
    );
    const first = Array.isArray(r) ? r[0] : r;
    if (first) {
      loc = { uri: first.targetUri ?? first.uri, line: (first.targetSelectionRange ?? first.range).start.line };
      break;
    }
    if (Date.now() > deadline) fail("definition stayed empty");
    await new Promise((r) => setTimeout(r, 1000));
  }
  const gotFile = fileURLToPath(loc.uri);
  if (gotFile !== expectFile || loc.line !== expectLine)
    fail(`definition is ${gotFile}:${loc.line}, expected ${expectFile}:${expectLine}`);
  console.log(`definition: ${opts.expect}`);

  await within(10000, request("shutdown", null), "shutdown");
  notify("exit", null);
  await within(10000, new Promise((res) => (exited ? res() : server.once("exit", res))), "exit");
  process.exit(0);
} catch (e) {
  fail(e.message);
}
