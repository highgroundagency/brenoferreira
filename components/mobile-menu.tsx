"use client";

import Link from "next/link";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { t } from "@/lib/i18n";

/** Menu de três tracinhos: no celular as áreas ficam aqui, não espremidas na barra. */
export function MobileMenu({ links, userName }: { links: { href: string; label: string }[]; userName: string }) {
  const [aberto, setAberto] = useState(false);
  return (
    <div className="sm:hidden">
      <button
        type="button"
        onClick={() => setAberto((v) => !v)}
        aria-expanded={aberto}
        aria-label={aberto ? "Fechar menu" : "Abrir menu"}
        className="inline-flex size-10 items-center justify-center rounded-md transition-colors hover:bg-accent"
      >
        <svg
          viewBox="0 0 24 24"
          aria-hidden="true"
          className="size-5"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
          strokeLinecap="round"
        >
          {aberto ? (
            <>
              <path d="M5 5l14 14" />
              <path d="M19 5L5 19" />
            </>
          ) : (
            <>
              <path d="M4 7h16" />
              <path d="M4 12h16" />
              <path d="M4 17h16" />
            </>
          )}
        </svg>
      </button>

      {aberto && (
        <>
          <button
            type="button"
            aria-hidden="true"
            tabIndex={-1}
            onClick={() => setAberto(false)}
            className="fixed inset-0 top-14 z-10 cursor-default bg-black/20"
          />
          <div className="absolute inset-x-0 top-14 z-20 border-b bg-background p-2 shadow-lg">
            <nav className="flex flex-col">
              {links.map((l) => (
                <Link
                  key={l.href}
                  href={l.href}
                  onClick={() => setAberto(false)}
                  className="rounded-md px-3 py-3 text-sm transition-colors hover:bg-accent"
                >
                  {l.label}
                </Link>
              ))}
            </nav>
            <div className="mt-2 flex items-center justify-between border-t px-3 pt-2">
              <span className="truncate text-xs text-muted-foreground">{userName}</span>
              <form action="/api/auth/signout" method="post">
                <Button type="submit" variant="ghost" size="sm">
                  {t("nav.logout")}
                </Button>
              </form>
            </div>
          </div>
        </>
      )}
    </div>
  );
}
