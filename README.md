# sql-mcp-powershell

MCP server for SQL Server: runs T-SQL through `sqlcmd` and PowerShell on Windows.

You need `sqlcmd` on your PATH (install with [SQL command-line tools](https://learn.microsoft.com/sql/tools/sqlcmd/sqlcmd-utility) or SSMS); without it, MCP can start but every tool call fails.

1. Clone this repository.
2. Copy `.env.example` to `.env` and set the variables it describes.

That is all you need; with the repo open in Cursor, `.cursor/mcp.json` starts the server.

Optional: open [`README-for-newbies.html`](README-for-newbies.html) in a browser (tabbed steps, diagram, troubleshooting).

Example agent prompts (simple → advanced): [`SUGGESTED-PROMPTS.md`](SUGGESTED-PROMPTS.md).
