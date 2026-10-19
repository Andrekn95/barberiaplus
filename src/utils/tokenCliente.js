const CLAVE = "barberia_token_cliente";

export function obtenerTokenCliente() {
  let token = null;

  try {
    token = localStorage.getItem(CLAVE);
  } catch {
    token = null;
  }

  if (token) return token;

  const nuevo = crypto.randomUUID();

  try {
    localStorage.setItem(CLAVE, nuevo);
  } catch {
    // Navegador bloquea el almacenamiento (modo privado): token temporal
    return nuevo;
  }

  return nuevo;
}
