# sql-mcp-powershell

MCP server for SQL Server: runs T-SQL through `sqlcmd` and PowerShell on Windows.

1. Put `sqlcmd` on your PATH, clone this repo, open it as the Cursor workspace.
2. Run `Copy-Item .env.example .env` and edit `SQL_SERVER`, `SQL_DATABASE`, and anything else you need in `.env`.
3. Reload MCP (or restart Cursor), then use the `execute_sql` / `execute_sql_file` tools.

end
