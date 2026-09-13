export type ReferralStatus = "new" | "triaged" | "in_progress" | "waiting" | "done" | "cancelled";

/** Espelha as transições validadas em public.referral_transition. */
export const TRANSITIONS: Record<ReferralStatus, ReferralStatus[]> = {
  new: ["triaged", "in_progress", "cancelled"],
  triaged: ["in_progress", "waiting", "done", "cancelled"],
  in_progress: ["waiting", "done", "cancelled"],
  waiting: ["in_progress", "done", "cancelled"],
  done: [],
  cancelled: [],
};

export function canTransition(from: ReferralStatus, to: ReferralStatus): boolean {
  return TRANSITIONS[from].includes(to);
}

export const STATUS_LABEL: Record<ReferralStatus, string> = {
  new: "Novo",
  triaged: "Triado",
  in_progress: "Em atendimento",
  waiting: "Aguardando",
  done: "Concluído",
  cancelled: "Cancelado",
};

export const REFERRAL_TYPE_LABEL: Record<string, string> = {
  basic_food: "Cesta básica",
  home_items: "Itens de casa",
  education: "Educação",
  employment: "Trabalho",
  follow_up: "Acompanhamento",
  strategy_review: "Estratégia",
  reward_delivery: "Premiação",
  church_connection: "Igreja",
  other: "Outro",
};

export const STAGE_LABEL: Record<string, string> = {
  registered: "Cadastrada",
  first_contact_pending: "Aguardando 1º contato",
  journey_active: "Jornada ativa",
  day7_done: "7 dias de conteúdo",
  day16_done: "16 dias de conteúdo",
  church_connected: "Conectada a uma igreja",
  supporter: "Mantenedora",
  paused: "Pausada",
  inactive: "Inativa",
  opted_out: "Pediu para sair",
  anonymized: "Anonimizada",
};

export const NEED_TYPE_LABEL: Record<string, string> = {
  food: "Alimento",
  furniture: "Móvel",
  appliance: "Eletrodoméstico",
  clothing: "Roupa",
  health: "Saúde",
  job: "Trabalho",
  training: "Curso",
  other: "Outro",
};

export const NEED_STATUS_LABEL: Record<string, string> = {
  open: "Em aberto",
  routed: "Encaminhada",
  met: "Atendida",
  cancelled: "Cancelada",
};

export const MESSAGE_STATUS_LABEL: Record<string, string> = {
  queued: "Na fila",
  sending: "Enviando",
  sent: "Enviada",
  delivered: "Entregue",
  read: "Lida",
  failed: "Falhou",
  skipped: "Não enviada",
};

export const MESSAGE_KIND_LABEL: Record<string, string> = {
  template: "Modelo",
  interactive: "Com botões",
  text: "Texto",
  media: "Vídeo",
};
