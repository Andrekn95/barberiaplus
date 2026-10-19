export const ZONA_HORARIA = "America/Guayaquil";
export const CODIGO_PAIS = "593";
export const MONEDA = "USD";
export const IDIOMA = "es-EC";

const MS_POR_DIA = 86_400_000;

export function formatearPrecio(valor) {
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: MONEDA,
  }).format(Number(valor) || 0);
}

export function fechaATexto(fecha) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: ZONA_HORARIA,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date(fecha));
}

export function formatearHora(fecha) {
  return new Intl.DateTimeFormat(IDIOMA, {
    timeZone: ZONA_HORARIA,
    hour: "numeric",
    minute: "2-digit",
    hour12: true,
  }).format(new Date(fecha));
}

export function formatearFechaLegible(fecha) {
  return new Intl.DateTimeFormat(IDIOMA, {
    timeZone: ZONA_HORARIA,
    weekday: "long",
    day: "numeric",
    month: "long",
  }).format(new Date(fecha));
}

export function normalizarWhatsApp(texto) {
  let digitos = String(texto ?? "").replace(/\D/g, "");

  if (digitos.startsWith("0")) {
    digitos = digitos.slice(1);
  }

  if (!digitos.startsWith(CODIGO_PAIS)) {
    digitos = CODIGO_PAIS + digitos;
  }

  const completo = `+${digitos}`;
  return /^\+[1-9][0-9]{9,14}$/.test(completo) ? completo : null;
}

export function hoyTexto() {
  return fechaATexto(Date.now());
}

export function sumarDias(fecha, dias) {
  return new Date(new Date(fecha).getTime() + dias * MS_POR_DIA);
}
