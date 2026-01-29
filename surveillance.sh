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
cd ~
DOCKER_UPDATES=""
for dir in erugo cloudflared nextcloud immich wordpress; do
    if [ -d "$dir" ]; then
        cd "$dir"
        CURRENT_IMAGES=$(docker-compose config | grep 'image:' | awk '{print $2}')
        for img in $CURRENT_IMAGES; do
            docker pull $img > /dev/null 2>&1
            LOCAL_HASH=$(docker images --no-trunc --quiet $img | head -1)
            REMOTE_HASH=$(docker inspect --format='{{.Id}}' $img)
            if [ "$LOCAL_HASH" != "$REMOTE_HASH" ]; then
                DOCKER_UPDATES="${DOCKER_UPDATES}    - $img (service: $dir)\n"
                ALERT=1
            fi
        done
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

# Nettoyage
rm $RAPPORT
