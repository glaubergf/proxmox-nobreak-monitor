# 📡 Proxmox Monitor Sentinela

![Image](https://github.com/glaubergf/proxmox-nobreak-monitor/blob/main/images/sentinela.png)

Monitoramento de falta de energia para um host Proxmox protegido por um **Intelbras XNB 600 120 V**, utilizando um equipamento externo ao nobreak como sentinela através da rede.

O projeto detecta indiretamente uma interrupção da rede elétrica, confirma a condição durante um período determinado e, caso a falta de energia persista, solicita o **shutdown ordenado do host Proxmox**.

O encerramento das VMs/CTs permanece sob responsabilidade do mecanismo nativo do Proxmox.

---

## ✨ Recursos

- 🔌 Detecção indireta de falta de energia através de equipamento sentinela;
- 📡 Monitoramento via ICMP;
- 🛡️ Validação adicional através do roteador protegido pelo nobreak;
- ⏱️ Confirmação temporal da falha;
- ⏳ Reserva de autonomia antes do desligamento;
- 🔄 Cancelamento automático caso a energia seja restabelecida;
- 🔍 Verificação final antes do shutdown;
- 🖥️ Shutdown ordenado do host Proxmox;
- 🧩 Integração com `systemd`;
- 📝 Registro de eventos no `journal`;
- 🧪 Modo de teste sem executar shutdown real;
- 🔒 Proteção contra desligamentos provocados por falhas gerais de rede.

O projeto utiliza Bash, systemd e ferramentas nativas do Linux, mantendo a implementação simples e com poucas dependências.

---

## ⚡ Como funciona

A arquitetura utiliza dois equipamentos com alimentação elétrica diferente:

```text
                         REDE ELÉTRICA
                              │
                 ┌────────────┴────────────┐
                 │                         │
                 ▼                         ▼
          TOMADA DIRETA                 NOBREAK
                 │                   Intelbras XNB 600
                 │                         │
                 ▼                         ├── Proxmox
           D-Link DIR-524                  │
           192.168.0.2                     ├── TP-Link EX511
           SENTINELA                       │    192.168.0.1
                                           │
                                           └── Nokia G-1425G-B
```

A condição utilizada como evidência de falta de energia é:

```text
Sentinela OFF
      +
Roteador ON
      ↓
Confirmação por 30s
      ↓
Espera de 600s
      ↓
Verificação final
      ↓
Shutdown do Proxmox
```

Se o sentinela e o roteador ficarem indisponíveis simultaneamente, o shutdown é cancelado para evitar desligamentos provocados por uma falha geral de rede.

---

## 🧠 Regra de decisão

```text
SENTINELA OFF
      +
ROTEADOR ON
      +
CONFIRMAÇÃO ≥ 30s
      +
ESPERA = 600s
      +
VERIFICAÇÃO FINAL
      ↓
SHUTDOWN DO NODE PROXMOX
```

Durante a espera, se o sentinela voltar a responder, o processo é cancelado.

Se o roteador deixar de responder, o processo também é cancelado.

---

## 🖥️ Shutdown das VMs

O monitor não executa individualmente:

```bash
qm shutdown <VMID>
```

Ele solicita o desligamento normal do host:

```bash
shutdown -h now
```

A partir daí, o mecanismo nativo do Proxmox assume o encerramento dos guests através do `pve-guests`.

```text
nobreak-monitor
      │
      ▼
shutdown do node
      │
      ▼
systemd / pve-guests
      │
      ▼
VMs / CTs
      │
      ▼
Host Proxmox desligado
```

Essa separação mantém o monitor simples e evita duplicar a lógica de gerenciamento de VMs.

---

# 🔧 Ambiente de referência

## Nobreak

| Item | Informação |
|---|---|
| Modelo | Intelbras XNB 600 120 V |
| Capacidade | 600 VA |
| Bateria original | 12 V / 7 Ah |
| Bateria instalada no ambiente | Moura 12 V / 9 Ah |
| Substituição | 15/04/2026 |

O XNB 600 não possui, neste projeto, uma interface de gerenciamento utilizada pelo Proxmox para fornecer diretamente informações como `ONBATT`, percentual da bateria ou autonomia restante.

## Host Proxmox

| Item | Especificação |
|---|---|
| Hardware | mini PC Beelink SER5 |
| CPU | AMD Ryzen 7 5800H |
| CPU | 8 cores / 16 threads |
| RAM | 24 GB DDR4 |
| Storage | SSD M.2 500 GB |
| Guests | 7 VMs/CTs |

## Rede protegida

| Equipamento | IP | Alimentação |
|---|---|---|
| TP-Link EX511 | `192.168.0.1` | Nobreak |
| Nokia G-1425G-B | — | Nobreak |
| Proxmox | — | Nobreak |

## Sentinela

| Item | Informação |
|---|---|
| Modelo | D-Link DIR-524 |
| IP | `192.168.0.2` |
| Alimentação | Rede elétrica |
| Nobreak | **Não** |

A separação elétrica entre o sentinela e os equipamentos protegidos é o elemento fundamental da arquitetura.

---

# ⚙️ Configuração

Configuração utilizada no ambiente de referência:

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
| `ROUTER` | `192.168.0.1` | Roteador de referência |
| `TEST_NETWORK_FAILURE` | `false` | Funcionamento normal |
| `CHECK_INTERVAL` | `5s` | Intervalo das verificações |
| `CONFIRM_TIME` | `30s` | Confirmação da falha |
| `SHUTDOWN_DELAY` | `600s` | Espera antes do shutdown |
| `SHUTDOWN_ENABLED` | `true` | Shutdown real habilitado |

Durante testes:

```bash
SHUTDOWN_ENABLED=false
```

Durante operação:

```bash
SHUTDOWN_ENABLED=true
```

---

# 📁 Estrutura

```text
├── configs
│   ├── nobreak-monitor.service
│   └── nobreak-monitor.sh
├── images
│   └── sentinela.png
├── notes
│   └── proxmox-monitor-sentinela.md
└── README.md
```

Arquivos instalados no Proxmox:

```text
/usr/local/sbin/nobreak-monitor.sh
/etc/systemd/system/nobreak-monitor.service
```

---

# 🚀 Instalação

## 1. Instalar o script

```bash
nano /usr/local/sbin/nobreak-monitor.sh
```

Copie o conteúdo de:

```text
configs/nobreak-monitor.sh
```

Aplique a permissão:

```bash
chmod 750 /usr/local/sbin/nobreak-monitor.sh
```

## 2. Criar o serviço systemd

```bash
nano /etc/systemd/system/nobreak-monitor.service
```

Copie o conteúdo de:

```text
configs/nobreak-monitor.service
```

## 3. Recarregar o systemd

```bash
systemctl daemon-reload
```

## 4. Habilitar no boot

```bash
systemctl enable nobreak-monitor.service
```

## 5. Iniciar

```bash
systemctl start nobreak-monitor.service
```

## 6. Verificar

```bash
systemctl status nobreak-monitor.service
```

---

# 🧪 Testes

Antes de habilitar o shutdown real, recomenda-se executar os testes com:

```bash
SHUTDOWN_ENABLED=false
```

### Testar conectividade

```bash
ping -c 10 192.168.0.2
ping -c 10 192.168.0.1
```

### Verificar o serviço

```bash
systemctl status nobreak-monitor.service
```

### Acompanhar o log

```bash
journalctl -u nobreak-monitor.service -f
```

### Simular perda do sentinela

Desligue somente o equipamento sentinela.

O comportamento esperado é:

```text
Sentinela não responde
        +
Roteador responde
        ↓
Condição compatível com falta de energia
```

### Testar recuperação

Religue o sentinela durante a confirmação ou durante a espera de 600 segundos.

O shutdown deverá ser cancelado.

---

# 🔋 Autonomia

A bateria atualmente instalada no ambiente de referência é:

```text
Moura
12 V / 9 Ah
```

Capacidade nominal teórica:

```text
12 V × 9 Ah = 108 Wh
```

Esse valor não representa a energia efetivamente disponível na saída AC do nobreak, devido às perdas do inversor, das fontes dos equipamentos e às características da descarga da bateria.

## Teste real

Foi realizado um teste com:

- Intelbras XNB 600 120 V;
- bateria Moura 12 V / 9 Ah;
- Proxmox em operação;
- 7 VMs/CTs;
- TP-Link EX511;
- Nokia G-1425G-B;
- sentinela fora do nobreak.

Resultado observado:

```text
≈ 15 minutos e 45 segundos
```

O teste foi encerrado antes do esgotamento da bateria e, portanto, não representa a autonomia máxima do conjunto.

### Margem operacional

O projeto utiliza:

```bash
SHUTDOWN_DELAY=600
```

ou:

```text
10 minutos
```

Esse valor representa uma margem operacional reservada e não uma afirmação de que o nobreak possui exatamente 10 minutos de autonomia.

---

# 🛠️ Operação e manutenção

### Status

```bash
systemctl status nobreak-monitor.service
```

### Iniciar

```bash
systemctl start nobreak-monitor.service
```

### Parar

```bash
systemctl stop nobreak-monitor.service
```

### Reiniciar

```bash
systemctl restart nobreak-monitor.service
```

### Habilitar no boot

```bash
systemctl enable nobreak-monitor.service
```

### Desabilitar no boot

```bash
systemctl disable nobreak-monitor.service
```

### Logs

```bash
journalctl -u nobreak-monitor.service
```

### Logs em tempo real

```bash
journalctl -u nobreak-monitor.service -f
```

### Logs do boot anterior

```bash
journalctl -b -1 -u nobreak-monitor.service
```

### Verificar shutdown dos guests

```bash
journalctl -b -1 -u pve-guests --no-pager
```

---

# 🔍 Troubleshooting

## Sentinela não responde

```bash
ping -c 5 192.168.0.2
```

Depois:

```bash
ping -c 5 192.168.0.1
```

Se somente o sentinela não responder, investigue o equipamento e sua alimentação.

## Sentinela e roteador não respondem

O monitor deverá cancelar a tentativa de shutdown.

Essa é uma proteção contra falha geral de rede.

## Shutdown não ocorre

Verifique:

```bash
systemctl status nobreak-monitor.service
```

E:

```bash
journalctl -u nobreak-monitor.service -n 100 --no-pager
```

Confirme também:

```text
SHUTDOWN_ENABLED=true
```

## Serviço não inicia

```bash
systemctl status nobreak-monitor.service
```

```bash
journalctl -u nobreak-monitor.service -b --no-pager
```

Verifique a permissão:

```bash
ls -l /usr/local/sbin/nobreak-monitor.sh
```

---

# ⚠️ Limitações

O projeto possui algumas limitações importantes:

- Não existe leitura direta do estado do nobreak;
- O Proxmox não conhece diretamente o percentual da bateria;
- A autonomia não é calculada dinamicamente;
- O sentinela pode apresentar uma falha independente;
- Falhas simultâneas do sentinela e roteador cancelam o shutdown;
- Alterações significativas na carga exigem reavaliação;
- O consumo individual dos equipamentos deve ser medido por wattímetro para dimensionamento preciso;
- O teste de 15m45s representa apenas a autonomia observada nas condições daquele teste.

---

# 🔮 Melhorias futuras

Caso seja possível, o projeto poderá evoluir com:

- 🔌 Integração direta com o nobreak através de **NUT, SNMP ou interface equivalente**;
- ⚡ Medição individual do consumo com wattímetro;
- 📡 Utilização de múltiplos sentinelas;
- 📊 Integração com sistema de observabilidade;
- 🔔 Alertas para início e término da falta de energia;
- ⏱️ Registro da duração efetiva das interrupções;
- 🔋 Monitoramento direto de tensão, carga e autonomia da bateria.

>Nota: Uma integração direta com NUT/SNMP permitiria obter informações como estado do nobreak, bateria, carga e autonomia estimada, reduzindo a dependência da inferência por sentinela.

---

# 📖 Documentação técnica

📖 [Documentação técnica completa](https://github.com/glaubergf/proxmox-nobreak-monitor/blob/main/notes/proxmox-monitor-sentinela.md)

Ela contém:

- arquitetura;
- hardware;
- lógica de detecção;
- máquina de estados;
- script;
- serviço systemd;
- testes;
- autonomia;
- troubleshooting;
- manutenção;
- critérios para futuras melhorias.

---

## 📜 Licença

Este projeto está licenciado sob os termos da **GNU General Public License v3.0 (GPLv3)**.

[GNU GPLv3](https://www.gnu.org/licenses/gpl-3.0.html)

### 🏛️ Aviso Legal

```text
Copyright (c) 2026 Glauber GF (mcnd2)

Este programa é software livre: você pode redistribuí-lo e/ou modificá-lo
sob os termos da Licença Pública Geral GNU conforme publicada pela
Free Software Foundation, na versão 3 da Licença.

Este programa é distribuído na esperança de que seja útil,
mas SEM NENHUMA GARANTIA; sem mesmo a garantia implícita de
COMERCIALIZAÇÃO ou ADEQUAÇÃO A UM DETERMINADO FIM.

Veja a GNU General Public License para mais detalhes.

Você deve ter recebido uma cópia da Licença Pública Geral GNU
junto com este programa. Caso contrário, consulte:

https://www.gnu.org/licenses/
```
