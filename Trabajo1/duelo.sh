#!/bin/bash
set -eo pipefail

dir_script="$(cd "$(dirname "$0")" && pwd)"
CFG="$dir_script/config.cfg"

declare -a deck_idx  

_valida_entero_rango(){  
  local nombre="$1" val="$2" min="$3" max="$4"
  val=${val%$'\r'}
  case "$val" in
    ''|*[!0-9]*) echo "$nombre debe ser entero"; return 1;;
  esac
  if [ "$val" -lt "$min" ] || [ "$val" -gt "$max" ]; then
    echo "$nombre fuera de rango [$min..$max]"
    return 1
  fi
}

_valida_enum(){ local nombre="$1" val="$2" x
  for x in $3; do [[ "$val" == "$x" ]] && return 0; done
  echo "$nombre debe ser uno de: $3"; return 1
}
_valida_log_ruta(){  
  local ruta="$1" abs parent
  [[ -n "$ruta" ]] || { echo "LOG vacio" >&2; return 1; }
  [[ "$ruta" == */ ]] && { echo "LOG no puede terminar en /" >&2; return 1; }
  [[ "$ruta" =~ [[:space:]] ]] && { echo "LOG no puede contener espacios" >&2; return 1; }

  if [[ "$ruta" = /* ]]; then abs="$ruta"; else abs="$dir_script/$ruta"; fi
  parent="${abs%/*}"

  [[ -d "$parent" ]] || { echo "Directorio de LOG inexistente: $parent" >&2; return 1; }
  [[ -w "$parent" ]] || { echo "Sin permisos de escritura en: $parent" >&2; return 1; }

  if [[ -e "$abs" && ! -w "$abs" ]]; then
    echo "Aviso: fichero LOG no escribible: $abs (se podra crear/rotar en el directorio)" >&2
  fi
  return 0
}

cargar_y_validar_cfg(){
  if [ ! -f "$CFG" ]; then
    echo "Falta $CFG" >&2; exit 1
  fi
  local GREP_E="/usr/xpg4/bin/grep"; [ -x "$GREP_E" ] || GREP_E="grep"
  if ! "$GREP_E" -q '[^[:space:]]' "$CFG"; then
    echo "$CFG esta vacio" >&2; exit 1
  fi

  local devuelto="JUGADORES PV ESTRATEGIA MAXIMO LOG"
  local idx=1 line k v nlines=0
  JUGADORES= PV= ESTRATEGIA= MAXIMO= LOG=
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    case "$line" in *=*) ;; * ) echo "Linea invalida (sin '='): '$line'" >&2; exit 1;; esac
    k=${line%%=*}; v=${line#*=}
    set -- $devuelto; eval "exp_k=\${$idx}"
    if [ "$k" != "$exp_k" ]; then
      echo "Orden/clave invalido en linea $idx: se esperaba '$exp_k', se leyo '$k'" >&2; exit 1
    fi
    case "$v" in *[[:space:]]*) echo "Espacios no permitidos en el valor de $k" >&2; exit 1;;
                    "" ) echo "Valor vacio en $k" >&2; exit 1;; esac
    case "$k" in
      JUGADORES)  JUGADORES="$v" ;;
      PV)         PV="$v" ;;
      ESTRATEGIA) ESTRATEGIA="$v" ;;
      MAXIMO)     MAXIMO="$v" ;;
      LOG)        LOG="$v" ;;
    esac
    nlines=$((nlines+1)); idx=$((idx+1))
  done < "$CFG"

  [ "$nlines" -eq 5 ] || { echo "$CFG debe tener exactamente 5 lineas (tiene $nlines)" >&2; exit 1; }

  _valida_entero_rango "JUGADORES" "$JUGADORES" 2 4 || exit 1
  _valida_entero_rango "PV"        "$PV"        10 30 || exit 1
  _valida_enum          "ESTRATEGIA" "$ESTRATEGIA" "0 1 2" || exit 1
  _valida_entero_rango  "MAXIMO"   "$MAXIMO"    0 50 || exit 1
  _valida_log_ruta      "$LOG" || exit 1
}

guardar_cfg(){
  local tmp
  tmp="$(mktemp /tmp/cfg.XXXXXX)" || { echo "No se pudo crear temporal" >&2; return 1; }
  {
    printf 'JUGADORES=%s\n'  "$JUGADORES"
    printf 'PV=%s\n'         "$PV"
    printf 'ESTRATEGIA=%s\n' "$ESTRATEGIA"
    printf 'MAXIMO=%s\n'     "$MAXIMO"
    printf 'LOG=%s\n'        "$LOG"
  } > "$tmp" || { rm -f "$tmp"; echo "No se pudo escribir temporal" >&2; return 1; }
  mv "$tmp" "$CFG" || { rm -f "$tmp"; echo "No se pudo reemplazar $CFG" >&2; return 1; }
}

configuracion(){
  cargar_y_validar_cfg || return 1
  echo "Configuracion actual:"
  echo "  JUGADORES=$JUGADORES"
  echo "  PV=$PV"
  echo "  ESTRATEGIA=$ESTRATEGIA"
  echo "  MAXIMO=$MAXIMO"
  echo "  LOG=$LOG"
  echo
  while :; do
    printf "Jugadores [2-4] (%s): " "$JUGADORES"; IFS= read -r nv
    [ -n "$nv" ] && cand="$nv" || cand="$JUGADORES"
    _valida_entero_rango "JUGADORES" "$cand" 2 4 && { JUGADORES="$cand"; break; }
  done
  while :; do
    printf "Puntos de vida PV [10-30] (%s): " "$PV"; IFS= read -r nv
    [ -n "$nv" ] && cand="$nv" || cand="$PV"
    _valida_entero_rango "PV" "$cand" 10 30 && { PV="$cand"; break; }
  done
  while :; do
    printf "Estrategia IA [0|1|2] (%s): " "$ESTRATEGIA"; IFS= read -r nv
    [ -n "$nv" ] && cand="$nv" || cand="$ESTRATEGIA"
    _valida_enum "ESTRATEGIA" "$cand" "0 1 2" && { ESTRATEGIA="$cand"; break; }
  done
  while :; do
    printf "Puntos maximo para victoria [0-50] (0 desactiva) (%s): " "$MAXIMO"; IFS= read -r nv
    [ -n "$nv" ] && cand="$nv" || cand="$MAXIMO"
    _valida_entero_rango "MAXIMO" "$cand" 0 50 && { MAXIMO="$cand"; break; }
  done
  guardar_cfg || { echo "No se pudo guardar $CFG" >&2; return 1; }
  echo "Configuracion actualizada en $CFG."
}

nombre_cartas(){
  case "$1" in
    ATK2)    echo "Espada corta (-2 PV)";;
    ATK4)    echo "Espada larga (-4 PV)";;
    ATK6)    echo "Hacha (-6 PV)";;
    DEF4)    echo "Escudo basico (bloquea 4)";;
    DEF6)    echo "Escudo reforzado (bloquea 6)";;
    HEAL3)   echo "Curacion (+3 PV)";;
    DRAW1)   echo "Robo de carta";;
    COUNTER) echo "Contraataque";;
    *)       echo "Carta desconocida? [$1]";;
  esac
}

_hacer_array_mazo(){
  local __name="$1"
  eval "$__name=( 'ATK2' 'ATK4' 'ATK4' 'ATK6' 'DEF4' 'DEF4' 'DEF6' 'HEAL3' 'DRAW1' 'COUNTER' )"
}

_barajar_array(){
  local __name="$1" n i j tmp
  eval "n=\${#${__name}[@]}"
  i=$((n-1))
  while [ $i -gt 0 ]; do
    j=$((RANDOM % (i+1)))
    eval "tmp=\${${__name}[$i]}"
    eval "${__name}[$i]=\${${__name}[$j]}"
    eval "${__name}[$j]=\$tmp"
    i=$((i-1))
  done
}

init_decks(){
  local p
  for p in 0 1 2 3; do
    if [ "$p" -lt "$JUGADORES" ]; then
      _hacer_array_mazo "deck$p"
      _barajar_array   "deck$p"
      deck_idx[$p]=0
    else
      eval "deck$p=()"
      deck_idx[$p]=0
    fi
  done
}

imprimir_mazo(){
  local p="$1" i=0 len code
  eval "len=\${#deck$p[@]}"
  echo "Mazo jugador $((p+1)) ($len cartas):"
  while [ "$i" -lt "$len" ]; do
    eval "code=\${deck$p[$i]}"
    printf "  [%02d] %s\n" "$i" "$(nombre_cartas "$code")"
    i=$((i+1))
  done
}

imprimir_mazo_restante(){  
  local p="$1" i code idx len
  idx=${deck_idx[$p]:-0}
  eval "len=\${#deck$p[@]}"
  echo "Mazo jugador $((p+1)) restante ($(($len-idx)) cartas):"
  for ((i=idx; i<len; i++)); do
    eval "code=\${deck$p[$i]}"
    printf "  [%02d] %s\n" "$((i-idx))" "$(nombre_cartas "$code")"
  done
}

iniciar_jugadores(){  
  local i
  for i in 0 1 2 3; do
    if [ "$i" -lt "$JUGADORES" ]; then
      pv[$i]="$PV"; escudo[$i]=0; contra[$i]=0; jugadas[$i]=0
    else
      pv[$i]=0; escudo[$i]=0; contra[$i]=0; jugadas[$i]=0
    fi
  done
}

anadir_carta_mano(){ local p=$1 c=$2; eval "hand$p+=(\"$c\")"; }
eliminar_carta_usada(){ local p=$1 idx=$2; eval "unset hand$p[$idx]"; eval "hand$p=(\"\${hand$p[@]}\")"; }
alive(){ local p=$1; [ "${pv[$p]:-0}" -gt 0 ]; }

reparto_mano_inicial(){  
  local p
  for p in 0 1 2 3; do
    if [ "$p" -lt "$JUGADORES" ]; then
      eval "hand$p=(\"\${deck$p[@]:0:5}\")"
      eval "deck$p=(\"\${deck$p[@]:5}\")"
      deck_idx[$p]=0
    else
      eval "hand$p=()"
      eval "deck$p=()"
      deck_idx[$p]=0
    fi
  done
  return 0
}

roba_carta(){  
  local p="$1" outvar="$2" idx len c
  idx=${deck_idx[$p]:-0}
  eval "len=\${#deck$p[@]}"
  if [ "$idx" -ge "$len" ]; then
    c=""
  else
    eval "c=\${deck$p[$idx]}"
    deck_idx[$p]=$((idx+1))
  fi
  printf -v "$outvar" '%s' "$c"
}

imprimir_mano(){  
  local p="$1" i=0 len code
  eval "len=\${#hand$p[@]}"
  echo "Mano jugador $((p+1)) ($len cartas):"
  while [ "$i" -lt "$len" ]; do
    eval "code=\${hand$p[$i]}"
    printf "  (%d) %s\n" "$((i+1))" "$(nombre_cartas "$code")"
    i=$((i+1))
  done
}

ia_escoger_carta(){ 
  local p=$1 strat="$ESTRATEGIA" code
  eval "local arr=(\"\${hand$p[@]}\")"
  local choice=""
  if [ "$strat" -eq 1 ]; then
    for code in "${arr[@]}"; do [[ "$code" == ATK* ]] && { choice="$code"; break; }; done
  elif [ "$strat" -eq 2 ]; then
    for code in "${arr[@]}"; do [[ "$code" == DEF* || "$code" == HEAL3 ]] && { choice="$code"; break; }; done
  fi
  [ -z "$choice" ] && choice="${arr[$((RANDOM % ${#arr[@]}))]}"
  echo "$choice"
}

ia_escoger_jugador(){ 
  local p=$1 i best=-1 bestpv=999999
  for ((i=0;i<JUGADORES;i++)); do
    [ "$i" -ne "$p" ] || continue
    alive "$i" || continue
    if [ "${pv[$i]}" -lt "$bestpv" ]; then bestpv="${pv[$i]}"; best="$i"; fi
  done
  echo "$best"
}

jugador_elegir_carta(){
  local p=$1 len i c sel
  eval "len=\${#hand$p[@]}"
  while :; do
    >&2 echo "Elige carta [1-$len]:"
    for ((i=0;i<len;i++)); do eval "c=\${hand$p[$i]}"; >&2 echo "  $((i+1))) $(nombre_cartas "$c")"; done
    IFS= read -r sel < /dev/tty
    case "$sel" in ''|*[!0-9]*) continue;; esac
    sel=$((sel-1))
    [ "$sel" -ge 0 ] && [ "$sel" -lt "$len" ] && { echo "$sel"; return; }
  done
}

jugador_elegir_jugador(){
  local p=$1 in t
  while :; do
    >&2 echo -n "Elige objetivo (1..$JUGADORES, distinto de ti): "
    IFS= read -r in < /dev/tty
    case "$in" in ''|*[!0-9]*) continue;; esac
    t=$((in-1))
    if [ "$t" -ge 0 ] && [ "$t" -lt "$JUGADORES" ] && [ "$t" -ne "$p" ] && [ "${pv[$t]:-0}" -gt 0 ]; then
      echo "$t"; return
    fi
  done
}

aplicar_ataque(){ # src dst dmg
  local src=$1 dst=$2 dmg=$3
  local eff block c
  eff=$dmg
  block="${escudo[$dst]}"
  c="${contra[$dst]}"
  (( block += 0 ))
  (( c += 0 ))

  if (( block > 0 )); then
    if (( block >= eff )); then
      escudo[$dst]=$(( block - eff ))
      eff=0
    else
      eff=$(( eff - block ))
    fi
    escudo[$dst]=0
  fi

  if (( eff > 0 )); then
    if (( c > 0 )); then
      local ret=$(( eff / 2 ))
      pv[$src]=$(( pv[$src] - ret ))
      contra[$dst]=0
    fi
   pv[$dst]=$(( pv[$dst] - eff ))

  if (( pv[$dst] <= 0 )); then
    escudo[$dst]=0
    contra[$dst]=0
    eval "hand$dst=()"
  fi
  fi
}

jugar_carta(){ # p code
  local p=$1 code=$2 tgt
  case "$code" in
    ATK2)
      tgt=$( [ "$p" -eq 0 ] && jugador_elegir_jugador "$p" || ia_escoger_jugador "$p" )
      [[ "$tgt" =~ ^[0-9]+$ ]] || { echo "No hay objetivos validos."; return; }
      aplicar_ataque "$p" "$tgt" 2
      echo "P$((p+1)) ataca a P$((tgt+1)) (-2)"
      ;;
    ATK4)
      tgt=$( [ "$p" -eq 0 ] && jugador_elegir_jugador "$p" || ia_escoger_jugador "$p" )
      [[ "$tgt" =~ ^[0-9]+$ ]] || { echo "No hay objetivos validos."; return; }
      aplicar_ataque "$p" "$tgt" 4
      echo "P$((p+1)) ataca a P$((tgt+1)) (-4)"
      ;;
    ATK6)
      tgt=$( [ "$p" -eq 0 ] && jugador_elegir_jugador "$p" || ia_escoger_jugador "$p" )
      [[ "$tgt" =~ ^[0-9]+$ ]] || { echo "No hay objetivos validos."; return; }
      aplicar_ataque "$p" "$tgt" 6
      echo "P$((p+1)) ataca a P$((tgt+1)) (-6)"
      ;;
    DEF4) escudo[$p]=$(( ${escudo[$p]:-0} + 4 )); echo "P$((p+1)) gana escudo +4";;
    DEF6) escudo[$p]=$(( ${escudo[$p]:-0} + 6 )); echo "P$((p+1)) gana escudo +6";;
    HEAL3) pv[$p]=$(( ${pv[$p]:-0} + 3 )); echo "P$((p+1)) se cura +3";;
    DRAW1)
      local nc; roba_carta "$p" nc
      if [ -n "$nc" ]; then
        anadir_carta_mano "$p" "$nc"
        echo "P$((p+1)) roba 1 carta ($(nombre_cartas "$nc"))"
      else
        echo "P$((p+1)) intenta robar, pero no quedan cartas"
      fi
      ;;
    COUNTER) contra[$p]=1; echo "P$((p+1)) prepara contraataque";;
  esac
}

cartas_restantes(){
  local s=0 p len
  for ((p=0; p<JUGADORES; p++)); do
    [ "${pv[$p]:-0}" -gt 0 ] || continue  
    eval "len=\${#deck$p[@]}"
    s=$(( s + (len - ${deck_idx[$p]:-0}) ))
  done
  echo "$s"
}
cartas_mano(){
  local s=0 p
  for ((p=0; p<JUGADORES; p++)); do
    [ "${pv[$p]:-0}" -gt 0 ] || continue  
    eval "s=\$(( s + \${#hand$p[@]} ))"
  done
  echo "$s"
}
revisar_fin(){
  local alivec=0 last=-1 p
  for ((p=0;p<JUGADORES;p++)); do
    [ "${pv[$p]}" -gt 0 ] && { alivec=$((alivec+1)); last=$p; }
  done
  [ "$alivec" -eq 1 ] && { echo "WIN:$last"; return; }

  if [ "$MAXIMO" -gt 0 ]; then
    for ((p=0;p<JUGADORES;p++)); do
      [ "${pv[$p]}" -ge "$MAXIMO" ] && { echo "WIN:$p"; return; }
    done
  fi

  if [ "$(cartas_restantes)" -eq 0 ] && [ "$(cartas_mano)" -eq 0 ]; then
    echo "DECKS_OUT"; return
  fi

  echo "CONT"
}


desempatar(){ 
  local best=-1 bestpv=-999 bestjg=-999 p
  for ((p=0;p<JUGADORES;p++)); do
    if [ "${pv[$p]}" -gt "$bestpv" ] || { [ "${pv[$p]}" -eq "$bestpv" ] && [ "${jugadas[$p]:-0}" -gt "$bestjg" ]; }; then
      bestpv=${pv[$p]}; bestjg=${jugadas[$p]:-0}; best=$p
    fi
  done
  echo "$best"
}

estado_actual_jugaores(){
  local i
  echo "Estado:"
  for ((i=0;i<JUGADORES;i++)); do
    printf "  P%d: PV=%d ESC=%d\n" $((i+1)) "${pv[$i]}" "${escudo[$i]}"
  done
}

finalizar_para_log(){
  local winner=$1 tpo=$((SECONDS - start_ts)) fecha hora tcz tcm tcj p1=- p2=- p3=- p4=-
  fecha=$(date +%d%m%y); hora=$(date +%H:%M:%S)
  tcz=$(cartas_restantes); tcm=$(cartas_mano)
  local s=0 p; for ((p=0;p<JUGADORES;p++)); do s=$((s+${jugadas[$p]:-0})); done; tcj=$s
  [ "$JUGADORES" -ge 1 ] && p1=${pv[0]}
  [ "$JUGADORES" -ge 2 ] && p2=${pv[1]}
  [ "$JUGADORES" -ge 3 ] && p3=${pv[2]}
  [ "$JUGADORES" -ge 4 ] && p4=${pv[3]}
  printf "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n" \
    "$fecha" "$hora" "$tpo" "$JUGADORES" "$PV" "$ESTRATEGIA" "$MAXIMO" "$((winner+1))" \
    "$p1" "$p2" "$p3" "$p4" "$tcz" "$tcm" "$tcj" >> "$LOG"
  echo "Ganador: Jugador $((winner+1))"
  echo "PV finales: P1=$p1 P2=$p2 P3=$p3 P4=$p4"
  echo "TCZ=$tcz TCM=$tcm TCJ=$tcj Tiempo=$tpo s (log: $LOG)"
}

bucle_turnos(){
  start_ts=$SECONDS
  local turn=1 pid sel code end hlen dcard
  while :; do
    echo; echo "--- Turno $turn ---"
    for ((pid=0; pid<JUGADORES; pid++)); do
      alive "$pid" || continue

      eval "hlen=\${#hand$pid[@]}"
      if [ "$hlen" -eq 0 ]; then
        code=""
        roba_carta "$pid" code
        [ -n "$code" ] && anadir_carta_mano "$pid" "$code"
        eval "hlen=\${#hand$pid[@]}"
      fi
        if [ "$hlen" -eq 0 ]; then
        echo "P$((pid+1)) no tiene cartas."
        end=$(revisar_fin)
        if [ "$end" != "CONT" ]; then
          if [[ "$end" == WIN:* ]]; then finalizar_para_log "${end#WIN:}"; return; fi
          if [ "$end" = "DECKS_OUT" ]; then local w; w=$(desempatar); finalizar_para_log "$w"; return; fi
        fi
        continue
      fi


      
      if [ "$pid" -eq 0 ]; then
        sel=$(jugador_elegir_carta "$pid")
        eval "code=\${hand$pid[$sel]}"
        eliminar_carta_usada "$pid" "$sel"
      else
        code=$(ia_escoger_carta "$pid")
        eval '
          for i in "${!hand'"$pid"'[@]}"; do
            if [ "${hand'"$pid"'[$i]}" = "'"$code"'" ]; then unset hand'"$pid"'[$i]; break; fi
          done
          hand'"$pid"'=("${hand'"$pid"'[@]}")
        '
      fi

      echo "P$((pid+1)) juega $(nombre_cartas "$code")"
      jugar_carta "$pid" "$code"
      jugadas[$pid]=$(( ${jugadas[$pid]:-0}+1 ))
      estado_actual_jugaores

      dcard=""
      roba_carta "$pid" dcard
      if [ -n "$dcard" ]; then
        anadir_carta_mano "$pid" "$dcard"
        echo "P$((pid+1)) roba del mazo: $(nombre_cartas "$dcard")"
      fi

      end=$(revisar_fin)
      if [ "$end" != "CONT" ]; then
        if [[ "$end" == WIN:* ]]; then finalizar_para_log "${end#WIN:}"; return; fi
        if [ "$end" = "DECKS_OUT" ]; then local w; w=$(desempatar); finalizar_para_log "$w"; return; fi
      fi
    done
    turn=$((turn+1))
  done
}

jugar(){
  set +e
  init_decks;          
  iniciar_jugadores;        

  echo "=== Mazos barajados (completos) ==="
  for ((p=0; p<JUGADORES; p++)); do imprimir_mazo "$p"; done

 reparto_mano_inicial;

  echo; echo "=== Manos iniciales ==="
  for ((p=0; p<JUGADORES; p++)); do imprimir_mano "$p"; done

  echo; echo "=== Mazos restantes tras repartir ==="
  for ((p=0; p<JUGADORES; p++)); do imprimir_mazo_restante "$p"; done

  echo; echo "=== PV iniciales ==="
  for ((i=0;i<JUGADORES;i++)); do echo "Jugador $((i+1)): PV=${pv[$i]}"; done

  bucle_turnos
}

estadisticas(){
  local LOGFILE="$LOG"

  if [ ! -f "$LOGFILE" ]; then
    echo "No existe el fichero de log: $LOGFILE"
    return 0
  fi
  if ! grep '[0-9]' "$LOGFILE"; then
    echo "No hay partidas registradas en $LOGFILE"
    return 0
  fi

  local AWK="/usr/xpg4/bin/awk"; [ -x "$AWK" ] || AWK="awk"

  "$AWK" -F'|' '
  function max(a,b){return a>b?a:b}

  BEGIN{
    total=0; sum_tpo=0; min_tpo=1e9
    max_pv_overall=-1; max_tcj=-1; sum_tcj=0
    for(i=1;i<=4;i++) wins[i]=0
  }

  $1 !~ /^[0-9]{6}$/ { next }

  {
    total++

    tpo = $3 + 0
    sum_tpo += tpo

    ganador = $8 + 0
    if (ganador>=1 && ganador<=4) wins[ganador]++

    if (tpo < min_tpo) { min_tpo=tpo; line_min=$0 }

    maxpv_game=-1
    topcount=0
    pv[1]=$9; pv[2]=$10; pv[3]=$11; pv[4]=$12
    for(i=1;i<=4;i++){
      if(pv[i] != "-"){
        v = pv[i] + 0
        if(v > maxpv_game) maxpv_game=v
      }
    }
    for(i=1;i<=4;i++){
      if(pv[i] != "-"){
        v = pv[i] + 0
        if(v == maxpv_game) topcount++
      }
    }
    if (maxpv_game > max_pv_overall) { max_pv_overall=maxpv_game; line_maxpv=$0 }

    if (topcount >= 2) { tie_count++; ties[tie_count]=$0 }

    tcj = $15 + 0
    sum_tcj += tcj
    if (tcj > max_tcj) { max_tcj=tcj; line_maxtcj=$0 }
  }

  END{
    if (total == 0) { print "No hay partidas validas en el log."; exit }

    printf "================ ESTADISTICAS ================\n"
    printf "Fichero: %s\n", "'"$LOGFILE"'"
    printf "Partidas totales: %d\n", total
    printf "Tiempo medio (s): %.2f\n", (sum_tpo/total)

    split(line_min, a, "|")
    printf "\n-- Partida mas corta --\n"
    printf "Fecha %s Hora %s | TPO=%s | Jug=%s PV=%s Estr=%s PMax=%s | Ganador=%s | P1=%s P2=%s P3=%s P4=%s | TCZ=%s TCM=%s TCJ=%s\n",
           a[1],a[2],a[3],a[4],a[5],a[6],a[7],a[8],a[9],a[10],a[11],a[12],a[13],a[14],a[15]

    split(line_maxpv, b, "|")
    printf "\n-- Partida con mayor PV final -- (PV max=%d)\n", max_pv_overall
    printf "Fecha %s Hora %s | TPO=%s | Jug=%s PV=%s Estr=%s PMax=%s | Ganador=%s | P1=%s P2=%s P3=%s P4=%s | TCZ=%s TCM=%s TCJ=%s\n",
           b[1],b[2],b[3],b[4],b[5],b[6],b[7],b[8],b[9],b[10],b[11],b[12],b[13],b[14],b[15]

    printf "\n-- Victorias --\n"
    for(i=1;i<=4;i++){
      pct = (total>0)? (100.0*wins[i]/total) : 0
      printf "Jugador %d: %d (%.1f%%)\n", i, wins[i], pct
    }

    printf "\n-- Partidas con empate por PV final --\n"
    if (tie_count==0) {
      printf "Ninguna.\n"
    } else {
      for(i=1;i<=tie_count;i++){
        split(ties[i], t, "|")
        printf "#%d -> Fecha %s Hora %s | Ganador=%s | PV finales: P1=%s P2=%s P3=%s P4=%s\n",
               i, t[1], t[2], t[8], t[9], t[10], t[11], t[12]
      }
    }

    printf "\n-- Extra --\n"
    printf "TCJ medio: %.2f\n", (sum_tcj/total)
    split(line_maxtcj, c, "|")
    printf "Partida con mas jugadas (TCJ=%d): Fecha %s Hora %s | Ganador=%s\n",
           max_tcj, c[1], c[2], c[8]
  }' "$LOGFILE"
}
salir(){ echo "Saliendo del programa. Hasta pronto!"; exit 0; }

menu(){
  while true; do
    echo "==========================="
    echo "      MENU PRINCIPAL       "
    echo "==========================="
    echo "[C] Configuracion"
    echo "[J] Jugar"
    echo "[E] Estadisticas"
    echo "[S] Salir"
    echo "==========================="
    printf "Selecciona una opcion: "
    IFS= read -r opcion
    case "$opcion" in
      [cC]) configuracion ;;
      [jJ]) jugar ;;
      [eE]) estadisticas ;;
      [sS]) salir ;;
      *)    echo "Opcion no valida. Intenta de nuevo." ;;
    esac
    echo
    printf "Presiona Enter para continuar..."
    IFS= read -r _
  done
}

cargar_y_validar_cfg || { echo "Config invalida. Corrige $CFG" >&2; exit 1; }
menu

