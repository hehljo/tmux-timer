#!/bin/bash
# timer - Schedules commands to tmux sessions using 'at'

# Farben für bessere Lesbarkeit auf schwarzem Hintergrund
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Logging — alles landet im Logfile des Ziel-Users
if [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ]; then
    LOG_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    LOG_HOME="$HOME"
fi
LOG_FILE="$LOG_HOME/.tmux-timer.log"
touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/tmp/tmux-timer.log"
if [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ] && [ -f "$LOG_FILE" ]; then
    chown "$SUDO_USER:$SUDO_USER" "$LOG_FILE" 2>/dev/null
fi

log() {
    # log <LEVEL> <message...>
    local lvl="$1"; shift
    printf '[%s] [SCHEDULE] [%s] [pid=%d] %s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$lvl" "$$" "$*" >> "$LOG_FILE"
}

log INFO "===== timer.sh started by uid=$EUID user=${SUDO_USER:-$USER} ====="

# Prüfen ob at installiert ist
if ! command -v at &> /dev/null; then
    echo -e "${RED}Error: 'at' ist nicht installiert.${NC}"
    echo "Installiere mit: sudo apt install at"
    exit 1
fi

# Prüfen ob atd service läuft
if ! systemctl is-active --quiet atd; then
    echo -e "${YELLOW}Warning: atd service läuft nicht.${NC}"
    echo "Starte mit: sudo systemctl start atd"
    exit 1
fi

echo -e "${CYAN}=== TMUX Timer Scheduler ===${NC}\n"

# Tmux Sessions auflisten
echo "Verfügbare tmux Sessions:"
echo ""

# Sessions sammeln
if [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ]; then
    SESSIONS=$(su - $SUDO_USER -c "tmux ls 2>/dev/null")
    TARGET_USER=$SUDO_USER
else
    SESSIONS=$(tmux ls 2>/dev/null)
    TARGET_USER=$USER
fi

if [ -z "$SESSIONS" ]; then
    echo -e "${RED}Keine aktiven tmux Sessions gefunden!${NC}"
    log ERROR "no tmux sessions found for target user $TARGET_USER"
    exit 1
fi
log INFO "found tmux sessions for $TARGET_USER:"
while IFS= read -r line; do log INFO "  session: $line"; done <<<"$SESSIONS"

# Sessions in Array speichern
IFS=$'\n' read -rd '' -a session_array <<<"$SESSIONS"

# Sessions nummeriert anzeigen
for i in "${!session_array[@]}"; do
    echo -e "${GREEN}[$((i+1))]${NC} ${session_array[$i]}"
done

echo ""
read -p "Wähle Session (Nummer): " session_choice

# Validierung
if ! [[ "$session_choice" =~ ^[0-9]+$ ]] || [ "$session_choice" -lt 1 ] || [ "$session_choice" -gt "${#session_array[@]}" ]; then
    echo -e "${RED}Ungültige Auswahl!${NC}"
    exit 1
fi

# Session Name extrahieren
SELECTED_SESSION=$(echo "${session_array[$((session_choice-1))]}" | cut -d: -f1)
log INFO "selected session: '$SELECTED_SESSION'"

echo ""
read -p "Befehl der ausgeführt werden soll: " COMMAND

if [ -z "$COMMAND" ]; then
    echo -e "${RED}Kein Befehl eingegeben!${NC}"
    log ERROR "empty command, aborting"
    exit 1
fi
log INFO "command to schedule: $COMMAND"

# Aktuelles Datum und Uhrzeit anzeigen
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${WHITE}Aktuelles Datum: $(date '+%d.%m.%Y')${NC}"
echo -e "${WHITE}Aktuelle Uhrzeit: $(date '+%H:%M:%S')${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Tag-Auswahl
echo ""
echo -e "${CYAN}=== Wann soll der Befehl ausgeführt werden? ===${NC}"
echo ""
echo -e "${GREEN}[1]${NC} Heute"
echo -e "${GREEN}[2]${NC} Morgen"
echo -e "${GREEN}[3]${NC} Bestimmtes Datum (DD.MM.YYYY)"
echo -e "${GREEN}[4]${NC} Wochentag (z.B. monday, tuesday)"
echo -e "${GREEN}[5]${NC} Relative Zeit (z.B. + 30 minutes)"
echo ""
read -p "Wähle Option (1-5): " day_choice

