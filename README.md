# OpenBSC EGPRS - Réseau GSM Virtuel (NITB) Docker

Ce projet déploie une pile GSM complète (2G) avec GPRS/EGPRS en utilisant **OpenBSC (osmo-nitb)** dans Docker sur base **Ubuntu 18.04**.

> **osmo-nitb** = BSC + MSC + HLR en un seul binaire (architecture monolithique legacy).
> Contrairement à l'architecture moderne split (osmo-bsc + osmo-msc + osmo-hlr + osmo-stp + osmo-mgw).

## ⚡ Démarrage rapide

```bash
# Option 1 : Build local
sudo ./build.sh
sudo ./start.sh

# Option 2 : Pull depuis le registry (si disponible)
sudo docker pull ghcr.io/<user>/openbsc_egprs:main
sudo docker tag ghcr.io/<user>/openbsc_egprs:main openbsc-nitb:latest
sudo ./start.sh
```

**Important :** Changez l'IP `192.168.1.69` dans les configs :
```bash
./set_ip.sh <votre_ip>
```

## 📋 Architecture

```
┌──────────────────────── Docker (Ubuntu 18.04) ──────────────────────────┐
│                                                                         │
│  ┌─────────────────────────────────────────────────────────┐            │
│  │                    osmo-nitb                            │            │
│  │              (BSC + MSC + HLR)                          │            │
│  │              VTY: telnet 4242                           │            │
│  └─────┬───────────────────┬───────────────────────────────┘            │
│        │ Abis/IP           │ Gb/NS-UDP                                  │
│        ▼                   ▼                                            │
│  ┌──────────┐        ┌──────────┐                                       │
│  │osmo-bts  │        │ osmo-pcu │                                       │
│  │  -trx    │◄──────►│ (EGPRS)  │                                       │
│  │ VTY:4241 │        │ VTY:4240 │                                       │
│  └────┬─────┘        └────┬─────┘                                       │
│       │ TRX                │ Gb                                          │
│       ▼                    ▼                                             │
│  ┌──────────┐        ┌──────────┐      ┌──────────┐                     │
│  │fake_trx  │        │osmo-sgsn │─────►│osmo-ggsn │──► Internet         │
│  │(virtuel) │        │ VTY:4245 │ GTP  │ VTY:4260 │                     │
│  └────┬─────┘        └──────────┘      └──────────┘                     │
│       │ L1                                  │                            │
│       ▼                                     │                            │
│  ┌──────────┐                          ┌────┴───┐                        │
│  │ trxcon   │                          │  apn0  │                        │
│  └────┬─────┘                          │ (TUN)  │                        │
│       │ L2                             └────────┘                        │
│       ▼                                                                  │
│  ┌──────────┐                                                            │
│  │ mobile   │                                                            │
│  │ VTY:4247 │                                                            │
│  └──────────┘                                                            │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

## 🚀 Installation & Build

### Prérequis
- Docker (>= 18.x)
- docker-compose (optionnel mais recommandé)

```bash
# Installer Docker si besoin
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
```

### Build
```bash
sudo ./build.sh
# ou directement :
docker build -t openbsc-nitb .
# ou via docker-compose :
docker-compose build
```

Le Dockerfile multi-stage compile dans l'ordre :
1. `libosmocore` → bibliothèque de base
2. `libosmo-abis` → protocole Abis
3. `libosmo-netif` → interface réseau
4. `libosmo-sccp` → signalisation SS7
5. `libsmpp34` → protocole SMPP
6. **`openbsc (osmo-nitb)`** → le cœur BSC+MSC+HLR
7. `osmo-bts` → BTS virtuelle
8. `osmo-trx` → transceiver (fake_trx)
9. `osmo-pcu` → GPRS/EGPRS PCU
10. `osmo-ggsn` → GPRS Gateway
11. `osmo-sgsn` → GPRS SGSN
12. `osmocom-bb` → mobile virtuel (trxcon + mobile)

Puis copie uniquement les binaires et libs dans l'image runtime (légère).

## ▶️ Utilisation

### Démarrer
```bash
sudo ./start.sh
# ou :
docker-compose up -d
```

### Logs
```bash
docker logs -f openbsc-nitb
```

### Shell dans le conteneur
```bash
docker exec -it openbsc-nitb bash
```

### Arrêter
```bash
sudo ./stop.sh
# ou :
docker-compose down
```

## 🛠 Administration VTY (Telnet)

### Ports VTY

| Composant  | Port | Rôle                   |
|------------|------|------------------------|
| osmo-nitb  | 4242 | BSC + MSC + HLR        |
| osmo-bts   | 4241 | Station de base        |
| osmo-pcu   | 4240 | GPRS/EGPRS PCU         |
| osmo-sgsn  | 4245 | Serving GPRS           |
| osmo-ggsn  | 4260 | Gateway GPRS           |
| mobile     | 4247 | Téléphone virtuel      |

### 1. Activer le mobile (allumer le téléphone)
```
telnet 127.0.0.1 4247
> enable
> sim reader 1
> network search
```

### 2. Voir les abonnés (HLR)
```
telnet 127.0.0.1 4242
> enable
> show subscriber all
```

### 3. Envoyer un SMS (MSC)
```
telnet 127.0.0.1 4242
> enable
> subscriber extension <msisdn> sms sender extension 111 send Bonjour!
```

### 4. Vérifier GPRS
```
telnet 127.0.0.1 4245
> show sgsn
> show pdp-context all
```

## 📻 Pour Linphone (SIP)

Account assistant → Use an SIP Account :
- IP : votre_ip
- User : myuser
- Pass : tester

## 📁 Structure du projet

```
openbsc_egprs/
├── .github/
│   └── workflows/
│       └── docker-build.yml  # CI/CD GitHub Actions
├── configs/
│   ├── openbsc.cfg           # OpenBSC (osmo-nitb) - BSC+MSC+HLR
│   ├── osmo-bts-trx.cfg      # BTS virtuelle
│   ├── osmo-trx.cfg          # Transceiver virtuel
│   ├── osmo-pcu.cfg          # GPRS/EGPRS PCU
│   ├── osmo-ggsn.cfg         # GPRS Gateway
│   └── osmo-sgsn.cfg         # GPRS SGSN
├── scripts/
│   └── entrypoint.sh         # Point d'entrée Docker
├── Dockerfile                 # Multi-stage build (Ubuntu 18.04)
├── docker-compose.yml         # Orchestration
├── build.sh                   # Wrapper build
├── start.sh                   # Wrapper start
├── stop.sh                    # Wrapper stop
├── set_ip.sh                  # Mise à jour IP
├── calypso.sh                 # Support téléphone Calypso
└── README.md
```

## 📊 Différences avec le projet osmo_egprs original

| Aspect                  | osmo_egprs (original)          | Ce projet                      |
|-------------------------|--------------------------------|--------------------------------|
| Architecture réseau     | Split (osmo-bsc/msc/hlr/stp)  | Monolithique (osmo-nitb)       |
| Nombre de binaires      | 8+ (bsc, msc, hlr, stp, mgw…) | 1 principal (osmo-nitb)        |
| HLR                     | osmo-hlr séparé                | SQLite intégré                 |
| Base image Docker       | Debian récent                  | Ubuntu 18.04 (Bionic)          |
| Complexité              | Élevée                         | Faible                         |
| Port VTY principal      | 4254 (MSC) + 4258 (HLR)       | 4242 (tout-en-un)             |
| Maintenance upstream    | Active                         | Archivée (legacy)              |

## ⚠️ Notes

- **OpenBSC est un projet archivé** par Osmocom. Pour la production, utilisez l'architecture split.
- Le conteneur tourne en mode **privileged** (nécessaire pour TUN/TAP et iptables).
- La policy d'auth est `accept-all` — tout IMSI est accepté automatiquement.
- EGPRS utilise les timeslots 5, 6, 7 configurés en PDCH.
- Les données HLR sont persistées dans le volume Docker `openbsc-data`.
