#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_FILE="${PROJECT_DIR}/turrisgreylist2mikrotik.rsc"
KEYRING="${PROJECT_DIR}/turris-greylist-keyring.gpg"
DOWNLOAD_URL="https://view.sentinel.turris.cz/greylist-data/greylist-latest.csv"
KEY_FINGERPRINT="E2669FDB3D97E854EC614D5FC042B53710876666"
KEYSERVER="hkps://keyserver.ubuntu.com"
TRIES=5
RETRY_SECONDS=60
MIN_IPV4_ENTRIES=100
MIN_IPV6_ENTRIES=1
MODE=both

usage() {
    cat <<EOF
Usage: ${0##*/} [--ipv4|--ipv6|--both|--help]
  --ipv4    Only IPv4 (RouterOS /ip firewall address-list)
  --ipv6    Only IPv6 (RouterOS /ipv6 firewall address-list)
  --both    Both address families (default)
  --help    Show this help
Output: $OUTPUT_FILE
EOF
}

if (( $# > 1 )); then usage >&2; exit 2; fi
case "${1:---both}" in
    --ipv4) MODE=ipv4 ;;
    --ipv6) MODE=ipv6 ;;
    --both) MODE=both ;;
    --help|-h) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
esac

log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*"; }
die() { log "ERROR: $*" >&2; exit 1; }

for cmd in curl gpg gpgv awk sort wc grep mktemp mv; do
    command -v "$cmd" >/dev/null 2>&1 || die "Missing command: $cmd"
done

TMP_DIR=$(mktemp -d "${PROJECT_DIR}/.turris.XXXXXXXX")
trap 'rm -rf -- "$TMP_DIR"' EXIT
CSV="${TMP_DIR}/greylist.csv"
ASC="${CSV}.asc"
IPV4_FILE="${TMP_DIR}/ipv4.txt"
IPV6_FILE="${TMP_DIR}/ipv6.txt"
RSC_TMP="${TMP_DIR}/generated.rsc"

# Check exact key fingerprint; do not trust short key IDs alone.
has_trusted_key() {
    [[ -s "$KEYRING" ]] || return 1
    gpg --batch --no-default-keyring --keyring "$KEYRING" \
        --with-colons --fingerprint --list-keys 2>/dev/null |
        awk -F: -v expected="$KEY_FINGERPRINT" '
            $1 == "fpr" && $10 == expected { found=1 }
            END { exit !found }
        '
}

if ! has_trusted_key; then
    log "Trusted RSA key missing; fetching from $KEYSERVER"
    GNUPGHOME="${TMP_DIR}/gnupg"
    mkdir -m 700 "$GNUPGHOME"
    gpg --homedir "$GNUPGHOME" --batch --keyserver "$KEYSERVER" \
        --keyserver-options timeout=15 --recv-keys "$KEY_FINGERPRINT" ||
        die "Could not retrieve trusted RSA key"
    gpg --homedir "$GNUPGHOME" --batch --with-colons --fingerprint \
        --list-keys "$KEY_FINGERPRINT" |
        awk -F: -v expected="$KEY_FINGERPRINT" '
            $1 == "fpr" && $10 == expected { found=1 }
            END { exit !found }
        ' || die "Downloaded key fingerprint mismatch"
    gpg --homedir "$GNUPGHOME" --batch --export "$KEY_FINGERPRINT" > "${TMP_DIR}/keyring.gpg"
    [[ -s "${TMP_DIR}/keyring.gpg" ]] || die "Cannot export public key"
    chmod 644 "${TMP_DIR}/keyring.gpg"
    mv -f -- "${TMP_DIR}/keyring.gpg" "$KEYRING"
    has_trusted_key || die "New keyring verification failed"
    log "Trusted RSA key imported"
else
    log "Using existing GPG keyring"
fi