case $day_choice in
    1)
        DAY_STRING="today"
        DISPLAY_DAY="Heute"
        ;;
    2)
        DAY_STRING="tomorrow"
        DISPLAY_DAY="Morgen"
        ;;
    3)
        read -p "Datum (DD.MM.YYYY): " date_input
        if [[ $date_input =~ ^([0-9]{2})\.([0-9]{2})\.([0-9]{4})$ ]]; then
            DAY_STRING="${BASH_REMATCH[3]}-${BASH_REMATCH[2]}-${BASH_REMATCH[1]}"
            DISPLAY_DAY="$date_input"
        else
            echo -e "${RED}Ungültiges Datumsformat!${NC}"
            exit 1
        fi
        ;;
    4)
        read -p "Wochentag (z.B. monday): " weekday_input
        DAY_STRING="$weekday_input"
        DISPLAY_DAY="$weekday_input"
        ;;
    5)
        read -p "Relative Zeit (z.B. now + 30 minutes): " relative_input
        SCHEDULED_TIME="$relative_input"
        DISPLAY_DAY="Relativ"
        SKIP_TIME=true
        ;;
    *)
        echo -e "${RED}Ungültige Auswahl!${NC}"
        exit 1
        ;;
esac

# Uhrzeit abfragen
if [ "$SKIP_TIME" != true ]; then
    echo ""
    echo "Uhrzeit-Beispiele:"
    echo "  - 14:30"
    echo "  - 23:45"
    echo "  - 09:00"
    echo ""
    read -p "Uhrzeit (HH:MM): " time_input
    
    if [ -z "$time_input" ]; then
        echo -e "${RED}Keine Zeit eingegeben!${NC}"
        exit 1
    fi
    
    SCHEDULED_TIME="$time_input $DAY_STRING"
    DISPLAY_TIME="$time_input"
else
    DISPLAY_TIME="$SCHEDULED_TIME"
fi

# Bestätigung anzeigen
echo ""
echo -e "${YELLOW}=== Bestätigung ===${NC}"
echo -e "Session:  ${GREEN}$SELECTED_SESSION${NC}"
echo -e "Befehl:   ${GREEN}$COMMAND${NC}"
echo -e "Tag:      ${GREEN}$DISPLAY_DAY${NC}"
echo -e "Zeit:     ${GREEN}$DISPLAY_TIME${NC}"
echo -e "User:     ${GREEN}$TARGET_USER${NC}"
echo ""

# Zeige geplante Ausführungszeit
PLANNED_EXEC=$(echo "" | at $SCHEDULED_TIME 2>&1 | grep -oP '(?<=job \d+ at )[^\n]+')
if [ -n "$PLANNED_EXEC" ]; then
    echo -e "Geplant für: ${CYAN}$PLANNED_EXEC${NC}"
    LAST_JOB=$(atq | tail -n1 | awk '{print $1}')
    [ -n "$LAST_JOB" ] && atrm $LAST_JOB 2>/dev/null
    echo ""
fi

read -p "Fortfahren? (j/N): " CONFIRM

if [[ ! "$CONFIRM" =~ ^[jJ]$ ]]; then
    echo "Abgebrochen."
    log INFO "user aborted at confirmation"
    exit 0
fi
log INFO "user confirmed schedule, SCHEDULED_TIME='$SCHEDULED_TIME'"

# Temporäres Script erstellen - KRITISCH: Befehl und Enter als separate send-keys!
TEMP_SCRIPT=$(mktemp /tmp/tmux_timer.XXXXXX.sh)
chmod +x "$TEMP_SCRIPT"
log INFO "temp script: $TEMP_SCRIPT"

# Befehl/Session in Datei schreim damit Quotes/Sonderzeichen sicher durchkommen
TEMP_CMD="${TEMP_SCRIPT}.cmd"
TEMP_SESSION="${TEMP_SCRIPT}.session"
printf '%s' "$COMMAND" > "$TEMP_CMD"
printf '%s' "$SELECTED_SESSION" > "$TEMP_SESSION"

