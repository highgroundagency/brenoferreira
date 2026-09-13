import Link from "next/link";

const LINKS = [
  ["/admin/usuarios", "Usuários"],
  ["/admin/unidade", "Unidade"],
  ["/admin/regras", "Roteamento"],
  ["/admin/jornada", "Jornada"],
  ["/admin/marcos", "Marcos"],
  ["/admin/conteudo", "Conteúdo"],
  ["/admin/templates", "Templates"],
  ["/admin/unidades", "Unidades"],
];

export function AdminNav({ current }: { current: string }) {
  return (
    <nav className="mb-4 flex flex-wrap gap-1 text-sm">
      {LINKS.map(([href, label]) => (
        <Link
          key={href}
          href={href}
          className={`rounded-full border px-3 py-1 ${current === href ? "bg-primary text-primary-foreground" : ""}`}
        >
          {label}
        </Link>
      ))}
    </nav>
  );
}
