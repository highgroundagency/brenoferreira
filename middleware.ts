import { type NextRequest, NextResponse } from "next/server";
import { updateSession } from "@/lib/supabase/middleware";

export async function middleware(request: NextRequest) {
  try {
    return await updateSession(request);
  } catch (err) {
    // O middleware roda antes de qualquer página: se ele lança, o site inteiro vira um 500 sem
    // explicação (MIDDLEWARE_INVOCATION_FAILED). Melhor responder dizendo o que aconteceu.
    return new NextResponse(
      `Transtornar — o middleware falhou.\n\n${err instanceof Error ? err.message : String(err)}\n\n` +
        "Diagnóstico sem sessão: /status",
      { status: 503, headers: { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store" } },
    );
  }
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|sw.js|manifest.webmanifest|icons/|.*\\.(?:png|svg|jpg|webp)$).*)",
  ],
};
