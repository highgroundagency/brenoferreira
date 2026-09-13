import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Card = {
  name: string | null;
  unit: string;
  status: string;
  since: string | null;
  code: string;
  benefits: { title: string; partner: string; rules: string | null }[];
};

/** Carteirinha pública do mantenedor: só primeiro nome, código e benefícios vigentes. */
export default async function CarteirinhaPage({ params }: { params: Promise<{ code: string }> }) {
  const { code } = await params;
  const supabase = await createClient();
  const { data } = await supabase.rpc("supporter_card", { p_code: code });
  const card = data as unknown as Card | null;
  if (!card) {
    return (
      <main className="mx-auto max-w-sm px-4 py-10 text-center">
        <h1 className="text-lg font-bold">Carteirinha não encontrada</h1>
        <p className="mt-2 text-sm text-muted-foreground">Confira o código ou fale com a central do Transtornar.</p>
      </main>
    );
  }
  return (
    <main className="mx-auto max-w-sm px-4 py-8">
      <section className="rounded-xl border bg-card p-5 shadow-sm">
        <p className="text-xs uppercase tracking-wide text-muted-foreground">Mantenedor · {card.unit}</p>
        <h1 className="mt-1 text-2xl font-bold">{card.name}</h1>
        <p className="mt-1 font-mono text-lg tracking-widest">{card.code}</p>
        {card.since ? (
          <p className="mt-1 text-xs text-muted-foreground">desde {new Date(card.since).toLocaleDateString("pt-BR")}</p>
        ) : null}
      </section>
      <h2 className="mt-6 mb-2 font-semibold">Benefícios</h2>
      <ul className="flex flex-col gap-2">
        {card.benefits.map((b) => (
          <li key={`${b.partner}-${b.title}`} className="rounded-md border p-3 text-sm">
            <div className="font-medium">{b.title}</div>
            <div className="text-muted-foreground">{b.partner}</div>
            {b.rules ? <div className="mt-1 text-xs">{b.rules}</div> : null}
          </li>
        ))}
        {card.benefits.length === 0 ? (
          <li className="text-sm text-muted-foreground">Nenhum benefício ativo no momento.</li>
        ) : null}
      </ul>
      <p className="mt-6 text-xs text-muted-foreground">
        Apresente este código no parceiro. Dúvidas: fale com a central do Transtornar.
      </p>
    </main>
  );
}
