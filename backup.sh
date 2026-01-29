#!/bin/bash

# Configuration
BACKUP_DEST="/mnt/backup"  # ou ~/backups si pas de disque externe
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$BACKUP_DEST/cloud_backup_$DATE"
EMAIL="votre.email@gmail.com"
HOSTNAME=$(hostname)
LOG_FILE="/tmp/backup_log.txt"

# Initialisation du log
echo "=== Sauvegarde du cloud - $(date) ===" > $LOG_FILE
echo "" >> $LOG_FILE

# Vérification de l'espace disque disponible
AVAILABLE_SPACE=$(df -BG "$BACKUP_DEST" | tail -1 | awk '{print $4}' | sed 's/G//')
echo "💾 Espace disponible : ${AVAILABLE_SPACE}G" >> $LOG_FILE

if [ $AVAILABLE_SPACE -lt 10 ]; then
    echo "❌ ERREUR : Espace disque insuffisant (moins de 10G disponibles)" >> $LOG_FILE
    cat $LOG_FILE | mail -s "❌ [ERREUR] Sauvegarde échouée - Espace disque" $EMAIL
    exit 1
fi

# Création du répertoire de sauvegarde
mkdir -p "$BACKUP_DIR"
echo "📁 Dossier de sauvegarde créé : $BACKUP_DIR" >> $LOG_FILE
echo "" >> $LOG_FILE

# Fonction de sauvegarde d'un service
backup_service() {
    SERVICE_NAME=$1
    SERVICE_PATH=~/$SERVICE_NAME
    
    if [ -d "$SERVICE_PATH" ]; then
        echo "📦 Sauvegarde de $SERVICE_NAME..." >> $LOG_FILE
        
        # Sauvegarde du docker-compose.yaml
        if [ -f "$SERVICE_PATH/docker-compose.yaml" ]; then
            cp "$SERVICE_PATH/docker-compose.yaml" "$BACKUP_DIR/${SERVICE_NAME}_docker-compose.yaml"
            echo "  ✅ docker-compose.yaml sauvegardé" >> $LOG_FILE
        fi
        
        # Arrêt temporaire du service pour cohérence des données
        cd "$SERVICE_PATH"
        docker-compose down >> $LOG_FILE 2>&1
        
        # Sauvegarde des volumes
        if [ -d "$SERVICE_PATH/volumes" ]; then
            tar -czf "$BACKUP_DIR/${SERVICE_NAME}_volumes.tar.gz" -C "$SERVICE_PATH" volumes/ 2>> $LOG_FILE
            SIZE=$(du -sh "$BACKUP_DIR/${SERVICE_NAME}_volumes.tar.gz" | awk '{print $1}')
            echo "  ✅ Volumes sauvegardés ($SIZE)" >> $LOG_FILE
        fi
        
        # Redémarrage du service
        docker-compose up -d >> $LOG_FILE 2>&1
        echo "  ✅ Service redémarré" >> $LOG_FILE
        cd ~
    else
        echo "  ⚠️  Service $SERVICE_NAME non trouvé" >> $LOG_FILE
    fi
    echo "" >> $LOG_FILE
}

# Sauvegarde de tous les services
backup_service "erugo"
backup_service "cloudflared"
backup_service "nextcloud"
backup_service "immich"
backup_service "wordpress"

# Calcul de la taille totale de la sauvegarde
BACKUP_SIZE=$(du -sh "$BACKUP_DIR" | awk '{print $1}')
echo "📊 Taille totale de la sauvegarde : $BACKUP_SIZE" >> $LOG_FILE
echo "" >> $LOG_FILE

# Nettoyage des anciennes sauvegardes (garde les 7 dernières)
echo "🧹 Nettoyage des anciennes sauvegardes..." >> $LOG_FILE
cd "$BACKUP_DEST"
ls -t | grep "cloud_backup_" | tail -n +8 | xargs -r rm -rf
KEPT=$(ls -d cloud_backup_* 2>/dev/null | wc -l)
echo "  ✅ $KEPT sauvegarde(s) conservée(s)" >> $LOG_FILE
echo "" >> $LOG_FILE

# Vérification de l'intégrité
echo "🔍 Vérification de l'intégrité..." >> $LOG_FILE
if [ -f "$BACKUP_DIR/nextcloud_volumes.tar.gz" ]; then
    tar -tzf "$BACKUP_DIR/nextcloud_volumes.tar.gz" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "  ✅ Archive Nextcloud valide" >> $LOG_FILE
    else
        echo "  ❌ Archive Nextcloud corrompue !" >> $LOG_FILE
    fi
fi
echo "" >> $LOG_FILE

echo "✅ Sauvegarde terminée avec succès !" >> $LOG_FILE

# Envoi du rapport
cat $LOG_FILE | mail -s "✅ [OK] Sauvegarde réussie - $HOSTNAME - $BACKUP_SIZE" $EMAIL

# Nettoyage
rm $LOG_FILE
