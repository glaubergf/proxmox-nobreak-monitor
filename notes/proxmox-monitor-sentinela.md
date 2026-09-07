<!---
# ==========================================================================
Projeto..........: proxmox-monitor-sentinela
Versão...........: 1.0.0
Autor............: Glauber GF (mcnd2)
Data.............: 16-08-2026
Atualizado.......: 06-09-2026
Descrição........: Documentação técnica detalhada sobre o projeto de monitoramento de falta de energia para um host Proxmox protegido por um nobreak, utilizando um equipamento externo como sentinela por meio de comunicação ICMP.
# ==========================================================================
-->

# Monitor Sentinela de Falta de Energia para Proxmox

**Documento técnico de referência, implementação, operação e manutenção**

> Este documento consolida a arquitetura, o hardware utilizado, a lógica de detecção, o script, o serviço systemd, os testes realizados e os critérios para futuras melhorias do projeto.

---

# 1. Visão geral

Este projeto implementa um mecanismo simples e conservador para proteger um ambiente Proxmox durante uma falta prolongada de energia elétrica.

O cenário utiliza um **Intelbras XNB 600 120 V**, sem interface de gerenciamento disponível para o Proxmox. Por esse motivo, o host não recebe diretamente uma informação como `ONBATT`, percentual de bateria ou autonomia restante.

A solução utiliza dois equipamentos com alimentações elétricas diferentes:

- **Sentinela:** um D-Link DIR-524 alimentado diretamente pela rede elétrica, fora do nobreak.
- **Roteador principal:** um TP-Link EX511 alimentado pelo nobreak.
- **Proxmox:** também alimentado pelo nobreak.
- **Modem/ONT:** Nokia G-1425G-B, também alimentado pelo nobreak.

A condição usada como evidência de falta de energia é:

```text
Sentinela indisponível
        +
Roteador principal disponível
```

Essa condição precisa permanecer por **30 segundos**. Depois disso, o monitor aguarda **600 segundos (10 minutos)** antes de realizar uma nova verificação final.

Somente se a condição continuar válida o Proxmox recebe uma solicitação normal de shutdown.

### Regra resumida

```text
SENTINELA OFF
      +
ROTEADOR ON
      +
CONFIRMAÇÃO = 30s
      +
ESPERA = 600s
      +
VERIFICAÇÃO FINAL
      ↓
SHUTDOWN DO NODE PROXMOX
      ↓
pve-guests
      ↓
7 VMs/CTs encerrados
      ↓
HOST DESLIGADO
```

O monitor **não executa `qm shutdown` individualmente**. A responsabilidade pelo encerramento dos guests permanece com o mecanismo nativo do Proxmox.

---

# 2. Objetivos

## 2.1 Objetivo principal

Evitar que o node Proxmox permaneça ligado até o esgotamento da bateria do nobreak durante uma interrupção prolongada de energia.

## 2.2 Objetivos secundários

- Detectar indiretamente uma falta de energia sem depender de interface USB, SNMP ou serial do nobreak.
- Reduzir falsos desligamentos provocados por falhas gerais de rede.
- Permitir o cancelamento automático caso o sentinela volte.
- Reservar uma margem de autonomia antes do shutdown.
- Permitir que as 7 VMs sejam encerradas adequadamente pelo Proxmox.
- Desligar o host somente depois que o processo normal de encerramento dos guests for iniciado.
- Manter o script pequeno e com poucas dependências.
- Registrar toda a operação no journal do systemd.
- Permitir testes sem executar shutdown real.

---

# 3. Escopo

## 3.1 Incluído

- Monitoramento ICMP do sentinela.
- Monitoramento ICMP do roteador.
- Confirmação temporal da falha.
- Contagem da autonomia reservada.
- Verificação final antes do shutdown.
- Solicitação de shutdown do host.
- Integração com systemd.
- Registro no journal.
- Procedimentos de instalação.
- Procedimentos de teste.
- Diagnóstico e manutenção.
- Documentação da arquitetura elétrica e lógica.

## 3.2 Fora do escopo

O projeto não implementa:

- leitura direta do estado da bateria;
- leitura de percentual de carga do nobreak;
- comunicação USB com o nobreak;
- SNMP do nobreak;
- monitoramento elétrico direto;
- desligamento individual das VMs pelo script;
- gerenciamento do roteador ou do modem;
- monitoramento de saúde dos discos.

Uma futura integração com NUT, SNMP ou outro mecanismo de gerenciamento de UPS pode complementar ou substituir a inferência atual.

---

# 4. Ambiente físico utilizado

## 4.1 Nobreak

**Modelo:** Intelbras XNB 600 120 V

