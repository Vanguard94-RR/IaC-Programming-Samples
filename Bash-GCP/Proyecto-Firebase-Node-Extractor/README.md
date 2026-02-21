# Firebase Node Extractor & Restorer

Simple scripts to extract and restore nodes from Firebase.

## Requirements

```bash
# macOS
brew install jq firebase-tools

# Ubuntu/Debian
sudo apt-get install jq
npm install -g firebase-tools
```

## Quick Start

### Interactive Interface (recommended)
```bash
./manage.sh
```

Menu-driven interface with prompts for:
- Extracting nodes from backup
- Restoring nodes to Firebase

### Command Line

**Extract node:**
```bash
./extract.sh /path/to/backup.json NodeName [output.json]
```

Examples:
```bash
./extract.sh gnp-appagentes-pro_data.json SectionsView
./extract.sh gnp-appagentes-pro_data.json Home
./extract.sh gnp-appagentes-pro_data.json "SectionsView/sections"
```

**Restore node:**
```bash
./restore.sh project-id node-path data.json
```

Example:
```bash
./restore.sh gnp-appagentes-pro SectionsView SectionsView.json
```

## Notes

- Backups must be valid JSON
- Requires prior authentication: `firebase login`
- Restore operations require confirmation
- Filenames include timestamp automatically: `NodeName_YYYYMMDD_HHMMSS.json`
- manage.sh is the recommended entry point
