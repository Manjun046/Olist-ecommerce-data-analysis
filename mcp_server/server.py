"""Single-file Olist BigQuery MCP server with built-in SQL guardrails.

Set BQ_KEY_PATH, GCP_PROJECT_ID and BQ_DATASET as environment variables."""
import os
import re

import sqlglot
from fastmcp import FastMCP
from google.cloud import bigquery
from sqlglot import exp


try:  # optional: load variables from a local .env file
    from dotenv import load_dotenv

    load_dotenv()
except ImportError:
    pass

# ---------------------------------------------------------
# SQL and identifier guardrails (pure logic, no BigQuery calls)
# ---------------------------------------------------------
# Intersect / Except are listed explicitly because in some sqlglot versions they
# are subclasses of Union and in others they are separate set-operation classes.
ALLOWED_ROOTS = (exp.Select, exp.Union, exp.Intersect, exp.Except)

# Things that can reach outside the Olist dataset even inside a plain SELECT.
BLOCKED_TOKENS = ("EXTERNAL_QUERY", "INFORMATION_SCHEMA")

_IDENT_RE = re.compile(r"^[A-Za-z0-9_]+$")


class GuardError(ValueError):
    """Raised when a query or identifier fails a security check."""


def validate_select(sql: str, *, project: str, dataset: str, max_rows: int = 100) -> str:
    """Return a safe, re-generated BigQuery SQL string or raise GuardError.

    Rules enforced:
      1. Exactly one statement (no "SELECT 1; DROP TABLE ...").
      2. The statement is a SELECT / WITH / UNION-style query (allowlist).
      3. Every real table reference stays inside project.dataset
         (unqualified names resolve via default_dataset on the job).
      4. No table-valued functions, EXTERNAL_QUERY or INFORMATION_SCHEMA.
      5. Row limit is always <= max_rows (a larger user LIMIT is clamped).
    """
    try:
        statements = sqlglot.parse(sql, read="bigquery")
    except sqlglot.errors.ParseError as exc:
        raise GuardError(f"Could not parse SQL: {exc}") from exc

    statements = [s for s in statements if s is not None]
    if len(statements) != 1:
        raise GuardError("Exactly one SQL statement is allowed.")
    parsed = statements[0]

    if not isinstance(parsed, ALLOWED_ROOTS):
        raise GuardError("Only read-only SELECT / WITH queries are allowed.")

    # Table allowlist: stay inside the Olist dataset.
    cte_names = {cte.alias_or_name for cte in parsed.find_all(exp.CTE)}
    for table in parsed.find_all(exp.Table):
        if not isinstance(table.this, exp.Identifier):
            raise GuardError("Table functions and complex table expressions are not allowed.")
        if not table.db and not table.catalog and table.name in cte_names:
            continue  # reference to a CTE defined in this query
        if table.catalog and table.catalog != project:
            raise GuardError(f"Access outside project '{project}' is not allowed.")
        if table.db and table.db != dataset:
            raise GuardError(f"Access outside dataset '{dataset}' is not allowed.")

    # Row cap: add a LIMIT if missing, clamp it if it is larger than max_rows.
    limit = parsed.args.get("limit")
    if limit is None:
        parsed = parsed.limit(max_rows)
    else:
        value = limit.expression
        within_cap = isinstance(value, exp.Literal) and value.is_int and int(value.name) <= max_rows
        if not within_cap:
            parsed = parsed.limit(max_rows)

    safe_sql = parsed.sql(dialect="bigquery")

    upper = safe_sql.upper()
    for token in BLOCKED_TOKENS:
        if token in upper:
            raise GuardError(f"'{token}' is not allowed.")

    return safe_sql


def require_known_identifier(value: str, allowed: set, kind: str) -> str:
    """Accept an identifier only if it is simple AND exists in the allowlist."""
    if not isinstance(value, str) or not _IDENT_RE.match(value) or value not in allowed:
        raise GuardError(f"Unknown {kind}: {value!r}")
    return value


# ---------------------------------------------------------
# Configuration (no credentials or personal paths in code)
# ---------------------------------------------------------
DATASET_NAME = os.environ.get("BQ_DATASET", "Olist_analysis")
MAX_SCAN_BYTES = 100 * 1024 * 1024  # 100 MiB cost guardrail
MAX_ROWS = 100                      # row cap for query results


