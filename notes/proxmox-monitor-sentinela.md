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

Documento técnico de referência, implementação, operação e manutenção.

## 1. Visão geral

Este projeto implementa um mecanismo simples e conservador para proteger um ambiente Proxmox durante uma falta prolongada de energia.

O cenário utiliza um Intelbras XNB 600 120 V, sem interface de gerenciamento utilizada pelo Proxmox. A solução usa dois equipamentos com alimentações elétricas diferentes: um D-Link DIR-524 como sentinela, fora do nobreak, e um TP-Link EX511 como referência de rede protegida, dentro do nobreak.

A condição usada como evidência de falta de energia é:

```text
Sentinela indisponível
        +
Roteador principal disponível
```

Essa condição deve permanecer por 30 segundos. Depois disso, o monitor aguarda 600 segundos (10 minutos) e realiza uma verificação final. Somente se a condição continuar válida o Proxmox recebe uma solicitação normal de shutdown.

O monitor não executa `qm shutdown` individualmente. O encerramento dos guests permanece sob responsabilidade do mecanismo nativo do Proxmox.

## 2. Arquitetura

```text
                         REDE ELÉTRICA
                               │
                  ┌────────────┴────────────┐
                  │                         │
                  ▼                         ▼
           TOMADA DIRETA                 NOBREAK
                  │                  Intelbras XNB 600
                  ▼                         │
          D-Link DIR-524                    ├── Proxmox
          192.168.0.2                       ├── TP-Link EX511
          SENTINELA                         │    192.168.0.1
                                            └── Nokia G-1425G-B
```

Ponto crítico:

```text
Sentinela = fora do nobreak
Roteador  = dentro do nobreak
Proxmox   = dentro do nobreak
```

A rede utilizada é `192.168.0.0/24`.

| IP | Equipamento | Função |
|---|---|---|
| `192.168.0.1` | TP-Link EX511 | Roteador de referência |
| `192.168.0.2` | D-Link DIR-524 | Sentinela |

O XNB 600 não fornece ao Proxmox informações como `ONBATT`, `LOWBATT`, percentual de bateria ou autonomia restante. A separação elétrica permite inferir uma falta de energia.

## 3. Lógica de decisão

```text
                    ┌──────────────┐
                    │ MONITORANDO  │
                    └──────┬───────┘
                           │
                    Sentinela OFF?
                           │
                    ┌──────┴──────┐
                   NÃO            SIM
                    │              │
                    └────────      ▼
                              Roteador ON?
                              │
                         ┌────┴────┐
                        NÃO       SIM
                         │          │
                      CANCELA   CONFIRMA 30s
                                    │
                           Sentinela voltou?
                              │          │
                             SIM        NÃO
                              │          │
                           CANCELA   ESPERA 600s
                                         │
                                Verificação final
                                         │
                              ┌──────────┴──────────┐
                         condição inválida     condição válida
                              │                     │
                           CANCELA               SHUTDOWN
```

Contrato lógico:

```text
SHUTDOWN =
    Sentinel OFF
    AND Router ON
    AND Confirmation >= 30s
    AND Delay >= 600s
    AND Final Sentinel OFF
    AND Final Router ON
```

Se sentinela e roteador ficarem indisponíveis simultaneamente, o monitor adota comportamento conservador e não executa shutdown.

## 4. Temporização

```text
CHECK_INTERVAL = 5s
CONFIRM_TIME   = 30s
SHUTDOWN_DELAY = 600s
```

Linha do tempo:

```text
T0
│
├── Sentinela deixa de responder
├── Roteador continua respondendo
├── Confirmação por 30s
├── Falha confirmada
├── Espera 600s
├── Verificação final
├── shutdown do host
├── systemd / pve-guests
├── encerramento ordenado dos 7 guests
└── Host Proxmox desligado
```

`SHUTDOWN_DELAY=600` representa uma margem operacional, e não uma autonomia nominal do nobreak.

## 5. Ambiente de referência

### Nobreak

