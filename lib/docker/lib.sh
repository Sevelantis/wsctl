#!/usr/bin/env bash
# lib.sh — shared formatting, unit conversion, and volume/image classification helpers for the docker scripts.

# Color: single knob, ON by default. COLOR=1 (default) color · COLOR=0 plain · COLOR=auto → color
# only at a terminal (off when piped, for clean logs).
COLOR="${COLOR:-1}"
[ "$COLOR" = auto ] && { [ -t 1 ] && COLOR=1 || COLOR=0; }
if [ "$COLOR" = "0" ]; then C_RED=""; C_YEL=""; C_GRN=""; C_DIM=""; C_BLD=""; C_RST=""
else C_RED=$'\033[31m'; C_YEL=$'\033[33m'; C_GRN=$'\033[32m'; C_DIM=$'\033[2m'; C_BLD=$'\033[1m'; C_RST=$'\033[0m'; fi

# --- units ---
human2bytes() { awk -v s="${1:-0}" 'BEGIN{n=s+0;u=s;sub(/^[0-9.]+/,"",u);gsub(/[^A-Za-z]/,"",u);u=tolower(u);m=1;
  if(u=="kb")m=1000;else if(u=="mb")m=1000000;else if(u=="gb")m=1000000000;else if(u=="tb")m=1000000000000;
  else if(u=="kib"||u=="k")m=1024;else if(u=="mib"||u=="m")m=1048576;else if(u=="gib"||u=="g")m=1073741824;else if(u=="tib"||u=="t")m=1099511627776;
  printf "%.0f\n",n*m}'; }
bytes2human() { awk -v b="${1:-0}" 'BEGIN{split("B KiB MiB GiB TiB PiB",u," ");i=1;while(b>=1024&&i<6){b/=1024;i++}printf(i==1?"%d %s":"%.2f %s"),b,u[i]}'; }

# --- time: compact "created N ago" from a YYYY-MM-DD (docker exposes no last-used, only created) ---
NOW="$(date +%s 2>/dev/null || echo 0)"
epoch_of() { date -d "$1" +%s 2>/dev/null || date -j -f '%Y-%m-%d' "${1:0:10}" +%s 2>/dev/null; }   # GNU || BSD
agefmt() { case "${1:-}" in ''|'-') printf '%s' '-'; return ;; esac   # missing date → '-' (GNU date -d "-" would say "today")
  local e d; e="$(epoch_of "$1")"; [ -n "$e" ] || { printf '%s' '-'; return; }
  d=$(( (NOW - e) / 86400 )); [ "$d" -lt 0 ] 2>/dev/null && d=0
  if   [ "$d" -lt 1 ]   2>/dev/null; then printf 'today'
  elif [ "$d" -lt 14 ]  2>/dev/null; then printf '%dd'  "$d"
  elif [ "$d" -lt 61 ]  2>/dev/null; then printf '%dw'  "$(( d / 7 ))"
  elif [ "$d" -lt 730 ] 2>/dev/null; then printf '%dmo' "$(( d / 30 ))"
  else printf '%dy' "$(( d / 365 ))"; fi; }

