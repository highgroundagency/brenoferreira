import Link from "next/link";
import { t } from "@/lib/i18n";

/** Coração simples na cor da identidade. currentColor para herdar do contexto. */
export function HeartMark({ className = "size-5" }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" className={className} fill="currentColor">
      <path d="M12 20.7l-1.2-1.1C6.1 15.4 3 12.6 3 9.1 3 6.4 5.1 4.3 7.8 4.3c1.5 0 3 .7 4.2 2 1.2-1.3 2.7-2 4.2-2 2.7 0 4.8 2.1 4.8 4.8 0 3.5-3.1 6.3-7.8 10.5l-1.2 1.1z" />
    </svg>
  );
}

/** Marca clicável: leva para a página inicial do papel de quem está logado. */
export function Brand({ href = "/", className = "" }: { href?: string; className?: string }) {
  return (
    <Link
      href={href}
      aria-label={`${t("app.name")} — início`}
      className={`flex items-center gap-2 rounded-md font-bold tracking-tight transition-opacity hover:opacity-80 ${className}`}
    >
      <HeartMark className="size-5 text-primary" />
      <span>{t("app.name")}</span>
    </Link>
  );
}