**Intelbras XNB 600 120 V**

- 600 VA.
- Quatro tomadas.
- Saída nominal de 120 V.
- Bateria original: 12 V / 7 Ah.
- DC Start.
- Restart automático.
- Proteções contra sobrecarga, curto-circuito, sobreaquecimento, sub/sobretensão e descarga total/sobrecarga.

### Bateria instalada

```text
Fabricante: Moura
Tensão:     12 V
Capacidade: 9 Ah
Troca:      15/04/2026
```

### Cargas

| Tomada | Equipamento |
|---|---|
| 1 | Mini PC com Proxmox |
| 2 | TP-Link EX511 |
| 3 | Nokia G-1425G-B |
| 4 | Livre |

### Proxmox

- Beelink.
- AMD Ryzen 7 5800H.
- 8 núcleos / 16 threads.
- 24 GB DDR4.
- 8 GB de swap.
- SSD M.2 2280 de 500 GB.
- 7 VMs/guests.

O monitor solicita o shutdown do host e não administra as VMs individualmente.

### TP-Link EX511

```text
IP:       192.168.0.1
Hardware: EX511 V2.0
Firmware: 0.7.0 3.0.0 v607e.0 Build 240930 Rel.11206n
```

A fonte é especificada em 12 V / 1,5 A. Isso representa a capacidade nominal da fonte, não o consumo contínuo real.

### Nokia G-1425G-B

É alimentada pelo nobreak e mantém a conectividade externa durante a autonomia. A documentação possui variantes de alimentação local em 12 V e detalhes de fonte de 12 V / 1,5 A. Para dimensionamento preciso, deve-se medir a entrada AC.

### D-Link DIR-524 L1

```text
IP LAN:      192.168.0.2
Máscara:     255.255.255.0
Firmware:    9.01
DHCP:        desativado
Wireless:    desativado
Conexão:     LAN → LAN
Alimentação: rede elétrica, fora do nobreak
```

## 6. Configuração

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
| `SENTINEL` | `192.168.0.2` | IP do sentinela |
| `ROUTER` | `192.168.0.1` | IP do roteador |
| `TEST_NETWORK_FAILURE` | `false` | Operação normal |
| `CHECK_INTERVAL` | `5s` | Intervalo entre verificações |
| `CONFIRM_TIME` | `30s` | Confirmação da falha |
| `SHUTDOWN_DELAY` | `600s` | Margem antes do shutdown |
| `SHUTDOWN_ENABLED` | `true` | Shutdown real habilitado |

Durante testes:

```bash
SHUTDOWN_ENABLED=false
```

## 7. Arquivos e serviço

Script:

```text
/usr/local/sbin/nobreak-monitor.sh
```

Serviço:

```text
/etc/systemd/system/nobreak-monitor.service
```

Arquivos versionados:

```text
configs/nobreak-monitor.sh
configs/nobreak-monitor.service
```

Instalação:

```bash
chmod 750 /usr/local/sbin/nobreak-monitor.sh
systemctl daemon-reload
systemctl enable nobreak-monitor.service
systemctl start nobreak-monitor.service
systemctl status nobreak-monitor.service
```

Após alterações:

```bash
systemctl daemon-reload
systemctl restart nobreak-monitor.service
```

## 8. Testes

### Conectividade

```bash
ping -c 10 192.168.0.2
ping -c 10 192.168.0.1
```

### Serviço e logs

```bash
systemctl status nobreak-monitor.service
journalctl -u nobreak-monitor.service -f
```

### Simulação sem shutdown

Use:

```bash
SHUTDOWN_ENABLED=false
systemctl restart nobreak-monitor.service
```

Desligue somente o sentinela, mantendo o Proxmox e o roteador ligados.

Esperado:

```text
Sentinela OFF
Roteador ON
→ confirmação
→ espera
→ verificação final
```

Religar o sentinela durante a confirmação ou espera deve cancelar o shutdown.

### Teste end-to-end

Depois dos testes sem shutdown, pode ser feito teste real controlado.