# --- chart primitives ---
pct_color() { awk -v p="${1:-0}" -v r="$C_RED" -v y="$C_YEL" -v g="$C_GRN" 'BEGIN{printf "%s",(p>=85)?r:(p>=60)?y:g}'; }
bar() { awk -v p="${1:-0}" -v w="${2:-20}" 'BEGIN{if(p<0)p=0;if(p>100)p=100;f=int(p*w/100+.5);s="";for(i=0;i<f;i++)s=s"█";for(i=0;i<w-f;i++)s=s"░";printf "%s",s}'; }
# barline <bytes> <max> <label> [width] [color] — bar scaled to max. 5th arg overrides color; DEFAULT is a
# neutral accent (green), NOT pct_color's danger palette — these bars show magnitude, not capacity/danger.
barline() { local b="${1:-0}" m="${2:-1}" l="${3:-}" w="${4:-14}" col="${5:-$C_GRN}" p; [ "$m" -gt 0 ] 2>/dev/null || m=1; p=$(awk -v b="$b" -v m="$m" 'BEGIN{printf "%.0f",b*100/m}'); printf '%s%s%s  %10s  %s\n' "$col" "$(bar "$p" "$w")" "$C_RST" "$(bytes2human "$b")" "$l"; }
# heat_color <bytes> <max> — magnitude heat RELATIVE to the largest bar in the list: top tier red,
# mid yellow, low green. Three tiers (not a gradient/rainbow). Used to color the TOP RECLAIMABLE bars.
heat_color() { awk -v b="${1:-0}" -v m="${2:-1}" -v r="$C_RED" -v y="$C_YEL" -v g="$C_GRN" 'BEGIN{if(m+0<=0)m=1;p=b*100/m; printf "%s",(p>=66)?r:(p>=33)?y:g}'; }
# stackbar <green_bytes> <total_bytes> <width> — two-tone: green run (reclaimable) + orange/▓ run (taken)
stackbar() { local g="${1:-0}" t="${2:-1}" w="${3:-24}" gl ol; [ "$t" -gt 0 ] 2>/dev/null || t=1
  gl=$(awk -v g="$g" -v t="$t" -v w="$w" 'BEGIN{f=int(g*w/t+.5);if(f<0)f=0;if(f>w)f=w;print f}'); ol=$(( w - gl ))
  printf '%s%s%s%s%s' "$C_GRN" "$(awk -v n="$gl" 'BEGIN{s="";for(i=0;i<n;i++)s=s"█";print s}')" \
    "$C_YEL" "$(awk -v n="$ol" 'BEGIN{s="";for(i=0;i<n;i++)s=s"▓";print s}')" "$C_RST"; }
rule() { printf '%s%s%s\n' "$C_DIM" "$(printf '%.0s─' {1..59})" "$C_RST"; }
# section <TITLE> [hint] — the ONE section-header style, used by every block (DRY: default + verbose match)
section() { printf '\n%s%s%s' "$C_BLD" "$1" "$C_RST"; [ -n "${2:-}" ] && printf '  %s%s%s' "$C_DIM" "$2" "$C_RST"; printf '\n'; }
# tgrid_rule <indent> <w1> <w2> … — dim grid rule; ┼ lands under each ' │ ' column separator.
# Built entirely in awk (bash 3.2 on macOS mishandles building unicode strings under set -u).
tgrid_rule() { local ind="${1:-0}"; shift
  awk -v ind="$ind" -v ws="$*" -v dim="$C_DIM" -v rst="$C_RST" 'BEGIN{
    line=sprintf("%*s", ind, ""); n=split(ws, a, " ")
    for (k=1;k<=n;k++){ if (k>1) line=line "─┼─"; for (i=0;i<a[k]+0;i++) line=line "─" }
    print dim line rst }'; }
report_head() { printf '\n%s' "$C_BLD"; printf '%.0s═' {1..24}; printf ' %s ' "${2:-REPORT}"; printf '%.0s═' {1..24}; printf '%s\n' "$C_RST"; [ -n "${1:-}" ] && printf '%s%s%s\n' "$C_DIM" "$1" "$C_RST"; }
log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }
print_error() { printf '%s%s%s\n' "$C_RED$C_BLD" "$*" "$C_RST" >&2; }

# vm_disk_bar <label> — macOS Docker VM disk ceiling (used / configured). Shared by audit + cleanup (DRY).
# %z = configured size, %b×512 = blocks actually on the SSD. Prints nothing if the VM file isn't found.
vm_disk_bar() {
  local label="$1" data="$HOME/Library/Containers/com.docker.docker/Data" f total used pct crit
  for f in "$data"/vms/0/data/Docker.raw "$data"/vms/0/data/disk.img "$data"/vms/0/data/Docker.qcow2; do
    [ -f "$f" ] || continue
    set -- $(stat -f '%z %b' "$f" 2>/dev/null); total="${1:-0}"; used=$(( ${2:-0} * 512 ))
    pct=$(awk -v u="$used" -v t="$total" 'BEGIN{printf "%.0f",(t>0)?(u*100)/t:0}')
    crit=""; [ "$pct" -ge 85 ] 2>/dev/null && crit="  ${C_RED}← writes fail near the cap${C_RST}"
    printf '%s%s%s  %s / %s  %s%s%s  %s%%%s\n' "$C_BLD" "$label" "$C_RST" \
      "$(bytes2human "$used")" "$(bytes2human "$total")" "$(pct_color "$pct")" "$(bar "$pct" 20)" "$C_RST" "$pct" "$crit"
    return 0
  done
}