def _make_client() -> bigquery.Client:
    """Use a service-account key if BQ_KEY_PATH is set, else Application Default Credentials."""
    key_path = os.environ.get("BQ_KEY_PATH")
    project = os.environ.get("GCP_PROJECT_ID")
    if key_path:
        return bigquery.Client.from_service_account_json(key_path, project=project)
    return bigquery.Client(project=project)


mcp = FastMCP(name="Olist BigQuery & Dashboard Architect")
bq_client = _make_client()
PROJECT_ID = bq_client.project
DEFAULT_DATASET = f"{PROJECT_ID}.{DATASET_NAME}"


def _live_config() -> bigquery.QueryJobConfig:
    """Job config for real queries: unqualified tables resolve to Olist, and
    BigQuery itself refuses to run anything billing more than MAX_SCAN_BYTES."""
    return bigquery.QueryJobConfig(
        default_dataset=DEFAULT_DATASET,
        maximum_bytes_billed=MAX_SCAN_BYTES,
    )


# ---------------------------------------------------------
# 1. TOOL: Live BigQuery Schema & Row Counts
# ---------------------------------------------------------
@mcp.tool
def inspect_olist_schema() -> str:
    """Returns all tables, row counts, and column schemas in Olist_analysis."""
    tables = list(bq_client.list_tables(DEFAULT_DATASET))

    if not tables:
        return f"No tables found in {DEFAULT_DATASET}."

    schema_lines = [f"BIGQUERY DATASET: `{DEFAULT_DATASET}`\n"]
    for table_item in tables:
        table = bq_client.get_table(table_item.reference)
        cols = ", ".join(f"{field.name} ({field.field_type})" for field in table.schema)
        schema_lines.append(
            f"TABLE: `{DEFAULT_DATASET}.{table.table_id}` [{table.num_rows:,} rows]\n  COLUMNS: {cols}"
        )

    return "\n\n".join(schema_lines)


# ---------------------------------------------------------
# 2. TOOL: Guarded Read-Only BigQuery SQL Runner
# ---------------------------------------------------------
@mcp.tool
def run_guarded_bigquery(sql: str) -> dict:
    """
    Executes a read-only BigQuery SQL query against Olist_analysis.
    Enforces single-statement SELECT-only AST checks, a dataset allowlist,
    BigQuery dry_run byte-scan limits, and caps output to 100 rows.
    """
    try:
        safe_sql = validate_select(
            sql, project=PROJECT_ID, dataset=DATASET_NAME, max_rows=MAX_ROWS
        )
    except GuardError as exc:
        raise ValueError(f"Security Block: {exc}") from exc

    # Cost guardrail 1: dry run gives a friendly error before anything executes.
    dry_config = bigquery.QueryJobConfig(
        dry_run=True, use_query_cache=False, default_dataset=DEFAULT_DATASET
    )
    dry_job = bq_client.query(safe_sql, job_config=dry_config)
    bytes_scanned = dry_job.total_bytes_processed or 0

    if bytes_scanned > MAX_SCAN_BYTES:
        raise ValueError(
            f"Cost Guardrail Triggered: Query scans {bytes_scanned / (1024**2):.2f} MiB "
            f"(limit is {MAX_SCAN_BYTES / (1024**2):.0f} MiB). Filter or aggregate your query."
        )

    # Cost guardrail 2 + row cap 2: server-side byte ceiling and max_results.
    job = bq_client.query(safe_sql, job_config=_live_config())
    df = job.result(max_results=MAX_ROWS).to_dataframe()
    return {
        "bytes_scanned": bytes_scanned,
        "row_count": len(df),
        "executed_sql": safe_sql,
        "rows": df.to_dict(orient="records"),
    }


