# Protocole de backtest et de calibration

Les paramètres livrés sont des **points de départ, pas des valeurs validées**.
Ce document décrit comment les calibrer sans se mentir à soi-même.

---

## 1. Avant de lancer quoi que ce soit

### Qualité des données

Le Strategy Tester MT5 propose plusieurs modes. Un seul est utilisable ici :

| Mode | Verdict |
|---|---|
| *Open prices only* | Inutilisable. La gestion intra-bougie (breakeven, trailing) n'existe pas. |
| *1 minute OHLC* | Acceptable pour un premier tri grossier uniquement. |
| **Every tick based on real ticks** | **Le seul mode qui compte.** |

Sans ticks réels, les résultats des stops et du trailing sont de la fiction. Si ton
broker ne fournit pas d'historique tick, prends-en un autre pour la phase de test.

### Spread et commission

Le spread historique de MT5 est souvent sous-estimé, surtout à l'ouverture.

1. Relève le spread réel de ton broker sur le US100, à l'ouverture NY et en milieu de séance.
2. Configure la commission dans les réglages du symbole si ton broker en facture.
3. Si le spread modélisé est plus optimiste que le réel, refais le test avec un spread fixe majoré.

Sur un système 2R avec un stop de ~30 points, 2 points de spread représentent
environ 7 % du risque par trade. Ce n'est pas un détail.

### Horaires

Vérifie la ligne de log au démarrage :

```
[session] window 16:30-23:00 server (warmup 15m, cutoff 30m) (mode=New York)
```

Si elle ne correspond pas à l'ouverture cash réelle, corrige
`InpBrokerGmtWinter` / `InpBrokerGmtSummer` **avant** de backtester. Voir `STRATEGY.md` §4.

---

## 2. Découpage des périodes

Ne jamais optimiser et évaluer sur la même période.

| Rôle | Période suggérée | Usage |
|---|---|---|
| **In-sample** | 2019 → 2022 | Optimisation des paramètres |
| **Out-of-sample 1** | 2023 → 2024 | Première validation, jamais utilisée pour choisir |
| **Out-of-sample 2** | 2025 → aujourd'hui | Validation finale, une seule fois |

La période doit contenir des régimes variés. 2020 (krach + rebond), 2022 (bear
market), 2023-2024 (tendance haussière), 2025 : un système qui ne survit qu'aux
années haussières n'est pas un système.

**Règle** : si tu retouches un paramètre après avoir vu l'out-of-sample, cette
période devient de l'in-sample. Tu n'as plus de validation.

---

## 3. Ce qu'il faut optimiser, et dans quel ordre

Optimiser 15 paramètres à la fois produit du bruit sur-ajusté. Procède par blocs,
en figeant ce qui précède.

