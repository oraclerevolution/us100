# US100 — Expert Advisor MQL5

Stratégie intraday automatisée pour le NASDAQ 100 (US100 / NAS100 / USTEC) sur
MetaTrader 5.

**Principe** : on ne trade que dans le sens de la tendance horaire, pendant la
séance cash de New York, et uniquement quand un repli vient d'être rejeté.
Taille de position dérivée d'un pourcentage d'équité et de l'ATR, flat en fin de
séance.

> ⚠️ Aucun paramètre n'a été optimisé ni validé sur données réelles. Les valeurs
> par défaut sont des points de départ raisonnables. Lis `docs/BACKTEST.md` avant
> d'envisager le réel.

---

## Installation

1. Dans MetaTrader 5 : **Fichier → Ouvrir le dossier de données**
2. Copier les fichiers :

```
MQL5/Include/US100/     ->  <dossier de données>/MQL5/Include/US100/
MQL5/Experts/US100/     ->  <dossier de données>/MQL5/Experts/US100/
```

3. Ouvrir MetaEditor (F4), ouvrir `US100_NY_TrendPullback.mq5`, compiler (F7).
4. Dans MT5 : rafraîchir le Navigateur, glisser l'EA sur un graphique **US100 en M5**.
5. Autoriser le trading algorithmique.

Au démarrage, l'EA logue les spécifications du symbole et la fenêtre de session
qu'il a calculée :

```
[init] US100 digits=1 point=0.10000 tickVal=0.10000 ptVal/lot=0.10000 lots[0.10..100.00 step 0.10] stopsLvl=0 freezeLvl=0
[session] window 16:30-23:00 server (warmup 15m, cutoff 30m) (mode=New York)
[init] US100_NY_TrendPullback v1.0.0 ready. Session 16:30-23:00 server (warmup 15m, cutoff 30m). Server time now 2026.11.09 14:02:11.
[init] risk 0.50%/trade, TP 2.00R, max 3 trades/day, day stop 2.00%
```

**Vérifie cette ligne `[session]`.** Si la fenêtre ne correspond pas à l'ouverture
réelle du cash US chez ton broker, corrige `InpBrokerGmtWinter` /
`InpBrokerGmtSummer`. Voir `docs/STRATEGY.md` §4.

---

## Structure

```
MQL5/
├── Experts/US100/
│   └── US100_NY_TrendPullback.mq5   EA principal : inputs et orchestration
└── Include/US100/
    ├── Defs.mqh              Enums, structs, libellés d'état
    ├── TimeZones.mqh         Conversion New York -> heure serveur (DST US + EU)
    ├── SymbolContext.mqh     Specs broker, conversions points/prix/lots
    ├── SessionFilter.mqh     Fenêtre de séance, warmup, cutoff, jours actifs
    ├── SignalEngine.mqh      Biais H1 + déclencheur de pullback M5
    ├── RiskManager.mqh       Placement du stop, TP, taille de position
    ├── PositionManager.mqh   Breakeven, trailing ATR, flatten de fin de séance
    ├── Guardrails.mqh        Limites journalières, reconstruites depuis l'historique
    └── Dashboard.mqh         Panneau d'état sur le graphique

docs/
├── STRATEGY.md   Règles exactes, raisonnement, paramètres, limites connues
└── BACKTEST.md   Protocole de calibration et de validation
```

Chaque module a une responsabilité unique et aucune dépendance circulaire.
Remplacer `SignalEngine.mqh` suffit à tester une autre logique d'entrée sans
toucher à la gestion du risque ni aux garde-fous.

---

## Réglages par défaut

| | |
|---|---|
| Séance | 9:30 – 16:00 New York (converti automatiquement) |
| Timeframes | Biais H1, entrée M5 |
| Biais | `close > EMA50` **et** EMA50 en hausse sur 3 bougies |
| Entrée | Repli sur l'EMA20 M5, puis bougie de rejet qui casse le haut précédent |
| Stop | Le plus large entre la structure (5 bougies) et `1.5 × ATR` |
| Objectif | 2 R |
| Risque | 0.5 % de l'équité par trade |
| Gestion | Breakeven à +1 R, trailing ATR à +1.5 R |
| Garde-fous | 1 position, 3 trades/jour, 2 pertes d'affilée, −2 % sur la journée |

Tous les détails et les plages de valeurs raisonnables : `docs/STRATEGY.md`.

---

## Choix d'implémentation notables

- **Décisions sur bougies clôturées uniquement.** Aucune décision d'entrée en intra-bougie, ce qui rend le backtest représentatif.
- **Sans état persistant.** Les compteurs journaliers sont recalculés depuis l'historique des deals, et le risque initial `R` est reconstruit depuis le TP. L'EA peut être redémarré en pleine position sans rien perdre.
- **Résultat net agrégé par position.** Profit + swap + commission de toutes les deals, pour que la commission d'ouverture ne transforme pas une perte en gain dans le compteur de pertes consécutives.
- **DST calculée depuis le calendrier**, jamais depuis `TimeGMT()` ou `TimeLocal()` — non fiables dans le Strategy Tester. Backtest et réel donnent donc la même fenêtre.
- **Lot arrondi vers le bas**, et trade refusé si le lot minimum dépasse le risque autorisé. Le risque annoncé n'est jamais dépassé.
- **Zéro constante spécifique au US100.** Utilisable tel quel sur US30 / GER40 / SPX500, avec une instance et une calibration dédiées.

---

## Pistes d'évolution

- Filtre news (calendrier économique MT5) — la lacune la plus importante
- Prises partielles + runner
- Entrée sur cassure du range d'ouverture, en alternative au pullback
- Mode multi-symboles dans une seule instance

---

## Licence

Usage personnel. Le trading sur CFD comporte un risque de perte en capital.
Aucune performance passée ne préjuge des résultats futurs.