Características relevantes do modelo:

- capacidade nominal: **600 VA**;
- quatro tomadas de saída;
- saída nominal de 120 V;
- bateria interna original especificada pelo fabricante: 12 V / 7 Ah;
- proteção contra sobrecarga, curto-circuito, sobreaquecimento, sub/sobretensão e descarga total/sobrecarga da bateria;
- função DC Start;
- restart automático;
- sem interface de gerenciamento utilizada pelo projeto.

A especificação oficial do fabricante identifica o XNB 600 como um nobreak de 600 VA com quatro tomadas e bateria interna de 12 V / 7 Ah. A bateria atualmente instalada neste equipamento, entretanto, foi substituída por uma **Moura 12 V / 9 Ah**. Portanto, os dados da bateria original do produto não devem ser usados como se fossem a capacidade da bateria atualmente instalada.

### Histórico da bateria

- **Data da substituição:** 15/04/2026
- **Fabricante:** Moura
- **Tensão:** 12 V
- **Capacidade nominal:** 9 Ah

### Equipamentos alimentados pelo XNB 600

| Tomada | Equipamento |
|---|---|
| 1 | Mini PC com Proxmox |
| 2 | Roteador principal TP-Link EX511 |
| 3 | Modem/ONT Nokia G-1425G-B |
| 4 | Livre |

O projeto foi dimensionado considerando esse conjunto real de equipamentos.

---

# 5. Proxmox / servidor

O host Proxmox é um mini PC Beelink baseado em:

- **AMD Ryzen 7 5800H**
- 8 núcleos / 16 threads
- 24 GB DDR4
- 8 GB Swap
- SSD M.2 2280 de 500 GB
- Proxmox VE (7 VMs)

### Função na arquitetura

O Proxmox é o principal equipamento protegido pelo nobreak e o alvo da decisão final do monitor.

Quando a falta de energia é confirmada, o monitor não tenta administrar cada VM diretamente. Ele solicita o shutdown do host.

---

# 6. Roteador principal

**Modelo:** TP-Link EX511 V2.0

Informações registradas no ambiente:

```text
IP:              192.168.0.1
Hardware:        EX511 v2.0
Firmware:        0.7.0 3.0.0 v607e.0 Build 240930 Rel.11206n
```

O equipamento é alimentado pelo nobreak.

Sua função no projeto não é apenas fornecer conectividade: ele funciona como **referência de rede protegida**.

A lógica é:

```text
Sentinela OFF + Roteador ON
        ↓
há evidência de que a rede protegida continua funcionando
        ↓
a perda do sentinela é compatível com perda da alimentação externa
```

A fonte do EX511 é especificada pelo fabricante em 12 V / 1,5 A. Esse valor representa a capacidade nominal da fonte, e não o consumo elétrico real medido pelo equipamento.

---

# 7. Modem / ONT

**Modelo:** Nokia G-1425G-B

O equipamento é alimentado pelo nobreak.

A documentação técnica do fabricante informa alimentação local de 12 V e consumo de energia inferior a **18 W** para o G-1425G-B.

O modem/ONT não participa diretamente da lógica do monitor.

Sua função é manter a conectividade externa durante a autonomia do nobreak.

---

# 8. Sentinela

**Modelo:** D-Link DIR-524

Informações registradas:

```text
Hardware:        L1
Firmware:        9.01
IP LAN:          192.168.0.2
Máscara:         255.255.255.0
DHCP:            desativado
Wireless:        desativado
Conexão:         LAN → LAN
Alimentação:     tomada da rede elétrica, fora do nobreak
```

O equipamento foi escolhido deliberadamente como sentinela porque é dedicado a essa função e fica eletricamente independente do nobreak.

O princípio fundamental é:

```text
REDE ELÉTRICA
     │
     └── Sentinela
           │
           └── deve responder normalmente

NOBREAK
     │
     ├── Roteador
     └── Proxmox
           │
           └── continuam funcionando durante a autonomia
```

---

# 9. Arquitetura elétrica

A arquitetura física do projeto é:

```text
                         REDE ELÉTRICA
                              │
                 ┌────────────┴────────────┐
                 │                         │
                 ▼                         ▼
          TOMADA DIRETA                 NOBREAK
                 │                  Intelbras XNB 600
                 │                         │
                 ▼                         ├── Proxmox
        D-Link DIR-524                     │
        192.168.0.2                        ├── TP-Link EX511
        SENTINELA                          │    192.168.0.1
                                           │
                                           └── Nokia G-1425G-B
```

O ponto crítico da arquitetura é a separação elétrica:

```text
Sentinela  = fora do nobreak
Roteador   = dentro do nobreak
Proxmox    = dentro do nobreak
```

