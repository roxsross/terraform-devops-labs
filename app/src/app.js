// Servidor HTTP sin dependencias externas.
const http = require("node:http");
const os = require("node:os");
const fs = require("node:fs");
const path = require("node:path");
const { crearAlmacen } = require("./tareas");

const MAX_TITULO = 100;
const INDEX_HTML = path.join(__dirname, "..", "public", "index.html");

function responder(res, status, cuerpo) {
  if (status === 204) { res.writeHead(204); return res.end(); }
  res.writeHead(status, { "Content-Type": "application/json; charset=utf-8" });
  res.end(JSON.stringify(cuerpo));
}

function error(res, status, mensaje) {
  responder(res, status, { error: mensaje });
}

function leerJson(req) {
  return new Promise((resolve) => {
    let datos = "";
    req.on("data", (c) => { datos += c; if (datos.length > 10_000) req.destroy(); });
    req.on("end", () => { try { resolve(JSON.parse(datos || "{}")); } catch { resolve(undefined); } });
  });
}

function crearApp(opciones = {}) {
  const almacen = opciones.almacen || crearAlmacen();
  const env = opciones.env || process.env;
  const info = () => ({
    app: "api-tareas",
    version: env.APP_VERSION || "dev",
    mensaje: env.MENSAJE || "Hola desde la API de tareas",
    pod: os.hostname(),
  });

  return http.createServer(async (req, res) => {
    const url = new URL(req.url, "http://localhost");
    const partes = url.pathname.split("/").filter(Boolean); // ["api","tareas",":id"]

    try {
      if (req.method === "GET" && url.pathname === "/health") return responder(res, 200, { status: "ok" });
      if (req.method === "GET" && url.pathname === "/info") return responder(res, 200, info());
      if (req.method === "GET" && url.pathname === "/") {
        res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
        return fs.createReadStream(INDEX_HTML).pipe(res);
      }

      if (partes[0] === "api" && partes[1] === "tareas" && partes.length <= 3) {
        const id = partes[2];

        if (!id && req.method === "GET") return responder(res, 200, almacen.listar());

        if (!id && req.method === "POST") {
          const cuerpo = await leerJson(req);
          if (cuerpo === undefined) return error(res, 400, "El cuerpo no es JSON válido");
          const titulo = typeof cuerpo.titulo === "string" ? cuerpo.titulo.trim() : "";
          if (!titulo) return error(res, 400, "El título es obligatorio");
          if (titulo.length > MAX_TITULO) return error(res, 400, `El título no puede superar ${MAX_TITULO} caracteres`);
          return responder(res, 201, almacen.crear(titulo));
        }

        if (id && req.method === "PATCH") {
          const cuerpo = await leerJson(req);
          if (cuerpo === undefined || typeof cuerpo.completada !== "boolean") {
            return error(res, 400, "El campo completada debe ser true o false");
          }
          const tarea = almacen.actualizar(id, cuerpo.completada);
          return tarea ? responder(res, 200, tarea) : error(res, 404, "Tarea no encontrada");
        }

        if (id && req.method === "DELETE") {
          return almacen.borrar(id) ? responder(res, 204) : error(res, 404, "Tarea no encontrada");
        }

        return error(res, 405, "Método no permitido");
      }

      return error(res, 404, "Ruta no encontrada");
    } catch (e) {
      console.error(e);
      return error(res, 500, "Error interno");
    }
  });
}

module.exports = { crearApp, MAX_TITULO };
