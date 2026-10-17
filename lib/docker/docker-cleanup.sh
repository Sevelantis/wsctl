#!/usr/bin/env bash
# docker-cleanup.sh — reclaim regenerable Docker space. Safe: never touches critical/anonymous/in-use.
#
# USAGE
#   docker-cleanup.sh [--soft] [--images] [--volumes] [--dry-run] [-h|--help]
#
# CATEGORIES (pick any; with NONE given, --soft runs by default)
#   --soft      stopped containers + dangling images + build cache + unused networks
#               (equals `docker system prune -f`; no volumes, no tagged images).
#   --images    superseded tagged images (an older tag of a repo with a newer local tag), used by
#               no container. Protects devcontainers-base + *-workspace / *-gateway.
#   --volumes   regenerable, UNLINKED volumes only (uv/npm caches, gateway-ca, …), BY NAME. NEVER
#               critical (claude / command-history / gateway-tls / sink-history / tsdb-data),
#               anonymous, keep-labeled, or in-use. One `docker volume rm` per name (never
#               `docker volume prune`), re-classified right before each removal.
#   --dry-run   change NOTHING — print the exact removal commands as copy/paste blocks.
#   -h, --help  this help
#
# Examples:  docker-cleanup.sh                      # soft only (the safe default)
#            docker-cleanup.sh --volumes --dry-run  # preview the `docker volume rm` lines
#            docker-cleanup.sh --images --volumes   # remove superseded images + regen volumes
#            docker-cleanup.sh --soft --images --volumes   # everything reclaimable
#
# ENV: COLOR (1|0|auto) · TOPVOL · CRITICAL_ROLES / REGEN_ROLES / KEEP_LABEL / PROTECT_IMAGE_RE (see lib.sh)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$DIR/lib.sh"

EX_USAGE=64; EX_UNAVAIL=69
DO_SOFT=false; DO_IMAGES=false; DO_VOLUMES=false; DRY_RUN=false; any=false

print_help() { awk 'NR==1{next} /^#/{sub(/^# ?/,"");print;next} {exit}' "${BASH_SOURCE[0]}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --soft)     DO_SOFT=true;    any=true ;;
    --images)   DO_IMAGES=true;  any=true ;;
    --volumes)  DO_VOLUMES=true; any=true ;;
    --hard)     print_error "--hard was renamed --volumes (regenerable, unlinked, guarded)"; exit "$EX_USAGE" ;;
    --dry-run)  DRY_RUN=true ;;
    -h|--help)  print_help; exit 0 ;;
    --)         shift; break ;;
    -*)         print_error "Unknown option: $1"; print_help; exit "$EX_USAGE" ;;
    *)          print_error "Unexpected argument: $1"; exit "$EX_USAGE" ;;
  esac; shift
done
[ "$any" = true ] || DO_SOFT=true   # no category flag → safe default = soft (never volumes/tagged images)

command -v docker >/dev/null || { print_error "FATAL: docker not on PATH"; exit "$EX_UNAVAIL"; }

# mode label from the selected categories
mode=""; [ "$DO_SOFT" = true ] && mode="SOFT"
[ "$DO_IMAGES" = true ]  && mode="${mode:+$mode + }IMAGES"
[ "$DO_VOLUMES" = true ] && mode="${mode:+$mode + }VOLUMES"

# used bytes = sum of all system-df type SIZEs → per-category freed via before/after diff
# (robust across Docker versions; the old text-parse of "Total reclaimed space:" broke on Docker 29).
df_usedb() { docker system df --format '{{.Size}}' 2>/dev/null | while read -r s; do human2bytes "$s"; done | awk '{t+=$1} END{printf "%.0f", t+0}'; }

