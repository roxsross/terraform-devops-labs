// Punto de entrada: levanta el servidor y maneja el apagado ordenado.
const { crearApp } = require("./app");

const PORT = Number(process.env.PORT || 3000);
const servidor = crearApp();

servidor.listen(PORT, () => {
  console.log(`api-tareas ${process.env.APP_VERSION || "dev"} escuchando en el puerto ${PORT}`);
});

function apagar(senal) {
  console.log(`Recibí ${senal}, cerrando el servidor...`);
  servidor.close(() => process.exit(0));
  setTimeout(() => process.exit(0), 5000).unref();
}
process.on("SIGTERM", () => apagar("SIGTERM"));
process.on("SIGINT", () => apagar("SIGINT"));