# Script erstellen — komplettes Logging beim Feuern
cat > "$TEMP_SCRIPT" <<EOFSCRIPT
#!/bin/bash
# Auto-generated by tmux-timer at $(date '+%Y-%m-%d %H:%M:%S')
LOG_FILE="$LOG_FILE"
TEMP_SCRIPT="$TEMP_SCRIPT"
TEMP_CMD="$TEMP_CMD"
TEMP_SESSION="$TEMP_SESSION"
SESSION=\$(cat "\$TEMP_SESSION")
COMMAND=\$(cat "\$TEMP_CMD")

flog() {
    local lvl="\$1"; shift
    printf '[%s] [FIRE]     [%s] [pid=%d] %s\n' \\
        "\$(date '+%Y-%m-%d %H:%M:%S')" "\$lvl" "\$\$" "\$*" >> "\$LOG_FILE"
}

flog INFO "===== fire start (script=\$TEMP_SCRIPT) ====="
flog INFO "running as: uid=\$EUID user=\$(id -un) tty=\$(tty 2>/dev/null || echo none)"
flog INFO "target session: '\$SESSION'"
flog INFO "command: \$COMMAND"
flog INFO "tmux binary: \$(command -v tmux || echo MISSING)"
flog INFO "available sessions at fire time:"
tmux ls 2>&1 | while IFS= read -r l; do flog INFO "  \$l"; done

# has-session check vor send
if ! tmux has-session -t "\$SESSION" 2>>"\$LOG_FILE"; then
    flog ERROR "session '\$SESSION' does not exist — aborting send (temp script kept for inspection)"
    exit 2
fi

# Befehl senden
SEND1_OUT=\$(tmux send-keys -t "\$SESSION" "\$COMMAND" 2>&1)
SEND1_RC=\$?
flog INFO "send-keys (command) rc=\$SEND1_RC out='\$SEND1_OUT'"
if [ \$SEND1_RC -ne 0 ]; then
    flog ERROR "send-keys failed (command), keeping temp script"
    exit 3
fi

sleep 0.1

SEND2_OUT=\$(tmux send-keys -t "\$SESSION" C-m 2>&1)
SEND2_RC=\$?
flog INFO "send-keys (Enter)   rc=\$SEND2_RC out='\$SEND2_OUT'"
if [ \$SEND2_RC -ne 0 ]; then
    flog ERROR "send-keys failed (Enter), keeping temp script"
    exit 4
fi

flog INFO "===== fire success ====="
rm -f "\$TEMP_SCRIPT" "\$TEMP_CMD" "\$TEMP_SESSION"
EOFSCRIPT

# at Job mit temporärem Script erstellen
if [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ]; then
    chown $SUDO_USER:$SUDO_USER "$TEMP_SCRIPT" "$TEMP_CMD" "$TEMP_SESSION"
    AT_OUT=$(su - $SUDO_USER -c "echo '$TEMP_SCRIPT' | at $SCHEDULED_TIME" 2>&1)
else
    AT_OUT=$(echo "$TEMP_SCRIPT" | at $SCHEDULED_TIME 2>&1)
fi
AT_RC=$?
log INFO "at command rc=$AT_RC output: $AT_OUT"
echo "$AT_OUT" | grep -E "job|warning"

if [ $AT_RC -eq 0 ]; then
    JOB_NUM=$(echo "$AT_OUT" | grep -oP 'job \K[0-9]+')
    log INFO "scheduled at job #$JOB_NUM successfully"
    echo -e "\n${GREEN}✓ Timer erfolgreich erstellt!${NC}"
    echo -e "${CYAN}Temp-Script: $TEMP_SCRIPT${NC}"
    echo -e "${CYAN}Logfile:     $LOG_FILE${NC}"
    echo ""
    echo "Geplante Jobs anzeigen: atq"
    echo "Job löschen: atrm <job-nummer>"
    echo "Script-Inhalt prüfen: cat $TEMP_SCRIPT"
    echo "Log live mitlesen:    tail -f $LOG_FILE"
else
    log ERROR "at command failed (rc=$AT_RC), removing temp files"
    echo -e "\n${RED}✗ Fehler beim Erstellen des Timers!${NC}"
    rm -f "$TEMP_SCRIPT" "$TEMP_CMD" "$TEMP_SESSION"
    exit 1
fi
