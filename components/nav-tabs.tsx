"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/utils";

export type NavTab = { href: string; label: string };

function ehAtual(pathname: string, href: string) {
  return pathname === href || (href.split("/").length > 2 && pathname.startsWith(`${href}/`));
}

function Pilula({ tab, pathname }: { tab: NavTab; pathname: string }) {
  const atual = ehAtual(pathname, tab.href);
  return (
    <Link
      href={tab.href}
      aria-current={atual ? "page" : undefined}
      className={cn(
        "shrink-0 rounded-full border px-3 py-1.5 transition-colors",
        atual ? "border-primary bg-primary text-primary-foreground" : "hover:bg-accent",
      )}
    >
      {tab.label}
    </Link>
  );
}

/**
 * Abas em pílula. No celular viram uma fila só, que rola de lado. A partir de sm são
 * distribuídas em duas filas de tamanho parecido — deixar o flex-wrap decidir empilhava
 * dez em cima e três embaixo.
 */
export function NavTabs({ tabs, className }: { tabs: NavTab[]; className?: string }) {
  const pathname = usePathname();
  const corte = Math.ceil(tabs.length / 2);
  const filas = tabs.length > 7 ? [tabs.slice(0, corte), tabs.slice(corte)] : [tabs];

  return (
    <nav aria-label="Seções" className={cn("mb-4 text-sm", className)}>
      <div className="-mx-4 flex gap-1.5 overflow-x-auto px-4 pb-1 sm:hidden">
        {tabs.map((tab) => (
          <Pilula key={tab.href} tab={tab} pathname={pathname} />
        ))}
      </div>
      <div className="hidden flex-col gap-1.5 sm:flex">
        {filas.map((fila) => (
          <div key={fila[0].href} className="flex flex-wrap gap-1.5">
            {fila.map((tab) => (
              <Pilula key={tab.href} tab={tab} pathname={pathname} />
            ))}
          </div>
        ))}
      </div>
    </nav>
  );
}
