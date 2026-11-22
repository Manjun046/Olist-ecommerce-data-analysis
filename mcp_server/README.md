# Olist BigQuery MCP Server

A single-file [FastMCP](https://gofastmcp.com) server (`server.py`) that lets an AI assistant (Claude Desktop, VS Code Copilot) explore the Olist BigQuery dataset safely: inspect the schema, profile columns, run natural-language-driven SQL, and get Tableau dashboard guidance. Every query goes through guardrails so AI-generated SQL cannot modify data, read outside the dataset, or run up cloud costs.

## Demo

**1. A normal query runs, and the guard adds LIMIT 100 automatically**

<img width="1137" height="852" alt="Prompt 2" src="https://github.com/user-attachments/assets/bacb80b0-eeab-4385-b3ec-648a8485883a" />

**2. Row cap: LIMIT 5000 is rewritten to LIMIT 100**

<img width="985" height="925" alt="Prompt 6" src="https://github.com/user-attachments/assets/64263ef3-bdad-47ab-9665-adeeba62cf84" />

**3. Multi-statement injection is blocked**

<img width="977" height="795" alt="Prompt 4" src="https://github.com/user-attachments/assets/38555c80-e6c7-431c-8f1c-2400a57f5f17" />

**4. A destructive DROP TABLE is blocked**

<img width="1006" height="822" alt="Prompt 3" src="https://github.com/user-attachments/assets/be305571-f334-4cd2-9294-5bd51f2b83dc" />

**5. Access outside the project is blocked**

<img width="1030" height="932" alt="Prompt 5" src="https://github.com/user-attachments/assets/55140aba-84e2-4ff8-92c6-d606cd0af6b4" />

## Tools

| Tool | What it does |
|---|---|
| `inspect_olist_schema` | Lists every table in `Olist_analysis` with row counts and column types, so the AI writes SQL against real column names. |
| `run_guarded_bigquery` | Runs one read-only SQL query through the guardrails below and returns at most 100 rows. |
| `profile_columns_for_charts` | Returns distinct count, null %, min and max for chosen columns, to help pick Tableau chart types. |
| `get_tableau_dashboard_kit` | Returns a dashboard layout, design rules and ready-to-paste Tableau calculated fields for Olist KPIs. |

## Guardrails

**Query safety (sqlglot AST parsing)**
- **Single statement only:** multi-statement input such as `SELECT 1; DROP TABLE x` is rejected.
- **Allowlist, not blocklist:** only `SELECT` / `WITH` / `UNION`-style queries pass; DDL and DML (DROP, DELETE, UPDATE, INSERT, CREATE...) are rejected.
- **Dataset allowlist:** every table must be in the configured project and dataset. Other projects, other datasets, `INFORMATION_SCHEMA`, table functions and `EXTERNAL_QUERY` are blocked.
- **Row cap:** a `LIMIT 100` is added when missing, and any larger `LIMIT` is clamped to 100. Results are also fetched with `max_results=100`.

**Cost safety**
- **Dry run first:** the estimated bytes scanned are checked before execution, with a clear error above 100 MiB.
- **Hard ceiling:** the real job also sets `maximum_bytes_billed`, so BigQuery itself refuses an over-limit query.

**Injection safety in the profiler**
- Table and column names are validated against the live schema before being placed in SQL, so they cannot be used to inject statements.

## Setup

1. **Create a least-privilege service account** in Google Cloud with only:
   - `BigQuery Job User` on the project
   - `BigQuery Data Viewer` on the `Olist_analysis` dataset

   Do not use Owner or Editor roles, and do not reuse the key you use for loading data. Read-only permissions mean that even a bug in the guardrails cannot modify data.
2. **Install dependencies**
   ```bash
   pip install fastmcp sqlglot google-cloud-bigquery pandas db-dtypes pyarrow python-dotenv
   ```
3. **Set configuration** as environment variables (or in a local `.env` file that is never committed):
   - `BQ_KEY_PATH`: path to the service-account key file, kept outside the repository. If unset, Application Default Credentials are used.
   - `GCP_PROJECT_ID`: your Google Cloud project id.
   - `BQ_DATASET`: defaults to `Olist_analysis`.
4. **Register the server in Claude Desktop** by adding this entry to your Claude Desktop config file (use your own paths), then restart Claude Desktop:
   ```json
   {
     "mcpServers": {
       "olist-bigquery": {
         "command": "python",
         "args": ["/absolute/path/to/mcp_server/server.py"],
         "env": {
           "BQ_KEY_PATH": "/absolute/path/to/your-service-account-key.json",
           "GCP_PROJECT_ID": "your-gcp-project-id",
           "BQ_DATASET": "Olist_analysis"
         }
       }
     }
   }
   ```

## Security notes
- **Never commit credentials.** Keep key files and `.env` out of the repository. If a key is ever committed, rotate it, because deleting the file does not remove it from Git history.
- The data contains customer review text. Treat query results as untrusted: text inside data could try to steer an AI assistant (prompt injection). Read-only permissions and the dataset allowlist limit what a manipulated assistant could do.

## Limitations
- The guardrails prevent damage and runaway cost, **not wrong answers**. A valid query can still use the wrong join or filter, so verify important results (row counts, reconciliation against known totals).
- Queries that use `INTERSECT`/`EXCEPT` or correlated array references may be rejected depending on the sqlglot version; this fails safe.
- `get_tableau_dashboard_kit` returns a fixed template, not a data-driven recommendation.
- Built for one dataset; it is not a general-purpose BigQuery gateway.
