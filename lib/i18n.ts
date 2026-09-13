import en from "@/messages/en.json";
import ptBR from "@/messages/pt-BR.json";

export type Locale = "pt-BR" | "en";
type Key = keyof typeof ptBR;

const CATALOGS: Record<Locale, Record<string, string>> = { "pt-BR": ptBR, en };

/** Helper mínimo de i18n. O idioma vem de `units.locale`; pt-BR é o padrão. `next-intl` só se virar necessário. */
export function t(key: Key, vars?: Record<string, string | number>, locale: Locale = "pt-BR"): string {
  const raw: string = CATALOGS[locale]?.[key] ?? ptBR[key] ?? key;
  if (!vars) return raw;
  return raw.replace(/\{(\w+)\}/g, (_, k: string) => String(vars[k] ?? `{${k}}`));
}

export function isLocale(value: string | null | undefined): value is Locale {
  return value === "pt-BR" || value === "en";
}
