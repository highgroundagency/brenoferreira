# ADR-004 — Multi-tenant por unidade (franquia) desde a migration 001

**Decisão.** `units` é o tenant; `unit_id NOT NULL` em toda tabela operacional; `cities`/`neighborhoods` são referência global ligada às unidades por `unit_neighborhoods`; catálogos (`routing_rules`, `message_templates`, `content_assets`) aceitam `unit_id NULL` = padrão global clonável (`clone_unit_defaults`).

**Acesso.** Sem Custom Access Token Hook: `auth_unit_id()`, `auth_role()`, `auth_team_ids()` leem `profiles`/`team_members` por `auth.uid()` a cada consulta (perfil inativo => acesso revogado imediatamente). Policies: leitura `can_read_unit` (própria unidade ou `global_admin`), escrita operacional `can_write_unit` (central/unit_admin da unidade). `global_admin` escreve só em `units`, `cities`, `neighborhoods`, `unit_neighborhoods`, `profiles` e nas linhas globais dos catálogos.

**Prova.** `isolation_second_unit.sql` cria a unidade `teste` e prova que cada papel só enxerga a sua (dados e catálogos).
