export type TemplateButton = { id: string; title: string };
export type SendResult = { providerMessageId: string; waId?: string };
export type SendError = { code: number | string; message: string; retryable: boolean };

export interface WhatsAppProvider {
  /** Template aprovado: variáveis do corpo, header de vídeo por link (opcional) e payloads dos quick replies. */
  sendTemplate(
    to: string,
    name: string,
    language: string,
    opts: { bodyParams?: string[]; headerVideoLink?: string; buttons?: TemplateButton[] },
  ): Promise<SendResult>;
  /** Mensagem interativa dentro da janela de 24 h: header de vídeo + corpo + botões de resposta. */
  sendVideoWithButtons(to: string, videoLink: string, body: string, buttons: TemplateButton[]): Promise<SendResult>;
  sendText(to: string, text: string): Promise<SendResult>;
  sendButtons(to: string, body: string, buttons: TemplateButton[]): Promise<SendResult>;
  listTemplates(
    wabaId: string,
  ): Promise<{ id: string; name: string; language: string; status: string; category: string }[]>;
}

export class WhatsAppSendError extends Error {
  code: number | string;
  retryable: boolean;
  constructor(e: SendError) {
    super(e.message);
    this.code = e.code;
    this.retryable = e.retryable;
  }
}

/** Códigos da Meta que significam "não insista": número sem WhatsApp, fora da janela, limites. */
export const NO_WHATSAPP_CODE = 131026;
export const OUTSIDE_WINDOW_CODE = 131047;
export const NON_RETRYABLE = new Set<number | string>([
  131026, 131047, 131049, 131051, 132000, 132001, 132012, 132015, 132016, 100, 190,
]);