Essa diferença permite inferir a interrupção da rede elétrica.

---

# 10. Arquitetura de rede

A rede utilizada é:

```text
192.168.0.0/24
```

Com:

```text
192.168.0.1 → TP-Link EX511 → roteador principal
192.168.0.2 → D-Link DIR-524 → sentinela
```

O monitor executado no Proxmox consulta ambos os endereços utilizando ICMP.

---

# 11. Por que utilizar um sentinela

O XNB 600 não fornece ao Proxmox uma interface de gerenciamento utilizada neste projeto.

O Proxmox não recebe diretamente:

```text
ONBATT
LOWBATT
BATERIA %
TEMPO RESTANTE
```

O sentinela resolve essa limitação de maneira simples.

### Condição normal

```text
Sentinela responde
Roteador responde
        ↓
Operação normal
```

### Possível falta de energia

```text
Sentinela não responde
Roteador responde
        ↓
Possível perda da alimentação externa
```

### Possível falha de rede

```text
Sentinela não responde
Roteador não responde
        ↓
Não é possível diferenciar corretamente
falta de energia de falha de rede
        ↓
CANCELAR SHUTDOWN
```

Essa última decisão é deliberadamente conservadora.

---

# 12. Consumo e autonomia

## 12.1 Importante: capacidade da fonte não é consumo real

Ao analisar o consumo dos equipamentos, é importante distinguir:

```text
Potência da fonte/adaptador
        ≠
Consumo real do equipamento
```

Por exemplo, uma fonte de 12 V / 1,5 A pode fornecer até aproximadamente:

```text
12 × 1,5 = 18 W
```

mas isso não significa que o roteador consuma continuamente 18 W.

Da mesma forma, um adaptador de 65 W do mini PC não significa que o Proxmox esteja consumindo 65 W continuamente.

Para dimensionamento preciso, o ideal é utilizar um wattímetro na entrada AC.

## 12.2 Valores de referência

| Equipamento | Informação disponível | Observação |
|---|---:|---|
| Beelink Ryzen 7 5800H | fonte/adaptador na faixa de 65 W em variantes SER5 | potência da fonte, não consumo contínuo |
| TP-Link EX511 | 12 V / 1,5 A | até 18 W pela especificação da fonte |
| Nokia G-1425G-B | < 18 W | consumo informado pelo fabricante |
| D-Link DIR-524 | não entra no nobreak | não participa do consumo da bateria |

O consumo real do mini PC depende da carga das 7 VMs, CPU, armazenamento, memória, rede, BIOS e demais condições de operação.

## 12.3 Capacidade nominal da bateria

A bateria instalada é:

```text
12 V × 9 Ah = 108 Wh
```

Esse valor é uma **energia nominal teórica** da bateria.

Não significa que 108 Wh estejam integralmente disponíveis na saída AC do nobreak.

Existem perdas:

```text
Bateria
  ↓
inversor
  ↓
nobreak
  ↓
fontes dos equipamentos
  ↓
cargas reais
```

Além disso, a capacidade efetiva de uma bateria chumbo-ácido depende da corrente de descarga, temperatura, idade, estado de carga e tensão de corte.

Por isso, a autonomia real deve ser tratada como informação obtida por teste do conjunto, e não calculada apenas por:

```text
Wh / consumo
```

---

# 13. Teste real de autonomia

Foi realizado um teste real com o conjunto utilizado no projeto.

### Condições

- XNB 600 120 V.
- Bateria Moura 12 V / 9 Ah.
- Proxmox ligado.
- 7 VMs/guests em operação.
- TP-Link EX511 ligado.
- Nokia G-1425G-B ligado.
- Sentinela fora do nobreak.
- Falta de energia simulada sem permitir que a bateria chegasse ao esgotamento.

### Resultado observado

O conjunto permaneceu alimentado por aproximadamente:

```text
15 minutos e 45 segundos
```

Durante esse período, o nobreak ainda **não havia apresentado o sinal sonoro de baixa bateria observado no equipamento**.

Esse teste não deve ser interpretado como a autonomia máxima do nobreak.

O resultado representa:

> **autonomia observada do conjunto real, sob as condições do teste, sem esgotar a bateria.**

---

# 14. Por que `SHUTDOWN_DELAY=600`

O valor atual é:

```bash
SHUTDOWN_DELAY=600
```

ou:

```text
10 minutos
```

Esse valor não significa que o XNB 600 tenha autonomia nominal de 10 minutos.

Ele representa uma **margem operacional reservada pelo projeto**.

O teste real apresentou aproximadamente:

```text
15m45s = 945 segundos
```

