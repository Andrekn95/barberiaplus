import { supabase } from "./supabase";

export async function obtenerBarberos() {
  const { data, error } = await supabase
    .from("barberos")
    .select("id, nombre, foto_url")
    .order("nombre");

  if (error) throw error;
  return data;
}
