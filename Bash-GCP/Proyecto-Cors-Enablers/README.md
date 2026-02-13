# CORS Enablers

A lightweight tool for managing Cross-Origin Resource Sharing (CORS) policies on GCP Cloud Storage and Firebase Storage buckets.

## Quick Start

```bash
make setup              # Configure your project
make enable            # Apply CORS policy to bucket
make verify            # Check current CORS settings
```

## What's This?

Need to enable CORS on a GCP storage bucket? This project automates that using simple Make commands. Pick your bucket, run a command, done.

## Installation

```bash
# Install dependencies (gcloud + gsutil)
make install

# Configure your project
make setup
```

You'll be prompted for:
- `PROJECT_ID` - Your GCP project ID
- `BUCKET_NAME` - The bucket you want to configure

## Available Commands

| Command | Purpose |
|---------|---------|
| `make setup` | Configure project and bucket |
| `make enable` | Apply CORS policy |
| `make verify` | Check CORS configuration |
| `make disable` | Remove CORS policy |
| `make list` | Show all buckets in project |
| `make logs` | View operation logs |
| `make clean` | Clean up logs and config |

## Usage

### Set it up once

```bash
make setup
```

This creates a `.env` file with your settings. You can also pass variables directly:

```bash
PROJECT_ID=my-project BUCKET_NAME=my-bucket make setup
```

### Enable CORS

```bash
make enable
```

Uses `cors-template-open.json` by default. If you need a different config, edit `.env` and change the `CONFIG` variable.

### Check what's configured

```bash
make verify
```

### Turn it off

```bash
make disable
```

## Templates

Two templates included:

- **cors-template-open.json** - Allows GET, HEAD, DELETE, PUT from any origin (dev/testing)
- **cors-template-restricted.json** - Lockdown version for tighter control

## Configuration

The `.env` file stores your settings:

```
PROJECT_ID=my-project
BUCKET_NAME=my-bucket
CONFIG=cors-template-open.json
```

## Security Note

⚠️ The open template allows requests from any origin. For production:
- Restrict to specific domains
- Limit HTTP methods
- Enable Cloud Audit Logs
- Consider additional authentication

## Prerequisites

- `gcloud` CLI installed and authenticated
- `gsutil` available (comes with gcloud SDK)
- Appropriate IAM permissions on the bucket

## Reference

- [Google Cloud CORS Setup](https://cloud.google.com/storage/docs/configuring-cors)
- [Firebase Storage CORS](https://firebase.google.com/docs/storage/web/download-files)
