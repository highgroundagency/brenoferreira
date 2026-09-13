"use client";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Select } from "@/components/ui/select";
import { createClient } from "@/lib/supabase/client";

type Referral = { id: string; referral_type: string; status: string };
type Consent = { purpose: string; granted: boolean; revoked_at: string | null };

/** Ações de educação, trabalho, igreja e itens de casa a partir da ficha. */
export function PersonPhase2b({
  personId,
  referrals,
  consents,
  isLegacy,
  children,
}: {
  personId: string;
  referrals: Referral[];
  consents: Consent[];
  isLegacy: boolean;
  children: { id: string; age_band: string }[];
}) {
  const router = useRouter();
  const supabase = createClient();
  const [courses, setCourses] = useState<{ id: string; name: string; audience: string }[]>([]);
  const [openings, setOpenings] = useState<{ id: string; role: string; companies: { name: string } | null }[]>([]);
  const [churches, setChurches] = useState<{ id: string; name: string; service_times: string | null }[]>([]);
  const [items, setItems] = useState<{ code: string; name: string }[]>([]);
  const [course, setCourse] = useState("");
  const [child, setChild] = useState("");
  const [opening, setOpening] = useState("");
  const [church, setChurch] = useState("");
  const [item, setItem] = useState("");
  const has = (p: string) => consents.some((c) => c.purpose === p && c.granted && !c.revoked_at);
  const open = (t: string) => referrals.find((r) => r.referral_type === t && !["done", "cancelled"].includes(r.status));

  useEffect(() => {
    (async () => {
      const [c, o, ch, it] = await Promise.all([
        supabase.from("courses").select("id, name, audience").eq("active", true),
        supabase.from("job_openings").select("id, role, companies(name)").eq("status", "open"),
        supabase.rpc("suggest_church", { p_person_id: personId }),
        supabase.from("catalog_items").select("code, name").eq("active", true),
      ]);
      setCourses(c.data ?? []);
      setOpenings((o.data ?? []) as never);
      setChurches((ch.data ?? []) as never);
      setItems(it.data ?? []);
    })();
  }, [personId, supabase]);

  async function run(label: string, fn: () => PromiseLike<{ error: { message: string } | null }>) {
    const { error } = await fn();
    if (error) toast.error(`${label}: ${error.message}`);
    else {
      toast.success(label);
      router.refresh();
    }
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Educação, trabalho, igreja e itens de casa</CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-3 text-sm">
        {isLegacy && !has("whatsapp_contact") ? (
          <Button
            variant="outline"
            onClick={() =>
              run("Consentimento registrado; primeiro contato agendado", () =>
                supabase.rpc("activate_legacy_person", { p_person_id: personId }),
              )
            }
          >
            Ativar (consentimento colhido por telefone)
          </Button>
        ) : null}
        <div className="flex flex-wrap items-end gap-2">
          <Select value={course} onChange={(e) => setCourse(e.target.value)} className="w-56">
            <option value="">curso…</option>
            {courses.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name} ({c.audience === "teen" ? "adolescentes" : "adultos"})
              </option>
            ))}
          </Select>
          <Select value={child} onChange={(e) => setChild(e.target.value)} className="w-40">
            <option value="">a própria pessoa</option>
            {children.map((ch, i) => (
              <option key={ch.id} value={ch.id}>
                filho {i + 1} ({ch.age_band.replace("_", "-")})
              </option>
            ))}
          </Select>
          <Button
            variant="outline"
            disabled={!course}
            onClick={() =>
              run("Matriculado", () =>
                supabase.rpc("enroll_person", {
                  p_person_id: personId,
                  p_course_id: course,
                  p_child_id: child || undefined,
                  p_referral_id: open("education")?.id,
                }),
              )
            }
          >
            Matricular
          </Button>
        </div>
        <div className="flex flex-wrap items-end gap-2">
          <Select value={opening} onChange={(e) => setOpening(e.target.value)} className="w-64">
            <option value="">vaga…</option>
            {openings.map((o) => (
              <option key={o.id} value={o.id}>
                {o.role} — {o.companies?.name}
              </option>
            ))}
          </Select>
          {!has("share_with_employer") ? (
            <Button
              variant="ghost"
              onClick={() =>
                run("Consentimento (empregador) registrado", () =>
                  supabase.rpc("grant_consent", {
                    p_person_id: personId,
                    p_purpose: "share_with_employer",
                    p_via: "admin",
                  }),
                )
              }
            >
              registrar consentimento (empregador)
            </Button>
          ) : null}
          <Button
            variant="outline"
            disabled={!opening || !has("share_with_employer")}
            onClick={() =>
              run("Encaminhado à vaga", () =>
                supabase.rpc("refer_to_job", {
                  p_person_id: personId,
                  p_job_opening_id: opening,
                  p_referral_id: open("employment")?.id,
                }),
              )
            }
          >
            Encaminhar à vaga
          </Button>
        </div>
        <div className="flex flex-wrap items-end gap-2">
          <Select value={church} onChange={(e) => setChurch(e.target.value)} className="w-64">
            <option value="">igreja…</option>
            {churches.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name} {c.service_times ? `(${c.service_times})` : ""}
              </option>
            ))}
          </Select>
          {!has("share_with_church") ? (
            <Button
              variant="ghost"
              onClick={() =>
                run("Consentimento (igreja) registrado", () =>
                  supabase.rpc("grant_consent", {
                    p_person_id: personId,
                    p_purpose: "share_with_church",
                    p_via: "admin",
                  }),
                )
              }
            >
              registrar consentimento (igreja)
            </Button>
          ) : null}
          <Button
            variant="outline"
            disabled={!church || !has("share_with_church")}
            onClick={() =>
              run("Convite enviado", () =>
                supabase.rpc("connect_church", { p_person_id: personId, p_church_id: church, p_status: "invited" }),
              )
            }
          >
            Convidar
          </Button>
          <Button
            variant="outline"
            disabled={!church || !has("share_with_church")}
            onClick={() =>
              run("Conectada à igreja", () =>
                supabase.rpc("connect_church", { p_person_id: personId, p_church_id: church, p_status: "connected" }),
              )
            }
          >
            Marcar conectada
          </Button>
        </div>
        {open("home_items") ? (
          <div className="flex flex-wrap items-end gap-2">
            <Select value={item} onChange={(e) => setItem(e.target.value)} className="w-56">
              <option value="">item do estoque…</option>
              {items.map((i) => (
                <option key={i.code} value={i.code}>
                  {i.name}
                </option>
              ))}
            </Select>
            <Button
              variant="outline"
              disabled={!item}
              onClick={() =>
                run("Entrega do item agendada", () =>
                  supabase.rpc("fulfill_home_item", {
                    p_referral_id: open("home_items")?.id as string,
                    p_item_code: item,
                  }),
                )
              }
            >
              Atender item de casa
            </Button>
          </div>
        ) : null}
      </CardContent>
    </Card>
  );
}