A diferença entre a duração observada e o atraso configurado é:

```text
945s - 600s = 345s
```

ou aproximadamente:

```text
5m45s
```

Entretanto, o teste completo também envolve o período de confirmação de 30 segundos e o tempo necessário para o Proxmox concluir seu próprio processo de shutdown.

Por isso, os 600 segundos devem ser entendidos como uma janela reservada para retardar a decisão, preservando margem para a etapa final.

### Decisão atual

**Não aumentar o valor neste momento.**

O valor de 600 segundos é adequado como configuração conservadora enquanto o tempo efetivo de encerramento das 7 VMs e do host permanecer compatível com a margem observada.

Aumentar o atraso para 720 segundos, por exemplo, reduziria a margem restante de bateria sem trazer benefício comprovado.

Uma alteração futura somente deve ser feita após medir:

1. tempo de confirmação;
2. tempo entre o início do shutdown e o encerramento das 7 VMs;
3. tempo adicional até o host realmente desligar;
4. margem necessária para variações de bateria e carga.

---

# 15. Linha do tempo do shutdown

Com a configuração atual:

```text
T0
│
├── Sentinela deixa de responder
│
├── Roteador continua respondendo
│
├── Confirmação: 30s
│
├── Falha confirmada
│
├── Espera: 600s
│
├── Verificação final
│
├── shutdown -h now
│
├── systemd / pve-guests
│
├── shutdown ordenado das 7 VMs
│
└── Host Proxmox desligado
```

O objetivo dos 600 segundos é evitar que o Proxmox consuma a maior parte da bateria antes de começar o encerramento ordenado.

---

# 16. Máquina de estados

```text
┌─────────────────────┐
│ MONITORAMENTO       │
│ NORMAL              │
└──────────┬──────────┘
           │
           │ Sentinela OFF
           ▼
┌─────────────────────┐
│ VERIFICAR ROTEADOR  │
└──────────┬──────────┘
           │
      ┌────┴────┐
      │         │
 Roteador OFF  Roteador ON
      │         │
      ▼         ▼
   CANCELA   CONFIRMAÇÃO
              30 segundos
                  │
            ┌─────┴─────┐
            │           │
      Sentinela ON   Continua OFF
            │           │
            ▼           ▼
         CANCELA     ESPERA
                     600 segundos
                         │
                  ┌──────┴──────┐
                  │             │
            Sentinela ON    Continua OFF
                  │             │
                  ▼             ▼
               CANCELA     VERIFICAÇÃO
                              FINAL
                                │
                          ┌─────┴─────┐
                          │           │
                      Condição     Condição
                      inválida    confirmada
                          │           │
                          ▼           ▼
                       CANCELA     SHUTDOWN
```

---

# 17. Parâmetros do script

A configuração atual é:

```bash
SENTINEL="192.168.0.2"
ROUTER="192.168.0.1"

TEST_NETWORK_FAILURE=false

CHECK_INTERVAL=5
CONFIRM_TIME=30
SHUTDOWN_DELAY=600

SHUTDOWN_ENABLED=true
```

| Parâmetro | Valor | Função |
|---|---:|---|
| `SENTINEL` | `192.168.0.2` | Endereço do sentinela |
| `ROUTER` | `192.168.0.1` | Endereço do roteador de referência |
| `TEST_NETWORK_FAILURE` | `false` | Funcionamento normal |
| `CHECK_INTERVAL` | `5s` | Intervalo entre verificações |
| `CONFIRM_TIME` | `30s` | Confirmação da falha |
| `SHUTDOWN_DELAY` | `600s` | Autonomia reservada |
| `SHUTDOWN_ENABLED` | `true` | Shutdown real habilitado |

Durante desenvolvimento e testes:

```bash
SHUTDOWN_ENABLED=false
```

Durante operação:

```bash
SHUTDOWN_ENABLED=true
```

---

# 18. Condição formal de shutdown

A decisão pode ser representada como:

```text
SHUTDOWN =
    Sentinel OFF
AND Router ON
AND Confirmation >= 30s
AND Autonomy >= 600s
AND Final Sentinel OFF
AND Final Router ON
```

Essa expressão deve ser tratada como o **contrato lógico do monitor**.

Alterações futuras no código devem preservar essa filosofia, salvo se a arquitetura for deliberadamente modificada.

---

# 19. Script

O script para execução da lógica do monitor sentinela deverá estar localizado em:

```text
/usr/local/sbin/nobreak-monitor.sh 
```

Atentar-se para o script ter permissão de execução.

Arquivo:

👉 [nobreak-monitor.sh](../configs/nobreak-monitor.sh)

O script executa continuamente e possui cinco funções principais:

