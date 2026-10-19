# Git Scripts

Ce dossier contient des scripts utilitaires pour le workflow Git du projet ios-memories-nextcloud.

---

## 📁 Scripts Disponibles

### pre-push-check.sh
**Hook de pré-push automatique** qui vérifie que les commits respectent les règles du projet.

#### Fonctionnalités :
- ✅ Bloque les commits de test séparés (`test: ...`)
- ✅ Bloque les commits feat + test non squashés
- ✅ Vérifie la présence de références à des issues (#X)
- ✅ Affiche les commits à pousser

#### Installation :
Déjà configuré via un lien symbolique dans `.git/hooks/pre-push`

Pour le réinstaller manuellement :
```bash
mkdir -p .git/hooks
ln -sf ../../scripts/pre-push-check.sh .git/hooks/pre-push
chmod +x .git/hooks/pre-push
```

#### Désactiver temporairement :
```bash
git push --no-verify
```
*(À utiliser avec modération !)*

---

### update-changelog.sh
**Génère les entrées "Unreleased" du CHANGELOG depuis les commits conventionnels.**

#### Fonctionnalités :
- ✅ Mappe `feat:` / `fix:` / `perf:` vers les sections Added / Fixed / Changed
- ✅ Le scope du commit devient la catégorie en gras (`fix(zoom): …` → `- **Zoom**: …`)
- ✅ Extrait les références d'issues (`#12`, `Fixes #12`) → `(Issue #12)`
- ✅ Ignore les commits non user-facing (`chore`, `docs`, `test`, `style`, `build`, `ci`, `refactor`)
- ✅ Idempotent : une entrée déjà présente (même puce ou mêmes issues) n'est pas dupliquée

#### Utilisation :
```bash
./scripts/update-changelog.sh                          # depuis le dernier tag
./scripts/update-changelog.sh --dry-run                # aperçu sans modifier le fichier
./scripts/update-changelog.sh v1.0.0-rc.10..HEAD       # plage explicite
```

À lancer après un commit `fix:`/`feat:`, ou en préparation d'une release.

---

## 🎯 Alias Git Configurés

### squash-last
Squashe les 2 derniers commits (feature + test) en un seul :
```bash
git squash-last
```

Avec un message personnalisé :
```bash
git squash-last -m "fix: votre message ici. Fixes #X"
```

### push-safe
Effectue les vérifications avant de pousser :
```bash
git push-safe
```

---

## 📋 Workflow Recommandé

### Pour une correction ou fonctionnalité :

```bash
# 1. Créer une branche
git checkout -b fix/issue-7

# 2. Implémenter la solution
git add .
git commit -m "fix: initial implementation"

# 3. Ajouter les tests
git add Tests/
git commit -m "test: add unit tests"

# 4. Squasher les commits
git squash-last -m "fix: use real server URL for public share links. Fixes #7"

# 5. Pousser (le hook vérifie automatiquement)
git push
# OU
 git push-safe
```

### Si le hook bloque le push :

```bash
# Corriger les commits
git squash-last -m "votre message complet"

# Puis pousser
git push
```

---

## 🔧 Configuration

Les alias sont stockés dans `.git/config`. Pour les ajouter globalement :

```bash
# Alias squash-last
git config --global alias.squash-last '!f() { git reset --soft HEAD~2 && git commit --amend; }; f'

# Alias push-safe
git config --global alias.push-safe '!f() { if ./scripts/pre-push-check.sh; then git push "$@"; else echo "Push annulé: corrigez les commits"; fi; }; f'
```

---

## 💡 Dépannage

### Le hook ne fonctionne pas ?
1. Vérifiez qu'il est exécutable :
   ```bash
   chmod +x .git/hooks/pre-push
   ```

2. Testez-le manuellement :
   ```bash
   ./scripts/pre-push-check.sh
   ```

3. Vérifiez les permissions :
   ```bash
   ls -la .git/hooks/pre-push
   ```

### Le script échoue ?
Exécutez-le en mode debug :
```bash
bash -x ./scripts/pre-push-check.sh
```

---

## 📚 Documentation Complète

Voir aussi :
- `.git-squash-rules.md` - Règles détaillées des commits
- `CHANGELOG.md` - Historique des versions

---

**Rappel** : Respectez toujours les règles de commit pour maintenir un historique propre ! 🎯
