# sql-mcp-powershell

A minimal [Model Context Protocol](https://modelcontextprotocol.io/) (MCP) server for **Microsoft SQL Server**. It runs T-SQL through **`sqlcmd`** on **Windows**, using **PowerShell 5.1+** and stdio JSON-RPC so tools like **Cursor** can execute queries safely from your workspace.

## Prerequisites

- **Windows** with **PowerShell 5.1 or later**
- **`sqlcmd`** on your `PATH` (install via [SQL Server Command Line Utilities](https://learn.microsoft.com/sql/tools/sqlcmd/sqlcmd-utility) or your SQL Server / SSMS distribution)
- A reachable **SQL Server** instance and permission to connect (Windows auth or SQL auth)

## Quick start

1. **Clone** this repository and open the folder in Cursor (or your editor).

2. **Configure connection** — copy the example environment file and edit it:

   ```powershell
   Copy-Item .env.example .env
   ```

   Set at least `SQL_SERVER` and `SQL_DATABASE`. See [.env.example](.env.example) for all options.

3. **Wire up MCP in Cursor** — this repo includes [`.cursor/mcp.json`](.cursor/mcp.json), which registers the server when you open this workspace. Reload MCP or restart Cursor after changing `.env` or `mcp.json`.

4. **Smoke test** — in the agent, ask it to run `SELECT 1` via the SQL MCP tool, or use your client’s MCP tool UI.

## How it works

- **Transport:** stdio MCP (JSON-RPC).
- **Execution:** `sqlcmd` with a UTF-8 temp script for ad-hoc SQL, or `-i` for workspace `.sql` files.
- **Workspace:** `SQL_MCP_WORKSPACE_ROOT` is set to `${workspaceFolder}` so `execute_sql_file` only allows paths under the repo root.
- **Connection:** Values from **`.env`** in the workspace root are loaded at startup (see [sql-server-run.ps1](mcp/sql-server-run/sql-server-run.ps1)). You can also set `SQLCMD*` variables in the MCP `env` block in `mcp.json` if you prefer not to use `.env`.

### MCP tools

| Tool | Purpose |
|------|--------|
| `execute_sql` | Run a T-SQL batch (supports `GO` in the script when written to temp file). Optional `database` overrides the default from `.env`. |
| `execute_sql_file` | Run a `.sql` file under the workspace via relative path. |

## Security notes

- **Never commit `.env`** — it is listed in `.gitignore`. Use `.env.example` as the template only.
- This server runs **whatever T-SQL the client sends**; use least-privilege database users and network rules appropriate for your environment.
- **`SQL_TRUST_CERT=1`** maps to sqlcmd **`-C`** (trust server certificate). Prefer proper certificates and `SQL_TRUST_CERT=0` in production.

## Troubleshooting

| Issue | What to check |
|--------|----------------|
| `sqlcmd` not found | Install command-line utilities; confirm `sqlcmd` in a new terminal: `Get-Command sqlcmd`. |
| Login failed | Verify `SQL_USER` / `SQL_PASSWORD` or Windows auth; firewall; TCP enabled on the instance. |
| TLS / certificate errors | Try `SQL_TRUST_CERT=1` for dev; for production, fix server cert chain and use `0`. |
| MCP not loading | Paths in `mcp.json` use forward slashes; workspace must be the repo root so `${workspaceFolder}/mcp/...` resolves. |

## License

[MIT](LICENSE).