1. monitorar o sentinela;
2. validar o roteador;
3. confirmar a falha;
4. aguardar a autonomia reservada;
5. solicitar o shutdown do host.

### 19.1 Log

```bash
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $*"
}
```

As mensagens são enviadas para a saída padrão e capturadas pelo systemd/journal.

### 19.2 Teste ICMP

```bash
ping -c 1 -W 2 "$1"
```

Significa:

- `-c 1`: um pacote ICMP;
- `-W 2`: aguarda até dois segundos pela resposta.

### 19.3 Simulação de falha

```bash
TEST_NETWORK_FAILURE=true
```

permite simular indisponibilidade de rede sem desligar fisicamente o equipamento.

### 19.4 Proteção contra shutdown acidental

```bash
SHUTDOWN_ENABLED=false
```

executa toda a lógica sem executar:

```bash
/sbin/shutdown -h now
```

Essa configuração deve ser utilizada durante implantação, alteração ou teste do script.

---

# 20. Serviço systemd

O arquivo de configuração do serviço deve estar localizado em:

```text
/etc/systemd/system/nobreak-monitor.service
```

Arquivo:

👉 [nobreak-monitor.service](../configs/nobreak-monitor.service)

### 20.1 Dependência de rede

```ini
After=network-online.target
Wants=network-online.target
```

O serviço depende da inicialização da rede para executar os testes ICMP.

### 20.2 Execução como root

```ini
User=root
```

O usuário root é necessário para permitir a solicitação de shutdown do host.

### 20.3 Reinício

```ini
Restart=no
```

Não existe necessidade de reiniciar o monitor automaticamente após o encerramento normal do processo.

---

# 21. Instalação

## 21.1 Criar o script

```bash
nano /usr/local/sbin/nobreak-monitor.sh
```

Colar o script revisado.

## 21.2 Permissão

```bash
chmod 750 /usr/local/sbin/nobreak-monitor.sh
```

## 21.3 Criar o serviço

```bash
nano /etc/systemd/system/nobreak-monitor.service
```

## 21.4 Recarregar systemd

```bash
systemctl daemon-reload
```

## 21.5 Habilitar no boot

```bash
systemctl enable nobreak-monitor.service
```

## 21.6 Iniciar

```bash
systemctl start nobreak-monitor.service
```

## 21.7 Verificar

```bash
systemctl status nobreak-monitor.service
```

---

# 22. Testes

## 22.1 Teste de conectividade

```bash
ping -c 10 192.168.0.2
ping -c 10 192.168.0.1
```

Ambos devem responder em condição normal.

## 22.2 Teste do serviço

```bash
systemctl status nobreak-monitor.service
```

E:

```bash
journalctl -u nobreak-monitor.service -f
```

O início esperado contém:

```text
Monitor iniciado.
Sentinela: 192.168.0.2
Roteador principal: 192.168.0.1
Intervalo de verificação: 5s
Confirmação de falha: 30s
Tempo até shutdown: 600s
```

## 22.3 Teste sem shutdown real

Usar:

```bash
SHUTDOWN_ENABLED=false
```

O monitor deve executar toda a lógica sem desligar o host.

## 22.4 Teste de perda do sentinela

Desligar somente o D-Link.

O esperado:

```text
ALERTA: sentinela 192.168.0.2 não respondeu.
Roteador 192.168.0.1 responde normalmente.
Condição compatível com perda de energia do sentinela.
```

## 22.5 Teste de recuperação

Religar o sentinela durante a confirmação ou durante a contagem de autonomia.

O shutdown deve ser cancelado.

## 22.6 Teste real

Após todos os testes anteriores:

```bash
SHUTDOWN_ENABLED=true
```

Reiniciar:

```bash
systemctl restart nobreak-monitor.service
```

Confirmar:

```bash
journalctl -u nobreak-monitor.service -f
```

---

# 23. Desligamento das VMs

O script NÃO executa:

```bash
qm shutdown <VMID>
```

para cada guest.

A responsabilidade é dividida:

```text
nobreak-monitor
       │
       │ detecta a condição
       ▼
shutdown do node
       │
       ▼
systemd / pve-guests
       │
       ▼
qmshutdown
       │
       ├── VM 1
       ├── VM 2
       └── VM ...
       │
       ▼
todos os guests parados
       │
       ▼
host continua desligando
```

Essa separação reduz a complexidade do monitor e aproveita o mecanismo nativo do Proxmox.

---

# 24. Validação do shutdown

A implementação foi validada de ponta a ponta.

Após o reboot, foi consultado:

```bash
journalctl -b -1 -u pve-guests --no-pager
```

Foram observados registros de parada das VMs, incluindo tarefas:

