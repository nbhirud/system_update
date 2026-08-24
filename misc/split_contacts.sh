#!/usr/bin/env bash
#
# split-vcf.sh
#
# Split a large VCF/vCard file into smaller files without breaking
# individual vCard records.
#
# Designed for Google Contacts' 20 MB import limit.
#
# Usage:
#   ./split-vcf.sh contacts.vcf
#   ./split-vcf.sh contacts.vcf output_dir
#   ./split-vcf.sh contacts.vcf output_dir 18
# sh misc/split_contacts.sh /home/nbhirud/nb/test/20260808_contacts_googlecontacts.vcf 18     
#
# Third argument = maximum size in MB (default: 18)
#
# The original VCF is never modified.
#

set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"

usage() {
    cat <<EOF
Usage:
  $SCRIPT_NAME INPUT.vcf [OUTPUT_DIR] [MAX_MB]

Examples:
  $SCRIPT_NAME contacts.vcf
  $SCRIPT_NAME contacts.vcf split-contacts
  $SCRIPT_NAME contacts.vcf split-contacts 18

Arguments:
  INPUT.vcf       Input vCard/VCF file.
  OUTPUT_DIR      Directory for generated files.
                  Default: ./<input-name>-split
  MAX_MB          Maximum size of each output file in MB.
                  Default: 18

Notes:
  - Contacts are never split in the middle.
  - PHOTO and all other vCard properties are preserved.
  - The input file is never modified.
  - MAX_MB should be below Google's 20 MB limit.
EOF
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

[[ $# -ge 1 && $# -le 3 ]] || {
    usage
    exit 1
}

INPUT=$1
OUTPUT_DIR=${2:-}
MAX_MB=${3:-18}

[[ -f "$INPUT" ]] || die "Input file does not exist: $INPUT"
[[ -r "$INPUT" ]] || die "Input file is not readable: $INPUT"

# Validate MAX_MB.
[[ "$MAX_MB" =~ ^[0-9]+([.][0-9]+)?$ ]] ||
    die "MAX_MB must be a positive number."

awk "BEGIN { exit !($MAX_MB > 0 && $MAX_MB < 20) }" ||
    die "MAX_MB must be greater than 0 and less than 20."

# Convert MB to bytes.
MAX_BYTES=$(awk -v mb="$MAX_MB" 'BEGIN { printf "%.0f", mb * 1024 * 1024 }')

# Derive output directory.
if [[ -z "$OUTPUT_DIR" ]]; then
    filename=$(basename "$INPUT")
    stem="${filename%.*}"
    OUTPUT_DIR="./${stem}-split"
fi

mkdir -p "$OUTPUT_DIR"

# Avoid accidentally overwriting existing generated files.
if compgen -G "$OUTPUT_DIR"/*.vcf >/dev/null 2>&1; then
    die "Output directory already contains .vcf files: $OUTPUT_DIR
Refusing to overwrite them."
fi

echo "Input       : $INPUT"
echo "Output      : $OUTPUT_DIR"
echo "Max size    : ${MAX_MB} MiB"
echo

# ---------------------------------------------------------------------------
# First, validate the VCF structure.
#
# We deliberately don't parse/reconstruct the vCards. We copy each complete
# record exactly as it occurs in the source file. This is important because
# PHOTO, X-* fields, vendor-specific fields, etc. must survive unchanged.
# ---------------------------------------------------------------------------

echo "Validating vCard structure..."

validation=$(
    awk '
        BEGIN {
            records = 0
            in_card = 0
            errors = 0
        }

        /^BEGIN:VCARD[[:space:]]*$/ {
            if (in_card) {
                print "Nested BEGIN:VCARD at line " NR > "/dev/stderr"
                errors++
            }
            in_card = 1
            records++
            next
        }

        /^END:VCARD[[:space:]]*$/ {
            if (!in_card) {
                print "END:VCARD without BEGIN:VCARD at line " NR > "/dev/stderr"
                errors++
            }
            in_card = 0
            next
        }

        END {
            if (in_card) {
                print "File ends before END:VCARD" > "/dev/stderr"
                errors++
            }

            if (records == 0) {
                print "No BEGIN:VCARD records found" > "/dev/stderr"
                errors++
            }

            if (errors > 0)
                exit 1

            print records
        }
    ' "$INPUT"
) || die "Input does not appear to contain valid complete vCard records."

TOTAL_CONTACTS=$validation

echo "Contacts found: $TOTAL_CONTACTS"
echo "Splitting..."
echo

# ---------------------------------------------------------------------------
# Split records.
#
# Important:
# We use awk only to identify complete records. Each record is written
# exactly as read, so PHOTO/base64 data and all other fields are untouched.
#
# We use wc -c on each record to measure actual bytes.
# ---------------------------------------------------------------------------

awk -v outdir="$OUTPUT_DIR" \
    -v maxbytes="$MAX_BYTES" \
    '
    function new_file(    name) {
        part++
        name = sprintf("%s/contacts-%03d.vcf", outdir, part)
        outfile = name
        bytes = 0
        contacts = 0
        files++
        file_contacts[part] = 0
        file_bytes[part] = 0
    }

    function write_record(    i, record_bytes) {
        record_bytes = 0

        # Calculate the exact byte size of the record as reconstructed by
        # awk. ORS is "\n", matching the normalized output below.
        for (i = 1; i <= record_lines; i++) {
            record_bytes += length(record[i]) + 1
        }

        # A single contact larger than maxbytes cannot be split without
        # breaking the vCard. Keep it intact and warn later.
        if (contacts > 0 && bytes + record_bytes > maxbytes) {
            close(outfile)
            new_file()
        }

        for (i = 1; i <= record_lines; i++)
            print record[i] >> outfile

        bytes += record_bytes
        contacts++

        file_contacts[part]++
        file_bytes[part] += record_bytes
    }

    BEGIN {
        RS = "\n"
        ORS = "\n"

        part = 0
        files = 0
        in_card = 0
        record_lines = 0

        new_file()
    }

    /^BEGIN:VCARD[[:space:]]*$/ {
        if (in_card) {
            print "ERROR: nested BEGIN:VCARD at line " NR > "/dev/stderr"
            exit 2
        }

        in_card = 1
        record_lines = 0
        record[++record_lines] = $0
        next
    }

    /^END:VCARD[[:space:]]*$/ {
        if (!in_card) {
            print "ERROR: END:VCARD without BEGIN:VCARD at line " NR > "/dev/stderr"
            exit 3
        }

        record[++record_lines] = $0
        write_record()

        in_card = 0
        record_lines = 0
        next
    }

    {
        if (in_card) {
            record[++record_lines] = $0
        }
    }

    END {
        if (in_card) {
            print "ERROR: incomplete vCard at end of file" > "/dev/stderr"
            exit 4
        }

        close(outfile)

        for (i = 1; i <= files; i++) {
            printf "%d\t%d\t%d\n", \
                i, file_contacts[i], file_bytes[i]
        }
    }
    ' "$INPUT" > "$OUTPUT_DIR/.split-stats"

# ---------------------------------------------------------------------------
# Recalculate actual filesystem sizes.
# ---------------------------------------------------------------------------

echo
echo "Generated files:"
echo "---------------------------------------------"

TOTAL_OUTPUT_CONTACTS=0
TOTAL_OUTPUT_BYTES=0
PARTS=0

while IFS=$'\t' read -r part contacts bytes; do
    [[ -n "$part" ]] || continue

    file=$(printf "%s/contacts-%03d.vcf" "$OUTPUT_DIR" "$part")

    actual_bytes=$(wc -c < "$file")
    actual_contacts=$contacts

    TOTAL_OUTPUT_CONTACTS=$((TOTAL_OUTPUT_CONTACTS + actual_contacts))
    TOTAL_OUTPUT_BYTES=$((TOTAL_OUTPUT_BYTES + actual_bytes))
    PARTS=$part

    actual_mib=$(awk -v b="$actual_bytes" 'BEGIN {
        printf "%.2f", b / 1024 / 1024
    }')

    printf "  %-20s %8d contacts  %8s MiB\n" \
        "$(basename "$file")" \
        "$actual_contacts" \
        "$actual_mib"

done < "$OUTPUT_DIR/.split-stats"

rm -f "$OUTPUT_DIR/.split-stats"

# ---------------------------------------------------------------------------
# Final verification.
# ---------------------------------------------------------------------------

echo
echo "Verifying generated files..."

[[ "$TOTAL_OUTPUT_CONTACTS" -eq "$TOTAL_CONTACTS" ]] ||
    die "Verification failed: contact count changed!"

# Validate every generated VCF.
for file in "$OUTPUT_DIR"/*.vcf; do
    awk '
        BEGIN {
            in_card = 0
            count = 0
            errors = 0
        }

        /^BEGIN:VCARD[[:space:]]*$/ {
            if (in_card)
                errors++
            in_card = 1
            count++
            next
        }

        /^END:VCARD[[:space:]]*$/ {
            if (!in_card)
                errors++
            in_card = 0
            next
        }

        END {
            if (in_card)
                errors++

            if (errors > 0)
                exit 1

            print count
        }
    ' "$file" >/dev/null ||
        die "Generated file failed validation: $file"
done

# Warn about oversized individual contacts.
oversized=0

for file in "$OUTPUT_DIR"/*.vcf; do
    size=$(wc -c < "$file")

    if (( size > MAX_BYTES )); then
        oversized=1
        mib=$(awk -v b="$size" 'BEGIN {
            printf "%.2f", b / 1024 / 1024
        }')

        echo "WARNING: $(basename "$file") is $mib MiB."
        echo "         It contains a contact larger than the requested limit."
    fi
done

echo
echo "============================================="
echo "Done"
echo "============================================="
echo "Contacts       : $TOTAL_OUTPUT_CONTACTS"
echo "Files          : $PARTS"
echo "Output         : $OUTPUT_DIR"
echo

if (( oversized )); then
    echo "WARNING:"
    echo "At least one individual contact is larger than ${MAX_MB} MiB."
    echo "That contact cannot be split without corrupting the vCard."
else
    echo "All files are below ${MAX_MB} MiB."
fi

echo
echo "The original file was NOT modified."