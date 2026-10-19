import { supabase } from "./supabase";
import { obtenerTokenCliente } from "../utils/tokenCliente";

export async function obtenerDisponibilidad({ servicioId, fecha, barberoId = null }) {
  const { data, error } = await supabase.rpc("disponibilidad", {
    p_servicio_id: servicioId,
    p_fecha: fecha,
    p_barbero_id: barberoId,
  });

  if (error) throw error;
  return data;
}

export async function crearCita({ nombre, whatsapp, servicioId, inicio, barberoId = null }) {
  const { data, error } = await supabase.rpc("crear_cita", {
    p_nombre: nombre,
    p_whatsapp: whatsapp,
    p_servicio_id: servicioId,
    p_inicio: inicio,
    p_barbero_id: barberoId,
    p_token: obtenerTokenCliente(),
  });

  if (error) throw error;
  return data;
}
