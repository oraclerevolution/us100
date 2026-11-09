# US100 — NY Session Trend Pullback

Système intraday sur le NASDAQ 100 (US100 / NAS100 / USTEC selon le broker).
Un seul principe : **on ne trade que dans le sens de la tendance horaire, pendant
la séance cash de New York, et uniquement quand un repli vient d'être rejeté.**

---

## 1. Pourquoi cette approche sur le NASDAQ

Trois caractéristiques du US100 dictent le design :

| Caractéristique | Conséquence sur le design |
|---|---|
| Drift structurel haussier fort, mais avec des phases baissières violentes | On ne force pas un biais long : le biais est mesuré, pas supposé |
| La volatilité est concentrée sur la séance cash US ; en dehors, le marché dérive avec un spread large et peu de volume | Trading restreint à la fenêtre NY, flat le reste du temps |
| Les journées de tendance détruisent le mean reversion, mais les pullbacks y sont nombreux et peu profonds | Suivi de tendance avec entrée sur repli, pas de contre-tendance |
| L'ATR varie du simple au triple selon le régime (15 pts un jour calme, 60+ pts en semaine FOMC) | Stops et taille de position proportionnels à l'ATR, jamais en points fixes |

Le risque overnight (gaps sur l'ouverture, frais de financement) est éliminé en
clôturant tout en fin de séance.

---

## 2. Les règles exactes

### 2.1 Fenêtre de trading

- Session cash NY : **9:30 → 16:00 heure de New York** (convertie automatiquement en heure serveur, voir §4).
- **Warmup** : aucune entrée pendant les 15 premières minutes. L'ouverture est bruitée, le spread est élargi, et le range d'ouverture n'est pas encore formé.
- **Cutoff** : aucune nouvelle entrée dans les 30 dernières minutes.
- **Flatten** : toutes les positions sont fermées 2 minutes avant la clôture de séance.
- Lundi → vendredi uniquement, chaque jour activable séparément.

### 2.2 Biais directionnel (H1)

Le biais est long si **les deux** conditions sont vraies sur la dernière bougie H1 clôturée :

1. `close > EMA50`
2. `EMA50` est en hausse sur les 3 dernières bougies (`EMA50[1] > EMA50[4]`)

Biais short : conditions miroir. Si aucune des deux n'est satisfaite → **biais neutre, aucun trade**.

La double condition est volontaire. Le prix au-dessus d'une EMA plate n'est pas une
tendance, c'est un range : c'est exactement la configuration qui génère le plus de
faux signaux de pullback.

### 2.3 Déclencheur d'entrée (M5)

Côté long (short en miroir), dans l'ordre :

1. Le biais H1 est long.
2. *(optionnel, actif par défaut)* La dernière bougie M5 clôture **au-dessus de l'EMA50 M5**. Évite d'acheter pendant une cassure de structure intraday alors que le H1 n'a pas encore tourné.
3. **Le repli a eu lieu** : sur l'une des 6 dernières bougies M5, le `low` est venu toucher ou passer sous l'**EMA20 M5** (la « zone de valeur »).
4. **Le momentum reprend**, sur la dernière bougie clôturée :
   - bougie haussière (`close > open`)
   - `close > EMA20`
   - `close > high` de la bougie précédente

L'entrée est envoyée **au marché à l'ouverture de la bougie suivante**. Aucune
décision n'est prise en intra-bougie : c'est ce qui rend le backtest exploitable.

### 2.4 Filtres de contexte

Évalués avant tout signal :

| Filtre | Défaut | Rôle |
|---|---|---|
| ATR min | désactivé | Écarte les journées trop plates où le TP n'est pas atteignable |
| ATR max | désactivé | Écarte les pics de volatilité (news, ouverture post-gap) |
| Spread max absolu | désactivé | Garde-fou broker |
| **Spread / ATR max** | **0.20** | Le vrai filtre : refuse l'entrée quand le coût de transaction dépasse 20 % de la volatilité de la bougie |

Le ratio spread/ATR est préféré à un plafond fixe parce qu'il reste valable quel
que soit le régime de volatilité. Les bornes ATR sont laissées désactivées par
défaut : elles doivent être calibrées sur les données **de ton** broker (§ BACKTEST.md).

### 2.5 Stop, objectif, taille

**Placement du stop** — 3 modes, défaut `SWING_ATR` :

| Mode | Distance du stop |
|---|---|
| `ATR` | `1.5 × ATR` |
| `SWING` | plus bas des 5 dernières bougies, moins `0.25 × ATR` de marge |
| `SWING_ATR` *(défaut)* | **le plus large des deux** |

Le mode par défaut place le stop derrière la structure réelle, tout en garantissant
qu'il ne sera jamais plus serré que la respiration normale du marché. Un stop
calé au tick sous le plus bas se fait balayer par le bruit ; un stop purement ATR
ignore la structure.

Le stop est ensuite élargi si nécessaire pour respecter le `stops level` du broker,
**spread inclus** : pour un achat, le SL est comparé au Bid alors que l'entrée se
fait à l'Ask, et oublier ce détail est une cause classique de rejet d'ordre.

**Objectif** : `TP = 2.0 × distance du stop` (2R).

**Taille de position** :

```
risque  = équité × 0.5 %
lot     = risque / (perte d'un lot si le stop est touché)
```

La perte d'un lot est calculée avec `OrderCalcProfit()`, donc exacte quel que soit
le contrat du broker, avec un repli sur le tick value si l'appel échoue. Le lot est
**arrondi vers le bas** sur le pas du broker — on ne dépasse jamais le risque
annoncé. Si le lot minimum dépasse déjà le risque autorisé, **le trade est refusé**
et la raison est loguée : l'EA ne prend jamais plus de risque que demandé.

Un tampon de marge (20 % par défaut) empêche de consommer toute la marge libre.

### 2.6 Gestion après l'entrée

| Étape | Déclencheur | Action |
|---|---|---|
| Breakeven | +1.0 R | SL ramené à l'entrée + `0.05 × ATR` |
| Trailing | +1.5 R | SL suivi à `1.5 × ATR` du prix, uniquement dans le sens favorable |
| Flatten | fin de séance | Clôture au marché |

Le risque initial `R` est **reconstruit depuis le TP** (`R = |TP − entrée| / 2.0`)
au lieu d'être stocké en mémoire. Conséquence concrète : l'EA peut être redémarré,
le terminal relancé, le graphique rechargé en pleine position — la gestion reprend
exactement où elle était.

### 2.7 Garde-fous

Recalculés **depuis l'historique des deals**, jamais depuis des compteurs en
mémoire, donc insensibles à un redémarrage :

| Garde-fou | Défaut |
|---|---|
| Positions simultanées | 1 |
| Trades par jour | 3 |
| Pertes consécutives → arrêt du jour | 2 |
| Drawdown journalier → arrêt du jour | 2 % |
| Cooldown après une perte | 3 bougies M5 |

Le résultat d'un trade est jugé sur son **net agrégé par position** (profit + swap +
commission de toutes les deals de la position). Un broker qui facture la commission
à l'ouverture ferait sinon passer une petite perte pour un gain, et fausserait le
compteur de pertes consécutives.

