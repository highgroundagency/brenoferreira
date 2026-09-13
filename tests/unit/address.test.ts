import { describe, expect, it } from "vitest";
import { addressFieldsFor, createsHousehold, formatCep, isValidCep, normalizeCep } from "@/lib/domain/address";

describe("address", () => {
  it("CEP", () => {
    expect(normalizeCep("81810-000")).toBe("81810000");
    expect(isValidCep("81810-000")).toBe(true);
    expect(isValidCep("8181")).toBe(false);
    expect(formatCep("81810000")).toBe("81810-000");
  });
  it("campos por tipo de endereço", () => {
    expect(addressFieldsFor("fixed").number).toBe(true);
    expect(addressFieldsFor("no_number").number).toBe(false);
    expect(addressFieldsFor("occupation").reference).toBe(true);
    expect(addressFieldsFor("no_fixed_address").street).toBe(false);
  });
  it("household só para endereço fixo/sem número", () => {
    expect(createsHousehold("fixed")).toBe(true);
    expect(createsHousehold("no_number")).toBe(true);
    expect(createsHousehold("occupation")).toBe(false);
    expect(createsHousehold("no_fixed_address")).toBe(false);
  });
});
