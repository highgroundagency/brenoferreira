export type Role = "evangelist" | "central" | "team_member" | "unit_admin" | "global_admin";

export const ROLE_LABEL: Record<Role, string> = {
  evangelist: "Evangelista",
  central: "Central",
  team_member: "Membro de time",
  unit_admin: "Admin da unidade",
  global_admin: "Admin global",
};

/** Para onde cada papel vai depois do login. */
export function homeFor(role: Role): string {
  switch (role) {
    case "evangelist":
      return "/nova-pessoa";
    case "team_member":
      return "/central/filas";
    case "unit_admin":
    case "central":
    case "global_admin":
      return "/central";
  }
}

export const CAMPO_ROLES: Role[] = ["evangelist", "central", "unit_admin"];
export const CENTRAL_ROLES: Role[] = ["central", "unit_admin", "global_admin", "team_member"];
export const STAFF_ROLES: Role[] = ["central", "unit_admin", "global_admin"];
export const ADMIN_ROLES: Role[] = ["unit_admin", "global_admin"];
