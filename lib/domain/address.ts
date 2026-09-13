export type AddressKind = "fixed" | "no_number" | "occupation" | "no_fixed_address";

export const ADDRESS_KINDS: { value: AddressKind; label: string }[] = [
  { value: "fixed", label: "Casa com número" },
  { value: "no_number", label: "Sem número / fundos" },
  { value: "occupation", label: "Ocupação" },
  { value: "no_fixed_address", label: "Sem endereço fixo" },
];

export function normalizeCep(raw: string): string {
  return raw.replace(/\D/g, "").slice(0, 8);
}

export function isValidCep(raw: string): boolean {
  return /^\d{8}$/.test(normalizeCep(raw));
}

export function formatCep(raw: string): string {
  const d = normalizeCep(raw);
  return d.length > 5 ? `${d.slice(0, 5)}-${d.slice(5)}` : d;
}

/** Quais campos de endereço fazem sentido para cada tipo (o resto vira "ponto de referência"). */
export function addressFieldsFor(kind: AddressKind): {
  street: boolean;
  number: boolean;
  complement: boolean;
  cep: boolean;
  reference: boolean;
} {
  switch (kind) {
    case "fixed":
      return { street: true, number: true, complement: true, cep: true, reference: false };
    case "no_number":
      return { street: true, number: false, complement: true, cep: true, reference: true };
    case "occupation":
      return { street: false, number: false, complement: false, cep: false, reference: true };
    default:
      return { street: false, number: false, complement: false, cep: false, reference: true };
  }
}

/** Domicílio só existe para endereço fixo ou sem número (mesma regra de register_person). */
export function createsHousehold(kind: AddressKind): boolean {
  return kind === "fixed" || kind === "no_number";
}