# --- volume table + grouped grid — shared by audit + cleanup (DRY) ---
# build_vtab — enriched, size-sorted rows: bytes<TAB>class<TAB>size<TAB>links<TAB>created<TAB>name
build_vtab() {
  local vols vq vcreated keepvols
  vols="$(docker system df -v 2>/dev/null | awk '/VOLUME NAME/{f=1;next} f{if($0=="")exit; print $1"\t"$2"\t"$NF}')"
  vq="$(docker volume ls -q 2>/dev/null)"
  # `docker volume inspect --format` does NOT turn \t into a tab (unlike `image ls`) → | delimiter + tr
  vcreated=""; [ -n "$vq" ] && vcreated="$(docker volume inspect $vq --format '{{.Name}}|{{.CreatedAt}}' 2>/dev/null | tr '|' "$(printf '\t')")"
  # volumes carrying a `keep` label are ALWAYS protected — override role-based class → keep
  keepvols=" $(docker volume ls --filter "label=${KEEP_LABEL:-keep=true}" -q 2>/dev/null | tr '\n' ' ') "
  awk -F'\t' 'NR==FNR{c[$1]=substr($2,1,10);next}{print $0"\t"(($1 in c)?c[$1]:"-")}' \
    <(printf '%s\n' "$vcreated") <(printf '%s\n' "$vols") \
  | while IFS=$'\t' read -r name links size created; do
      [ -n "$name" ] || continue
      cls="$(vol_class "$name")"; case "$keepvols" in *" $name "*) cls=keep ;; esac
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(human2bytes "$size")" "$cls" "$size" "$links" "${created:--}" "$name"
    done | sort -rn
}

# vgroup <vtab> <class> <label> <color> [topN] — one class as a titled grid (label → header → rule → rows)
vgroup() {
  local vt="$1" cls="$2" label="$3" color="$4" top="${5:-${TOPVOL:-10}}" rows n bytes
  rows="$(printf '%s\n' "$vt" | awk -F'\t' -v c="$cls" '$2==c')"
  n=$(printf '%s\n' "$rows" | grep -c .); [ "$n" -gt 0 ] || return 0
  bytes=$(printf '%s\n' "$rows" | awk -F'\t' '{s+=$1} END{print s+0}')
  printf '\n %s%s%s  %s(%s · %s)%s\n' "$color" "$label" "$C_RST" "$C_DIM" "$n" "$(bytes2human "$bytes")" "$C_RST"
  printf '   %s%10s │ %-32s │ %5s │ %s%s\n' "$C_DIM" SIZE NAME LINKS CREATED "$C_RST"
  tgrid_rule 3 10 32 5 7
  printf '%s\n' "$rows" | head -"$top" | while IFS=$'\t' read -r _b _c size links created name; do
    vol_is_anon "$name" && name="${name:0:12}..(anon)"
    printf '   %10s │ %-32s │ %5s │ %s\n' "$(bytes2human "$_b")" "$name" "$links" "$(agefmt "$created")"
  done
  if [ "$n" -gt "$top" ]; then printf '   %s…and %s more%s\n' "$C_DIM" "$(( n - top ))" "$C_RST"; fi
}

# render_volume_groups <vtab> — the three class grids in cleanup-priority order
render_volume_groups() {
  vgroup "$1" regen   "🟢 regenerable — safe to remove"        "$C_GRN"
  vgroup "$1" keep    "🔴 keep — critical state, never remove"  "$C_RED"
  vgroup "$1" unknown "⚠ unknown — anonymous, inspect first"    "$C_YEL"
}

# --- volume role classification — SINGLE SOURCE OF TRUTH for audit + cleanup ---
# A volume name is <project>_<role>; classification keys on <role>. Env-overridable.
CRITICAL_ROLES="${CRITICAL_ROLES:-claude command-history gateway-tls sink-history tsdb-data}"  # never remove — real state
REGEN_ROLES="${REGEN_ROLES:-uv-cache npm-cache gateway-ca sink-tls prometheus-data vscode}"     # safe to recreate
KEEP_LABEL="${KEEP_LABEL:-keep=true}"   # a `keep`-labeled image/volume is ALWAYS protected (docker label convention)