# The file can have two signatures. gpgv returns 2 if one signature is
# made by an unknown key, even when the pinned RSA signature is valid.
verify_signature() {
    local status rc=0 err_keys missing_keys key
    status=$(gpgv --status-fd 1 --keyring "$KEYRING" "$ASC" "$CSV" 2>/dev/null) || rc=$?

    grep -Fq "[GNUPG:] VALIDSIG ${KEY_FINGERPRINT} " <<< "$status" || {
        log "ERROR: Missing valid signature from pinned RSA key"; return 1;
    }
    # Never ignore explicitly bad signatures or unexpected verification failures.
    if grep -Eq '^\[GNUPG:\] (BADSIG|EXPSIG|EXPKEYSIG|REVKEYSIG|NODATA|FAILURE|ERROR)( |$)' <<< "$status"; then
        log "ERROR: GPG reported invalid signature or processing failure"
        return 1
    fi
    err_keys=$(awk '$2=="ERRSIG" {print $3}' <<< "$status")
    missing_keys=$(awk '$2=="NO_PUBKEY" {print $3}' <<< "$status")
    if [[ -n "$err_keys" ]]; then
        while IFS= read -r key; do
            if ! grep -Fxq "$key" <<< "$missing_keys"; then
                log "ERROR: Unexpected ERRSIG for key $key"
                return 1
            fi
        done <<< "$err_keys"
    elif (( rc != 0 )); then
        log "ERROR: Unexpected gpgv exit code $rc"
        return 1
    fi
    log "OK: Valid signature from pinned RSA key"
    [[ -z "$err_keys" ]] || log "INFO: Ignoring additional signature(s) with unknown public key"
    return 0
}

SUCCESS=0
for ((attempt=1; attempt<=TRIES; attempt++)); do
    log "Downloading Greylist ($attempt/$TRIES)"
    rm -f -- "$CSV" "$ASC"
    if curl -fSLsS --connect-timeout 15 --max-time 120 "$DOWNLOAD_URL" -o "$CSV" &&
       curl -fSLsS --connect-timeout 15 --max-time 120 "${DOWNLOAD_URL}.asc" -o "$ASC" &&
       [[ -s "$CSV" && -s "$ASC" ]]; then
        # Do not retry a downloaded file whose signature is invalid.
        verify_signature || die "Signature verification failed"
        SUCCESS=1
        break
    fi
    log "WARN: Download failed or empty file"
    if (( attempt < TRIES )); then sleep "$RETRY_SECONDS"; fi
done
(( SUCCESS == 1 )) || die "Download failed after $TRIES attempts"

: > "$IPV4_FILE"
: > "$IPV6_FILE"

