#!/usr/bin/env bash
# docker-space-audit.sh — READ-ONLY Docker disk audit (macOS / Docker Desktop).
# Nothing is ever pruned/removed/resized. Default = brief chart report.
# -v adds detail tables ABOVE the report, so the summary stays the last thing on screen (no scroll-up).
#
# USAGE
#   docker-space-audit.sh [-v|--verbose] [-h|--help]
#     (default)          brief chart report — VM disk, usage, top reclaimable volumes + images
#     -v, --verbose      prepend IMAGES + grouped VOLUMES + BUILD-CACHE tables, then the report
#     -h, --help         this help
#
# ENV: COLOR (1|0|auto) · TOPV (5) top reclaimable rows · TOPI (10) image rows · TOPVOL (10) rows per volume group
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$DIR/lib.sh"

EX_USAGE=64; EX_UNAVAIL=69
TOPV="${TOPV:-5}"; TOPI="${TOPI:-10}"; TOPVOL="${TOPVOL:-10}"
VERBOSE=false

print_help() { awk 'NR==1{next} /^#/{sub(/^# ?/,"");print;next} {exit}' "${BASH_SOURCE[0]}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    -v|--verbose) VERBOSE=true ;;
    -h|--help)    print_help; exit 0 ;;
    --)           shift; break ;;
    -*)           print_error "Unknown option: $1"; print_help; exit "$EX_USAGE" ;;
    *)            print_error "Unexpected argument: $1"; exit "$EX_USAGE" ;;
  esac; shift
done

command -v docker >/dev/null || { print_error "FATAL: docker not on PATH"; exit "$EX_UNAVAIL"; }

# --- collect once (shared by report + tables) ---
stale="$(stale_image_ids)"
vtab="$(build_vtab)"   # enriched, size-sorted volume table (bytes class size links created name) — lib.sh

# ---------------------------------------------------------------------------
# VERBOSE DETAIL — printed FIRST so the report below is the last thing on screen.
# ---------------------------------------------------------------------------
detail() {
  local inuse; inuse="$(image_inuse_ids)"   # $stale already computed

  section "IMAGES"
  printf ' %s%8s │ %-34s │ %-6s │ %s%s\n' "$C_DIM" SIZE 'REPOSITORY:TAG' CREATED FLAG "$C_RST"
  tgrid_rule 1 8 34 6 8
  docker image ls --all --format '{{.Size}}\t{{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.CreatedAt}}' 2>/dev/null \
    | while IFS=$'\t' read -r size repotag id created; do printf '%s\t%s\t%s\t%s\t%s\n' "$(human2bytes "$size")" "$size" "$repotag" "$id" "$created"; done \
    | sort -rn | head -"$TOPI" | while IFS=$'\t' read -r _b size repotag id created; do   # sort by bytes (portable; BSD sort lacks -h)
        flag="${C_DIM}keep${C_RST}"; printf '%s' "$inuse" | grep -qxF "$id" && flag="${C_GRN}✓ used${C_RST}"
        printf '%s' "$stale" | grep -qxF "$id" && flag="${C_YEL}stale${C_RST}"
        printf ' %8s │ %-34.34s │ %-6s │ %b\n' "$size" "$repotag" "$(agefmt "${created:0:10}")" "$flag"
      done
  local ti; ti=$(docker image ls --all --format '{{.ID}}' 2>/dev/null | wc -l | tr -d ' ')
  [ "${ti:-0}" -gt "$TOPI" ] 2>/dev/null && printf ' %s…and %s more (showing top %s by size)%s\n' "$C_DIM" "$(( ti - TOPI ))" "$TOPI" "$C_RST"
  printf ' %sFLAG: keep = kept · ✓ used = a container uses it · stale = superseded old tag → docker-clean --images%s\n' "$C_DIM" "$C_RST"
  printf ' %s(removal is by supersession + not-in-use — never by age)%s\n' "$C_DIM" "$C_RST"

  # VOLUMES — grouped by class (regenerable → keep → unknown), each a size-sorted sub-list
  local vk vr vu vt
  vk=$(printf '%s\n' "$vtab" | awk -F'\t' '$2=="keep"'    | grep -c .)
  vr=$(printf '%s\n' "$vtab" | awk -F'\t' '$2=="regen"'   | grep -c .)
  vu=$(printf '%s\n' "$vtab" | awk -F'\t' '$2=="unknown"' | grep -c .)
  vt=$(printf '%s\n' "$vtab" | awk -F'\t' '{s+=$1} END{print s+0}')
  section "VOLUMES" "$(bytes2human "$vt") across $((vk+vr+vu)) — grouped by class"
  render_volume_groups "$vtab"
  local un; un=$(docker volume ls -f dangling=true -q 2>/dev/null | wc -l | tr -d ' ')
  printf '\n %sunlinked volumes: %s  (critical + anonymous are never auto-removed)%s\n' "$C_DIM" "$un" "$C_RST"

  section "BUILD CACHE" "active builder"
  docker buildx du 2>/dev/null | tail -3 | awk '{printf " %-13s %s\n",$1,$2}'
}