# ---- the exact removable sets — shared by dry-run and the real run (plan == apply) ----
stale_rows() {     # bytes<TAB>id<TAB>repo:tag for the superseded-image set (UNIQUE size)
  local ids uniqmap id size rt u; ids="$(stale_image_ids)"; [ -n "$ids" ] || return 0
  uniqmap="$(image_unique_bytes)"
  docker image ls --all --format '{{.ID}}\t{{.Size}}\t{{.Repository}}:{{.Tag}}' 2>/dev/null \
  | while IFS=$'\t' read -r id size rt; do
      printf '%s' "$ids" | grep -qxF "$id" || continue
      u="$(printf '%s\n' "$uniqmap" | awk -F'\t' -v i="$id" '$1==i{print $2; exit}')"
      printf '%s\t%s\t%s\n' "$(human2bytes "${u:-$size}")" "$id" "$rt"
    done | sort -rn
}
regen_vol_rows() { # bytes<TAB>name for regenerable + unlinked volumes (the guarded-safe set)
  build_vtab | awk -F'\t' '$2=="regen" && $4=="0" {print $1"\t"$6}' | sort -rn
}

# ---- shared read-only VOLUME SAFETY section — full classification for manual review ----
volume_safety_report() {
  local vtab unlinked crit regen unk
  vtab="$(build_vtab)"
  unlinked="$(printf '%s\n' "$vtab" | awk -F'\t' '$4=="0"')"   # LINKS 0 = review candidates
  crit=$(printf '%s\n' "$unlinked" | awk -F'\t' '$2=="keep"'    | grep -c .)
  regen=$(printf '%s\n' "$unlinked" | awk -F'\t' '$2=="regen"'  | grep -c .)
  unk=$(printf '%s\n' "$unlinked" | awk -F'\t' '$2=="unknown"' | grep -c .)
  section "VOLUME SAFETY" "unlinked volumes by class — --volumes removes ONLY the 🟢 set"
  if [ $((crit+regen+unk)) -eq 0 ]; then
    printf ' %snone unlinked — nothing to review%s\n' "$C_DIM" "$C_RST"
  else
    render_volume_groups "$unlinked"
  fi
  rule
  printf '  %s🔴 %s critical%s · %s🟢 %s regenerable%s · %s⚠ %s unknown%s   (🔴/⚠ are never removed by --volumes)\n' \
    "$C_RED" "$crit" "$C_RST" "$C_GRN" "$regen" "$C_RST" "$C_YEL" "$unk" "$C_RST"
}

cmdhead() { printf '\n%s====== %s ======%s\n' "$C_BLD" "$1" "$C_RST"; }   # copy/paste block header

