const http = require("http");
const net = require("net");
const os = require("os");

const PORT = process.env.PORT || 3000;
const MENSAJE = process.env.MENSAJE || "Hola desde Kubernetes";
const VERSION = process.env.APP_VERSION || "1.0";
const VALKEY_HOST = process.env.VALKEY_HOST || "";
const VALKEY_PORT = Number(process.env.VALKEY_PORT || 6379);

// Envía comandos a Valkey y devuelve la última respuesta (o null si falla)
function valkey(commands) {
  return new Promise((resolve) => {
    if (!VALKEY_HOST) return resolve(null);
    const encode = (args) => `*${args.length}\r\n` + args.map((a) => `$${Buffer.byteLength(String(a))}\r\n${a}\r\n`).join("");
    const all = commands;
    const socket = net.createConnection({ host: VALKEY_HOST, port: VALKEY_PORT });
    let data = "";
    const done = (v) => { socket.destroy(); resolve(v); };
    socket.setTimeout(1500, () => done(null));
    socket.on("error", () => done(null));
    socket.on("connect", () => socket.write(all.map(encode).join("")));
    socket.on("data", (chunk) => {
      data += chunk.toString();
      const lines = data.split("\r\n").filter(Boolean);
      if (lines.length >= all.length) {
        const last = lines[all.length - 1];
        if (last.startsWith("-")) return done(null);
        done(last.replace(/^[:+]/, ""));
      }
    });
  });
}

const server = http.createServer(async (req, res) => {
  if (req.url === "/health") {
    res.writeHead(200, { "Content-Type": "text/plain" });
    return res.end("ok");
  }
  if (req.url !== "/") {
    res.writeHead(404, { "Content-Type": "text/plain" });
    return res.end("no encontrado");
  }

  const visitas = await valkey([["INCR", "visitas"]]);
  const info = {
    mensaje: MENSAJE,
    version: VERSION,
    pod: os.hostname(),
    visitas: visitas === null ? (VALKEY_HOST ? "Valkey no responde" : "sin Valkey") : Number(visitas),
  };
  console.log(`${new Date().toISOString()} GET / desde ${info.pod}`);

  if ((req.headers.accept || "").includes("text/html")) {
    res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
    return res.end(`<!doctype html><html lang="es"><head><meta charset="utf-8"><title>k8s-app</title>
<style>body{font-family:system-ui,sans-serif;background:#0f172a;color:#f8fafc;display:grid;place-items:center;min-height:100vh;margin:0}
main{text-align:center;padding:2rem}h1{font-size:2.6rem;margin:0 0 1.5rem}.d{display:flex;gap:1rem;justify-content:center;flex-wrap:wrap}
.c{background:#1e293b;border-radius:12px;padding:1rem 1.4rem;min-width:150px}.l{color:#94a3b8;font-size:.8rem;text-transform:uppercase}
.v{font-size:1.2rem;font-weight:700;margin-top:.3rem;color:#60a5fa}</style></head><body><main>
<h1>${MENSAJE.replace(/</g, "&lt;")}</h1><div class="d">
<div class="c"><div class="l">Pod</div><div class="v">${info.pod}</div></div>
<div class="c"><div class="l">Versión</div><div class="v">${VERSION}</div></div>
<div class="c"><div class="l">Visitas</div><div class="v">${info.visitas}</div></div>
</div></main></body></html>`);
  }
  res.writeHead(200, { "Content-Type": "application/json" });
  res.end(JSON.stringify(info) + "\n");
});

server.listen(PORT, () => console.log(`k8s-app ${VERSION} escuchando en el puerto ${PORT}`));
process.on("SIGTERM", () => server.close(() => process.exit(0)));
