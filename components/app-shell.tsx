import Link from "next/link";
import { Button } from "@/components/ui/button";
import { ADMIN_ROLES, CAMPO_ROLES, type Role, STAFF_ROLES } from "@/lib/auth/roles";
import { t } from "@/lib/i18n";

type Profile = { id: string; full_name: string; role: string; unit_id: string | null; active: boolean };

export function AppShell({ profile, children }: { profile: Profile; children: React.ReactNode }) {
  const role = profile.role as Role;
  const links: { href: string; label: string }[] = [];
  if (CAMPO_ROLES.includes(role))
    links.push(
      { href: "/nova-pessoa", label: t("nav.newPerson") },
      { href: "/meus-cadastros", label: t("nav.myRegistrations") },
    );
  if (STAFF_ROLES.includes(role)) links.push({ href: "/central", label: t("nav.central") });
  if (role === "team_member") links.push({ href: "/central/filas", label: t("central.queues") });
  if (ADMIN_ROLES.includes(role)) links.push({ href: "/admin/usuarios", label: t("nav.admin") });

  return (
    <div className="mx-auto flex min-h-dvh w-full max-w-5xl flex-col">
      <header className="sticky top-0 z-10 flex items-center justify-between gap-2 border-b bg-background/95 px-4 py-2 backdrop-blur">
        <nav className="flex flex-wrap items-center gap-1 overflow-x-auto">
          <Link href="/" className="mr-2 font-bold">
            {t("app.name")}
          </Link>
          {links.map((l) => (
            <Link key={l.href} href={l.href} className="rounded-md px-2 py-1 text-sm hover:bg-accent">
              {l.label}
            </Link>
          ))}
        </nav>
        <form action="/api/auth/signout" method="post" className="flex items-center gap-2">
          <span className="hidden text-xs text-muted-foreground sm:inline">{profile.full_name}</span>
          <Button type="submit" variant="ghost" size="sm">
            {t("nav.logout")}
          </Button>
        </form>
      </header>
      <main className="flex-1 px-4 pb-24 pt-4">{children}</main>
    </div>
  );
}
