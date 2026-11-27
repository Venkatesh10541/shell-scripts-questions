#Write a script that accepts a source directory and backup destination,
# creates a timestamped compressed archive, and verifies that the 
# archive was created successfully and is readable. 
# ans) To create reliable compressed backups in Bash, pair tar -czf (gzip compression with a timestamped filename) with verification steps that check the file exists, is non-empty, and passes a tar -tzf integrity read test—cleaning up any partial or corrupt archive if verification fails.
#!/bin/bash

SOURCE_DIR="${1:-${SOURCE_DIR:-}}"
BACKUP_DEST="${2:-${BACKUP_DEST:-}}"

if [ -z "$SOURCE_DIR" ] || [ -z "$BACKUP_DEST" ]; then
  echo "Error: Both source directory and backup destination are required."
  echo "Usage: $0 <source_directory> <backup_destination>"
  echo "Example: $0 /var/www/app /backups"
  exit 1
fi

if [ ! -d "$SOURCE_DIR" ]; then
  echo "Error: Source directory '$SOURCE_DIR' does not exist or is not a directory."
  exit 1
fi

mkdir -p "$BACKUP_DEST"
if [ ! -d "$BACKUP_DEST" ] || [ ! -w "$BACKUP_DEST" ]; then
  echo "Error: Backup destination '$BACKUP_DEST' is not writable."
  exit 1
fi

# Clean up trailing slashes so base name and paths stay predictable
clean_src="${SOURCE_DIR%/}"
src_base=$(basename "$clean_src")
parent_dir=$(dirname "$clean_src")
timestamp=$(date "+%Y%m%d_%H%M%S")
archive_path="${BACKUP_DEST%/}/${src_base}_${timestamp}.tar.gz"

echo "Creating archive: $archive_path"
echo "Source:           $clean_src"

# Create compressed archive (-c create, -z gzip, -f file, -C change dir so paths stay clean)
if ! tar -czf "$archive_path" -C "$parent_dir" "$src_base" >/dev/null 2>&1; then
  echo "Error: Archive creation failed."
  rm -f "$archive_path"
  exit 1
fi

# Verify archive exists, is a non-empty regular file, and is readable/valid via tar -tzf
if [ ! -f "$archive_path" ] || [ ! -s "$archive_path" ]; then
  echo "Error: Archive file '$archive_path' is missing or empty."
  rm -f "$archive_path"
  exit 1
fi

if ! tar -tzf "$archive_path" >/dev/null 2>&1; then
  echo "Error: Archive '$archive_path' failed integrity/readability check."
  rm -f "$archive_path"
  exit 1
fi

archive_size=$(du -h "$archive_path" | awk '{print $1}')
echo "SUCCESS: Backup verified and readable ($archive_size)."
echo "Saved at: $archive_path"
exit 0
#Input and directory validation: Checks that both <source_directory> and <backup_destination> are provided, confirms $SOURCE_DIR exists, creates $BACKUP_DEST with mkdir -p, and checks write permission (-w) before starting.

#Timestamped archive naming: Uses date "+%Y%m%d_%H%M%S" so repeated backups never overwrite each other—for example, app_20261127_143500.tar.gz.

#tar -czf with -C: Compresses the target folder into a .tar.gz archive while -C "$parent_dir" "$src_base" keeps relative folder paths clean inside the archive rather than embedding full root paths.

#Three-part verification and cleanup:

#Checks tar -czf exit status (0 means creation succeeded).

#Checks [ -f "$archive_path" ] && [ -s "$archive_path" ] to ensure the file exists and has size greater than zero bytes.

#Runs tar -tzf "$archive_path" >/dev/null 2>&1 to test listing/decompressing the archive contents and confirm it is readable and not truncated. If any check fails, rm -f "$archive_path" removes the broken file and exits with 1.