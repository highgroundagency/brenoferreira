import { createServerClient } from "@supabase/ssr";
import { type NextRequest, NextResponse } from "next/server";
import { missingSupabaseEnv, SUPABASE_PUBLISHABLE_KEY, SUPABASE_URL } from "@/lib/supabase/env";

const PUBLIC_PATHS = [
  "/login",
  "/convite",
  "/api/auth",
  "/termos",
  "/carteirinha",
  "/manifest.webmanifest",
  "/sw.js",
  "/icons",
];

/** Renova a sessão e exige login fora das rotas públicas. O gate por papel fica nos layouts. */
export async function updateSession(request: NextRequest) {
  const { pathname } = request.nextUrl;
  const isPublic = PUBLIC_PATHS.some((p) => pathname === p || pathname.startsWith(`${p}/`));

  // Sem configuração não há como validar sessão. Responde explicando o que falta em vez de
  // derrubar o middleware (que vira um 500 branco em todas as rotas do site).
  const missing = missingSupabaseEnv();
  if (missing.length) {
    return new NextResponse(
      `Transtornar — configuração incompleta.\n\nFaltam estas variáveis de ambiente no build: ${missing.join(", ")}.\n` +
        "Defina-as no projeto (Vercel: Settings → Environment Variables, para Production e Preview) e refaça o deploy.\n" +
        "Elas são embutidas durante o build, então adicionar sem um novo build não resolve.",
      { status: 503, headers: { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store" } },
    );
  }

  let response = NextResponse.next({ request });
  const supabase = createServerClient(SUPABASE_URL as string, SUPABASE_PUBLISHABLE_KEY as string, {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet) {
        for (const { name, value } of cookiesToSet) {
          request.cookies.set(name, value);
        }
        response = NextResponse.next({ request });
        for (const { name, value, options } of cookiesToSet) {
          response.cookies.set(name, value, options);
        }
      },
    },
  });

  // Uma falha de rede ao falar com o Auth não pode derrubar o site: trata como "sem sessão".
  let user = null;
  try {
    ({
      data: { user },
    } = await supabase.auth.getUser());
  } catch {
    user = null;
  }

  if (!user && !isPublic) {
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    url.searchParams.set("next", pathname);
    return NextResponse.redirect(url);
  }
  return response;
}
