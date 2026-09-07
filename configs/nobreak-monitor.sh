#!/bin/bash

# ==========================================================
# Arquivo..........: nobreak-monitor.sh
# Versão...........: 1.0.0
# Autor............: Glauber GF (mcnd2)
# Data.............: 16-08-2026
# Atualizado.......: 06-09-2026
# Descrição........: Script de monitoramento de energia elétrica para
# ambiente Proxmox conectado a um nobreak Intelbras XNB 600 tendo 
# como referência um sentinela de energia NÃO conectado ao nobreak e o 
# roteador principal conectado ao nobreak.
# Objetivo.........: Permitir desligamento seguro do node Proxmox em 
# caso de falta de energia elétrica.
#
#   Detectar indiretamente uma falta de energia elétrica
#   utilizando dois equipamentos com alimentações distintas:
#
#   SENTINELA:
#       - Fora do nobreak
#       - Deve desligar em caso de falta de energia
#
#   ROTEADOR:
#       - Alimentado pelo nobreak
#       - Deve permanecer disponível durante a autonomia
#
# A combinação:
#
#   Sentinela OFF + Roteador ON
#
# é utilizada como evidência de falta de energia.
#
# Após confirmação e término da autonomia configurada,
# o node Proxmox poderá ser desligado com segurança.
# ==========================================================

# ==========================================================
# CONFIGURAÇÃO
# ==========================================================

SENTINEL="192.168.0.2"
ROUTER="192.168.0.1"

# Proteção contra falso desligamento por falha de rede.
#
# false = funcionamento normal
# true  = simula indisponibilidade de rede para testes
TEST_NETWORK_FAILURE=false

# Intervalo entre verificações
CHECK_INTERVAL=5

# Tempo necessário para confirmar a condição de falta de energia
CONFIRM_TIME=30

# Tempo de autonomia do nobreak antes do shutdown
SHUTDOWN_DELAY=600

# Segurança:
#
# false = somente simulação/teste
# true  = executa shutdown real
SHUTDOWN_ENABLED=false


# ==========================================================
# FUNÇÕES
# ==========================================================

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $*"
}


ping_host() {

    # Modo de teste de falha de rede.
    if [ "$TEST_NETWORK_FAILURE" = true ]; then
        return 1
    fi

    ping -c 1 -W 2 "$1" >/dev/null 2>&1
}


# ==========================================================
# INICIALIZAÇÃO
# ==========================================================

log "=============================================="
log "Monitor Sentinela de Energia - Proxmox"
log "=============================================="
log "Monitor iniciado."
log "Sentinela: $SENTINEL"
log "Roteador principal: $ROUTER"
log "Intervalo de verificação: ${CHECK_INTERVAL}s"
log "Confirmação de falha: ${CONFIRM_TIME}s"
log "Tempo até shutdown: ${SHUTDOWN_DELAY}s"
log "Shutdown real habilitado: $SHUTDOWN_ENABLED"


# ==========================================================
# MONITORAMENTO PRINCIPAL
# ==========================================================