# ---------------------------------------------------------------------------
# DRY RUN — print the exact removal commands as copy/paste blocks. Zero mutation.
# plan == apply: the same sets the real run acts on (stale_rows / regen_vol_rows / targeted prunes).
# ---------------------------------------------------------------------------
if [ "$DRY_RUN" = true ]; then
  report_head "DRY RUN · nothing removed · copy the blocks below to run manually · $(date '+%FT%T')" "DOCKER CLEAN · PREVIEW ($mode)"
  total=0

  if [ "$DO_SOFT" = true ]; then
    cmdhead "soft — stopped containers · dangling images · build cache · networks"
    printf 'docker container prune -f\ndocker image prune -f\ndocker builder prune -f\ndocker network prune -f\n'
    cb=$(human2bytes "$(docker system df --format '{{.Type}}\t{{.Reclaimable}}' 2>/dev/null | awk -F'\t' '$1=="Build Cache"{print $2}' | sed 's/ .*//')")
    printf '%s# ~%s reclaimable (cache estimate; Docker will not itemize cache before pruning)%s\n' "$C_DIM" "$(bytes2human "$cb")" "$C_RST"
    total=$(( total + cb ))
  fi

  if [ "$DO_IMAGES" = true ]; then
    rows="$(stale_rows)"; n=$(printf '%s\n' "$rows" | grep -c .); tot=$(printf '%s\n' "$rows" | awk -F'\t' 'NF{s+=$1}END{print s+0}')
    cmdhead "images — superseded, unused ($n · $(bytes2human "$tot") unique)"
    if [ "$n" -gt 0 ]; then
      printf '%s\n' "$rows" | while IFS=$'\t' read -r b id rt; do
        [ -n "$id" ] || continue; printf 'docker rmi %s   %s# %s · %s%s\n' "$id" "$C_DIM" "$rt" "$(bytes2human "$b")" "$C_RST"
      done
    else printf '%s# none superseded + unused%s\n' "$C_DIM" "$C_RST"; fi
    total=$(( total + tot ))
  fi

  if [ "$DO_VOLUMES" = true ]; then
    rows="$(regen_vol_rows)"; n=$(printf '%s\n' "$rows" | grep -c .); tot=$(printf '%s\n' "$rows" | awk -F'\t' 'NF{s+=$1}END{print s+0}')
    cmdhead "volumes — regenerable, unlinked ($n · $(bytes2human "$tot")) · never criticals/anonymous"
    if [ "$n" -gt 0 ]; then
      printf '%s\n' "$rows" | while IFS=$'\t' read -r b name; do
        [ -n "$name" ] || continue; printf 'docker volume rm %s   %s# %s%s\n' "$name" "$C_DIM" "$(bytes2human "$b")" "$C_RST"
      done
    else printf '%s# none regenerable + unlinked%s\n' "$C_DIM" "$C_RST"; fi
    total=$(( total + tot ))
  fi

  printf '%s======%s\n' "$C_DIM" "$C_RST"

  # advisory volume classification (before the summary, mirroring the real run)
  printf '\n'; volume_safety_report

  # PROJECTED SUMMARY — the last block (report at the bottom, per the clean/audit template):
  # a now → after preview so you see the outcome without scrolling. Nothing is removed.
  used_now=$(df_usedb); proj_after=$(( used_now - total )); [ "$proj_after" -lt 0 ] 2>/dev/null && proj_after=0
  umax=$used_now; [ "$umax" -gt 0 ] 2>/dev/null || umax=1
  section "PROJECTED  used now → after" "if you run the commands above — nothing removed yet"
  barline "$used_now"   "$umax" "now"   20 "$C_YEL"
  barline "$proj_after" "$umax" "after" 20 "$C_GRN"
  rule
  printf '  %sESTIMATED RECLAIM%s  ≈ %s%s%s   %s(projected; reconcile against a real run)%s\n' \
    "$C_BLD" "$C_RST" "$C_GRN" "$(bytes2human "$total")" "$C_RST" "$C_DIM" "$C_RST"
  printf '\n'; vm_disk_bar "DISK CEILING"
  printf '\n'
  exit 0
fi

# ================================= REAL RUN =================================
used_before=$(df_usedb); b_prev=$used_before
log "cleaning ($mode) — critical / anonymous / in-use are never touched…"

freed_cache=0; freed_cont=0; freed_img=0; freed_stale=0; freed_vol=0
removed=""        # "<unique-bytes>\t<repo:tag>" per image removed
removed_vol=""    # "<bytes>\t<name>" per volume removed

if [ "$DO_SOFT" = true ]; then
  log "soft: build cache…";        docker builder prune -f   >/dev/null 2>&1; b=$(df_usedb); freed_cache=$(( b_prev - b )); b_prev=$b
  log "soft: stopped containers…"; docker container prune -f >/dev/null 2>&1; b=$(df_usedb); freed_cont=$(( b_prev - b )); b_prev=$b
  log "soft: dangling images…";    docker image prune -f     >/dev/null 2>&1; b=$(df_usedb); freed_img=$(( b_prev - b )); b_prev=$b
  log "soft: unused networks…";    docker network prune -f   >/dev/null 2>&1
fi

if [ "$DO_IMAGES" = true ]; then
  n=0
  while IFS=$'\t' read -r b id rt; do          # stale_rows snapshots repo:tag + unique size before rmi
    [ -n "$id" ] || continue
    docker rmi "$id" >/dev/null 2>&1 || continue
    n=$((n+1)); removed="$removed$b	$rt
"
  done < <(stale_rows)
  b=$(df_usedb); freed_stale=$(( b_prev - b )); b_prev=$b
  log "images: removed $n superseded image(s)"
fi

if [ "$DO_VOLUMES" = true ]; then
  vn=0
  while IFS=$'\t' read -r b name; do
    [ -n "$name" ] || continue
    [ "$(vol_class "$name")" = regen ] || continue         # defensive re-check: never critical/anon/keep
    docker volume rm "$name" >/dev/null 2>&1 || continue   # no -f → Docker refuses in-use as a final backstop
    vn=$((vn+1)); removed_vol="$removed_vol$b	$name
