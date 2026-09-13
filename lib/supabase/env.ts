/** Configuração pública do Supabase. Em NEXT_PUBLIC_* o valor é embutido no build:
 *  se a variável não existia na hora de compilar, ela chega aqui como undefined em produção. */
export const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
export const SUPABASE_PUBLISHABLE_KEY = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

export function missingSupabaseEnv(): string[] {
  const missing: string[] = [];
  if (!SUPABASE_URL) missing.push("NEXT_PUBLIC_SUPABASE_URL");
  if (!SUPABASE_PUBLISHABLE_KEY) missing.push("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY");
  return missing;
}

/** Lança com o nome da variável que falta, em vez de um erro genérico do SDK. */
export function requireSupabaseEnv(): { url: string; key: string } {
  const missing = missingSupabaseEnv();
  if (missing.length) {
    throw new Error(
      `Configuração ausente: ${missing.join(", ")}. Defina no ambiente (Vercel: Settings → Environment Variables) e refaça o build.`,
    );
  }
  return { url: SUPABASE_URL as string, key: SUPABASE_PUBLISHABLE_KEY as string };
}
