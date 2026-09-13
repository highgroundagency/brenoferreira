import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

export async function POST(request: Request) {
  const supabase = await createClient();
  await supabase.rpc("refresh_impact");
  return NextResponse.redirect(new URL("/central/impacto", request.url), { status: 303 });
}