"
  done < <(regen_vol_rows)
  b=$(df_usedb); freed_vol=$(( b_prev - b )); b_prev=$b
  log "volumes: removed $vn regenerable volume(s)"
fi

used_after=$(df_usedb)

# --- VOLUME SAFETY (advisory) — printed BEFORE the summary so the reclaim report is the LAST thing on screen ---
volume_safety_report

# ---------------------------------------------------------------------------
# SUMMARY — the last block, no scroll-up: what was removed · what was freed · before → after.
# ---------------------------------------------------------------------------
report_head "critical / anonymous / in-use never touched · $(date '+%FT%T')" "DOCKER CLEAN · $mode"

# REMOVED IMAGES — exactly which tags went (UNIQUE size), size-sorted
rn=$(printf '%s' "$removed" | grep -c .)
if [ "${rn:-0}" -gt 0 ] 2>/dev/null; then
  rtot=$(printf '%s' "$removed" | awk -F'\t' 'NF{s+=$1}END{print s+0}')
  section "REMOVED IMAGES" "$rn · $(bytes2human "$rtot") unique freed"
  printf '%s' "$removed" | sort -rn | while IFS=$'\t' read -r b rt; do
    [ -n "$rt" ] || continue; printf '   %10s  %s\n' "$(bytes2human "$b")" "$rt"
  done
fi

# REMOVED VOLUMES — exactly which volumes went (regenerable only), size-sorted
rvn=$(printf '%s' "$removed_vol" | grep -c .)
if [ "${rvn:-0}" -gt 0 ] 2>/dev/null; then
  rvtot=$(printf '%s' "$removed_vol" | awk -F'\t' 'NF{s+=$1}END{print s+0}')
  section "REMOVED VOLUMES" "$rvn · $(bytes2human "$rvtot") · regenerable only"
  printf '%s' "$removed_vol" | sort -rn | while IFS=$'\t' read -r b name; do
    [ -n "$name" ] || continue; printf '   %10s  %s\n' "$(bytes2human "$b")" "$name"
  done
fi

# FREED BY CATEGORY — approximate (docker df double-counts shared layers); the before→after total is exact
[ "$freed_cache" -lt 0 ] 2>/dev/null && freed_cache=0; [ "$freed_cont" -lt 0 ] 2>/dev/null && freed_cont=0
[ "$freed_img" -lt 0 ] 2>/dev/null && freed_img=0;   [ "$freed_stale" -lt 0 ] 2>/dev/null && freed_stale=0
[ "$freed_vol" -lt 0 ] 2>/dev/null && freed_vol=0
fmax=1; for v in $freed_cache $freed_cont $freed_img $freed_stale $freed_vol; do [ "$v" -gt "$fmax" ] 2>/dev/null && fmax=$v; done
section "FREED BY CATEGORY" "approx — shared layers; the total below is exact"
if [ "$DO_SOFT" = true ]; then
  barline "$freed_cache" "$fmax" "build cache"        12
  barline "$freed_cont"  "$fmax" "stopped containers" 12
  barline "$freed_img"   "$fmax" "dangling images"    12
fi
[ "$DO_IMAGES" = true ]  && barline "$freed_stale" "$fmax" "superseded images" 12
[ "$DO_VOLUMES" = true ] && barline "$freed_vol"   "$fmax" "regen volumes"     12

# BEFORE → AFTER (total used across all types) — the exact, headline reclaim
reclaimed=$(( used_before - used_after )); [ "$reclaimed" -lt 0 ] 2>/dev/null && reclaimed=0
umax=$used_before; [ "$umax" -gt 0 ] 2>/dev/null || umax=1
section "USED  before → after"
barline "$used_before" "$umax" "before" 20 "$C_YEL"
barline "$used_after"  "$umax" "after"  20 "$C_GRN"
rule
printf '  %sRECLAIMED%s  ≈ %s%s%s\n' "$C_BLD" "$C_RST" "$C_GRN" "$(bytes2human "$reclaimed")" "$C_RST"

# VM disk ceiling — physical file; only shrinks on a Docker Desktop restart/compact (freed space still stops write failures)
printf '\n'; vm_disk_bar "DISK CEILING"
printf '\n'