Antes:

1. confirmar os 7 guests;
2. confirmar o sentinela fora do nobreak;
3. confirmar o roteador no nobreak;
4. confirmar o serviço ativo;
5. confirmar a bateria em boas condições;
6. garantir que não existam tarefas críticas;
7. manter acesso local.

## 9. Encerramento das VMs

O monitor não executa:

```bash
qm shutdown <VMID>
```

para cada guest.

Ele solicita o desligamento normal do host. O Proxmox utiliza o mecanismo nativo, especialmente `pve-guests`, para conduzir o encerramento.

Verificação:

```bash
journalctl -b -1 -u pve-guests --no-pager
```

O shutdown foi validado no ambiente real: 7 VMs/guests foram encerrados, o host executou shutdown normal, o journal confirmou o processo e os guests configurados com `onboot` retornaram após a restauração da energia.

## 10. Operação e manutenção

```bash
systemctl status nobreak-monitor.service
systemctl start nobreak-monitor.service
systemctl stop nobreak-monitor.service
systemctl restart nobreak-monitor.service
systemctl enable nobreak-monitor.service
systemctl disable nobreak-monitor.service
```

Logs:

```bash
journalctl -u nobreak-monitor.service
journalctl -u nobreak-monitor.service -f
journalctl -b -1 -u nobreak-monitor.service
journalctl -b -1 -u pve-guests --no-pager
```

## 11. Troubleshooting

### Sentinela não responde

```bash
ping -c 10 192.168.0.2
```

Verificar alimentação, cabo, IP, DHCP desativado, conexão LAN → LAN e se o equipamento está realmente fora do nobreak.

### Roteador não responde

```bash
ping -c 10 192.168.0.1
```

O monitor deve evitar shutdown porque não consegue distinguir com segurança falha de rede de falta de energia.

### Serviço não inicia

```bash
systemctl status nobreak-monitor.service
journalctl -u nobreak-monitor.service -n 100 --no-pager
```

Verificar sintaxe, permissões, caminhos e configuração.

### Shutdown inesperado

```bash
journalctl -b -1 -u nobreak-monitor.service --no-pager
journalctl -b -1 -u pve-guests --no-pager
```

Procurar a sequência:

```text
Sentinela OFF
Roteador ON
confirmação
espera
verificação final
shutdown
```

## 12. Autonomia

Teste real com:

- XNB 600 120 V;
- bateria Moura 12 V / 9 Ah;
- Proxmox;
- 7 VMs/guests;
- TP-Link EX511;
- Nokia G-1425G-B;
- sentinela fora do nobreak.

Resultado observado:

```text
≈ 15 minutos e 45 segundos
```

O teste foi interrompido antes do esgotamento da bateria. Portanto, é autonomia observada, não autonomia máxima garantida.

Energia nominal teórica:

```text
12 V × 9 Ah = 108 Wh
```

A energia útil na saída AC é menor devido a perdas do inversor, fontes dos equipamentos, corrente de descarga, temperatura, estado da bateria e tensão de corte.

O valor de 600 segundos foi escolhido como margem operacional:

```text
15m45s = 945s
945s - 600s = 345s
≈ 5m45s
```

Essa diferença não é uma garantia absoluta porque ainda existe o tempo de confirmação, encerramento dos guests e desligamento do host.

O valor atual deve ser mantido enquanto carga e bateria permanecerem compatíveis com o teste.

## 13. Consumo elétrico

É importante distinguir:

```text
Potência nominal da fonte
        ≠
Consumo real do equipamento
```

Exemplo:

```text
12 V × 1,5 A = 18 W
```

representa a capacidade nominal de uma fonte de 12 V / 1,5 A, não consumo contínuo.

Para dimensionamento preciso, utilizar wattímetro na entrada AC.

## 14. Limitações

O monitor não sabe diretamente:

- percentual da bateria;
- tensão;
- corrente;
- autonomia restante;
- estado `ONBATT`;
- estado `LOWBATT`.

