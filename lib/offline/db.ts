import Dexie, { type EntityTable } from "dexie";

export type PendingKind = "register" | "tally";
export interface PendingItem {
  id: string; // client_uuid (register) ou uuid aleatório (tally)
  kind: PendingKind;
  payload: Record<string, unknown>;
  created_at: number;
  attempts: number;
  last_error?: string;
}

/** Fila de reenvio: só payloads pendentes de envio. Nada de dados da base é cacheado. */
export class OfflineDb extends Dexie {
  pending_registrations!: EntityTable<PendingItem, "id">;
  constructor() {
    super("transtornar");
    this.version(1).stores({ pending_registrations: "id, kind, created_at" });
  }
}

let db: OfflineDb | undefined;
export function getDb() {
  if (!db) db = new OfflineDb();
  return db;
}
