#!/usr/bin/env python3
"""Gera lib/database.types.ts a partir de um Postgres local (fallback sem Docker).
No CI/dev com Docker use: pnpm db:types (supabase gen types typescript --local).
Uso: DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:5432/transtornar_local python3 scripts/gen-types.py > lib/database.types.ts
"""
import json, os, subprocess, sys

DB = os.environ.get("DATABASE_URL", "postgresql://postgres:postgres@127.0.0.1:5432/transtornar_local")

def q(sql):
    out = subprocess.run(["psql", DB, "-X", "-A", "-t", "-c", sql], capture_output=True, text=True, check=True).stdout
    return [line for line in out.splitlines() if line.strip()]

def ts(pgtype, udt):
    t = udt.lstrip("_")
    arr = udt.startswith("_") or pgtype == "ARRAY"
    base = {"uuid": "string", "text": "string", "bpchar": "string", "varchar": "string", "citext": "string",
            "timestamptz": "string", "timestamp": "string", "date": "string", "time": "string", "interval": "string",
            "int2": "number", "int4": "number", "int8": "number", "numeric": "number", "float4": "number", "float8": "number",
            "bool": "boolean", "jsonb": "Json", "json": "Json", "bytea": "string"}.get(t, "unknown")
    return f"{base}[]" if arr else base

def columns(kind):
    rows = q(f"""select json_build_object('table', c.table_name, 'column', c.column_name, 'type', c.data_type, 'udt', c.udt_name,
                 'nullable', c.is_nullable = 'YES', 'default', c.column_default is not null, 'gen', c.is_generated = 'ALWAYS')
                 from information_schema.columns c join information_schema.tables t on t.table_schema = c.table_schema and t.table_name = c.table_name
                 where c.table_schema = 'public' and t.table_type = '{kind}' order by c.table_name, c.ordinal_position""")
    out = {}
    for r in rows:
        d = json.loads(r); out.setdefault(d["table"], []).append(d)
    return out

def relationships():
    rows = q("""select json_build_object('table', rel.relname, 'name', c.conname,
                 'columns', (select json_agg(a.attname order by k.ord) from unnest(c.conkey) with ordinality k(attnum, ord) join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum),
                 'ref', frel.relname,
                 'ref_columns', (select json_agg(a.attname order by k.ord) from unnest(c.confkey) with ordinality k(attnum, ord) join pg_attribute a on a.attrelid = c.confrelid and a.attnum = k.attnum),
                 'one_to_one', exists (select 1 from pg_constraint u where u.conrelid = c.conrelid and u.contype in ('p','u') and u.conkey = c.conkey))
                from pg_constraint c join pg_class rel on rel.oid = c.conrelid join pg_class frel on frel.oid = c.confrelid
                join pg_namespace n on n.oid = rel.relnamespace
                where c.contype = 'f' and n.nspname = 'public' order by rel.relname, c.conname""")
    out = {}
    for r in rows:
        d = json.loads(r); out.setdefault(d["table"], []).append(d)
    return out

RELS = None
def rel_ts(name):
    global RELS
    if RELS is None: RELS = relationships()
    items = []
    for r in RELS.get(name, []):
        cols = ", ".join(f'"{c}"' for c in r["columns"]); rcols = ", ".join(f'"{c}"' for c in r["ref_columns"])
        items.append(f'{{ foreignKeyName: "{r["name"]}"; columns: [{cols}]; isOneToOne: {"true" if r["one_to_one"] else "false"}; referencedRelation: "{r["ref"]}"; referencedColumns: [{rcols}] }}')
    return "[" + ", ".join(items) + "]"

def emit_table(name, cols, view=False):
    row = "; ".join(f"{c['column']}: {ts(c['type'], c['udt'])}{' | null' if c['nullable'] else ''}" for c in cols)
    if view:
        return f"      {name}: {{ Row: {{ {row} }}; Relationships: [] }};"
    ins = "; ".join(f"{c['column']}{'?' if c['nullable'] or c['default'] else ''}: {ts(c['type'], c['udt'])}{' | null' if c['nullable'] else ''}" for c in cols if not c["gen"])
    upd = "; ".join(f"{c['column']}?: {ts(c['type'], c['udt'])}{' | null' if c['nullable'] else ''}" for c in cols if not c["gen"])
    return f"      {name}: {{ Row: {{ {row} }}; Insert: {{ {ins} }}; Update: {{ {upd} }}; Relationships: {rel_ts(name)} }};"

def functions():
    rows = q("""select json_build_object('name', p.proname, 'args', (
                  select coalesce(json_agg(json_build_object('name', a.name, 'type', a.type, 'has_default', a.has_default) order by a.ord), '[]')
                  from (select unnest(p.proargnames) as name, unnest(p.proargtypes::regtype[])::text as type, generate_series(1, p.pronargs) as ord,
                               generate_series(1, p.pronargs) > p.pronargs - p.pronargdefaults as has_default) a),
                'returns', pg_get_function_result(p.oid))
                from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                where n.nspname = 'public' and p.prokind = 'f' and pg_get_function_result(p.oid) <> 'trigger'
                  and not exists (select 1 from pg_depend dep where dep.objid = p.oid and dep.deptype = 'e')
                order by p.proname""")
    out = []
    seen = set()
    for r in rows:
        d = json.loads(r)
        if d["name"] in seen: continue
        seen.add(d["name"])
        args = "; ".join(f"{a['name']}{'?' if a['has_default'] else ''}: {pgret(a['type'])}" for a in d["args"] if a["name"])
        ret = d["returns"]
        setof = ret.startswith("SETOF ")
        rt = pgret(ret.replace("SETOF ", ""))
        out.append(f"      {d['name']}: {{ Args: {{ {args} }}; Returns: {rt}{'[]' if setof else ''} }};")
    return out

def pgret(t):
    t = t.strip()
    arr = t.endswith("[]")
    base = {"uuid": "string", "text": "string", "character": "string", "timestamp with time zone": "string", "date": "string",
            "integer": "number", "smallint": "number", "bigint": "number", "numeric": "number", "boolean": "boolean",
            "jsonb": "Json", "json": "Json", "void": "undefined", "record": "Record<string, unknown>"}.get(t.rstrip("[]"), "unknown")
    return f"{base}[]" if arr else base

tables = columns("BASE TABLE"); views = columns("VIEW")
print("// Gerado por scripts/gen-types.py (fallback sem Docker). Com Docker: pnpm db:types.")
print("export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];\n")
print("export type Database = {\n  public: {\n    Tables: {")
for name, cols in tables.items(): print(emit_table(name, cols))
print("    };\n    Views: {")
for name, cols in views.items(): print(emit_table(name, cols, view=True))
print("    };\n    Functions: {")
for f in functions(): print(f)
print("    };\n    Enums: { [_ in never]: never };\n    CompositeTypes: { [_ in never]: never };\n  };\n};\n")
print("""export type Tables<T extends keyof Database["public"]["Tables"]> = Database["public"]["Tables"][T]["Row"];
export type Views<T extends keyof Database["public"]["Views"]> = Database["public"]["Views"][T]["Row"];
export type Functions<T extends keyof Database["public"]["Functions"]> = Database["public"]["Functions"][T];""")
