/** wa_id (dígitos) -> E.164. */
export function waIdToE164(waId: string): string {
  return `+${waId.replace(/\D/g, "")}`;
}

/** E.164 -> destino da Cloud API (dígitos, sem +). */
export function e164ToWa(e164: string): string {
  return e164.replace(/\D/g, "");
}

/** Variantes BR com e sem o 9º dígito (espelha public.phone_variants). */
export function phoneVariants(e164: string): string[] {
  const m = /^\+55(\d{2})9?(\d{8})$/.exec(e164);
  if (!m) return [e164];
  return [`+55${m[1]}9${m[2]}`, `+55${m[1]}${m[2]}`];
}