while true; do

    # ======================================================
    # ESTADO NORMAL
    # ======================================================

    if ping_host "$SENTINEL"; then
        sleep "$CHECK_INTERVAL"
        continue
    fi


    # ======================================================
    # SENTINELA NÃO RESPONDE
    # ======================================================

    log "ALERTA: sentinela $SENTINEL não respondeu."


    # ======================================================
    # VERIFICAÇÃO DO ROTEADOR
    # ======================================================

    if ! ping_host "$ROUTER"; then

        log "ROTEADOR $ROUTER também não responde."
        log "POSSÍVEL FALHA DE REDE: shutdown não será iniciado."

        sleep "$CHECK_INTERVAL"
        continue
    fi


    log "Roteador $ROUTER responde normalmente."
    log "Condição compatível com perda de energia do sentinela."


    # ======================================================
    # CONFIRMAÇÃO DA FALHA
    # ======================================================

    FAIL_START=$(date +%s)

    while true; do

        # --------------------------------------------------
        # Sentinela voltou
        # --------------------------------------------------

        if ping_host "$SENTINEL"; then

            log "Sentinela voltou durante a confirmação."
            log "Falha cancelada."
            log "Retornando ao monitoramento normal."

            # Sai da confirmação e volta ao loop principal.
            continue 2

        fi


        # --------------------------------------------------
        # Roteador deixou de responder
        # --------------------------------------------------

        if ! ping_host "$ROUTER"; then

            log "Roteador $ROUTER deixou de responder durante a confirmação."
            log "Possível falha de rede: shutdown cancelado."
            log "Retornando ao monitoramento normal."

            continue 2
        fi


        NOW=$(date +%s)
        ELAPSED=$((NOW - FAIL_START))


        if [ "$ELAPSED" -ge "$CONFIRM_TIME" ]; then

            log "FALHA CONFIRMADA: sentinela indisponível há ${ELAPSED}s."
            log "Roteador continua disponível."

            # Sai somente da confirmação.
            break

        fi


        sleep "$CHECK_INTERVAL"

    done


    # ======================================================
    # CONTAGEM REGRESSIVA
    # ======================================================

    COUNTDOWN_START=$(date +%s)

    log "MODO DE ESPERA: iniciando contagem de ${SHUTDOWN_DELAY}s."


    while true; do

        # --------------------------------------------------
        # Sentinela voltou
        # --------------------------------------------------

        if ping_host "$SENTINEL"; then

            log "ENERGIA RESTABELECIDA: sentinela voltou."
            log "Shutdown cancelado."
            log "Retornando ao monitoramento normal."

            continue 2

        fi


        # --------------------------------------------------
        # Roteador deixou de responder
        # --------------------------------------------------

        if ! ping_host "$ROUTER"; then

            log "ROTEADOR $ROUTER deixou de responder."
            log "Possível falha de rede."
            log "Shutdown cancelado por segurança."
            log "Retornando ao monitoramento normal."

            continue 2

        fi


        NOW=$(date +%s)
        ELAPSED=$((NOW - COUNTDOWN_START))


        if [ "$ELAPSED" -ge "$SHUTDOWN_DELAY" ]; then

            # ==================================================
            # TEMPO ESGOTADO
            # ==================================================

            log "TEMPO ESGOTADO."
            log "Iniciando verificação final antes do shutdown."


            # --------------------------------------------------
            # VERIFICAÇÃO FINAL DO SENTINELA
            # --------------------------------------------------

            log "Verificação final do sentinela..."

            if ping_host "$SENTINEL"; then

                log "Sentinela voltou."
                log "Shutdown cancelado."
                log "Retornando ao monitoramento normal."

                continue 2

            fi

            log "Sentinela continua indisponível."


            # --------------------------------------------------
            # VERIFICAÇÃO FINAL DO ROTEADOR
            # --------------------------------------------------

            log "Verificação final do roteador..."

            if ! ping_host "$ROUTER"; then

                log "Roteador deixou de responder."
                log "Possível falha de rede."
                log "Shutdown cancelado por segurança."
                log "Retornando ao monitoramento normal."

                continue 2

            fi

            log "Roteador continua disponível."


            # ==================================================
            # DECISÃO FINAL
            # ==================================================

            log "CONDIÇÃO DE FALTA DE ENERGIA CONFIRMADA."
            log "Sentinela indisponível."
            log "Roteador disponível."
            log "Tempo de autonomia excedido: ${SHUTDOWN_DELAY}s."
            log "DECISÃO: desligar o node Proxmox."


            # ==================================================
            # SHUTDOWN
            # ==================================================

            if [ "$SHUTDOWN_ENABLED" = true ]; then

                log "SHUTDOWN REAL HABILITADO."
                log "Executando shutdown do node Proxmox agora."

                /sbin/shutdown -h now

            else

                log "TESTE: shutdown real está DESABILITADO."
                log "TESTE: o Proxmox seria desligado agora."

            fi


            log "Monitor encerrado após timeout."
            exit 0

        fi


        sleep "$CHECK_INTERVAL"

    done

done