# ---------------------------------------------------------------------------
# BRIEF REPORT — chart summary; printed LAST so it never needs a scroll-up.
# ---------------------------------------------------------------------------
brief() {
  report_head "read-only · nothing modified · $(date -u '+%FT%TZ')" "DOCKER DISK · AUDIT"
  vm_disk_bar "VM DISK"

  # usage breakdown — sorted by size desc; bar scaled to the largest type
  local dfrows maxb usedb reclb
  dfrows="$(docker system df --format '{{.Type}}\t{{.Size}}\t{{.Reclaimable}}' 2>/dev/null)"
  maxb=1; usedb=0; reclb=0
  while IFS=$'\t' read -r _t size recl; do
    b=$(human2bytes "$size"); [ "$b" -gt "$maxb" ] 2>/dev/null && maxb=$b
    usedb=$(( usedb + b )); reclb=$(( reclb + $(human2bytes "${recl%% *}") ))
  done <<< "$dfrows"
  section "USAGE"
  printf ' %s%-11s %9s  %-10s  %s%s\n' "$C_DIM" 'type' 'size' 'used' 'reclaimable' "$C_RST"
  printf '%s\n' "$dfrows" | while IFS=$'\t' read -r type size recl; do
    printf '%s\t%s\t%s\t%s\n' "$(human2bytes "$size")" "$type" "$size" "$recl"
  done | sort -rn | while IFS=$'\t' read -r b type size recl; do
    case "$type" in "Local Volumes") type="Volumes" ;; "Build Cache") type="Build cache" ;; esac
    p=$(awk -v b="$b" -v m="$maxb" 'BEGIN{printf "%.0f",(b*100)/m}')
    printf ' %-11s %9s  %s%s%s  %s\n' "$type" "$size" "$(pct_color "$p")" "$(bar "$p" 10)" "$C_RST" "$recl"
  done
  rule
  local taken=$(( usedb - reclb )); [ "$taken" -lt 0 ] 2>/dev/null && taken=0
  printf ' %sRECLAIMABLE%s %s  %s%s reclaim%s · %s%s taken%s\n' "$C_BLD" "$C_RST" \
    "$(stackbar "$reclb" "$usedb" 28)" \
    "$C_GRN" "$(bytes2human "$reclb")" "$C_RST" "$C_YEL" "$(bytes2human "$taken")" "$C_RST"
  printf ' %sdocker-reported; docker-clean frees cache + dangling (+ --images superseded); volumes are manual-only%s\n' "$C_DIM" "$C_RST"

  # TOP RECLAIMABLE VOLUMES — full candidate set (for count/total), show top TOPV
  local vall vn vtot vmax aprojects
  vall="$(printf '%s\n' "$vtab" | awk -F'\t' '$2=="regen" && $4=="0" {print $1"\t"$6}' | sort -rn)"
  vn=$(printf '%s\n' "$vall" | grep -c .); vtot=$(printf '%s\n' "$vall" | awk -F'\t' '{s+=$1}END{print s+0}')
  section "TOP RECLAIMABLE VOLUMES" "unlinked · regenerable · manual rm only — $vn · $(bytes2human "$vtot")"
  aprojects="$(active_projects)"   # flotsam "source project gone" signal — mark confident orphans
  vmax=$(printf '%s\n' "$vall" | head -1 | cut -f1); [ -n "$vmax" ] && [ "$vmax" -gt 0 ] 2>/dev/null || vmax=1
  if [ "$vn" -gt 0 ]; then printf '%s\n' "$vall" | head -"$TOPV" | while IFS=$'\t' read -r b name; do
      tag=""; [ "$aprojects" != "  " ] && vol_orphaned "$name" "$aprojects" && tag="  ${C_DIM}· project gone${C_RST}"
      barline "$b" "$vmax" "$name$tag" 10 "$(heat_color "$b" "$vmax")"
    done
    [ "$vn" -gt "$TOPV" ] && printf ' %s…and %s more%s\n' "$C_DIM" "$(( vn - TOPV ))" "$C_RST"
  else printf ' %snone unlinked — nothing idle to reclaim%s\n' "$C_DIM" "$C_RST"; fi

  # TOP RECLAIMABLE IMAGES — superseded + unused (what `docker-clean --images` removes)
  # UNIQUE size (space actually freed); raw image size counts shared layers → overstates. Falls back to raw.
  local iall in itot imax uniqmap
  uniqmap="$(image_unique_bytes)"
  iall="$(docker image ls --all --format '{{.ID}}\t{{.Size}}\t{{.Repository}}:{{.Tag}}' 2>/dev/null \
    | while IFS=$'\t' read -r id size rt; do
        printf '%s' "$stale" | grep -qxF "$id" || continue
        u="$(printf '%s\n' "$uniqmap" | awk -F'\t' -v i="$id" '$1==i{print $2; exit}')"
        printf '%s\t%s\n' "$(human2bytes "${u:-$size}")" "$rt"
      done | sort -rn)"
  in=$(printf '%s\n' "$iall" | grep -c .); itot=$(printf '%s\n' "$iall" | awk -F'\t' '{s+=$1}END{print s+0}')
  section "TOP RECLAIMABLE IMAGES" "superseded · unused · unique size — docker-clean --images — $in · $(bytes2human "$itot")"
  imax=$(printf '%s\n' "$iall" | head -1 | cut -f1); [ -n "$imax" ] && [ "$imax" -gt 0 ] 2>/dev/null || imax=1
  if [ "$in" -gt 0 ]; then printf '%s\n' "$iall" | head -"$TOPV" | while IFS=$'\t' read -r b rt; do barline "$b" "$imax" "$rt" 10 "$(heat_color "$b" "$imax")"; done
    [ "$in" -gt "$TOPV" ] && printf ' %s…and %s more%s\n' "$C_DIM" "$(( in - TOPV ))" "$C_RST"
  else printf ' %snone — no superseded images to reclaim%s\n' "$C_DIM" "$C_RST"; fi
  printf '\n'
}

[ "$VERBOSE" = true ] && detail
brief
