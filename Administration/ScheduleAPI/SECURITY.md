# Security

## Reporting a vulnerability

Report suspected vulnerabilities through GitHub private vulnerability reporting
for this repository. Do not open a public issue containing credentials, access
tokens, tenant URLs, customer data, workbook contents, request traces, or
execution artifacts.

If private vulnerability reporting is not enabled, contact the repository owner
through an approved private channel.

## Sensitive local data

The application stores uploaded workbooks, Dataverse request and response
details, record identifiers, and activity logs under `execution_records/`.
Treat generated content in that directory as customer data. It is excluded by
`.gitignore`; only the explanatory `README.md` is tracked. Generated records
must not be attached to public issues without review and redaction.

The application never deletes these records automatically. Retention and
cleanup are explicit user or organizational decisions. Stop the application
before manually deleting old records, and preserve `active-upload.json` plus
its referenced run folder whenever an interrupted upload may need recovery.

Never commit `.env`, `.streamlit/secrets.toml`, access tokens, refresh tokens,
passwords, tenant-specific URLs, or user identifiers.