#!/bin/bash

# pre-push-check.sh
# Vérification avant push pour ios-memories-nextcloud
# Ce script vérifie que les commits à pousser respectent les règles du projet

set -e

# Couleurs pour les messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Compter le nombre de commits à pousser
COMMIT_COUNT=$(git rev-list @{u}..HEAD --count 2>/dev/null || echo "0")

if [ "$COMMIT_COUNT" -eq "0" ]; then
    echo -e "${GREEN}✓ Aucun commit à pousser${NC}"
    exit 0
fi

echo -e "${YELLOW}Analyse des $COMMIT_COUNT commit(s) à pousser...${NC}"

# Récupérer les messages des commits à pousser
COMMIT_MESSAGES=$(git log @{u}..HEAD --format="%s" --no-merges)

# Vérifier les règles
ERRORS=0

# Règle 1 : Pas de commits avec "test:" ou "feat:" séparés
if echo "$COMMIT_MESSAGES" | grep -qE "^test:"; then
    echo -e "${RED}✗ ERREUR: Commit de test séparé détecté${NC}"
    echo "   → Les commits de test doivent être squashés avec la feature"
    ERRORS=$((ERRORS + 1))
fi

if echo "$COMMIT_MESSAGES" | grep -qE "^feat:"; then
    FEAT_COUNT=$(echo "$COMMIT_MESSAGES" | grep -cE "^feat:")
    TEST_COUNT=$(echo "$COMMIT_MESSAGES" | grep -cE "^test:")
    if [ "$TEST_COUNT" -gt "0" ] && [ "$FEAT_COUNT" -gt "0" ]; then
        echo -e "${RED}✗ ERREUR: Commits feat et test séparés détectés${NC}"
        echo "   → Squashez-les avec : git squash-last"
        ERRORS=$((ERRORS + 1))
    fi
fi

# Règle 2 : Vérifier que chaque commit a une référence à une issue
if ! echo "$COMMIT_MESSAGES" | grep -qE "#[0-9]+"; then
    echo -e "${YELLOW}⚠ AVERTISSEMENT: Aucun numéro d'issue détecté dans les commits${NC}"
    echo "   → Pensez à ajouter 'Fixes #X' ou 'Resolves #X'"
fi

# Afficher les commits à pousser
echo -e "\n${YELLOW}Commits à pousser:${NC}"
git log @{u}..HEAD --oneline --no-merges

# Résumé
if [ "$ERRORS" -gt "0" ]; then
    echo -e "\n${RED}❌ Push bloqué: $ERRORS règle(s) non respectée(s)${NC}"
    echo -e "${YELLOW}Corrigez avec :${NC}"
    echo "  git squash-last -m \"votre message ici\""
    echo "  git push"
    exit 1
else
    echo -e "\n${GREEN}✅ Tous les commits respectent les règles${NC}"
    exit 0
fi
