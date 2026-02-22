#!/bin/bash

# Configuration
EMAIL="votre.email@gmail.com"
HOSTNAME=$(hostname)
ALERT=0
RAPPORT="/tmp/rapport_surveillance.txt"

# Initialisation du rapport
echo "=== Rapport de surveillance - $(date) ===" > $RAPPORT
echo "" >> $RAPPORT

# 1. Vérification des mises à jour disponibles
echo "📦 Vérification des mises à jour système..." >> $RAPPORT
sudo apt update > /dev/null 2>&1
UPDATES=$(sudo apt list --upgradable 2>/dev/null | grep -c upgradable)
if [ $UPDATES -gt 1 ]; then
    ALERT=1
    echo "⚠️  $((UPDATES-1)) mise(s) à jour disponible(s) !" >> $RAPPORT
    echo "" >> $RAPPORT
    sudo apt list --upgradable 2>/dev/null | grep upgradable | head -20 >> $RAPPORT
else
    echo "✅ Système à jour" >> $RAPPORT
fi
echo "" >> $RAPPORT

# 2. Vérification des images Docker
echo "🐳 Vérification des images Docker..." >> $RAPPORT
cd ~/Docker
DOCKER_UPDATES=""
CURRENT_DIR=""

# Parcourir tous les sous-dossiers contenant un docker-compose
for dir in */; do
    dir=${dir%/}  # Enlever le slash final
    
    if [ -f "$dir/docker-compose.yml" ] || [ -f "$dir/compose.yml" ]; then
        cd "$dir"
        
        # Charger les variables d'environnement du .env s'il existe
        if [ -f ".env" ]; then
            set -a
            source .env
            set +a
        fi
        
        # Récupérer les images avec les variables substituées
        CURRENT_IMAGES=$(docker compose config 2>/dev/null | grep 'image:' | awk '{print $2}')
        
        DIR_UPDATES=""
        
        for img in $CURRENT_IMAGES; do
            # Enlever les digests SHA si présents
            IMAGE_NAME=$(echo "$img" | sed 's/@sha256.*//')
            
            # Extraire le tag actuel
            CURRENT_TAG=$(echo "$IMAGE_NAME" | rev | cut -d':' -f1 | rev)
            
            # Cas 1 : Image avec tag "latest" - comparer les hashes
            if [[ "$CURRENT_TAG" == "latest" ]]; then
                LOCAL_HASH=$(docker images --no-trunc --quiet "$IMAGE_NAME" 2>/dev/null | head -1)
                docker pull "$IMAGE_NAME" > /dev/null 2>&1
                REMOTE_HASH=$(docker images --no-trunc --quiet "$IMAGE_NAME" 2>/dev/null | head -1)
                
                if [ ! -z "$LOCAL_HASH" ] && [ "$LOCAL_HASH" != "$REMOTE_HASH" ]; then
                    DIR_UPDATES="${DIR_UPDATES}    - $IMAGE_NAME\n"
                fi
            
            # Cas 2 : Image avec version fixe - comparer les versions disponibles
            else
                IMAGE_PATH=$(echo "$IMAGE_NAME" | cut -d':' -f1)
                REGISTRY=$(echo "$IMAGE_NAME" | cut -d'/' -f1)
                
                # Récupérer les tags disponibles selon le registre
                if [[ "$REGISTRY" == "ghcr.io" ]]; then
                    TAGS_JSON=$(curl -s "https://ghcr.io/v2/${IMAGE_PATH#*/}/tags/list" 2>/dev/null)
                    AVAILABLE_TAGS=$(echo "$TAGS_JSON" | grep -o '"tags":\[[^]]*\]' | grep -o '"[^"]*"' | sed 's/"//g')
                elif [[ "$REGISTRY" == "docker.io" ]] || [[ ! "$IMAGE_NAME" =~ "/" ]]; then
                    # Docker Hub
                    REPO_PATH=$(echo "$IMAGE_PATH" | sed 's/docker.io\///')
                    [ -z "$(echo $REPO_PATH | grep '/')" ] && REPO_PATH="library/$REPO_PATH"
                    AVAILABLE_TAGS=$(curl -s "https://registry.hub.docker.com/v2/repositories/${REPO_PATH}/tags/?page_size=100" 2>/dev/null | grep -o '"name":"[^"]*"' | cut -d'"' -f4)
                else
                    # Autres registres
                    AVAILABLE_TAGS=$(curl -s "https://${REGISTRY}/v2/${IMAGE_PATH#*/}/tags/list" 2>/dev/null | grep -o '"tags":\[[^]]*\]' | grep -o '"[^"]*"' | sed 's/"//g')
                fi
                
                # Filtrer les tags instables et les numéroter
                STABLE_TAGS=$(echo "$AVAILABLE_TAGS" | grep -viE '(alpha|beta|rc|dev|nightly|unstable|trixie|bookworm|bullseye|buster|stretch|jammy|focal|bionic|xenial|edge|canary|pre|test|snapshot)' | sort -V)
                
                # Vérifier si une version plus récente existe
                LATEST_TAG=$(echo "$STABLE_TAGS" | tail -1)
                if [ ! -z "$LATEST_TAG" ] && [ "$CURRENT_TAG" != "$LATEST_TAG" ]; then
                    DIR_UPDATES="${DIR_UPDATES}    - $IMAGE_NAME → ${LATEST_TAG}\n"
                fi
            fi
        done
        
        # Ajouter le bloc du dossier s'il y a des mises à jour
        if [ ! -z "$DIR_UPDATES" ]; then
            DOCKER_UPDATES="${DOCKER_UPDATES}📁 $dir\n${DIR_UPDATES}\n"
            ALERT=1
        fi
        
        cd ..
    fi
