#!/bin/sh
# adjust_time.sh - Buildroot/BusyBox friendly time setter
# 1) Try ntpd (if present)
# 2) Try HTTP Date header over *HTTP* (no TLS needed) via curl/wget/busybox wget
# 3) Fall back to manual DD - MM - YYYY - HH - mm (prompts via /dev/tty)
#
# Portability note:
#   BusyBox `date` parses an input string with:  date -D "<informat>" -d "<str>"
#   GNU coreutils `date` has NO -D option; it parses RFC1123 natively with -d.
#   set_time_from_http() below tries both so it works on either userland.
ROME_TZ="Europe/Rome"
# Prefer POSIX TZ if zoneinfo is missing
ROMETZ_POSIX='CET-1CEST,M3.5.0/2,M10.5.0/3'
have() { command -v "$1" >/dev/null 2>&1; }
show_result() {
  echo "Now (UTC):  $(date -u '+%Y-%m-%d %H:%M:%S %Z')"
  # Try zoneinfo first, else POSIX TZ string
  if [ -e /etc/localtime ] || [ -d /usr/share/zoneinfo ]; then
    TZ="Europe/Rome" date '+Now (Rome): %Y-%m-%d %H:%M:%S %Z' 2>/dev/null \
      || TZ="$ROMETZ_POSIX" date '+Now (Rome): %Y-%m-%d %H:%M:%S %Z'
  else
    TZ="$ROMETZ_POSIX" date '+Now (Rome): %Y-%m-%d %H:%M:%S %Z'
  fi
}
# --- A) SNTP via BusyBox ntpd (best if available)
try_ntpd() {
  have ntpd || return 1
  if ntpd -q -p pool.ntp.org >/dev/null 2>&1; then
    echo "System time set via ntpd (SNTP)."
    return 0
  fi
  return 1
}
# --- B) HTTP Date header over HTTP (no TLS/certs required)
fetch_http_date() {
  # Use plain HTTP to avoid TLS/cert issues
  SITES="http://example.com http://neverssl.com http://1.1.1.1"
  for url in $SITES; do
    if have curl; then
      d=$(curl -sI --max-time 5 -L "$url" | awk -F': ' 'tolower($1)=="date"{print $2; exit}')
      [ -n "$d" ] && { echo "$d"; return 0; }
    elif have wget; then
      # BusyBox wget prints headers to stderr with -S; capture and parse
      d=$(wget -q --spider -S --timeout=5 "$url" 2>&1 | awk -F': ' '/^[[:space:]]*Date:/ {print $2; exit}')
      [ -n "$d" ] && { echo "$d"; return 0; }
    elif have busybox && busybox | grep -q wget; then
      # Explicit busybox wget
      d=$(busybox wget -q --spider -S --timeout=5 "$url" 2>&1 | awk -F': ' '/^[[:space:]]*Date:/ {print $2; exit}')
      [ -n "$d" ] && { echo "$d"; return 0; }
    fi
  done
  return 1
}
# --- B2) Set clock from an HTTP "Date:" header, portable across BusyBox & GNU date
set_time_from_http() {
  http_date="$1"
  epoch=""

  # Guard: empty input (GNU `date -d ""` would wrongly resolve to today 00:00)
  [ -n "$http_date" ] || return 1

  # 1) BusyBox date: needs -D to describe the input format
  epoch=$(date -u -D "%a, %d %b %Y %H:%M:%S %Z" -d "$http_date" +%s 2>/dev/null)

  # 2) GNU coreutils date: no -D; parses RFC1123 natively with -d
  if [ -z "$epoch" ]; then
    epoch=$(date -u -d "$http_date" +%s 2>/dev/null)
  fi

  # Sanity: epoch must be all digits and after 2020-01-01 (1577836800)
  case "$epoch" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$(expr "$epoch" \> 1577836800)" -eq 1 ] || return 1

  # Set the clock. -s "@epoch" works on both BusyBox and GNU date.
  if date -u -s "@$epoch" >/dev/null 2>&1; then
    :
  else
    # Last resort: reformat epoch to a literal both accept, then set
    human=$(date -u -d "@$epoch" "+%Y-%m-%d %H:%M:%S" 2>/dev/null) || return 1
    date -u -s "$human" >/dev/null 2>&1 || return 1
  fi

  echo "System time set from Internet (HTTP Date)."
  return 0
}
# --- C) Manual fallback (prompts read/write via /dev/tty)
pad2() {
  v="$1"
  case "$v" in
    [0-9]) echo "0$v" ;;
    [0-9][0-9]) echo "$v" ;;
    *) echo "$v" ;;
  esac
}
ask_num() {
  prompt="$1"; min="$2"; max="$3"
  while :; do
    printf "%s" "$prompt" > /dev/tty
    # Read from the controlling terminal to ensure we see prompts
    IFS= read -r v < /dev/tty || return 1
    v=$(echo "$v" | tr -d '[:space:]')
    case "$v" in
      ''|*[!0-9]*) echo "Please enter digits only." > /dev/tty; continue ;;
    esac
    # numeric compare via expr to avoid octal traps
    if [ "$(expr "$v" \>= "$min")" -eq 1 ] && [ "$(expr "$v" \<= "$max")" -eq 1 ]; then
      echo "$v"
      return 0
    else
      echo "Value must be between $min and $max." > /dev/tty
    fi
  done
}
manual_fallback() {
  echo "Network time failed. Enter date/time manually." > /dev/tty
  DAY=$(ask_num   "Enter day (DD): "         1 31)   || exit 1
  MONTH=$(ask_num "Enter month (MM): "       1 12)   || exit 1
  YEAR=$(ask_num  "Enter year (YYYY): "   1970 2999) || exit 1
  HOUR=$(ask_num  "Enter hour (HH, 24h): "   0 23)   || exit 1
  MIN=$(ask_num   "Enter minutes (MM): "     0 59)   || exit 1
  DAY=$(pad2 "$DAY"); MONTH=$(pad2 "$MONTH"); HOUR=$(pad2 "$HOUR"); MIN=$(pad2 "$MIN")
  DT="$YEAR-$MONTH-$DAY $HOUR:$MIN:00"
  echo "Setting date to: $DT" > /dev/tty
  if date -s "$DT" >/dev/null 2>&1; then
    show_result
    exit 0
  else
    echo "Failed to set time with manual input." > /dev/tty
    exit 1
  fi
}
# --- Main ---
if try_ntpd; then
  show_result
  exit 0
fi
if http=$(fetch_http_date); then
  echo "Fetched HTTP Date: $http"
  if set_time_from_http "$http"; then
    show_result
    exit 0
  fi
fi
manual_fallback