Le drawdown journalier est mesuré contre le **solde en début de journée serveur**,
reconstruit comme `solde actuel − réalisé du jour`, et inclut le flottant.

---

## 3. Paramètres

### Identité
| Paramètre | Défaut | Note |
|---|---|---|
| `InpMagic` | 100100 | À changer si plusieurs instances |
| `InpSlippagePoints` | 20 | Déviation max acceptée |

### Session
| Paramètre | Défaut | Note |
|---|---|---|
| `InpSessionMode` | `NY` | `NY` = heures ci-dessous en heure de New York, converties automatiquement. `SERVER` = heures brutes du serveur |
| `InpSessionStartHour/Min` | 9:30 | Ouverture cash NY |
| `InpSessionEndHour/Min` | 16:00 | Clôture cash NY |
| `InpBrokerGmtWinter` | 2 | Offset GMT du broker hors heure d'été EU |
| `InpBrokerGmtSummer` | 3 | Offset GMT du broker en heure d'été EU |
| `InpWarmupMinutes` | 15 | |
| `InpEntryCutoffMin` | 30 | |
| `InpFlattenBeforeEnd` | 2 | |

### Signal
| Paramètre | Défaut | Plage raisonnable |
|---|---|---|
| `InpBiasTF` | H1 | H1, H4 |
| `InpBiasEmaPeriod` | 50 | 20–100 |
| `InpBiasSlopeBars` | 3 | 2–6 |
| `InpEntryTF` | M5 | M5, M15 |
| `InpFastEmaPeriod` | 20 | 9–34 |
| `InpSlowEmaPeriod` | 50 | 34–100 |
| `InpPullbackLookback` | 6 | 3–12 |

