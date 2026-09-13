"use client";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { toast } from "sonner";
import { parseCsv } from "@/components/central/csv-import";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select } from "@/components/ui/select";
import { createClient } from "@/lib/supabase/client";

export type UnitRow = {
  unit_id: string;
  slug: string;
  name: string;
  locale: string;
  active: boolean;
  members: number;
  neighborhoods: number;
  people_registered: number | null;
  journey_active: number | null;
  reached_day7: number | null;
  church_connected: number | null;
  food_baskets_delivered: number | null;
  people_hired: number | null;
  events_done: number | null;
  active_supporters: number | null;
  pct_day7: number | null;
};

/** Abertura de unidades (franquia) e comparação entre elas. Só `global_admin` chega aqui. */
export function UnitManager({
  units,
  cities,
}: {
  units: UnitRow[];
  cities: { id: string; name: string; state: string; ibge_code: string | null }[];
}) {
  const router = useRouter();
  const [form, setForm] = useState({
    slug: "",
    name: "",
    city: "",
    state: "PR",
    ibge: "",
    timezone: "America/Sao_Paulo",
    locale: "pt-BR",
  });
  const [busy, setBusy] = useState(false);
  const [importUnit, setImportUnit] = useState("");
  const [importCity, setImportCity] = useState("");
  const supabase = () => createClient();

  async function create() {
    if (!form.slug || !form.name || !form.city) return toast.error("Preencha identificador, nome e cidade.");
    setBusy(true);
    const { error } = await supabase().rpc("create_unit", {
      p_slug: form.slug,
      p_name: form.name,
      p_city_name: form.city,
      p_state: form.state,
      p_ibge_code: form.ibge || undefined,
      p_timezone: form.timezone,
      p_locale: form.locale,
    });
    setBusy(false);
    if (error)
      return toast.error(error.message.includes("slug_taken") ? "Esse identificador já existe." : error.message);
    toast.success("Unidade aberta com times, regras, jornada e marcos clonados.");
    setForm({ ...form, slug: "", name: "", city: "", ibge: "" });
    router.refresh();
  }

  async function importNeighborhoods(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file || !importCity) return toast.error("Escolha a cidade antes do arquivo.");
    const rows = parseCsv(await file.text()).map((r) => ({
      name: r.name ?? r.bairro ?? "",
      aliases: (r.aliases ?? "").split("|").filter(Boolean),
      region: r.region ?? r.regional ?? "",
    }));
    setBusy(true);
    const { data, error } = await supabase().rpc("import_neighborhoods", {
      p_city_id: importCity,
      p_rows: rows as never,
      p_unit_id: importUnit || undefined,
    });
    setBusy(false);
    if (error) return toast.error(error.message);
    const r = data as { created: number; existing: number };
    toast.success(`${r.created} bairro(s) criado(s); ${r.existing} já existiam.`);
    router.refresh();
  }

  return (
    <div className="flex flex-col gap-6">
      <Card>
        <CardHeader>
          <CardTitle>Abrir unidade (franquia)</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-wrap items-end gap-2 text-sm">
          <div className="flex flex-col gap-1">
            <Label>Identificador</Label>
            <Input
              value={form.slug}
              onChange={(e) => setForm({ ...form, slug: e.target.value.toLowerCase().replace(/[^a-z0-9-]/g, "-") })}
              placeholder="sao-jose"
              className="w-40"
            />
          </div>
          <div className="flex flex-col gap-1">
            <Label>Nome</Label>
            <Input
              value={form.name}
              onChange={(e) => setForm({ ...form, name: e.target.value })}
              placeholder="Transtornar São José"
              className="w-64"
            />
          </div>
          <div className="flex flex-col gap-1">
            <Label>Cidade</Label>
            <Input value={form.city} onChange={(e) => setForm({ ...form, city: e.target.value })} className="w-48" />
          </div>
          <div className="flex flex-col gap-1">
            <Label>UF</Label>
            <Input
              value={form.state}
              onChange={(e) => setForm({ ...form, state: e.target.value.toUpperCase().slice(0, 2) })}
              className="w-16"
            />
          </div>
          <div className="flex flex-col gap-1">
            <Label>IBGE (opcional)</Label>
            <Input value={form.ibge} onChange={(e) => setForm({ ...form, ibge: e.target.value })} className="w-32" />
          </div>
          <div className="flex flex-col gap-1">
            <Label>Idioma</Label>
            <Select value={form.locale} onChange={(e) => setForm({ ...form, locale: e.target.value })} className="w-32">
              <option value="pt-BR">pt-BR</option>
              <option value="en">en</option>
            </Select>
          </div>
          <Button onClick={create} disabled={busy}>
            Abrir unidade
          </Button>
          <p className="w-full text-xs text-muted-foreground">
            A unidade nasce com os times, as regras de roteamento, a jornada, os marcos e o texto de consentimento
            copiados do padrão global. Os templates entram como pendentes: cada unidade precisa da própria aprovação na
            Meta e do próprio número.
          </p>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Importar bairros de uma cidade</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-wrap items-end gap-2 text-sm">
          <Select value={importCity} onChange={(e) => setImportCity(e.target.value)} className="w-64">
            <option value="">cidade…</option>
            {cities.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}/{c.state}
              </option>
            ))}
          </Select>
          <Select value={importUnit} onChange={(e) => setImportUnit(e.target.value)} className="w-56">
            <option value="">vincular a… (opcional)</option>
            {units.map((u) => (
              <option key={u.unit_id} value={u.unit_id}>
                {u.name}
              </option>
            ))}
          </Select>
          <input type="file" accept=".csv,text/csv" onChange={importNeighborhoods} disabled={busy} />
          <p className="w-full text-xs text-muted-foreground">
            CSV com as colunas name, aliases (separados por |) e region.
          </p>
        </CardContent>
      </Card>

      <section>
        <h2 className="mb-2 font-semibold">Comparação entre unidades</h2>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b text-left text-muted-foreground">
                <th className="py-1 pr-2">Unidade</th>
                <th className="py-1 pr-2 text-right">Equipe</th>
                <th className="py-1 pr-2 text-right">Bairros</th>
                <th className="py-1 pr-2 text-right">Cadastros</th>
                <th className="py-1 pr-2 text-right">Em jornada</th>
                <th className="py-1 pr-2 text-right">7 dias</th>
                <th className="py-1 pr-2 text-right">% 7 dias</th>
                <th className="py-1 pr-2 text-right">Igreja</th>
                <th className="py-1 pr-2 text-right">Cestas</th>
                <th className="py-1 pr-2 text-right">Empregos</th>
                <th className="py-1 pr-2 text-right">Eventos</th>
                <th className="py-1 text-right">Mantenedores</th>
              </tr>
            </thead>
            <tbody>
              {units.map((u) => (
                <tr key={u.unit_id} className="border-b">
                  <td className="py-1 pr-2">
                    <span className="font-medium">{u.name}</span> <Badge variant="outline">{u.locale}</Badge>
                    {!u.active ? <Badge variant="destructive">inativa</Badge> : null}
                  </td>
                  <td className="py-1 pr-2 text-right tabular-nums">{u.members}</td>
                  <td className="py-1 pr-2 text-right tabular-nums">{u.neighborhoods}</td>
                  <td className="py-1 pr-2 text-right tabular-nums">{u.people_registered ?? 0}</td>
                  <td className="py-1 pr-2 text-right tabular-nums">{u.journey_active ?? 0}</td>
                  <td className="py-1 pr-2 text-right tabular-nums">{u.reached_day7 ?? 0}</td>
                  <td className="py-1 pr-2 text-right tabular-nums">{u.pct_day7 ?? 0}%</td>
                  <td className="py-1 pr-2 text-right tabular-nums">{u.church_connected ?? 0}</td>
                  <td className="py-1 pr-2 text-right tabular-nums">{u.food_baskets_delivered ?? 0}</td>
                  <td className="py-1 pr-2 text-right tabular-nums">{u.people_hired ?? 0}</td>
                  <td className="py-1 pr-2 text-right tabular-nums">{u.events_done ?? 0}</td>
                  <td className="py-1 text-right tabular-nums">{u.active_supporters ?? 0}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <p className="mt-1 text-xs text-muted-foreground">
          Números do relatório de impacto, atualizados diariamente (ou no botão "atualizar números" em
          /central/impacto).
        </p>
      </section>
    </div>
  );
}
