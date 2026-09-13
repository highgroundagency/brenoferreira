"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/utils";

export type NavTab = { href: string; label: string };

/**
 * Abas em pílula, o mesmo desenho do admin. Rolam na horizontal no celular em vez de
 * quebrar em várias linhas, e marcam sozinhas a aba da página atual.
 */
export function NavTabs({ tabs, className }: { tabs: NavTab[]; className?: string }) {
  const pathname = usePathname();
  return (
    <nav
      aria-label="Seções"
      className={cn(
        "-mx-4 mb-4 flex gap-1.5 overflow-x-auto px-4 pb-1 text-sm sm:mx-0 sm:flex-wrap sm:px-0",
        className,
      )}
    >
      {tabs.map(({ href, label }) => {
        const atual = pathname === href || (href !== "/central" && pathname.startsWith(`${href}/`));
        return (
          <Link
            key={href}
            href={href}
            aria-current={atual ? "page" : undefined}
            className={cn(
              "shrink-0 rounded-full border px-3 py-1.5 transition-colors",
              atual ? "border-primary bg-primary text-primary-foreground" : "hover:bg-accent",
            )}
          >
            {label}
          </Link>
        );
      })}
    </nav>
  );
}