### Bloc 1 — structure du signal
```
InpBiasEmaPeriod    : 20, 34, 50, 100
InpFastEmaPeriod    : 9, 20, 34
InpPullbackLookback : 3, 6, 9, 12
```
Critère : nombre de trades suffisant (**≥ 200 sur l'in-sample**) et espérance positive.

### Bloc 2 — stop et objectif
```
InpSlAtrMult   : 1.0, 1.5, 2.0, 2.5
InpRewardRatio : 1.5, 2.0, 2.5, 3.0
InpSwingBars   : 3, 5, 8
```
Critère : profit factor et drawdown. C'est le bloc le plus sensible.

### Bloc 3 — filtres de contexte
Mesure d'abord la distribution de l'ATR M5 pendant la séance NY sur ton
historique, puis fixe `InpMinAtrPoints` / `InpMaxAtrPoints` sur des percentiles
(par exemple P10 et P95) — **pas** sur une valeur trouvée par optimisation.

### Bloc 4 — gestion
```
InpUseBreakeven / InpUseTrailing : on, off
InpBeTriggerR  : 0.8, 1.0, 1.3
InpTrailStartR : 1.2, 1.5, 2.0
InpTrailAtrMult: 1.0, 1.5, 2.0
```
Teste aussi **tout désactivé**. Le trailing dégrade souvent l'espérance en échange
d'une courbe plus lisse — c'est un arbitrage, pas une amélioration automatique.

### À ne pas optimiser
Les garde-fous (`InpMaxTradesPerDay`, `InpMaxConsecLosses`, `InpMaxDailyLossPct`,
`InpRiskPercent`). Ce sont des contraintes de survie, pas des variables de
performance. Les « optimiser » revient à les désactiver.

---

## 4. Métriques à regarder

Dans l'ordre d'importance :

1. **Drawdown maximum relatif** — la seule métrique qui décide si tu tiendras le système.
2. **Profit factor** — en dessous de 1.2, la marge est trop fine pour absorber une dégradation du spread.
3. **Nombre de trades** — moins de 100, aucune conclusion statistique possible.
4. **Espérance en R** — le gain moyen par trade exprimé en multiple du risque. Robuste aux changements de taille.
5. **Pire série de pertes consécutives** — doit rester compatible avec `InpMaxConsecLosses`.
6. **Stabilité de la courbe** — ouvre le graphique. Une courbe portée par 3 trades n'est pas une edge.

Ce qu'il faut **ignorer** : le profit net absolu et le « Expected Payoff » de MT5
(dépendants de la taille), ainsi que le ratio de Sharpe calculé par le tester
(peu significatif sur un faible nombre de trades).

---

## 5. Signaux de sur-ajustement

Si l'un de ces points est vrai, le résultat ne tiendra pas en réel :

- Décaler un paramètre d'un cran fait s'effondrer la performance → tu as trouvé un pic de bruit, pas un plateau. **Cherche toujours un plateau.**
- L'out-of-sample est nettement moins bon que l'in-sample.
- Le résultat change beaucoup entre « ticks réels » et « 1 minute OHLC ».
- Moins de 150 trades.
- Le top 10 de l'optimisation contient des valeurs totalement dispersées.

---

## 6. Avant le réel

1. **Walk-forward** : optimise sur 12 mois, teste sur les 3 suivants, décale, répète. Si les paramètres optimaux changent radicalement à chaque fenêtre, il n'y a pas d'edge stable.
2. **Stress spread** : relance le meilleur jeu de paramètres avec un spread doublé. S'il devient perdant, la marge est illusoire.
3. **Stress risque** : vérifie que le drawdown reste tenable à `InpRiskPercent` × 2.
4. **Démo, 4 semaines minimum.** Compare le nombre de trades et le fill moyen avec le backtest sur la même période. Un écart important révèle un problème d'exécution, de spread ou d'horaires — pas de stratégie.
5. **Réel en taille réduite** (`InpRiskPercent = 0.1`) pendant 4 semaines avant de passer à la taille cible.

Active `InpWriteCsvLog = true` : chaque trade clôturé est écrit dans
`MQL5/Files/US100_trades_<symbole>_<magic>.csv` (dossier `Tester/Files` en
backtest), ce qui permet de comparer démo et backtest trade par trade.

---

## 7. Checklist de mise en production

- [ ] Horaires de session vérifiés dans le log au démarrage
- [ ] `InpMagic` unique par instance
- [ ] Symbole correct (`US100`, `NAS100`, `USTEC`… selon le broker)
- [ ] Graphique sur le timeframe d'entrée (M5 par défaut)
- [ ] Algo trading activé dans le terminal
- [ ] Testé en ticks réels sur au moins 3 régimes de marché distincts
- [ ] Validé sur un out-of-sample jamais utilisé pour choisir les paramètres
- [ ] 4 semaines de démo cohérentes avec le backtest
- [ ] `InpRiskPercent` et `InpMaxDailyLossPct` fixés sur ta tolérance réelle, pas sur le backtest
