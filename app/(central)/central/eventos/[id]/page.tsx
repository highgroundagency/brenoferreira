import { EventDetail } from "@/components/central/event-detail";
import { requireRole } from "@/lib/auth/require-role";
import { STAFF_ROLES } from "@/lib/auth/roles";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function EventoPage({ params }: { params: Promise<{ id: string }> }) {
  await requireRole(STAFF_ROLES);
  const { id } = await params;
  const supabase = await createClient();
  const [{ data: event }, { data: audience }, { data: invites }] = await Promise.all([
    supabase.from("events").select("*").eq("id", id).maybeSingle(),
    supabase.rpc("event_audience", { p_event_id: id }),
    supabase
      .from("event_invitations")
      .select(
        "id, person_id, rsvp, checkin_code, checked_in_at, sent_at, people(people_contacts(full_name), neighborhoods(name))",
      )
      .eq("event_id", id)
      .order("sent_at"),
  ]);
  if (!event) return <p className="text-sm text-destructive">Evento não encontrado.</p>;
  const rows = (
    (invites ?? []) as unknown as {
      id: string;
      person_id: string;
      rsvp: string | null;
      checkin_code: string | null;
      checked_in_at: string | null;
      people: { people_contacts: { full_name: string } | null; neighborhoods: { name: string } | null } | null;
    }[]
  ).map((i) => ({
    ...i,
    full_name: i.people?.people_contacts?.full_name ?? "—",
    neighborhood: i.people?.neighborhoods?.name ?? "",
  }));
  return <EventDetail event={event as never} audienceSize={(audience ?? []).length} invitations={rows} />;
}