```text
qmshutdown:206
qmshutdown:205
qmshutdown:204
qmshutdown:203
qmshutdown:202
qmshutdown:201
qmshutdown:200
```

e:

```text
all VMs and CTs stopped
```

O serviço também terminou corretamente:

```text
pve-guests.service: Deactivated successfully.
pve-guests.service: Stopped
```

A validação confirmou que o monitor não precisa implementar o desligamento individual dos guests.

---

# 25. Validação do journal

O histórico do boot anterior pode ser consultado:

```bash
journalctl -b -1
```

Os registros do monitor confirmaram:

```text
CONDIÇÃO DE FALTA DE ENERGIA CONFIRMADA.
DECISÃO: desligar o node Proxmox.
SHUTDOWN REAL HABILITADO.
Executando shutdown do node Proxmox agora.
```

Também foi observada a transição normal do sistema:

```text
Reached target shutdown.target - Shutdown.
```

e:

```text
Reached target shutdown.target - System Shutdown.
Syncing filesystems and block devices.
Sending SIGTERM to remaining processes...
```

Isso confirma que o comando do monitor iniciou o processo normal de desligamento do host.

---

# 26. Validação do retorno

As VMs configuradas com inicialização automática retornaram após o boot do Proxmox.

O fluxo completo validado foi:

```text
Falta de energia
      ↓
Sentinela OFF
      ↓
Roteador ON
      ↓
30s de confirmação
      ↓
600s de espera
      ↓
Verificação final
      ↓
shutdown do Proxmox
      ↓
pve-guests
      ↓
7 VMs encerradas
      ↓
Host desligado
      ↓
Energia restaurada
      ↓
Host inicia
      ↓
VMs com onboot iniciam novamente
```

---

# 27. Operação e manutenção

## Ver status

```bash
systemctl status nobreak-monitor.service
```

## Ver logs

```bash
journalctl -u nobreak-monitor.service
```

## Acompanhar em tempo real

```bash
journalctl -u nobreak-monitor.service -f
```

## Ver boot anterior

```bash
journalctl -b -1 -u nobreak-monitor.service
```

## Ver processo de VMs

```bash
journalctl -b -1 -u pve-guests --no-pager
```

## Reiniciar

```bash
systemctl restart nobreak-monitor.service
```

## Parar

```bash
systemctl stop nobreak-monitor.service
```

## Habilitar no boot

```bash
systemctl enable nobreak-monitor.service
```

## Desabilitar no boot

```bash
systemctl disable nobreak-monitor.service
```

Depois de alterar o arquivo `.service`:

```bash
systemctl daemon-reload
systemctl restart nobreak-monitor.service
```

Depois de alterar somente o script:

```bash
systemctl restart nobreak-monitor.service
```

---

# 28. Troubleshooting

## 28.1 Sentinela não responde

Testar:

```bash
ping -c 5 192.168.0.2
```

Depois:

```bash
ping -c 5 192.168.0.1
```

Se o roteador responder e o sentinela não, a condição é compatível com a lógica do projeto, mas o equipamento deve ser investigado antes de concluir que houve falta de energia.

## 28.2 Sentinela e roteador não respondem

O monitor deve cancelar a tentativa.

Essa é uma proteção contra falha geral de rede.

## 28.3 Shutdown não ocorre

Verificar:

```bash
systemctl status nobreak-monitor.service
```

Depois:

```bash
journalctl -u nobreak-monitor.service -n 100 --no-pager
```

Confirmar:

```text
Shutdown real habilitado: true
```

## 28.4 Serviço não inicia

Verificar:

```bash
systemctl status nobreak-monitor.service
```

E:

```bash
journalctl -u nobreak-monitor.service -b --no-pager
```

Verificar também:

```bash
ls -l /usr/local/sbin/nobreak-monitor.sh
```

## 28.5 VMs não desligam

Não adicionar imediatamente `qm shutdown` ao script.

Primeiro investigar:

```bash
journalctl -b -1 -u pve-guests --no-pager
```

Verificar também a configuração dos guests e o QEMU Guest Agent quando aplicável.

---

# 29. Segurança operacional

## 29.1 Shutdown desabilitado durante alterações

Durante desenvolvimento:

```bash
SHUTDOWN_ENABLED=false
```

Somente habilitar o shutdown real depois de validar o comportamento.

## 29.2 Não reduzir a confirmação sem motivo

Os 30 segundos protegem contra indisponibilidade transitória.

## 29.3 Não tratar o sentinela como sensor elétrico

O sentinela não mede tensão.

Ele apenas fornece uma evidência indireta:

```text
Sentinela OFF + Roteador ON
```