done

if [ ! -z "$DOCKER_UPDATES" ]; then
    echo "⚠️  Nouvelles versions d'images Docker disponibles :" >> $RAPPORT
    echo -e "$DOCKER_UPDATES" >> $RAPPORT
else
    echo "✅ Images Docker à jour" >> $RAPPORT
fi
echo "" >> $RAPPORT

# 3. Vérification de l'espace disque
echo "💾 Vérification de l'espace disque..." >> $RAPPORT
DISK_USAGE=$(df -h / | tail -1 | awk '{print $5}' | sed 's/%//')
if [ $DISK_USAGE -gt 80 ]; then
    ALERT=1
    echo "⚠️  Espace disque critique : ${DISK_USAGE}% utilisé !" >> $RAPPORT
    df -h / >> $RAPPORT
elif [ $DISK_USAGE -gt 70 ]; then
    echo "⚠️  Espace disque élevé : ${DISK_USAGE}% utilisé" >> $RAPPORT
else
    echo "✅ Espace disque OK : ${DISK_USAGE}% utilisé" >> $RAPPORT
fi
echo "" >> $RAPPORT

# 4. Vérification de l'état des conteneurs Docker
echo "🔍 Vérification des conteneurs Docker..." >> $RAPPORT
STOPPED=$(docker ps -a --filter "status=exited" --filter "status=dead" --format "{{.Names}}" | wc -l)
if [ $STOPPED -gt 0 ]; then
    ALERT=1
    echo "⚠️  $STOPPED conteneur(s) arrêté(s) détecté(s) :" >> $RAPPORT
    docker ps -a --filter "status=exited" --filter "status=dead" --format "    - {{.Names}} ({{.Status}})" >> $RAPPORT
else
    RUNNING=$(docker ps --format "{{.Names}}" | wc -l)
    echo "✅ Tous les conteneurs fonctionnent ($RUNNING actifs)" >> $RAPPORT
fi
echo "" >> $RAPPORT

# 5. Vérification de la charge système
echo "⚡ Vérification de la charge système..." >> $RAPPORT
LOAD=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | xargs)
LOAD_INT=$(echo "$LOAD * 100" | bc | cut -d'.' -f1)
CPU_CORES=$(nproc)
LOAD_PERCENT=$((LOAD_INT / CPU_CORES))

if [ $LOAD_PERCENT -gt 80 ]; then
    ALERT=1
    echo "⚠️  Charge système élevée : $LOAD (${LOAD_PERCENT}% de capacité)" >> $RAPPORT
else
    echo "✅ Charge système normale : $LOAD" >> $RAPPORT
fi
echo "" >> $RAPPORT

# 6. Vérification de la mémoire
echo "🧠 Vérification de la mémoire..." >> $RAPPORT
MEM_USED=$(free | grep Mem | awk '{print int($3/$2 * 100)}')
if [ $MEM_USED -gt 85 ]; then
    ALERT=1
    echo "⚠️  Utilisation mémoire élevée : ${MEM_USED}%" >> $RAPPORT
    free -h >> $RAPPORT
else
    echo "✅ Utilisation mémoire OK : ${MEM_USED}%" >> $RAPPORT
fi
echo "" >> $RAPPORT

# Envoi du rapport si alerte
if [ $ALERT -eq 1 ]; then
    echo "⚠️  Des alertes ont été détectées, envoi du rapport..." >> $RAPPORT
    cat $RAPPORT | mail -s "⚠️ [ALERTE] Surveillance $HOSTNAME - $(date +%d/%m/%Y)" $EMAIL
else
    echo "✅ Tout va bien, pas d'alerte à signaler" >> $RAPPORT
    # Envoi d'un rapport hebdomadaire même si tout va bien (tous les dimanches)
    if [ $(date +%u) -eq 7 ]; then
        cat $RAPPORT | mail -s "✅ [OK] Rapport hebdomadaire $HOSTNAME - $(date +%d/%m/%Y)" $EMAIL
    fi
fi

#Affichage du rapport en mode lancement manuel
cat $RAPPORT

# Nettoyage
rm $RAPPORT
