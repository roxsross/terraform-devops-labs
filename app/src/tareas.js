// Almacén de tareas en memoria. Cada Pod tiene su propia lista.
const crypto = require("node:crypto");

function crearAlmacen() {
  const tareas = new Map();
  return {
    listar() {
      return [...tareas.values()].sort((a, b) => a.creadaEn.localeCompare(b.creadaEn));
    },
    crear(titulo) {
      const tarea = { id: crypto.randomUUID(), titulo, completada: false, creadaEn: new Date().toISOString() };
      tareas.set(tarea.id, tarea);
      return tarea;
    },
    actualizar(id, completada) {
      const tarea = tareas.get(id);
      if (!tarea) return null;
      tarea.completada = completada;
      return tarea;
    },
    borrar(id) {
      return tareas.delete(id);
    },
  };
}

module.exports = { crearAlmacen };
