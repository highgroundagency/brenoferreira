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
  paused: "Pausada",
  inactive: "Inativa",
  opted_out: "Pediu para sair",
  anonymized: "Anonimizada",
};
