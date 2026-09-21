# Public Release Checklist

Complete these items before making the GitHub repository public.

## Approval and ownership

- [ ] Obtain the required organizational open-source and legal approvals.
- [ ] Confirm that the upstream sample permits this derivative distribution and
      preserve any required attribution or notices.
- [ ] Choose an approved license and add a root `LICENSE` file. Without one,
      others can view the code but do not receive permission to use, modify, or
      redistribute it.
- [ ] Confirm the repository owner and maintainers.

## Data and security

- [ ] Confirm every committed workbook contains synthetic, publishable data.
- [ ] Confirm no generated file under `execution_records/` is staged; only its
      explanatory `README.md` may be tracked. Also confirm `.env`, Streamlit
      secrets, bytecode, and local virtual environments are not staged.
- [ ] Search the complete Git history for credentials, tenant URLs, email
      addresses, customer names, GUIDs, and access tokens.
- [ ] If sensitive data ever entered Git history, rotate affected credentials
      and rewrite the history before publication.
- [ ] Enable GitHub secret scanning, push protection, Dependabot alerts, and
      private vulnerability reporting.

## Quality

- [ ] Run `python -m pip check`.
- [ ] Run `python -m unittest discover -s tests -v`.
- [ ] Confirm the GitHub Actions workflow passes on Python 3.11 and 3.13.
- [ ] Complete a sandbox end-to-end import using a fresh clone and clean virtual
      environment.
- [ ] Verify stop, continuation, token renewal, uncertain-submission recovery,
      and removal of an uploaded file.

## Documentation and release

- [ ] Replace placeholders in repository About, support, and security settings.
- [ ] Confirm the README accurately states support boundaries and single-user
      deployment constraints.
- [ ] From a clean Windows folder, open the repository in Visual Studio Code
      and confirm **Terminal > Run Build Task** creates `.venv` and launches the
      application without manual package installation.
- [ ] Add release notes describing validated scenarios and known limitations.
- [ ] Protect the default branch and require the CI check for pull requests.
- [ ] Tag the reviewed commit with an initial version such as `v0.1.0`.