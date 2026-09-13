import { Feed } from "@/components/central/feed";
import { requireRole } from "@/lib/auth/require-role";
import { STAFF_ROLES } from "@/lib/auth/roles";
import { t } from "@/lib/i18n";

export const dynamic = "force-dynamic";

export default async function CentralPage() {
  await requireRole(STAFF_ROLES);
  return (
    <div className="mx-auto max-w-3xl">
      <h1 className="mb-3 text-xl font-bold">{t("central.feed")}</h1>
      <Feed />
    </div>
  );
}
