import { parsePhoneNumberFromString } from "libphonenumber-js/min";

/** Normaliza um telefone digitado no Brasil para E.164 (+55DDNNNNNNNNN). Retorna null se inválido. */
export function toE164(raw: string, defaultCountry: "BR" = "BR"): string | null {
  const digits = raw.replace(/\D/g, "");
  if (digits.length < 10) return null;
  const parsed = parsePhoneNumberFromString(raw, defaultCountry);
  if (!parsed?.isPossible()) return null;
  return parsed.number;
}

/** Máscara de exibição (41) 9 9999-9999 enquanto o usuário digita. */
export function formatBrPhone(raw: string): string {
  const d = raw.replace(/\D/g, "").slice(0, 11);
  if (d.length <= 2) return d.length ? `(${d}` : "";
  if (d.length <= 6) return `(${d.slice(0, 2)}) ${d.slice(2)}`;
  if (d.length <= 10) return `(${d.slice(0, 2)}) ${d.slice(2, 6)}-${d.slice(6)}`;
  return `(${d.slice(0, 2)}) ${d.slice(2, 3)} ${d.slice(3, 7)}-${d.slice(7)}`;
}

/** Variantes BR com e sem o 9º dígito (a Meta pode devolver wa_id sem o 9). Espelha public.phone_variants. */
export function phoneVariants(e164: string): string[] {
  const m = /^\+55(\d{2})9?(\d{8})$/.exec(e164);
  if (!m) return [e164];
  return [`+55${m[1]}9${m[2]}`, `+55${m[1]}${m[2]}`];
}

/** wa_id da Meta (dígitos, sem +) -> E.164. */
export function waIdToE164(waId: string): string {
  return `+${waId.replace(/\D/g, "")}`;
}
