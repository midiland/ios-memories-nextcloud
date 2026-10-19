#!/bin/bash
#
# update-changelog.sh
# Génère les entrées "Unreleased" du CHANGELOG depuis les commits conventionnels.
#
# Usage :
#   ./scripts/update-changelog.sh                 Commits depuis le dernier tag (défaut)
#   ./scripts/update-changelog.sh --dry-run       Aperçu sans modifier le fichier
#   ./scripts/update-changelog.sh <plage-git>     Plage explicite (ex: v1.0.0-rc.10..HEAD)
#
# Les commits conventionnels (https://www.conventionalcommits.org) sont mappés vers
# les sections de Keep a Changelog ; le scope devient la catégorie en gras :
#
#   fix(zoom): disable pinch-to-zoom   →  ### Fixed
#                                         - **Zoom**: Disable pinch-to-zoom. (Issue #12)
#
# Les commits non user-facing (chore, docs, test, style, build, ci, refactor) sont ignorés.
# Les références d'issues sont lues dans le sujet et le corps (#12, Fixes #12, Closes #12…).
# Idempotent : une entrée déjà présente (même puce ou mêmes issues) n'est pas dupliquée.

set -euo pipefail

cd "$(dirname "$0")/.."
CHANGELOG="CHANGELOG.md"

DRY_RUN=0
if [ "${1:-}" = "--dry-run" ] || [ "${1:-}" = "-n" ]; then
  DRY_RUN=1
  shift
fi

range="${1:-}"
if [ -z "$range" ]; then
  last_tag=$(git describe --tags --abbrev=0 2>/dev/null || true)
  if [ -z "$last_tag" ]; then
    echo "Erreur : aucun tag trouvé, passez une plage explicite (ex: v1.0.0-rc.11..HEAD)" >&2
    exit 1
  fi
  range="$last_tag..HEAD"
fi

