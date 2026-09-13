import { sha256Hex } from "./auth.ts";

/** Classifica uma mensagem inbound da Meta no formato que public.handle_inbound espera (função pura). */
export function classifyMessage(msg: Record<string, unknown>): {
  kind: "button" | "text";
  payload: Record<string, unknown>;
} {
  const wamid = msg.id as string;
  const type = msg.type as string;
  if (type === "button") {
    const b = msg.button as { payload?: string; text?: string };
    return { kind: "button", payload: { button_id: b.payload ?? b.text ?? "", wamid } };
  }
  if (type === "interactive") {
    const i = msg.interactive as {
      type: string;
      button_reply?: { id: string; title: string };
      list_reply?: { id: string; title: string };
    };
    const reply = i.button_reply ?? i.list_reply;
    return { kind: "button", payload: { button_id: reply?.id ?? "", wamid } };
  }
  if (type === "text") {
    return { kind: "text", payload: { text: String((msg.text as { body?: string })?.body ?? ""), wamid } };
  }
  return { kind: "text", payload: { text: `[${type}] mídia recebida`, wamid } };
}

/** Chave idempotente: sha256(wamid|tipo|status|timestamp). */
export async function dedupKey(parts: (string | number | undefined)[]): Promise<string> {
  return await sha256Hex(parts.map((p) => String(p ?? "")).join("|"));
}
