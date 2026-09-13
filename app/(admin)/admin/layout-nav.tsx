import { NavTabs } from "@/components/nav-tabs";

const LINKS = [
  { href: "/admin/usuarios", label: "Usuários" },
  { href: "/admin/unidade", label: "Unidade" },
  { href: "/admin/regras", label: "Roteamento" },
  { href: "/admin/jornada", label: "Jornada" },
  { href: "/admin/marcos", label: "Marcos" },
  { href: "/admin/conteudo", label: "Conteúdo" },
  { href: "/admin/templates", label: "Templates" },
  { href: "/admin/unidades", label: "Unidades" },
];

/** `current` continua aceito pelas páginas existentes, mas a aba ativa vem da rota. */
export function AdminNav(_props: { current?: string } = {}) {
  return <NavTabs tabs={LINKS} />;
}
