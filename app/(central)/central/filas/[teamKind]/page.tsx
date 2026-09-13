import { LiveRefresh } from "@/components/central/live-refresh";
import { type QueueItem, QueueList } from "@/components/central/queue-list";
import { type Role, STAFF_ROLES } from "@/lib/auth/roles";
import { createClient, getProfile } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

const KIND_LABEL: Record<string, string> = {
  central: "Central",
  basic_food: "Cesta básica",
  home_items: "Itens de casa",
  education: "Educação",
  employment: "Trabalho",
  follow_up: "Acompanhamento",
  logistics: "Logística",
  strategy: "Estratégia",
};

export default async function FilaPage({ params }: { params: Promise<{ teamKind: string }> }) {
  const { teamKind } = await params;
  const supabase = await createClient();
  const profile = await getProfile();
  const { data } = await supabase.rpc("get_team_queue", { p_team_kind: teamKind });
  const items = (data ?? []) as unknown as QueueItem[];
  return (
    <div className="mx-auto max-w-3xl">
      <h1 className="mb-3 text-xl font-bold">Fila — {KIND_LABEL[teamKind] ?? teamKind}</h1>
      <LiveRefresh tables={["referrals"]} />
      <QueueList items={items} canOpenRecord={STAFF_ROLES.includes((profile?.role ?? "") as Role)} />
    </div>
  );
}
