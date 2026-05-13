# Suggested prompts (SQL MCP)

Use these with the **`execute_sql`** / **`execute_sql_file`** tools after this MCP is connected. Rephrase for your database names, schemas, and safety rules (read-only user, no `DROP` in prod, etc.).

---

## Quick inventory

- **List tables** — “Using the SQL MCP, list all user tables in the current database: query `INFORMATION_SCHEMA.TABLES` (or `sys.tables`) and show schema, name, and row counts if cheap to obtain.”
- **List columns for one table** — “Describe every column on `[schema].[TableName]`: names, types, nullability, defaults, and identity/computed flags via `INFORMATION_SCHEMA.COLUMNS` or `sys.columns` joined to `sys.types`.”
- **Keys & relationships** — “Show primary and foreign keys involving schema `X`: parent/child tables, key columns, and update/delete rules from the catalog views.”

---

## Data quality & profiling

- **Nulls & cardinality** — “For tables A, B, C, profile key columns: NULL %, distinct count, min/max for dates, and flag likely duplicates on the business key.”
- **Referential gaps** — “Find orphan rows: FK children with no matching parent, and parents with no children where the model expects them.”
- **Date sanity** — “Scan date/datetime columns for values outside plausible ranges (e.g. before 1900, far future) and summarize by table.”

---

## Modeling & warehouse design

- **Grain & facts** — “Given these fact tables, state the grain of each in one sentence and list dimensions that conform or violate that grain.”
- **Slowly changing** — “Recommend Type 1 vs Type 2 per dimension table with rationale; note which columns are true attributes vs natural keys.”
- **Kimball-style star** — “Inspect the current database, then propose a **star schema** (Kimball): conformed dimensions, fact table grains, degenerate dimensions, and role-playing dimensions where relevant. Output: (1) target table list, (2) naming conventions, (3) view layer vs physical tables tradeoffs.”
- **End-to-end warehouse pass** — “Do a **full database inspection** using SQL MCP: tables, relationships, volumes, and obvious modeling smells. Then design a **new schema** (e.g. `dw` or `mart`) of **views** that implements a **clean star schema** following **Kimball** principles (facts + dimensions, surrogate keys where appropriate, clear grains). At the end, produce a **single self-contained HTML wireframe** with **tabs**, **color-coded** sections, **SVG or CSS diagrams** (star / bus matrix sketch), and a **short executive summary** of findings and recommendations. Keep SQL read-only unless I explicitly allow DDL.”

---

## Performance & operations

- **Index candidates** — “From recent heavy queries (or hypothetical workload), suggest nonclustered indexes with included columns and explain duplicate/narrow index risks.”
- **Bloat & maintenance** — “Summarize large tables, heap vs clustered, and fill-factor or maintenance hints suitable for this engine version.”
- **Permissions audit** — “List database users/roles and effective `SELECT`/`EXEC` rights on sensitive schemas; call out over-privileged principals.”

---

## Reporting & storytelling

- **Metric dictionary** — “Build a markdown data dictionary: metric name, definition, SQL sketch, grain, and caveats.”
- **Cohort or funnel SQL** — “Write and test read-only SQL for a weekly cohort retention matrix (explain assumptions).”
- **Handoff HTML** — “After exploring the schema with SQL MCP, generate a **lite HTML** management summary: tabs for KPIs, risks, and next steps; use semantic colors; no external assets.”

---

## Tips

- Ask the model to **cite result sets** from MCP runs when making claims about the data.
- Prefer a **read-only** SQL login for exploration; use `execute_sql_file` for reviewed scripts in the repo.
- For large designs, split into **inspect → design → DDL review** turns instead of one giant prompt.
