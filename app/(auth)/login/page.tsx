import { LoginForm } from "@/components/auth/login-form";

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ next?: string; inactive?: string }>;
}) {
  const { next, inactive } = await searchParams;
  return (
    <main className="mx-auto flex min-h-dvh max-w-sm flex-col justify-center gap-6 px-4 py-8">
      <div>
        <h1 className="text-2xl font-bold">Transtornar</h1>
        <p className="text-sm text-muted-foreground">Entre com o e-mail e a senha criados no convite.</p>
        {inactive ? (
          <p className="mt-2 text-sm text-destructive">Seu acesso está inativo. Fale com a central.</p>
        ) : null}
      </div>
      <LoginForm next={next} />
    </main>
  );
}