Se o sentinela falhar independentemente, poderá haver falso positivo. A confirmação pelo roteador e os temporizadores reduzem esse risco, mas não eliminam a dependência.

Se sentinela e roteador ficarem indisponíveis, o monitor adota comportamento conservador.

O valor de 600 segundos deve ser reavaliado após troca da bateria, alteração da carga, inclusão/remoção de equipamentos ou mudança significativa no consumo.

## 15. Melhorias futuras

### NUT / SNMP

Permitir leitura direta de estado da alimentação, bateria, tensão, autonomia, `ONBATT` e `LOWBATT`.

### Medição com wattímetro

Medir consumo normal, idle, carga, conjunto completo e comportamento durante autonomia.

### Múltiplos sentinelas

Reduzir a dependência de um único equipamento.

### Observabilidade

Integração futura com Zabbix, Prometheus, Grafana, syslog ou e-mail.

## 16. Estado atual

| Item | Estado |
|---|---|
| Detecção por sentinela | OK |
| Referência pelo roteador | OK |
| Confirmação de 30s | OK |
| Espera de 600s | OK |
| Verificação final | OK |
| Shutdown do Proxmox | OK |
| Encerramento dos 7 guests | OK |
| Registro no journal | OK |
| Retorno dos guests com `onboot` | OK |
| Teste de autonomia | Realizado |
| Medição AC com wattímetro | Futuro |
| Integração direta com UPS | Futuro |

## 17. Referência rápida

Arquivos:

```text
/usr/local/sbin/nobreak-monitor.sh
/etc/systemd/system/nobreak-monitor.service
```

Configuração:

```text
Sentinela:       192.168.0.2
Roteador:        192.168.0.1
Confirmação:     30s
Espera:          600s
Shutdown:        habilitado
```

Comandos:

```bash
systemctl status nobreak-monitor.service
systemctl restart nobreak-monitor.service
journalctl -u nobreak-monitor.service -f
journalctl -b -1 -u nobreak-monitor.service --no-pager
journalctl -b -1 -u pve-guests --no-pager
```

Critério de shutdown:

```text
Sentinela OFF
+
Roteador ON
+
30s de confirmação
+
600s de espera
+
Sentinela OFF na verificação final
+
Roteador ON na verificação final
```

## 18. Referências técnicas

- Repositório: https://github.com/glaubergf/proxmox-nobreak-monitor
- Script: `configs/nobreak-monitor.sh`
- Serviço: `configs/nobreak-monitor.service`
- Intelbras XNB 600: https://www.intelbras.com/pt-br/nobreak-interativo-monovolt-xnb-600-va
- Manual Intelbras XNB: https://backend.intelbras.com/sites/default/files/2021-07/Manual_Nobreak_XNB_600_720_1200_1440_1800_VA_01-21_site.pdf
- TP-Link EX511: https://www.tp-link.com/br/home-networking/wifi-router/ex511/
- Beelink SER5 Ryzen 7 5800H: https://www.bee-link.com.cn/cms/support/driverhardware?product_id=116
- AMD Ryzen 7 5800H - especificações técnicas: https://www.amd.com/pt/support/downloads/drivers.html/processors/ryzen/ryzen-5000-series/amd-ryzen-7-5800h.html

## Conclusão

O monitor sentinela fornece uma solução simples para um nobreak sem telemetria integrada ao Proxmox.

A segurança da decisão vem da combinação de separação elétrica entre sentinela e nobreak, confirmação pelo roteador protegido, confirmação temporal de 30 segundos, espera operacional de 600 segundos, verificação final, shutdown normal do Proxmox e encerramento dos guests pelo mecanismo nativo.

A solução foi testada no ambiente real e demonstrou capacidade de conduzir o encerramento ordenado do Proxmox e de seus 7 guests.

Enquanto o nobreak permanecer sem telemetria, `SHUTDOWN_DELAY=600` deve ser tratado como margem operacional baseada no teste realizado, e não como medição dinâmica da autonomia restante.
