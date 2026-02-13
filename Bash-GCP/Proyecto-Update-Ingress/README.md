# Proyecto-Update-Ingress

This folder contains a modularized v2 of the existing `update_ingress.sh` script.

## Structure

- `bin/update_ingress.v2.sh`  -> main entrypoint (sources libs)
- `lib/ui.sh`                -> UI helpers (colors, banners, prompts)
- `lib/downloader.sh`        -> GitLab raw downloader wrapper
- `lib/healthcheck.sh`       -> health-check polling and validation
- `test/run-smoke.sh`        -> small smoke test harness (non-destructive)

## Goals

- Make the code easier to test and maintain.
- Keep behavior identical to the current `Scripts/update_ingress.sh` unless intentionally improved.

## How to run

    cd "Proyecto-Update-Ingress"
    ./bin/update_ingress.v2.sh [optional-gitlab-blob-url]

The script will:

1. Ask for the Ticket ID (e.g., CTASK0337281 or TASK2280877)
2. Change to the ticket directory under `/home/admin/Documents/GNP/Tickets/<TICKET_ID>/`
3. Create the directory if it doesn't exist (with confirmation)
4. Proceed with the ingress update workflow

If you're already in a ticket directory, the script will auto-detect the ticket ID.

## Flags

- `--dry-run`

    When provided, the script will skip destructive operations and will not perform network downloads in the downloader module. Useful for CI or testing.

    Example (dry-run only):

        ./bin/update_ingress.v2.sh --dry-run https://gitlab.com/yourgroup/yourproj/-/blob/v1.2.3/path/to/ingress.yaml

- `--verbose`

    Enables additional log output for debugging and to show internal decisions (for example, token detection and API URL construction).

## Environment variables

- `GITLAB_PRIVATE_TOKEN`

    If set, this token will be used by the downloader to authenticate requests to private GitLab repositories. If not set the downloader will attempt to locate a token file at common paths (for example, `Repos/token-gitlab-jmcm` relative to the workspace).

- `TICKET_ID`

    If set, the script will use this ticket ID and skip the interactive prompt. Useful for automation.

- `TICKET_DIR`

    If set, the script will use this directory path instead of auto-detecting or prompting for a ticket.

## Examples

Dry-run with verbose output:

    ./bin/update_ingress.v2.sh --dry-run --verbose https://gitlab.com/yourgroup/yourproj/-/blob/v1.2.3/path/to/ingress.yaml

## Interrupt / Ctrl+C behavior

The scripts are designed to be cancellable by the user. Key points:

- Pressing Ctrl+C (SIGINT) during an interactive prompt will abort the script immediately. The process will exit with code 130.
- Temporary files created by the scripts are cleaned up on normal exit and also when interrupted. The cleanup routine runs before the process exits.
- Interactive prompts are handled through a central `read_input` helper which ensures that user interrupts are detected and acted upon; this avoids prompts reappearing after Ctrl+C.

If you need to run the script non-interactively (for CI or automation), either:

- Provide all required inputs via command-line arguments (e.g., supply the download URL positionally), or
- Use the `--dry-run` flag and set environment variables like `GITLAB_PRIVATE_TOKEN` when applicable. Consider adding a `--non-interactive` option if you want stricter non-interactive behavior (not currently required but recommended for CI).
