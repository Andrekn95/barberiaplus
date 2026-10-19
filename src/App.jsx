import { useEffect } from "react";
import { obtenerBarberos } from "./services/barberosService";
import { obtenerDisponibilidad } from "./services/citasService";
import { sumarDias, fechaATexto, formatearHora } from "./utils";

const SERVICIO_ID = "00986906-d6dd-4623-ad63-68f034cc6ecc"; // Corte clásico

function App() {
  useEffect(() => {
    obtenerBarberos()
      .then((barberos) => console.log("Barberos:", barberos))
      .catch((e) => console.error("Barberos error:", e.message));

    const manana = fechaATexto(sumarDias(Date.now(), 1));

    obtenerDisponibilidad({ servicioId: SERVICIO_ID, fecha: manana })
      .then((slots) =>
        console.log(
          `Disponibilidad ${manana}:`,
          slots.map((s) => `${formatearHora(s.inicio)} (${s.barbero_id.slice(0, 8)})`)
        )
      )
      .catch((e) => console.error("Disponibilidad error:", e.message));
  }, []);

  return <h1>Prueba de servicios</h1>;
}

export default App;
