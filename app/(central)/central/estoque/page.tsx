import { StockForm } from "@/components/central/stock-form";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function EstoquePage() {
  const supabase = await createClient();
  const [{ data: items }, { data: stock }, { data: moves }] = await Promise.all([
    supabase.from("catalog_items").select("code, name, category").eq("active", true).order("name"),
    supabase.from("inventory_stock").select("item_code, quantity"),
    supabase
      .from("inventory_movements")
      .select("item_code, delta, reason, note, created_at")
      .order("created_at", { ascending: false })
      .limit(50),
  ]);
  const qty = new Map((stock ?? []).map((s) => [s.item_code, s.quantity]));
  return (
    <div className="mx-auto flex max-w-3xl flex-col gap-4">
      <h1 className="text-xl font-bold">Itens de casa — estoque de doações</h1>
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b text-left text-muted-foreground">
            <th className="py-1">Item</th>
            <th className="py-1">Categoria</th>
            <th className="py-1 text-right">Em estoque</th>
          </tr>
        </thead>
        <tbody>
          {(items ?? []).map((i) => (
            <tr key={i.code} className="border-b">
              <td className="py-1">{i.name}</td>
              <td className="py-1">{i.category}</td>
              <td className="py-1 text-right tabular-nums">{qty.get(i.code) ?? 0}</td>
            </tr>
          ))}
        </tbody>
      </table>
      <StockForm items={(items ?? []).map((i) => ({ code: i.code, name: i.name }))} />
      <div className="text-xs text-muted-foreground">
        {(moves ?? []).map((m, i) => (
          <div key={`${m.created_at}-${i.toString()}`}>
            {new Date(m.created_at).toLocaleString("pt-BR")} · {m.item_code} {m.delta > 0 ? `+${m.delta}` : m.delta} (
            {m.reason}) {m.note ?? ""}
          </div>
        ))}
      </div>
    </div>
  );
}
