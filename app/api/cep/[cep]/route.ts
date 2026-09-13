import { NextResponse } from "next/server";
import { normalizeCep } from "@/lib/domain/address";

export const dynamic = "force-dynamic";

type Cep = { street: string; neighborhood: string; city: string; state: string };

/** CEP -> endereço (ViaCEP, fallback BrasilAPI). Sem chave. Só usado para preencher rua/bairro. */
export async function GET(_req: Request, { params }: { params: Promise<{ cep: string }> }) {
  const { cep } = await params;
  const c = normalizeCep(cep);
  if (c.length !== 8) return NextResponse.json({ error: "cep_invalido" }, { status: 400 });
  try {
    const r = await fetch(`https://viacep.com.br/ws/${c}/json/`, { next: { revalidate: 86400 } });
    if (r.ok) {
      const j = (await r.json()) as {
        erro?: boolean;
        logradouro?: string;
        bairro?: string;
        localidade?: string;
        uf?: string;
      };
      if (!j.erro)
        return NextResponse.json<Cep>({
          street: j.logradouro ?? "",
          neighborhood: j.bairro ?? "",
          city: j.localidade ?? "",
          state: j.uf ?? "",
        });
    }
  } catch {
    // tenta o fallback
  }
  try {
    const r = await fetch(`https://brasilapi.com.br/api/cep/v2/${c}`, { next: { revalidate: 86400 } });
    if (r.ok) {
      const j = (await r.json()) as { street?: string; neighborhood?: string; city?: string; state?: string };
      return NextResponse.json<Cep>({
        street: j.street ?? "",
        neighborhood: j.neighborhood ?? "",
        city: j.city ?? "",
        state: j.state ?? "",
      });
    }
  } catch {
    // sem rede
  }
  return NextResponse.json({ error: "cep_nao_encontrado" }, { status: 404 });
}
