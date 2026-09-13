import { describe, expect, it } from "vitest";
import { registrationSchema, toRegisterPayload } from "@/lib/domain/schemas";

const base = {
  client_uuid: "8d5c2e2a-4c0e-4c7b-9c9d-2f4b1a6e7d10",
  full_name: "João",
  phone: "(41) 98765-0001",
  phone_owner: "self" as const,
  age: "25_34" as const,
  neighborhood_id: "8d5c2e2a-4c0e-4c7b-9c9d-2f4b1a6e7d11",
  address_kind: "fixed" as const,
  street: "Rua A",
  number: "10",
  needs: [{ need_type: "food" as const }],
  children: ["15_17" as const],
  consent_accepted: true,
  consent_version: "v1",
};

describe("registrationSchema", () => {
  it("aceita o cadastro mínimo", () => {
    const r = registrationSchema.safeParse(base);
    expect(r.success).toBe(true);
  });
  it("bloqueia menor de 18 (gate de maioridade)", () => {
    const r = registrationSchema.safeParse({ ...base, age: "minor" });
    expect(r.success).toBe(false);
  });
  it("bloqueia sem consentimento", () => {
    const r = registrationSchema.safeParse({ ...base, consent_accepted: false });
    expect(r.success).toBe(false);
  });
  it("exige quem atende quando o número não é da pessoa", () => {
    expect(registrationSchema.safeParse({ ...base, phone_owner: "family" }).success).toBe(false);
    expect(registrationSchema.safeParse({ ...base, phone_owner: "family", contact_name: "Ana" }).success).toBe(true);
  });
  it("ocupação exige referência e dispensa rua/número", () => {
    expect(
      registrationSchema.safeParse({ ...base, address_kind: "occupation", street: undefined, number: undefined })
        .success,
    ).toBe(false);
    expect(
      registrationSchema.safeParse({
        ...base,
        address_kind: "occupation",
        street: undefined,
        number: undefined,
        address_raw: "perto do campo",
      }).success,
    ).toBe(true);
  });
  it("payload: 'Prefiro não dizer' => age_range null e is_adult true; telefone em E.164", () => {
    const parsed = registrationSchema.parse({ ...base, age: "unknown" });
    const p = toRegisterPayload(parsed);
    expect(p.age_range).toBeNull();
    expect(p.is_adult).toBe(true);
    expect(p.phone).toBe("+5541987650001");
    expect(p.consent).toEqual({ accepted: true, version: "v1" });
  });
});
