import Link from "next/link";
import { Brand } from "@/components/brand";
import { MobileMenu } from "@/components/mobile-menu";
import { Button } from "@/components/ui/button";
import { ADMIN_ROLES, CAMPO_ROLES, homeFor, type Role, STAFF_ROLES } from "@/lib/auth/roles";
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
      <header className="sticky top-0 z-20 border-b bg-background/95 backdrop-blur">
        <div className="flex h-14 items-center justify-between gap-3 px-4">
          <Brand href={homeFor(role)} />

          {/* No celular as áreas ficam no menu; a partir de sm aparecem na barra. */}
          <nav className="hidden items-center gap-1 sm:flex">
            {links.map((l) => (
              <Link
                key={l.href}
                href={l.href}
                className="rounded-md px-3 py-1.5 text-sm transition-colors hover:bg-accent"
              >
                {l.label}
              </Link>
            ))}
          </nav>

          <div className="flex items-center gap-1">
            <form action="/api/auth/signout" method="post" className="hidden items-center gap-2 sm:flex">
              <span className="max-w-[12ch] truncate text-xs text-muted-foreground">{profile.full_name}</span>
              <Button type="submit" variant="ghost" size="sm">
                {t("nav.logout")}
              </Button>
            </form>
            <MobileMenu links={links} userName={profile.full_name} />
          </div>
        </div>
      </header>
      <main className="flex-1 px-4 pb-24 pt-4">{children}</main>
    </div>
  );
}