## 29.4 Não tratar 600 segundos como autonomia garantida

Os 600 segundos são um parâmetro operacional.

A autonomia depende de:

- carga real;
- estado da bateria;
- idade da bateria;
- temperatura;
- eficiência do inversor;
- corrente de descarga;
- comportamento do nobreak.

## 29.5 Reavaliar após troca de bateria

Sempre que a bateria for substituída, o teste de autonomia deve ser repetido.

---

# 30. Limitações

A solução possui as seguintes limitações:

1. Não existe leitura direta do nobreak.
2. O estado da bateria não é conhecido pelo Proxmox.
3. Uma falha do sentinela pode se parecer com uma falta de energia.
4. Uma falha simultânea do sentinela e do roteador cancela o shutdown.
5. A autonomia não é calculada dinamicamente.
6. O valor de 600 segundos foi definido para o cenário atual e deve ser reavaliado se a carga mudar.
7. O consumo real dos equipamentos não foi medido individualmente neste projeto.
8. A autonomia observada de 15m45s foi obtida sem levar a bateria ao limite e, portanto, não representa a autonomia máxima garantida.

---

# 31. Critério para futuras alterações da autonomia

O valor:

```bash
SHUTDOWN_DELAY=600
```

deve ser alterado somente após novo teste.

O procedimento recomendado é:

1. medir a autonomia real;
2. medir o tempo de desligamento das cinco VMs;
3. medir o tempo adicional necessário para o host desligar;
4. adicionar margem;
5. repetir o teste.

A relação conceitual é:

```text
Autonomia observada
        >
tempo de confirmação
        +
tempo de espera configurado
        +
tempo de shutdown dos guests
        +
tempo de shutdown do host
        +
margem de segurança
```

Se essa relação deixar de ser verdadeira, o projeto deve ser reavaliado.

---

# 32. Melhorias futuras

## 32.1 Integração direta com o nobreak

Uma futura integração via NUT, SNMP ou interface equivalente permitiria obter:

- estado da rede;
- estado da bateria;
- percentual;
- tensão;
- carga;
- autonomia estimada;
- evento `ONBATT`;
- evento `LOWBATT`.

Essa seria uma evolução arquitetural, não uma correção necessária da implementação atual.

## 32.2 Medição real de consumo

Instalar um wattímetro na entrada do conjunto permitiria documentar:

```text
Proxmox:       XX W
Roteador:      XX W
ONT:           XX W
Total:         XX W
```

Isso permitiria correlacionar consumo e autonomia com maior precisão.

## 32.3 Mais de um sentinela

Uma evolução poderia utilizar múltiplos dispositivos independentes.

## 32.4 Alertas

O monitor poderia futuramente integrar-se ao sistema de observabilidade para registrar:

- início da falta de energia;
- confirmação;
- cancelamento;
- shutdown iminente;
- duração da interrupção.

---

# 33. Estado atual da implementação

## Hardware

- [x] Intelbras XNB 600 120 V identificado.
- [x] Bateria Moura 12 V / 9 Ah registrada.
- [x] Bateria substituída em 15/04/2026.
- [x] Proxmox identificado.
- [x] TP-Link EX511 identificado.
- [x] Nokia G-1425G-B identificado.
- [x] D-Link DIR-524 configurado como sentinela.
- [x] Separação elétrica entre sentinela e equipamentos protegidos validada.

## Software

- [x] Script instalado.
- [x] Serviço systemd criado.
- [x] Serviço habilitado.
- [x] Monitoramento ICMP validado.
- [x] Confirmação de 30 segundos.
- [x] Espera de 600 segundos.
- [x] Verificação final.
- [x] Cancelamento quando o sentinela retorna.
- [x] Cancelamento quando o roteador deixa de responder.
- [x] `SHUTDOWN_ENABLED` validado.

## Shutdown

- [x] Shutdown real validado.
- [x] Proxmox recebeu corretamente o comando.
- [x] `pve-guests` executou o processo normal.
- [x] 7 VMs/guests foram encerrados.
- [x] Node concluiu o desligamento.
- [x] Journal do boot anterior confirmou a sequência.
- [x] Guests com inicialização automática retornaram após o boot.

## Autonomia

- [x] Bateria atual registrada.
- [x] Teste real realizado.
- [x] Aproximadamente 15m45s observados.
- [x] Teste realizado sem esgotar a bateria.
- [x] Valor operacional atual definido em 600s.
- [x] Margem de autonomia preservada.

---

# 34. Referência rápida

## Arquivos

```text
/usr/local/sbin/nobreak-monitor.sh
/etc/systemd/system/nobreak-monitor.service
```

## Serviço

