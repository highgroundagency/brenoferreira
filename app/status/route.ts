import { NextResponse } from "next/server";
import { missingSupabaseEnv, SUPABASE_URL } from "@/lib/supabase/env";

export const dynamic = "force-dynamic";

/** Diagnóstico público: responde mesmo com a configuração incompleta, e não expõe segredo nenhum
 *  (só quais variáveis existem, o host do Supabase e qual commit está no ar). */
export function GET() {
  const missing = missingSupabaseEnv();
  return NextResponse.json(
    {
      ok: missing.length === 0,
      faltando: missing,
      supabase_host: SUPABASE_URL ? new URL(SUPABASE_URL).host : null,
      commit: process.env.VERCEL_GIT_COMMIT_SHA?.slice(0, 7) ?? "desconhecido",
      branch: process.env.VERCEL_GIT_COMMIT_REF ?? "desconhecida",
      ambiente: process.env.VERCEL_ENV ?? "local",
      agora: new Date().toISOString(),
    },
    { headers: { "cache-control": "no-store" } },
  );
}
