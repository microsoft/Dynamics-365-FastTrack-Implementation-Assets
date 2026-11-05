# Execution records

The application writes uploaded workbooks, Dataverse request and response
details, record identifiers, diagnostics, checkpoints, and activity logs to
this directory while it runs.

Treat generated files in this directory as sensitive customer data. They are
ignored by Git and must not be committed or attached to public issues. The
GitHub Actions rejects pull requests that track any file here other than this
README. The application never deletes execution records automatically;
retention and cleanup remain user-controlled.