```bash
systemctl status nobreak-monitor.service
systemctl start nobreak-monitor.service
systemctl stop nobreak-monitor.service
systemctl restart nobreak-monitor.service
systemctl enable nobreak-monitor.service
systemctl disable nobreak-monitor.service
```

## Logs

```bash
journalctl -u nobreak-monitor.service
journalctl -u nobreak-monitor.service -f
journalctl -b -1 -u nobreak-monitor.service
journalctl -b -1 -u pve-guests --no-pager
```

## Parâmetros atuais

```text
Sentinela:             192.168.0.2
Roteador:              192.168.0.1
Verificação:           5 segundos
Confirmação:           30 segundos
Espera/autonomia:      600 segundos
Shutdown real:         habilitado
```

## Equipamentos

```text
Nobreak:       Intelbras XNB 600 120 V
Bateria:       Moura 12 V / 9 Ah
Sentinela:     D-Link DIR-524 → 192.168.0.2
Roteador:      TP-Link EX511 → 192.168.0.1
ONT:           Nokia G-1425G-B
Host:          Beelink Ryzen 7 5800H / 24 GB / 500 GB
Guests:        7
```

## Regra principal

```text
Sentinela OFF
      +
Roteador ON
      +
30s de confirmação
      +
600s de espera
      +
verificação final
      ↓
shutdown do node Proxmox
```

---

# 35. Conclusão

O projeto implementa uma solução simples, de baixa dependência e orientada à segurança para um ambiente Proxmox protegido por um Intelbras XNB 600.

A arquitetura utiliza uma diferença deliberada de alimentação elétrica:

```text
D-Link sentinela
      ↓
fora do nobreak

TP-Link + ONT + Proxmox
      ↓
dentro do nobreak
```

Essa separação permite inferir uma interrupção da rede elétrica sem necessidade de comunicação direta com o nobreak.

A solução não tenta substituir um UPS inteligente. Ela utiliza uma estratégia simples de observação com o que tem disponível, confirmação e espera:

```text
detectar
   ↓
confirmar
   ↓
aguardar
   ↓
verificar novamente
   ↓
desligar
```

O teste real de aproximadamente **15 minutos e 45 segundos** demonstrou que o conjunto possui margem suficiente para a configuração atual de **600 segundos**, sem que a bateria chegasse ao estado de baixa carga observado durante o teste.

O valor de 600 segundos deve continuar sendo tratado como **parâmetro operacional**, e não como autonomia nominal do XNB 600.

A decisão de manter o desligamento das VMs sob responsabilidade do próprio Proxmox também é deliberada. O monitor decide **quando o host deve desligar**; o Proxmox decide **como os guests devem ser encerrados**.

Essa separação mantém o projeto pequeno, compreensível e fácil de manter.

---

# 36. Fontes técnicas externas

As informações de hardware foram separadas das informações obtidas diretamente dos testes do ambiente.

### Intelbras

A documentação oficial do XNB 600 confirma a capacidade de 600 VA, quatro tomadas e a especificação da bateria original de 12 V / 7 Ah.

Fonte: documentação oficial do produto **[Intelbras XNB 600 120 V](https://backend.intelbras.com/sites/default/files/2024-08/XNB%20600%20VA%20-%20Datasheet.pdf)**.

### TP-Link

A documentação oficial do EX511 informa, entre outras características, fonte de alimentação externa de **12 V / 1,5 A**.

Fonte: documentação oficial do produto **[TP-Link EX511](https://service-provider.tp-link.com/br/wifi-router/ex511/#specifications)**.

### Nokia

A ficha técnica oficial do G-1425G-B informa alimentação local de 12 V e consumo inferior a **18 W**.

Fonte: ficha técnica oficial **[Nokia ONT G-1425G-B](https://fccid.io/2ADZRG1425GB/User-Manual/User-Manual-6022243)**.

> **Nota:** valores de potência de fontes/adaptadores são referências de capacidade e não substituem uma medição de consumo real. Para dimensionamento futuro, recomenda-se medir o consumo AC do conjunto com wattímetro.

---

# 37. Princípio de manutenção da documentação

Sempre que houver uma alteração significativa no projeto, atualizar este documento junto com a alteração técnica.

Devem ser revisados especialmente:

- modelo ou bateria do nobreak;
- equipamentos conectados às tomadas;
- endereço do sentinela;
- endereço do roteador;
- quantidade de VMs/CTs;
- tempo de confirmação;
- tempo de autonomia reservado;
- lógica do script;
- comportamento do `pve-guests`;
- tempo real de shutdown;
- testes de autonomia.

A documentação deve continuar representando o **ambiente real**, e não apenas o código.
