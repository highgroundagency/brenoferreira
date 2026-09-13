import {
  NON_RETRYABLE,
  type SendResult,
  type TemplateButton,
  type WhatsAppProvider,
  WhatsAppSendError,
} from "./provider.ts";

export type MetaConfig = { token: string; phoneNumberId: string; apiVersion?: string; fetchImpl?: typeof fetch };

/** Corpo de envio para a Graph API (função pura, testável). */
export function buildTemplatePayload(
  to: string,
  name: string,
  language: string,
  opts: { bodyParams?: string[]; headerVideoLink?: string; buttons?: TemplateButton[] },
) {
  const components: Record<string, unknown>[] = [];
  if (opts.headerVideoLink)
    components.push({ type: "header", parameters: [{ type: "video", video: { link: opts.headerVideoLink } }] });
  if (opts.bodyParams?.length)
    components.push({ type: "body", parameters: opts.bodyParams.map((text) => ({ type: "text", text })) });
  (opts.buttons ?? []).forEach((b, index) => {
    components.push({
      type: "button",
      sub_type: "quick_reply",
      index,
      parameters: [{ type: "payload", payload: b.id }],
    });
  });
  return {
    messaging_product: "whatsapp",
    to,
    type: "template",
    template: { name, language: { code: language }, components },
  };
}

export function buildInteractivePayload(to: string, body: string, buttons: TemplateButton[], videoLink?: string) {
  return {
    messaging_product: "whatsapp",
    to,
    type: "interactive",
    interactive: {
      type: "button",
      ...(videoLink ? { header: { type: "video", video: { link: videoLink } } } : {}),
      body: { text: body },
      action: {
        buttons: buttons.slice(0, 3).map((b) => ({ type: "reply", reply: { id: b.id, title: b.title.slice(0, 20) } })),
      },
    },
  };
}

export class MetaCloudProvider implements WhatsAppProvider {
  private base: string;
  private fetchImpl: typeof fetch;
  constructor(private cfg: MetaConfig) {
    const v = cfg.apiVersion ?? "v24.0";
    this.base = `https://graph.facebook.com/${v}`;
    this.fetchImpl = cfg.fetchImpl ?? fetch;
  }

  private async post(path: string, body: unknown): Promise<SendResult> {
    const r = await this.fetchImpl(`${this.base}/${path}`, {
      method: "POST",
      headers: { Authorization: `Bearer ${this.cfg.token}`, "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    const j = (await r.json().catch(() => ({}))) as {
      messages?: { id: string }[];
      contacts?: { wa_id: string }[];
      error?: { code: number; message: string; error_data?: { details?: string } };
    };
    if (!r.ok || j.error) {
      const code = j.error?.code ?? r.status;
      throw new WhatsAppSendError({
        code,
        message: `${j.error?.message ?? r.statusText}${j.error?.error_data?.details ? ` — ${j.error.error_data.details}` : ""}`,
        retryable: !NON_RETRYABLE.has(code) && r.status >= 500,
      });
    }
    return { providerMessageId: j.messages?.[0]?.id ?? "", waId: j.contacts?.[0]?.wa_id };
  }

  sendTemplate(
    to: string,
    name: string,
    language: string,
    opts: { bodyParams?: string[]; headerVideoLink?: string; buttons?: TemplateButton[] },
  ) {
    return this.post(`${this.cfg.phoneNumberId}/messages`, buildTemplatePayload(to, name, language, opts));
  }
  sendVideoWithButtons(to: string, videoLink: string, body: string, buttons: TemplateButton[]) {
    return this.post(`${this.cfg.phoneNumberId}/messages`, buildInteractivePayload(to, body, buttons, videoLink));
  }
  sendText(to: string, text: string) {
    return this.post(`${this.cfg.phoneNumberId}/messages`, {
      messaging_product: "whatsapp",
      to,
      type: "text",
      text: { body: text, preview_url: false },
    });
  }
  sendButtons(to: string, body: string, buttons: TemplateButton[]) {
    return this.post(`${this.cfg.phoneNumberId}/messages`, buildInteractivePayload(to, body, buttons));
  }
  async listTemplates(wabaId: string) {
    const r = await this.fetchImpl(
      `${this.base}/${wabaId}/message_templates?fields=id,name,language,status,category&limit=100`,
      {
        headers: { Authorization: `Bearer ${this.cfg.token}` },
      },
    );
    const j = (await r.json()) as {
      data?: { id: string; name: string; language: string; status: string; category: string }[];
    };
    return j.data ?? [];
  }
}