# --- 1. Génération des entrées : "section<TAB>puce<TAB>refs" ---
entries=$(git log --format='%s%x1f%b%x1e' "$range" | awk '
  BEGIN { RS = "\036"; FS = "\037" }
  {
    subject = $1; body = $2; n = 0; refs = ""; reftext = ""
    if (subject !~ /^(feat|fix|perf|refactor|style|test|build|ci|chore|docs)(\([^)]*\))?!?: /) next
    type = subject; sub(/\(.*/, "", type); sub(/:.*/, "", type)
    if (type == "chore" || type == "docs" || type == "test" || type == "style" || type == "build" || type == "ci" || type == "refactor") next
    scope = ""
    if (subject ~ /^[a-z]+\(/) { scope = subject; sub(/^[a-z]+\(/, "", scope); sub(/\).*/, "", scope) }
    desc = subject; sub(/^[a-z]+(\([^)]*\))?!?: /, "", desc)
    section = (type == "feat") ? "Added" : (type == "fix") ? "Fixed" : "Changed"
    tmp = subject " " body
    while (match(tmp, /#[0-9]+/)) {
      num = substr(tmp, RSTART + 1, RLENGTH - 1) + 0
      dup = 0
      for (k = 1; k <= n; k++) if (iss[k] == num) dup = 1
      if (!dup) { n++; iss[n] = num; refs = refs (refs ? "," : "") num; reftext = reftext (reftext ? ", " : "") "#" num }
      tmp = substr(tmp, RSTART + RLENGTH)
    }
    desc = toupper(substr(desc, 1, 1)) substr(desc, 2)
    if (desc !~ /\.$/) desc = desc "."
    suffix = (n > 0) ? ((n > 1 ? " (Issues " : " (Issue ") reftext ")") : ""
    if (scope != "") {
      cat = toupper(substr(scope, 1, 1)) substr(scope, 2)
      bullet = "- **" cat "**: " desc suffix
    } else {
      bullet = "- " desc suffix
    }
    print section "\t" bullet "\t" refs
  }
')

if [ -z "$entries" ]; then
  echo "Aucune entrée à ajouter."
  exit 0
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo "Aperçu des entrées générées (dry-run) :"
  echo "$entries" | awk -F'\t' '{ printf "  [%s] %s\n", $1, $2 }'
  exit 0
fi

# --- 2. Fusion idempotente dans CHANGELOG.md ---
tmp_entries=$(mktemp)
tmp_changelog=$(mktemp)
trap 'rm -f "$tmp_entries" "$tmp_changelog"' EXIT
echo "$entries" > "$tmp_entries"

awk -v entries="$tmp_entries" '
  BEGIN {
    nnew = 0
    while ((getline line < entries) > 0) {
      nnew++
      split(line, a, "\t")
      esec[nnew] = a[1]; ebul[nnew] = a[2]; eref[nnew] = a[3]
    }
    close(entries)
    ord[1] = "Added"; ord[2] = "Changed"; ord[3] = "Deprecated"
    ord[4] = "Removed"; ord[5] = "Fixed"; ord[6] = "Security"
  }
  { L[NR] = $0 }
  END {
    start = 0
    for (i = 1; i <= NR; i++) if (L[i] ~ /^## Unreleased[ \t]*$/) { start = i; break }
    if (!start) { print "update-changelog: pas de section \"## Unreleased\"" > "/dev/stderr"; exit 1 }
    end = NR + 1
    for (i = start + 1; i <= NR; i++) if (L[i] ~ /^---/ || L[i] ~ /^## /) { end = i; break }

    # Références d'"'"'issues déjà présentes dans le fichier (idempotence)
    for (i = 1; i <= NR; i++) {
      tmp = L[i]
      while (match(tmp, /\(Issues? #[0-9]+(, #[0-9]+)*\)/)) {
        rs = RSTART; rl = RLENGTH
        t2 = substr(tmp, rs, rl)
        while (match(t2, /#[0-9]+/)) { existing[substr(t2, RSTART + 1, RLENGTH - 1) + 0] = 1; t2 = substr(t2, RSTART + RLENGTH) }
        tmp = substr(tmp, rs + rl)
      }
    }

    # Filtrer les entrées déjà couvertes, regrouper par section
    for (e = 1; e <= nnew; e++) {
      skip = 0
      for (i = 1; i <= NR; i++) if (L[i] == ebul[e]) { skip = 1; break }
      if (!skip && eref[e] != "") {
        m = split(eref[e], rr, ","); all = 1
        for (k = 1; k <= m; k++) if (!((rr[k] + 0) in existing)) { all = 0; break }
        if (all) skip = 1
      }
      if (skip) continue
      sec = esec[e]
      pendn[sec]++
      pend[sec, pendn[sec]] = ebul[e]
    }

    for (i = start + 1; i < end; i++) if (L[i] ~ /^### /) secexists[substr(L[i], 5)] = 1

    # Reconstruire le bloc Unreleased
    nb = 0; prevsec = ""
    for (i = start + 1; i < end; i++) {
      if (L[i] ~ /^### /) {
        if (prevsec != "") for (c = 1; c <= pendn[prevsec]; c++) NB[++nb] = pend[prevsec, c]
        prevsec = substr(L[i], 5)
        NB[++nb] = L[i]
      } else NB[++nb] = L[i]
    }
    if (prevsec != "") for (c = 1; c <= pendn[prevsec]; c++) NB[++nb] = pend[prevsec, c]
    while (nb > 0 && NB[nb] ~ /^[ \t]*$/) nb--
    for (o = 1; o <= 6; o++) {
      sec = ord[o]
      if (pendn[sec] > 0 && !(sec in secexists)) {
        NB[++nb] = ""
        NB[++nb] = "### " sec
        for (c = 1; c <= pendn[sec]; c++) NB[++nb] = pend[sec, c]
      }
    }

    for (i = 1; i <= start; i++) print L[i]
    for (i = 1; i <= nb; i++) print NB[i]
    if (end <= NR) print ""
    for (i = end; i <= NR; i++) print L[i]

    added = 0
    for (s in pendn) added += pendn[s]
    printf "update-changelog: %d entrée(s) ajoutée(s) dans Unreleased\n", added > "/dev/stderr"
  }
' "$CHANGELOG" > "$tmp_changelog"

if cmp -s "$CHANGELOG" "$tmp_changelog"; then
  echo "CHANGELOG déjà à jour, rien à ajouter."
else
  mv "$tmp_changelog" "$CHANGELOG"
  echo "CHANGELOG mis à jour (voir git diff)."
fi