### Risque
| Paramètre | Défaut | Plage raisonnable |
|---|---|---|
| `InpRiskPercent` | 0.5 | 0.25–1.0 |
| `InpSlMode` | `SWING_ATR` | |
| `InpSlAtrMult` | 1.5 | 1.0–2.5 |
| `InpSwingBars` | 5 | 3–10 |
| `InpRewardRatio` | 2.0 | 1.5–3.0 |

---

## 4. Le piège des horaires (lis ça avant de te plaindre que l'EA ne trade pas)

La séance NYSE est définie en heure de New York. L'EA voit l'heure du serveur du
broker. **Les deux changent d'heure à des dates différentes** :

- États-Unis : 2ᵉ dimanche de mars → 1ᵉʳ dimanche de novembre
- Union européenne : dernier dimanche de mars → dernier dimanche d'octobre

Pour un broker GMT+2/+3 (le cas le plus courant en MT5), la session cash NY en
heure serveur donne :

| Période | Session en heure serveur |
|---|---|
| Janvier → 8 mars 2026 | 16:30 – 23:00 |
| 8 mars → 29 mars 2026 | **15:30 – 22:00** |
| 29 mars → 25 octobre 2026 | 16:30 – 23:00 |
| 25 octobre → 1ᵉʳ novembre 2026 | **15:30 – 22:00** |
| 1ᵉʳ novembre → fin 2026 | 16:30 – 23:00 |

Soit **environ 4 semaines par an** où une fenêtre codée en dur serait décalée d'une
heure — et ce décalage est invisible en backtest puisque le backtest utiliserait le
même offset erroné.

C'est pourquoi `InpSessionMode = NY` est le défaut : les deux calendriers DST sont
calculés depuis le calendrier (`TimeZones.mqh`), sans jamais appeler `TimeGMT()`
ni `TimeLocal()`, qui ne sont pas fiables dans le Strategy Tester. Le résultat est
donc **identique en backtest et en réel**.

**À faire une fois** : vérifier l'offset GMT de ton broker, puis renseigner
`InpBrokerGmtWinter` / `InpBrokerGmtSummer`. Au démarrage, l'EA logue la fenêtre
qu'il a calculée :

```
[session] window 16:30-23:00 server (warmup 15m, cutoff 30m) (mode=New York)
```

Si cette ligne ne correspond pas à l'ouverture réelle du cash US chez ton broker,
corrige les deux offsets. Un broker qui ne change jamais d'heure : mets la même
valeur dans les deux champs.

---

## 5. Ce que ce système ne fait pas

À savoir avant de le mettre en réel :

- **Pas de filtre news.** Un CPI ou un FOMC en pleine séance peut déclencher une entrée dans le pic. Le filtre spread/ATR aide mais ne protège pas. C'est le premier ajout à envisager.
- **Pas de gestion de gap.** Le flatten de fin de séance supprime le risque, mais l'EA ne tire pas parti des gaps d'ouverture.
- **Pas de prises partielles.** Tout ou rien sur le TP, avec breakeven et trailing.
- **Un seul symbole par instance.** Le code est générique (aucun chiffre spécifique au US100 en dur), donc utilisable sur US30 / GER40 / SPX500, mais chaque symbole a besoin de sa propre instance et de sa propre calibration.
- **Aucun paramètre n'a été optimisé.** Les défauts sont des points de départ raisonnables, pas des valeurs validées. La calibration se fait sur les données de ton broker : voir `BACKTEST.md`.
