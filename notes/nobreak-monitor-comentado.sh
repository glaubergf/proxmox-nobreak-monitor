#!/bin/bash

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

# Equipamento fora do nobreak.
# Sua indisponibilidade representa uma possível perda
# da alimentação elétrica normal.
SENTINEL="192.168.0.2"

# Equipamento alimentado pelo nobreak.
# Sua disponibilidade confirma que a rede local continua
# operacional e que o Proxmox ainda possui conectividade.
ROUTER="192.168.0.1"


# ----------------------------------------------------------
# Modo de teste
# ----------------------------------------------------------
#
# false = comportamento normal
# true  = simula uma falha de comunicação com os hosts
#
# IMPORTANTE:
# Este parâmetro é útil para testar a lógica do monitor
# sem precisar provocar uma falha real de energia.
TEST_NETWORK_FAILURE=false


# ----------------------------------------------------------
# Intervalo de monitoramento
# ----------------------------------------------------------
#
# Define quanto tempo o monitor espera entre verificações
# durante o funcionamento normal.
CHECK_INTERVAL=5


# ----------------------------------------------------------
# Confirmação da falha
# ----------------------------------------------------------
#
# Depois que o sentinela deixa de responder, a condição
# precisa permanecer durante este período antes de ser
# considerada uma falta de energia confirmada.
#
# Isso evita reagir imediatamente a uma indisponibilidade
# momentânea do sentinela.
CONFIRM_TIME=30


# ----------------------------------------------------------
# Autonomia reservada do nobreak
# ----------------------------------------------------------
#
# Depois que a falta de energia é confirmada, o monitor
# aguarda este período antes de iniciar o shutdown.
#
# 600 segundos = 10 minutos
#
# Esse valor deve ser compatível com a autonomia observada
# do conjunto alimentado pelo nobreak.
SHUTDOWN_DELAY=600


# ----------------------------------------------------------
# Proteção contra shutdown acidental
# ----------------------------------------------------------
#
# false = modo de teste
# true  = permite shutdown real do Proxmox
#
# Recomenda-se manter false durante a instalação e os testes.
SHUTDOWN_ENABLED=false


# ==========================================================
# FUNÇÕES
# ==========================================================

# ----------------------------------------------------------
# log()
# ----------------------------------------------------------
#
# Centraliza as mensagens do monitor.
#
# Como o serviço é executado pelo systemd, a saída padrão
# do script fica disponível no journal:
#
#   journalctl -u nobreak-monitor.service
#
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $*"
}