# AWK validates plain IPv4 / CIDR and hexadecimal IPv6 / CIDR (including ::).
# It skips license comments and blank lines before the Address header.
# IPv4 and IPv6 are validated even in single-family output mode.
awk -F, -v out4="$IPV4_FILE" -v out6="$IPV6_FILE" '
function valid4(s, parts, addr, n, i, oct) {
    n=split(s, parts, "/")
    if (n>2) return 0
    if (n==2 && (parts[2]!~/^[0-9]+$/ || parts[2]+0>32)) return 0
    n=split(parts[1],addr,".")
    if (n!=4) return 0
    for(i=1;i<=4;i++) {
        oct=addr[i]
        if (oct!~/^[0-9]+$/ || length(oct)>3 || oct+0>255) return 0
        if (length(oct)>1 && substr(oct,1,1)=="0") return 0
    }
    return 1
}
function hextets(s, a, n, i) {
    if (s=="") return 0
    n=split(s,a,":")
    for(i=1;i<=n;i++) {
        if (a[i]!~/^[[:xdigit:]]+$/ || length(a[i])>4) return 0
    }
    return n
}
function valid6(s, parts, n, addr, pos, l, r, lc, rc) {
    n=split(s,parts,"/")
    if (n>2) return 0
    if (n==2 && (parts[2]!~/^[0-9]+$/ || parts[2]+0>128)) return 0
    addr=parts[1]
    if (addr!~/^[0-9a-fA-F:]+$/) return 0
    pos=index(addr,"::")
    if (pos) {
        l=substr(addr,1,pos-1)
        r=substr(addr,pos+2)
        if (index(r,"::")) return 0
        lc=(l=="" ? 0 : hextets(l))
        rc=(r=="" ? 0 : hextets(r))
        if ((l!="" && !lc) || (r!="" && !rc)) return 0
        return lc+rc<8
    }
    return hextets(addr)==8
}
{
    field=$1
    if (NR==1) sub(/^\357\273\277/,"",field)
    sub(/\r$/, "", field)
    gsub(/^[ \t]+|[ \t]+$/, "", field)
    if (field=="" && $0~/^[[:space:]]*$/) next
    if (field~/^#/) next
    if (!header_seen) {
        gsub(/^"|"$/, "", field)
        if (field!="Address") {
            printf "ERROR: Unexpected CSV header on line %d: %s\n", NR, field > "/dev/stderr"
            invalid=1; exit 1
        }
        header_seen=1; next
    }
    if (valid4(field)) { print field >> out4; n4++ }
    else if (valid6(field)) { print field >> out6; n6++ }
    else {
        printf "ERROR: Invalid IP on line %d: %s\n", NR, field > "/dev/stderr"
        invalid=1
    }
}
END {
    if (!header_seen) { print "ERROR: CSV Address header not found" > "/dev/stderr"; invalid=1 }
    printf "INFO: CSV rows: IPv4=%d IPv6=%d\n", n4, n6 > "/dev/stderr"
    if (invalid) exit 1
}
' "$CSV" || die "CSV validation failed"

LC_ALL=C sort -u "$IPV4_FILE" -o "$IPV4_FILE"
LC_ALL=C sort -u "$IPV6_FILE" -o "$IPV6_FILE"
COUNT4=$(wc -l < "$IPV4_FILE"); COUNT4=${COUNT4//[[:space:]]/}
COUNT6=$(wc -l < "$IPV6_FILE"); COUNT6=${COUNT6//[[:space:]]/}

if [[ "$MODE" != ipv6 ]] && (( COUNT4 < MIN_IPV4_ENTRIES )); then
    die "Too few IPv4 addresses ($COUNT4 < $MIN_IPV4_ENTRIES)"
fi
if [[ "$MODE" != ipv4 ]] && (( COUNT6 < MIN_IPV6_ENTRIES )); then
    die "Too few IPv6 addresses ($COUNT6 < $MIN_IPV6_ENTRIES)"
fi
log "Valid unique addresses: IPv4=$COUNT4 IPv6=$COUNT6 (mode=$MODE)"

# Generate new entries in a staging list, verify the count, then swap.
# NOTE: RouterOS has no atomic rename/swap of address lists.
generate_family() {
    local name="$1" file="$2" count="$3" path
    case "$name" in
        ipv4) path='/ip firewall address-list' ;;
        ipv6) path='/ipv6 firewall address-list' ;;
    esac
    cat <<ROS

# $name ($count entries)
:log info "Loading Turris Greylist $name"
$path remove [$path find where list="turris_greylist_new"]
ROS
    awk -v path="$path" '{print path " add address=" $1 " list=turris_greylist_new timeout=60d"}' "$file"
    cat <<ROS
:local expectedCount $count
:local newCount [:len [$path find where list="turris_greylist_new"]]
:if (\$newCount != \$expectedCount) do={
    :log error ("Turris Greylist $name incomplete: " . \$newCount . "/" . \$expectedCount)
    :error "Turris Greylist $name import incomplete"
}
$path remove [$path find where list="turris_greylist"]
:foreach item in=[$path find where list="turris_greylist_new"] do={
    $path set \$item list="turris_greylist"
}
:log info "Turris Greylist $name updated"
ROS
}

{
    printf '# Turris Greylist generated %s; mode=%s; IPv4=%s; IPv6=%s\n' "$(date '+%F %T')" "$MODE" "$COUNT4" "$COUNT6"
    if [[ "$MODE" != ipv6 ]]; then generate_family ipv4 "$IPV4_FILE" "$COUNT4"; fi
    if [[ "$MODE" != ipv4 ]]; then generate_family ipv6 "$IPV6_FILE" "$COUNT6"; fi
} > "$RSC_TMP"
[[ -s "$RSC_TMP" ]] || die "Generated RSC is empty"
chmod 644 "$RSC_TMP"
mv -f -- "$RSC_TMP" "$OUTPUT_FILE"
log "OK: $OUTPUT_FILE"

