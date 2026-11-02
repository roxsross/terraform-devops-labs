// Tests de la API. Se ejecutan con: npm test
const { test, before, after } = require("node:test");
const assert = require("node:assert/strict");
const { crearApp, MAX_TITULO } = require("../src/app");

let servidor, base;
before(async () => {
  servidor = crearApp({ env: { APP_VERSION: "test-1", MENSAJE: "Hola test" } });
  await new Promise((r) => servidor.listen(0, r));
  base = `http://127.0.0.1:${servidor.address().port}`;
});
after(() => servidor.close());

const pedir = (ruta, metodo = "GET", cuerpo) =>
  fetch(base + ruta, {
    method: metodo,
    headers: { "Content-Type": "application/json" },
    body: cuerpo === undefined ? undefined : typeof cuerpo === "string" ? cuerpo : JSON.stringify(cuerpo),
  });

test("GET /health responde 200 con status ok", async () => {
  const r = await pedir("/health");
  assert.equal(r.status, 200);
  assert.deepEqual(await r.json(), { status: "ok" });
});

test("GET /info devuelve versión, mensaje y pod", async () => {
  const i = await (await pedir("/info")).json();
  assert.equal(i.version, "test-1");
  assert.equal(i.mensaje, "Hola test");
  assert.ok(i.pod);
});

test("GET / devuelve la página HTML", async () => {
  const r = await pedir("/");
  assert.equal(r.status, 200);
  assert.match(r.headers.get("content-type"), /text\/html/);
  await r.text();
});

test("POST crea una tarea y GET la lista", async () => {
  const r = await pedir("/api/tareas", "POST", { titulo: "  Aprender ARC  " });
  assert.equal(r.status, 201);
  const t = await r.json();
  assert.equal(t.titulo, "Aprender ARC");
  assert.equal(t.completada, false);
  assert.ok(t.id && t.creadaEn);
  const lista = await (await pedir("/api/tareas")).json();
  assert.ok(lista.some((x) => x.id === t.id));
});

test("POST rechaza títulos vacíos, largos o JSON inválido", async () => {
  assert.equal((await pedir("/api/tareas", "POST", { titulo: "   " })).status, 400);
  assert.equal((await pedir("/api/tareas", "POST", {})).status, 400);
  assert.equal((await pedir("/api/tareas", "POST", { titulo: "x".repeat(MAX_TITULO + 1) })).status, 400);
  const r = await pedir("/api/tareas", "POST", "{no es json");
  assert.equal(r.status, 400);
  assert.ok((await r.json()).error);
});

test("PATCH marca una tarea como completada", async () => {
  const t = await (await pedir("/api/tareas", "POST", { titulo: "Completar" })).json();
  const r = await pedir(`/api/tareas/${t.id}`, "PATCH", { completada: true });
  assert.equal(r.status, 200);
  assert.equal((await r.json()).completada, true);
  assert.equal((await pedir(`/api/tareas/${t.id}`, "PATCH", { completada: "si" })).status, 400);
});

test("PATCH y DELETE devuelven 404 si la tarea no existe", async () => {
  assert.equal((await pedir("/api/tareas/no-existe", "PATCH", { completada: true })).status, 404);
  assert.equal((await pedir("/api/tareas/no-existe", "DELETE")).status, 404);
});

test("DELETE borra una tarea", async () => {
  const t = await (await pedir("/api/tareas", "POST", { titulo: "Borrar" })).json();
  assert.equal((await pedir(`/api/tareas/${t.id}`, "DELETE")).status, 204);
  const lista = await (await pedir("/api/tareas")).json();
  assert.ok(!lista.some((x) => x.id === t.id));
});

test("rutas desconocidas devuelven 404 en JSON", async () => {
  const r = await pedir("/nada");
  assert.equal(r.status, 404);
  assert.ok((await r.json()).error);
});