# ---------------------------------------------------------
# 3. TOOL: Column Profiler for Tableau Chart Selection
# ---------------------------------------------------------
@mcp.tool
def profile_columns_for_charts(table_name: str, columns: list[str]) -> dict:
    """
    Profiles column cardinality, null percentage, and min/max values in BigQuery
    so the AI can recommend the optimal Tableau chart type and encoding.
    """
    # Validate names against what actually exists, so they can never be used
    # to inject SQL into the query below.
    try:
        known_tables = {t.table_id for t in bq_client.list_tables(DEFAULT_DATASET)}
        table_name = require_known_identifier(table_name, known_tables, "table")
        table_obj = bq_client.get_table(f"{DEFAULT_DATASET}.{table_name}")
        known_cols = {field.name for field in table_obj.schema}
        cols = [require_known_identifier(c, known_cols, "column") for c in columns]
    except GuardError as exc:
        raise ValueError(f"Security Block: {exc}") from exc

    if not cols:
        raise ValueError("Provide at least one column to profile.")
    if len(cols) > 20:
        raise ValueError("Profile at most 20 columns per call.")

    total_rows = table_obj.num_rows
    full_table = f"`{DEFAULT_DATASET}.{table_name}`"

    selects = []
    for i, col in enumerate(cols):
        selects += [
            f"COUNT(DISTINCT `{col}`) AS u{i}",
            f"COUNTIF(`{col}` IS NULL) AS n{i}",
            f"CAST(MIN(`{col}`) AS STRING) AS lo{i}",
            f"CAST(MAX(`{col}`) AS STRING) AS hi{i}",
        ]
    query = f"SELECT {', '.join(selects)} FROM {full_table}"
    row = list(bq_client.query(query, job_config=_live_config()).result())[0]

    profiles = {}
    for i, col in enumerate(cols):
        null_count = row[f"n{i}"]
        profiles[col] = {
            "unique_values": row[f"u{i}"],
            "null_count": null_count,
            "null_pct": round((null_count / total_rows) * 100, 2) if total_rows else 0,
            "min": row[f"lo{i}"],
            "max": row[f"hi{i}"],
        }

    return {"table": full_table, "total_rows": total_rows, "column_profiles": profiles}


# ---------------------------------------------------------
# 4. TOOL: Tableau Public Dashboard Blueprint & Formulas
# ---------------------------------------------------------
@mcp.tool
def get_tableau_dashboard_kit(business_goal: str) -> dict:
    """
    Returns Tableau Public layout specifications, visual best practices, and
    ready-to-paste Tableau Calculated Field formulas tailored to Olist KPIs.
    """
    return {
        "dashboard_goal": business_goal,
        "recommended_canvas": "1400 x 900 px Desktop Fixed Layout (Top KPI Banner + 2x2 Chart Grid + Right Filter Rail)",
        "tableau_calculated_fields": {
            # Null delivery dates are labelled separately (not silently 'On-Time'),
            # and DATE() matches the date-level comparison used in the SQL analysis.
            "Delivery_Status": (
                "IF ISNULL([Order Delivered Customer Date]) THEN 'Not Delivered' "
                "ELSEIF DATE([Order Delivered Customer Date]) > [Order Estimated Delivery Date] "
                "THEN 'Late' ELSE 'On-Time' END"
            ),
            # Rate is measured against delivered orders only.
            "Late_Delivery_Rate": (
                "COUNTD(IF [Delivery_Status] = 'Late' THEN [Order Id] END) / "
                "COUNTD(IF [Delivery_Status] <> 'Not Delivered' THEN [Order Id] END)"
            ),
            "Order_Total_GMV_LOD": "{FIXED [Order Id] : SUM([Price] + [Freight Value])}",
            "Delivery_Delay_Days": (
                "DATEDIFF('day', [Order Estimated Delivery Date], DATE([Order Delivered Customer Date]))"
            ),
            "Category_Revenue_Pct": "SUM([Price]) / TOTAL(SUM([Price]))",
        },
        "visual_design_rules": [
            "Place 4 BANs (Big Ass Numbers) across the top: Total GMV, Total Orders, Avg Review Score, and Late Delivery %.",
            "Pair any Brazil state choropleth map with a sorted horizontal bar chart so exact state rankings are readable.",
            "Limit each dashboard view to 4-5 charts and use action filters on State and Product Category.",
        ],
    }


if __name__ == "__main__":
    mcp.run()
