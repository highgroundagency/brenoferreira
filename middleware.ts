import { type NextRequest, NextResponse } from "next/server";
import { missingSupabaseEnv } from "@/lib/supabase/env";

const PUBLIC_PATHS = [
  "/login",
  "/convite",
  "/api/auth",
  "/termos",
  "/carteirinha",
  "/manifest.webmanifest",
  "/sw.js",
  "/icons",
  "/status",
];

/** Cookie de sessão do Supabase: sb-<project-ref>-auth-token, às vezes fatiado em .0/.1 */
function temSessao(request: NextRequest): boolean {
  return request.cookies.getAll().some((c) => /^sb-.+-auth-token(\.\d+)?$/.test(c.name));
}

/**
 * Porteiro leve: manda quem não tem sessão para o login e deixa o resto passar.
 *
 * Não usa o SDK do Supabase de propósito. O middleware roda no runtime de edge, onde o SDK
 * acaba puxando `node:buffer` e quebra no carregamento do módulo — antes de qualquer try/catch,
 * o que derruba todas as rotas com um 500 sem mensagem. A autorização de verdade continua nos
 * layouts (`requireRole`, runtime Node, onde o SDK funciona) e na RLS do banco; a presença do
 * cookie aqui é só uma dica para evitar uma renderização inútil.
 */
export function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  if (pathname === "/status") return NextResponse.next();

  const faltando = missingSupabaseEnv();
  if (faltando.length) {
    return new NextResponse(
      `Transtornar — configuração incompleta.\n\nFaltam estas variáveis de ambiente no build: ${faltando.join(", ")}.\n` +
        "Defina-as no projeto (Vercel: Settings → Environment Variables, para Production e Preview) e refaça o deploy.\n" +
        "Elas são embutidas durante o build, então adicionar sem um novo build não resolve.",
      { status: 503, headers: { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store" } },
    );
  }

  const publica = PUBLIC_PATHS.some((p) => pathname === p || pathname.startsWith(`${p}/`));
  if (publica || temSessao(request)) return NextResponse.next();

  const url = request.nextUrl.clone();
  url.pathname = "/login";
  url.searchParams.set("next", pathname);
  return NextResponse.redirect(url);
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|sw.js|manifest.webmanifest|icons/|.*\\.(?:png|svg|jpg|webp)$).*)",
  ],
};