# ----------------------------------------------------------
# ping_host()
# ----------------------------------------------------------
#
# Testa a disponibilidade de um equipamento através de ICMP.
#
# -c 1 = envia apenas um pacote
# -W 2 = aguarda no máximo 2 segundos pela resposta
#
# Retorno:
#   0 = host respondeu
#   1 = host não respondeu
#
ping_host() {

    # Permite simular uma falha de comunicação durante testes.
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
    #
    # Enquanto o sentinela responde, não existe indicação
    # de falta de energia.
    #

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
    #
    # O sentinela sozinho não é suficiente para decidir
    # pelo shutdown.
    #
    # Se o roteador também não responder, pode existir uma
    # falha geral de rede. Nesse cenário, por segurança,
    # o shutdown não deve ser iniciado.
    #

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
    #
    # A partir daqui temos:
    #
    #   Sentinela OFF
    #   Roteador ON
    #
    # Ainda não desligamos o host.
    #
    # A condição precisa permanecer durante CONFIRM_TIME.
    #

    FAIL_START=$(date +%s)

    while true; do

        # --------------------------------------------------
        # Sentinela voltou
        # --------------------------------------------------
        #
        # A condição foi considerada transitória.
        # Cancela esta tentativa e volta ao monitoramento
        # normal.
        #

        if ping_host "$SENTINEL"; then

            log "Sentinela voltou durante a confirmação."
            log "Falha cancelada."
            log "Retornando ao monitoramento normal."

            # "continue 2" sai do loop de confirmação e
            # continua a próxima iteração do loop principal.
            continue 2

        fi


        # --------------------------------------------------
        # Roteador deixou de responder
        # --------------------------------------------------
        #
        # A referência de conectividade desapareceu.
        # Não é mais possível afirmar que o problema é
        # exclusivamente uma falta de energia.
        #

        if ! ping_host "$ROUTER"; then

            log "Roteador $ROUTER deixou de responder durante a confirmação."
            log "Possível falha de rede: shutdown cancelado."
            log "Retornando ao monitoramento normal."

            continue 2
        fi


        # Calcula há quanto tempo o sentinela está indisponível.
        NOW=$(date +%s)
        ELAPSED=$((NOW - FAIL_START))


        # --------------------------------------------------
        # Falha confirmada
        # --------------------------------------------------

        if [ "$ELAPSED" -ge "$CONFIRM_TIME" ]; then

            log "FALHA CONFIRMADA: sentinela indisponível há ${ELAPSED}s."
            log "Roteador continua disponível."

            # Aqui queremos sair somente deste loop.
            # O próximo estado será a contagem regressiva.
            break

        fi


        sleep "$CHECK_INTERVAL"

    done


    # ======================================================
    # CONTAGEM REGRESSIVA
    # ======================================================
    #
    # A falta de energia já foi confirmada.
    #
    # Agora o monitor aguarda a autonomia configurada do
    # nobreak antes de tomar a decisão de desligar o host.
    #

    COUNTDOWN_START=$(date +%s)

    log "MODO DE ESPERA: iniciando contagem de ${SHUTDOWN_DELAY}s."


    while true; do

        # --------------------------------------------------
        # Sentinela voltou
        # --------------------------------------------------
        #
        # A energia provavelmente foi restabelecida.
        # O shutdown deve ser cancelado.
        #

        if ping_host "$SENTINEL"; then

            log "ENERGIA RESTABELECIDA: sentinela voltou."
            log "Shutdown cancelado."
            log "Retornando ao monitoramento normal."

            continue 2

        fi


        # --------------------------------------------------
        # Roteador deixou de responder
        # --------------------------------------------------
        #
        # Se o roteador cair, perdemos a referência de rede.
        # Por segurança, o shutdown é cancelado.
        #

        if ! ping_host "$ROUTER"; then

            log "ROTEADOR $ROUTER deixou de responder."
            log "Possível falha de rede."
            log "Shutdown cancelado por segurança."
            log "Retornando ao monitoramento normal."

            continue 2

        fi


        # Calcula o tempo transcorrido desde o início
        # da contagem de autonomia.
        NOW=$(date +%s)
        ELAPSED=$((NOW - COUNTDOWN_START))


        # ==================================================
        # TEMPO DE AUTONOMIA ESGOTADO
        # ==================================================

        if [ "$ELAPSED" -ge "$SHUTDOWN_DELAY" ]; then

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
            #
            # Neste ponto temos:
            #
            #   Sentinela OFF
            #   Roteador ON
            #   Falha confirmada
            #   Autonomia esgotada
            #   Verificação final OK
            #
            # A condição de falta de energia é considerada
            # confirmada e o host pode ser desligado.
            #

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

                # O script não executa "qm shutdown" nas VMs.
                #
                # Ele solicita o desligamento normal do host.
                # A partir daqui, o próprio Proxmox/systemd
                # assume o encerramento dos guests.
                #
                /sbin/shutdown -h now

            else

                # Modo seguro para testes.
                # Toda a lógica é executada normalmente,
                # mas o host não será desligado.
                log "TESTE: shutdown real está DESABILITADO."
                log "TESTE: o Proxmox seria desligado agora."

            fi


            log "Monitor encerrado após timeout."
            exit 0

        fi


        sleep "$CHECK_INTERVAL"

    done

done