"use client";
import { zodResolver } from "@hookform/resolvers/zod";
import { useEffect, useMemo, useState } from "react";
import { Controller, useForm } from "react-hook-form";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Checkbox } from "@/components/ui/checkbox";
import { ChipGroup } from "@/components/ui/chip-group";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select } from "@/components/ui/select";
import { Stepper } from "@/components/ui/stepper";
import { Textarea } from "@/components/ui/textarea";
import type { Json } from "@/lib/database.types";
import { ADDRESS_KINDS, addressFieldsFor, normalizeCep } from "@/lib/domain/address";
import { formatBrPhone, toE164 } from "@/lib/domain/phone";
import {
  AGE_OPTIONS,
  CHILD_BANDS,
  ITEM_OPTIONS,
  NEED_OPTIONS,
  OCCUPATION_AREAS,
  type RegistrationInput,
  registrationSchema,
  toRegisterPayload,
} from "@/lib/domain/schemas";
import { t } from "@/lib/i18n";
import { enqueue, isNetworkError } from "@/lib/offline/queue";
import { createClient } from "@/lib/supabase/client";

type Neighborhood = { id: string; name: string; normalized_name: string };
type Consent = { version?: string; base?: string; social_assistance?: string; terms_url?: string } | null;
type NeedType = (typeof NEED_OPTIONS)[number]["value"] | "none";
type ChildBand = (typeof CHILD_BANDS)[number]["value"];

const LAST_NBH_KEY = "transtornar:last_neighborhood";
const OWNER_LABEL = { self: "própria pessoa", family: "família", other: "outro" } as const;

function newDefaults(neighborhoodId: string, consentVersion: string): RegistrationInput {
  return {
    client_uuid: crypto.randomUUID(),
    full_name: "",
    phone: "",
    phone_owner: "self",
    contact_name: "",
    age: undefined as unknown as RegistrationInput["age"],
    neighborhood_id: neighborhoodId,
    address_kind: "fixed",
    street: "",
    number: "",
    complement: "",
    postal_code: "",
    address_raw: "",
    needs: [],
    children: [],
    consent_accepted: false,
    consent_version: consentVersion,
    needs_job: undefined,
    wants_training: undefined,
    occupation_area: "",
    attends_church: undefined,
    observation: "",
    email: "",
    decided_at: "",
  };
}

