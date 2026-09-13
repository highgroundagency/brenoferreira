import { z } from "zod";
import { toE164 } from "./phone";

export const AGE_OPTIONS = [
  { value: "minor", label: "Menor de 18" },
  { value: "18_24", label: "18-24" },
  { value: "25_34", label: "25-34" },
  { value: "35_49", label: "35-49" },
  { value: "50_64", label: "50-64" },
  { value: "65_plus", label: "65+" },
  { value: "unknown", label: "Prefiro não dizer" },
] as const;
export type AgeChoice = (typeof AGE_OPTIONS)[number]["value"];

export const NEED_OPTIONS = [
  { value: "food", label: "Alimento" },
  { value: "furniture", label: "Móvel" },
  { value: "appliance", label: "Eletrodoméstico" },
  { value: "clothing", label: "Roupas" },
  { value: "health", label: "Saúde" },
] as const;
export const ITEM_OPTIONS: Record<"furniture" | "appliance", { value: string; label: string }[]> = {
  furniture: [
    { value: "cama", label: "Cama" },
    { value: "sofa", label: "Sofá" },
    { value: "mesa", label: "Mesa" },
  ],
  appliance: [
    { value: "fogao", label: "Fogão" },
    { value: "geladeira", label: "Geladeira" },
    { value: "maquina", label: "Máquina de lavar" },
  ],
};
export const CHILD_BANDS = [
  { value: "0_5", label: "0-5" },
  { value: "6_11", label: "6-11" },
  { value: "12_14", label: "12-14" },
  { value: "15_17", label: "15-17" },
  { value: "18_plus", label: "18+" },
] as const;
export const OCCUPATION_AREAS = [
  "cozinha",
  "construção",
  "limpeza",
  "vendas",
  "transporte",
  "cuidados",
  "administrativo",
  "autônomo/empresário",
  "outro",
] as const;

const needSchema = z.object({
  need_type: z.enum(["food", "furniture", "appliance", "clothing", "health", "other"]),
  item_code: z.string().max(40).optional(),
  raw_text: z.string().max(140).optional(),
});

/** Formulário "Nova pessoa" — uma tela obrigatória + "Mais detalhes". */
export const registrationSchema = z
  .object({
    client_uuid: z.string().uuid(),
    full_name: z.string().trim().min(2, "Informe o nome").max(120),
    phone: z.string().refine((v) => toE164(v) !== null, "Telefone inválido"),
    phone_owner: z.enum(["self", "family", "other"]),
    contact_name: z.string().trim().max(80).optional(),
    age: z.enum(["minor", "18_24", "25_34", "35_49", "50_64", "65_plus", "unknown"]),
    neighborhood_id: z.string().uuid("Escolha o bairro"),
    address_kind: z.enum(["fixed", "no_number", "occupation", "no_fixed_address"]),
    street: z.string().trim().max(120).optional(),
    number: z.string().trim().max(20).optional(),
    complement: z.string().trim().max(80).optional(),
    postal_code: z.string().trim().max(9).optional(),
    address_raw: z.string().trim().max(200).optional(),
    needs: z.array(needSchema).max(8),
    children: z.array(z.enum(["0_5", "6_11", "12_14", "15_17", "18_plus"])).max(9),
    consent_accepted: z.boolean(),
    consent_version: z.string().default("v1"),
    needs_job: z.boolean().optional(),
    wants_training: z.boolean().optional(),
    occupation_area: z.string().max(60).optional(),
    attends_church: z.boolean().optional(),
    observation: z.string().trim().max(140).optional(),
    email: z.string().trim().email("E-mail inválido").optional().or(z.literal("")),
    decided_at: z.string().optional(),
  })
  .superRefine((v, ctx) => {
    if (v.age === "minor")
      ctx.addIssue({
        code: "custom",
        path: ["age"],
        message: "Menor de 18: registre apenas a decisão (sem cadastro).",
      });
    if (!v.consent_accepted)
      ctx.addIssue({ code: "custom", path: ["consent_accepted"], message: "Leia o roteiro e marque o consentimento." });
    if (v.phone_owner !== "self" && !v.contact_name)
      ctx.addIssue({ code: "custom", path: ["contact_name"], message: "Quem atende esse número?" });
    if (v.address_kind === "fixed" && !v.street)
      ctx.addIssue({ code: "custom", path: ["street"], message: "Informe a rua" });
    if (v.address_kind === "fixed" && !v.number)
      ctx.addIssue({ code: "custom", path: ["number"], message: "Informe o número" });
    if (v.address_kind !== "fixed" && !v.address_raw && !v.street)
      ctx.addIssue({ code: "custom", path: ["address_raw"], message: "Dê um ponto de referência" });
  });

export type RegistrationInput = z.input<typeof registrationSchema>;
export type Registration = z.output<typeof registrationSchema>;

/** Converte o formulário validado no payload da RPC register_person. */
export function toRegisterPayload(v: Registration) {
  return {
    client_uuid: v.client_uuid,
    full_name: v.full_name,
    phone: toE164(v.phone),
    phone_owner: v.phone_owner,
    contact_name: v.contact_name || null,
    is_adult: v.age !== "minor",
    age_range: v.age === "unknown" || v.age === "minor" ? null : v.age,
    neighborhood_id: v.neighborhood_id,
    address_kind: v.address_kind,
    street: v.street || null,
    number: v.number || null,
    complement: v.complement || null,
    postal_code: v.postal_code || null,
    address_raw: v.address_raw || null,
    needs: v.needs,
    children: v.children,
    consent: { accepted: v.consent_accepted, version: v.consent_version },
    needs_job: v.needs_job ?? null,
    wants_training: v.wants_training ?? null,
    occupation_area: v.occupation_area || null,
    attends_church: v.attends_church ?? null,
    observation: v.observation || null,
    email: v.email || null,
    decided_at: v.decided_at || null,
    source: "street",
  };
}
