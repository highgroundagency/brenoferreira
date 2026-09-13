import Link from "next/link";
import { Feed } from "@/components/central/feed";
import { requireRole } from "@/lib/auth/require-role";
import { STAFF_ROLES } from "@/lib/auth/roles";
import { t } from "@/lib/i18n";

export const dynamic = "force-dynamic";

export default async function CentralPage() {
  await requireRole(STAFF_ROLES);
  return (
    <div className="mx-auto max-w-3xl">
      <div className="mb-3 flex items-center justify-between">
        <h1 className="text-xl font-bold">{t("central.feed")}</h1>
        <nav className="flex gap-2 text-sm">
          <Link className="underline" href="/central/filas">
            {t("central.queues")}
          </Link>
          <Link className="underline" href="/central/acompanhamento">
            Acompanhamento
          </Link>
          <Link className="underline" href="/central/entregas">
            Entregas
          </Link>
          <Link className="underline" href="/central/educacao">
            Educação
          </Link>
          <Link className="underline" href="/central/trabalho">
            Trabalho
          </Link>
          <Link className="underline" href="/central/igrejas">
            Igrejas
          </Link>
          <Link className="underline" href="/central/estoque">
            Estoque
          </Link>
          <Link className="underline" href="/central/eventos">
            Eventos
          </Link>
          <Link className="underline" href="/central/mantenedores">
            Mantenedores
          </Link>
          <Link className="underline" href="/central/beneficios">
            Benefícios
          </Link>
          <Link className="underline" href="/central/impacto">
            Impacto
          </Link>
          <Link className="underline" href="/central/bairros">
            {t("central.neighborhoods")}
          </Link>
        </nav>
      </div>
      <Feed />
    </div>
  );
}