vol_role() { printf '%s' "${1##*_}"; }              # role = suffix after LAST _ (project names may contain _); bare name → itself
vol_is_anon() { [ ${#1} -eq 64 ] && [ -z "${1//[0-9a-f]/}" ]; }                                   # 64-hex = anonymous
vol_class() {                       # echoes: keep | regen | unknown
  vol_is_anon "$1" && { printf 'unknown'; return; }
  local r; r="$(vol_role "$1")"
  case " $CRITICAL_ROLES " in *" $r "*) printf 'keep'; return;; esac
  case " $REGEN_ROLES " in *" $r "*) printf 'regen'; return;; esac
  printf 'unknown'
}

# --- "source project gone" orphan signal (flotsam pattern) — a volume <project>_<role> whose compose
# project has NO container left (running or stopped) is a confident orphan. Host-side only (we see all).
active_projects() { printf ' %s ' "$(docker ps -a --format '{{.Label "com.docker.compose.project"}}' 2>/dev/null | awk 'NF' | sort -u | tr '\n' ' ')"; }
vol_orphaned() { local p="${1%_*}"; case "$2" in *" $p "*) return 1;; *) return 0;; esac; }   # return 0 = project gone

# --- stale-image detection — SINGLE SOURCE OF TRUTH for audit (mark) + cleanup (remove) ---
# "Stale" = a tagged image that is (a) used by NO container AND (b) a superseded version
# (an older tag of a repo that also has a newer tag present locally). Protected repos are never stale.
PROTECT_IMAGE_RE="${PROTECT_IMAGE_RE:-(^|/)devcontainers-base$|-workspace$|-gateway$}"

image_inuse_ids() {   # short image IDs referenced by any container (running or stopped)
  local ids; ids="$(docker ps -a -q 2>/dev/null)"; [ -n "$ids" ] || return 0   # guard empty; no `xargs -r` (BSD/macOS lacks it)
  printf '%s\n' "$ids" | xargs docker inspect -f '{{.Image}}' 2>/dev/null | sed 's/^sha256://' | cut -c1-12 | sort -u
}
stale_image_ids() {   # short IDs safe to remove per the definition above
  # in-use + keep-labeled IDs go to awk via ENVIRON (awk -v can't hold newlines → "awk: newline in string")
  docker image ls --all --format '{{.CreatedAt}}\t{{.ID}}\t{{.Repository}}\t{{.Tag}}' 2>/dev/null \
  | INUSE="$(image_inuse_ids)" KEEP="$(docker images --filter "label=${KEEP_LABEL:-keep=true}" -q 2>/dev/null | sort -u)" awk -F'\t' -v protect="$PROTECT_IMAGE_RE" '
      BEGIN { n=split(ENVIRON["INUSE"], ia, "\n"); for (i=1;i<=n;i++) if (ia[i]!="") used[ia[i]]=1
              m=split(ENVIRON["KEEP"], ka, "\n"); for (i=1;i<=m;i++) if (ka[i]!="") keeplbl[ka[i]]=1 }
      $3=="<none>" || $4=="<none>" { next }
      { ts=$1; id=$2; repo=$3;                                   # CreatedAt sorts chronologically as text
        if (ts > newest[repo]) { newest[repo]=ts; newestid[repo]=id }
        rows[NR]=ts "\t" id "\t" repo }
      END { for (r in newestid) keepid[newestid[r]]=1             # an ID that is the newest tag of ANY repo
        for (r in rows) { split(rows[r], f, "\t"); ts=f[1]; id=f[2]; repo=f[3]
          if (repo ~ protect) continue
          if (used[id]) continue
          if (id in keeplbl) continue                            # explicit keep=true label → always protect
          if (ts >= newest[repo]) continue                       # keep the newest tag of each repo
          if (id in keepid) continue                             # …and never a shared ID current elsewhere
          print id } }' | sort -u
}

# image_unique_bytes — ID<TAB>unique-size(human) from `docker system df -v`. UNIQUE = space actually freed when
# the image is removed; raw Size counts shared layers → overstates reclaim. NF-based parse tolerates the
# multi-word CREATED column; empty output → caller falls back to raw size.
image_unique_bytes() {
  docker system df -v 2>/dev/null | awk '
    /Images space usage:/{img=1; next}
    /space usage:/{img=0}
    img && /IMAGE ID/{next}
    img && NF>=8 { print $3"\t"$(NF-1) }'
}
