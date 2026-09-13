import messages from "@/messages/pt-BR.json";

type Key = keyof typeof messages;

/** Helper mínimo de i18n (pt-BR). `next-intl` só na Fase 4; as chaves já ficam externalizadas. */
export function t(key: Key, vars?: Record<string, string | number>): string {
  const raw: string = messages[key] ?? key;
  if (!vars) return raw;
  return raw.replace(/\{(\w+)\}/g, (_, k: string) => String(vars[k] ?? `{${k}}`));
}
