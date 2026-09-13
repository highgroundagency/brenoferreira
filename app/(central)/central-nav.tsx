import { NavTabs } from "@/components/nav-tabs";

const SECOES = [
  { href: "/central", label: "Chegadas" },
  { href: "/central/filas", label: "Filas" },
  { href: "/central/acompanhamento", label: "Acompanhamento" },
  { href: "/central/entregas", label: "Entregas" },
  { href: "/central/educacao", label: "Educação" },
  { href: "/central/trabalho", label: "Trabalho" },
  { href: "/central/igrejas", label: "Igrejas" },
  { href: "/central/estoque", label: "Estoque" },
  { href: "/central/eventos", label: "Eventos" },
  { href: "/central/mantenedores", label: "Mantenedores" },
  { href: "/central/beneficios", label: "Benefícios" },
  { href: "/central/impacto", label: "Impacto" },
  { href: "/central/bairros", label: "Bairros" },
];

export function CentralNav() {
  return <NavTabs tabs={SECOES} />;
}
