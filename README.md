<!---
# ===========================================================================
Projeto..........: proxmox-monitor-sentinela
Versão...........: 1.0.0
Autor............: Glauber GF (mcnd2)
Data.............: 16-08-2026
Atualizado.......: 06-09-2026
Descrição........: Documentação técnica completa do projeto de monitoramento de falta de energia para um host Proxmox protegido por um nobreak, utilizando um equipamento externo ao nobreak como sentinela por comunicação de rede.
# ===========================================================================
-->

# Proxmox Monitor Sentinela

Monitoramento de falta de energia para um host **Proxmox** protegido por um **Intelbras XNB 600 120 V**, utilizando um equipamento externo ao nobreak como sentinela.

![Image](https://github.com/glaubergf/proxmox-nobreak-monitor/blob/main/images/sentinela.png)

## Como funciona

- **Sentinela:** D-Link DIR-524 — `192.168.0.2` — fora do nobreak.
- **Roteador:** TP-Link EX511 — `192.168.0.1` — alimentado pelo nobreak.

```text
Sentinela indisponível
        +
Roteador disponível
        ↓
confirmação: 30s
        ↓
espera: 600s
        ↓
verificação final
        ↓
shutdown do Proxmox
        ↓
pve-guests → 7 VMs/guests
```

O monitor decide **quando** desligar o host; o Proxmox permanece responsável por **como** desligar ordenadamente as VMs.

## Arquivos principais

```text
/usr/local/sbin/nobreak-monitor.sh
/etc/systemd/system/nobreak-monitor.service
```

## Configuração atual

```text
Intervalo de verificação: 5s
Confirmação da falha:     30s
Espera antes do shutdown: 600s
Shutdown real:            habilitado
```

## Documentação técnica completa

Para arquitetura, hardware, instalação, configuração, lógica do script, testes, autonomia, troubleshooting e manutenção:

**[📖 Documentação técnica completa — `proxmox-monitor-sentinela.md`](notes/proxmox-monitor-sentinela.md)**

## Estado

Projeto operacional e validado no ambiente atual.

Alterações de hardware, bateria, quantidade de VMs ou parâmetros do monitor devem ser refletidas na documentação técnica completa.