export function NewPersonForm({ neighborhoods, consent }: { neighborhoods: Neighborhood[]; consent: Consent }) {
  const consentVersion = consent?.version ?? "v1";
  const [lastNbh] = useState(() => {
    try {
      return localStorage.getItem(LAST_NBH_KEY) ?? "";
    } catch {
      return "";
    }
  });
  const form = useForm<RegistrationInput>({
    resolver: zodResolver(registrationSchema),
    defaultValues: newDefaults(lastNbh, consentVersion),
    mode: "onTouched",
  });
  const { register, handleSubmit, control, watch, setValue, reset, formState } = form;

  const [needTypes, setNeedTypes] = useState<NeedType[]>([]);
  const [items, setItems] = useState<string[]>([]);
  const [childrenCount, setChildrenCount] = useState(0);
  const [bands, setBands] = useState<ChildBand[]>([]);
  const [more, setMore] = useState(false);
  const [confirming, setConfirming] = useState<ReturnType<typeof toRegisterPayload> | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [success, setSuccess] = useState<string | null>(null);
  const [contactsSupported, setContactsSupported] = useState(false);

  const phone = watch("phone");
  const phoneOwner = watch("phone_owner");
  const age = watch("age");
  const addressKind = watch("address_kind");
  const neighborhoodId = watch("neighborhood_id");
  const consentAccepted = watch("consent_accepted");
  const e164 = useMemo(() => toE164(phone ?? ""), [phone]);
  const fields = addressFieldsFor(addressKind ?? "fixed");
  const hasNeed = needTypes.some((n) => n !== "none");
  const isMinor = age === "minor";

  useEffect(() => {
    setContactsSupported(typeof navigator !== "undefined" && "contacts" in navigator && "ContactsManager" in window);
  }, []);

  // necessidades -> array do schema
  useEffect(() => {
    const needs: RegistrationInput["needs"] = [];
    for (const n of needTypes) {
      if (n === "none") continue;
      if (n === "furniture" || n === "appliance") {
        const chosen = items.filter((i) => ITEM_OPTIONS[n].some((o) => o.value === i));
        if (chosen.length === 0) needs.push({ need_type: n });
        for (const i of chosen) needs.push({ need_type: n, item_code: i });
      } else {
        needs.push({ need_type: n });
      }
    }
    setValue("needs", needs);
  }, [needTypes, items, setValue]);

  // filhos -> faixas
  useEffect(() => {
    setBands((prev) => {
      const next = [...prev].slice(0, childrenCount);
      while (next.length < childrenCount) next.push("6_11");
      return next;
    });
  }, [childrenCount]);
  useEffect(() => {
    setValue("children", bands);
  }, [bands, setValue]);

  async function pickContact() {
    try {
      const nav = navigator as Navigator & {
        contacts?: {
          select: (props: string[], opts: { multiple: boolean }) => Promise<{ tel?: string[]; name?: string[] }[]>;
        };
      };
      const res = await nav.contacts?.select(["tel", "name"], { multiple: false });
      const c = res?.[0];
      if (c?.tel?.[0]) setValue("phone", formatBrPhone(c.tel[0]), { shouldValidate: true });
      if (c?.name?.[0] && !watch("full_name")) setValue("full_name", c.name[0]);
    } catch {
      // usuário cancelou
    }
  }

  async function lookupCep(raw: string) {
    const cep = normalizeCep(raw);
    if (cep.length !== 8) return;
    try {
      const r = await fetch(`/api/cep/${cep}`);
      if (!r.ok) return;
      const j = (await r.json()) as { street: string; neighborhood: string };
      if (j.street && !watch("street")) setValue("street", j.street);
      if (j.neighborhood) {
        const norm = j.neighborhood
          .normalize("NFD")
          .replace(/\p{Diacritic}/gu, "")
          .toLowerCase()
          .trim();
        const match = neighborhoods.find((n) => n.normalized_name === norm);
        if (match) setValue("neighborhood_id", match.id, { shouldValidate: true });
      }
    } catch {
      // sem rede: segue manual
    }
  }

  const onValid = handleSubmit((values) => {
    const parsed = registrationSchema.parse(values);
    setConfirming(toRegisterPayload(parsed));
  });

  async function send() {
    if (!confirming) return;
    setSubmitting(true);
    const payload = confirming;
    const supabase = createClient();
    const nbhName = neighborhoods.find((n) => n.id === payload.neighborhood_id)?.name ?? "";
    const firstName = String(payload.full_name).split(" ")[0];
    try {
      localStorage.setItem(LAST_NBH_KEY, payload.neighborhood_id);
    } catch {
      // storage indisponível
    }
    const { data, error } = await supabase.rpc("register_person", { payload: payload as unknown as Json });
    setSubmitting(false);
    if (error) {
      if (isNetworkError(error)) {
        await enqueue(payload.client_uuid, "register", payload as unknown as Record<string, unknown>);
        toast.info(t("form.savedOffline"));
        finish(`${firstName} salvo(a) no aparelho — envia quando houver sinal.`);
        return;
      }
      toast.error(humanError(error.message));
      setConfirming(null);
      return;
    }
    const res = data as { first_contact?: string | null; review_status?: string; idempotent?: boolean } | null;
    if (res?.review_status === "possible_duplicate") {
      finish(
        `${firstName} registrado(a) em ${nbhName}. Telefone já cadastrado: a central vai revisar antes do primeiro contato.`,
      );
    } else if (res?.first_contact === "transtornar_video1_v1") {
      finish(t("form.success", { name: firstName, neighborhood: nbhName }));
    } else {
      finish(t("form.successOptin", { name: firstName, neighborhood: nbhName }));
    }
  }

  function finish(message: string) {
    setSuccess(message);
    setConfirming(null);
    setNeedTypes([]);
    setItems([]);
    setChildrenCount(0);
    setBands([]);
    setMore(false);
    reset(newDefaults(watch("neighborhood_id") ?? "", consentVersion));
  }

  async function tally(minor: boolean) {
    if (!neighborhoodId) {
      toast.error("Escolha o bairro para registrar a decisão.");
      return;
    }
    const supabase = createClient();
    const { error } = await supabase.rpc("record_decision_tally", {
      p_neighborhood_id: neighborhoodId,
      p_minor: minor,
    });
    if (error && isNetworkError(error)) {
      await enqueue(crypto.randomUUID(), "tally", { neighborhood_id: neighborhoodId, minor });
      toast.info(t("form.savedOffline"));
    } else if (error) {
      toast.error(humanError(error.message));
      return;
    }
    finish(
      minor
        ? "Decisão registrada (menor de 18, sem cadastro). Deus abençoe!"
        : "Decisão registrada, sem cadastro. Deus abençoe!",
    );
  }

  if (success) {
    return (
      <Card>
        <CardContent className="flex flex-col gap-4 p-4">
          <p className="text-lg font-medium">{success}</p>
          <Button size="lg" onClick={() => setSuccess(null)}>
            Nova pessoa
          </Button>
        </CardContent>
      </Card>
    );
  }

  if (confirming) {
    const nbhName = neighborhoods.find((n) => n.id === confirming.neighborhood_id)?.name ?? "";
    return (
      <Card>
        <CardContent className="flex flex-col gap-3 p-4">
          <p className="text-sm text-muted-foreground">Confira antes de enviar:</p>
          <p className="text-lg font-semibold">{String(confirming.full_name)}</p>
          <p className="text-2xl font-bold tabular-nums">{formatBrPhone(String(confirming.phone ?? ""))}</p>
          <p className="text-sm">
            Número: {OWNER_LABEL[confirming.phone_owner as keyof typeof OWNER_LABEL]}
            {confirming.contact_name ? ` (${confirming.contact_name})` : ""} · {nbhName}
          </p>
          <p className="text-sm text-muted-foreground">
            {confirming.phone_owner === "self"
              ? "Vai receber o vídeo de boas-vindas em alguns minutos."
              : "Quem atende vai receber uma mensagem neutra pedindo autorização."}
          </p>
          <div className="flex gap-2">
            <Button
              variant="outline"
              size="lg"
              className="flex-1"
              onClick={() => setConfirming(null)}
              disabled={submitting}
            >
              Voltar
            </Button>
            <Button size="lg" className="flex-1" onClick={send} disabled={submitting}>
              {submitting ? "Enviando…" : "Confirmar"}
            </Button>
          </div>
        </CardContent>
      </Card>
    );
  }

  return (
    <form onSubmit={onValid} className="flex flex-col gap-5">
      {/* 1. Nome */}
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="full_name">{t("form.name")}</Label>
        <Input
          id="full_name"
          autoComplete="off"
          placeholder="Nome (pode ser só o primeiro)"
          {...register("full_name")}
        />
        <FieldError msg={formState.errors.full_name?.message} />
      </div>

      {/* 2. WhatsApp */}
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="phone">{t("form.phone")}</Label>
        <div className="flex gap-2">
          <Controller
            control={control}
            name="phone"
            render={({ field }) => (
              <Input
                id="phone"
                type="tel"
                inputMode="tel"
                autoComplete="off"
                placeholder="(41) 9 9999-9999"
                value={field.value ?? ""}
                onChange={(e) => field.onChange(formatBrPhone(e.target.value))}
                onBlur={field.onBlur}
              />
            )}
          />
          {contactsSupported ? (
            <Button type="button" variant="outline" onClick={pickContact}>
              Contatos
            </Button>
          ) : null}
        </div>
        {e164 ? <p className="text-xs text-muted-foreground">Confirme: {formatBrPhone(e164)}</p> : null}
        <FieldError msg={formState.errors.phone?.message} />
        <Label className="mt-1">{t("form.phoneOwner")}</Label>
        <Controller
          control={control}
          name="phone_owner"
          render={({ field }) => (
            <ChipGroup
              name="phone_owner"
              options={[
                { value: "self", label: "Própria pessoa" },
                { value: "family", label: "Família" },
                { value: "other", label: "Outro" },
              ]}
              value={field.value}
              onChange={(v) => field.onChange(v ?? "self")}
              allowEmpty={false}
            />
          )}
        />
        {phoneOwner !== "self" ? (
          <div className="flex flex-col gap-1.5">
            <Input placeholder="Nome de quem atende esse número" {...register("contact_name")} />
            <FieldError msg={formState.errors.contact_name?.message} />
          </div>
        ) : null}
      </div>

      {/* 3. Idade */}
      <div className="flex flex-col gap-1.5">
        <Label>{t("form.age")}</Label>
        <Controller
          control={control}
          name="age"
          render={({ field }) => (
            <ChipGroup
              name="age"
              options={[...AGE_OPTIONS]}
              value={field.value ?? null}
              onChange={(v) => field.onChange(v)}
              allowEmpty={false}
            />
          )}
        />
        {isMinor ? (
          <div className="rounded-md border border-amber-300 bg-amber-50 p-3 text-sm text-amber-900">
            Menor de 18: registramos só a decisão, sem nome e telefone. O acompanhamento depende do responsável (Fase
            2).
            <Button type="button" className="mt-2 w-full" onClick={() => tally(true)}>
              Registrar decisão do adolescente
            </Button>
          </div>
        ) : (
          <FieldError msg={formState.errors.age?.message} />
        )}
      </div>

      {/* 4. Bairro */}
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="neighborhood_id">{t("form.neighborhood")}</Label>
        <Select id="neighborhood_id" {...register("neighborhood_id")}>
          <option value="">Escolha o bairro</option>
          {neighborhoods.map((n) => (
            <option key={n.id} value={n.id}>
              {n.name}
            </option>
          ))}
        </Select>
        <FieldError msg={formState.errors.neighborhood_id?.message} />
      </div>

      {/* 5. Endereço */}
      <div className="flex flex-col gap-1.5">
        <Label>{t("form.address")}</Label>
        <Controller
          control={control}
          name="address_kind"
          render={({ field }) => (
            <ChipGroup
              name="address_kind"
              options={ADDRESS_KINDS}
              value={field.value}
              onChange={(v) => field.onChange(v ?? "fixed")}
              allowEmpty={false}
            />
          )}
        />
        {fields.cep ? (
          <Input
            placeholder="CEP (opcional)"
            inputMode="numeric"
            {...register("postal_code", { onChange: (e) => lookupCep(e.target.value) })}
          />
        ) : null}
        {fields.street ? <Input placeholder="Rua" {...register("street")} /> : null}
        <FieldError msg={formState.errors.street?.message} />
        <div className="flex gap-2">
          {fields.number ? (
            <Input placeholder="Número" className="w-32" inputMode="numeric" {...register("number")} />
          ) : null}
          {fields.complement ? <Input placeholder="Complemento" {...register("complement")} /> : null}
        </div>
        <FieldError msg={formState.errors.number?.message} />
        {fields.reference ? <Input placeholder="Ponto de referência" {...register("address_raw")} /> : null}
        <FieldError msg={formState.errors.address_raw?.message} />
      </div>

      {/* 6. Necessidades */}
      <div className="flex flex-col gap-1.5">
        <Label>{t("form.needs")}</Label>
        <ChipGroup<NeedType>
          name="needs"
          multiple
          options={[...NEED_OPTIONS, { value: "none", label: "Nada" }]}
          value={needTypes}
          onChange={(v) => {
            const last = v[v.length - 1];
            if (last === "none") setNeedTypes(["none"]);
            else setNeedTypes(v.filter((x) => x !== "none"));
          }}
        />
        {(["furniture", "appliance"] as const).map((k) =>
          needTypes.includes(k) ? (
            <ChipGroup
              key={k}
              name={`items_${k}`}
              multiple
              options={ITEM_OPTIONS[k]}
              value={items}
              onChange={setItems}
              className="pl-2"
            />
          ) : null,
        )}
      </div>

      {/* 7. Filhos */}
      <div className="flex flex-col gap-1.5">
        <Label>{t("form.children")}</Label>
        <Stepper value={childrenCount} onChange={setChildrenCount} max={9} label="quantidade de filhos" />
        {bands.map((b, i) => (
          <div key={`child-${i.toString()}`} className="flex items-center gap-2">
            <span className="w-14 text-xs text-muted-foreground">Filho {i + 1}</span>
            <ChipGroup<ChildBand>
              name={`child_${i}`}
              options={[...CHILD_BANDS]}
              value={b}
              onChange={(v) => setBands((prev) => prev.map((x, j) => (j === i ? (v ?? x) : x)))}
              allowEmpty={false}
            />
          </div>
        ))}
      </div>

      {/* 8. Consentimento */}
      <div className="flex flex-col gap-2 rounded-md border p-3">
        <Label>{t("form.consent")} — leia em voz alta</Label>
        <p className="text-sm">
          {consent?.base ??
            "O Transtornar vai guardar seus dados para te acompanhar. Você pode pedir para parar ou apagar a qualquer momento respondendo SAIR."}
        </p>
        {hasNeed && consent?.social_assistance ? <p className="text-sm">{consent.social_assistance}</p> : null}
        <label htmlFor="consent_accepted" className="flex items-center gap-2 text-sm">
          <Checkbox id="consent_accepted" {...register("consent_accepted")} /> A pessoa concordou.
          <a
            href={consent?.terms_url ?? "/termos"}
            target="_blank"
            rel="noreferrer"
            className="ml-auto text-xs underline"
          >
            termo
          </a>
        </label>
        <FieldError msg={formState.errors.consent_accepted?.message} />
      </div>

      {/* Mais detalhes */}
      <Button type="button" variant="ghost" onClick={() => setMore((m) => !m)}>
        {more ? "Ocultar detalhes" : `${t("form.moreDetails")} (opcional)`}
      </Button>
      {more ? (
        <div className="flex flex-col gap-4 rounded-md border p-3">
          <div className="flex flex-col gap-1.5">
            <Label>Trabalho</Label>
            <Controller
              control={control}
              name="needs_job"
              render={({ field }) => (
                <ChipGroup
                  name="needs_job"
                  options={[
                    { value: "yes", label: "Precisa de trabalho" },
                    { value: "no", label: "Não precisa" },
                  ]}
                  value={field.value === undefined ? null : field.value ? "yes" : "no"}
                  onChange={(v) => field.onChange(v === null ? undefined : v === "yes")}
                />
              )}
            />
            <Controller
              control={control}
              name="wants_training"
              render={({ field }) => (
                <ChipGroup
                  name="wants_training"
                  options={[{ value: "yes", label: "Quer fazer curso" }]}
                  value={field.value ? "yes" : null}
                  onChange={(v) => field.onChange(v === "yes" ? true : undefined)}
                />
              )}
            />
            <Controller
              control={control}
              name="occupation_area"
              render={({ field }) => (
                <ChipGroup
                  name="occupation_area"
                  options={OCCUPATION_AREAS.map((a) => ({ value: a, label: a }))}
                  value={field.value || null}
                  onChange={(v) => field.onChange(v ?? "")}
                />
              )}
            />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label>Já frequenta igreja?</Label>
            <Controller
              control={control}
              name="attends_church"
              render={({ field }) => (
                <ChipGroup
                  name="attends_church"
                  options={[
                    { value: "yes", label: "Sim" },
                    { value: "no", label: "Não" },
                  ]}
                  value={field.value === undefined ? null : field.value ? "yes" : "no"}
                  onChange={(v) => field.onChange(v === null ? undefined : v === "yes")}
                />
              )}
            />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="observation">Algo que a central deve saber?</Label>
            <Textarea id="observation" maxLength={140} rows={2} {...register("observation")} />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="email">E-mail (opcional)</Label>
            <Input id="email" type="email" inputMode="email" {...register("email")} />
            <FieldError msg={formState.errors.email?.message} />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="decided_at">Aceitou em outra data?</Label>
            <Input id="decided_at" type="date" {...register("decided_at")} />
          </div>
        </div>
      ) : null}

      {/* Rodapé fixo */}
      <div className="fixed inset-x-0 bottom-0 z-10 border-t bg-background/95 p-3 backdrop-blur">
        <div className="mx-auto flex max-w-lg flex-col gap-2">
          <Button type="submit" size="lg" disabled={isMinor || !consentAccepted || submitting}>
            {t("form.submit")}
          </Button>
          {!isMinor ? (
            <Button type="button" variant="link" size="sm" onClick={() => tally(false)}>
              {t("form.tally")}
            </Button>
          ) : null}
        </div>
      </div>
    </form>
  );
}

function FieldError({ msg }: { msg?: string }) {
  return msg ? <p className="text-xs text-destructive">{msg}</p> : null;
}

function humanError(message: string): string {
  if (message.includes("neighborhood_not_in_unit")) return "Esse bairro não pertence à sua unidade.";
  if (message.includes("invalid_phone")) return "Telefone inválido.";
  if (message.includes("minor_not_allowed")) return "Menores de 18 não são cadastrados: use o botão de decisão.";
  if (message.includes("consent_required")) return "É preciso o consentimento para cadastrar.";
  if (message.includes("papel não autorizado") || message.includes("permission"))
    return "Seu acesso não permite cadastrar.";
  return "Não foi possível enviar. Tente novamente.";
}
