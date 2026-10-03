# Especificación: ScalpMetals Basket EA (XAUUSDc)

Versión 0.1 · 2026-10-03 · Estado: implementada en `ScalpMetals_Basket_EA.mq5` (pendiente de compilar y backtest)

Este documento define la estrategia completa antes de escribir una línea de MQL5.
Cada regla está numerada (R-xx) y cada parámetro configurable tiene nombre de
input, valor por defecto y justificación. Lo que no está aquí no se programa.

---

## 1. Resumen en una frase

EA de cesta (basket) para XAUUSDc que abre una ráfaga de N posiciones al recibir
señal, promedia en niveles de soporte/resistencia si el precio va en contra,
cierra toda la cesta cuando el beneficio neto de costes supera el objetivo,
corta la cesta entera si la pérdida flotante alcanza el 3% de la cuenta, y sube
el tamaño de ráfaga de 2 en 2 (hasta 10) tras cada cesta ganadora.

Familia a la que pertenece: **DCA grid basket EA con progresión anti-martingala
(Paroli) y equity stop**.

---

## 2. Glosario

| Término | Significado en este EA |
|---|---|
| Cesta (basket) | Conjunto de posiciones abiertas por el EA con el mismo `basket_id`. Se gestiona como una unidad. |
| Ráfaga (burst) | Grupo de N órdenes a mercado enviadas en segundos consecutivos. "Pulsación". |
| Escalera (ladder) | Secuencia de tamaños de ráfaga: 2, 4, 6, 8, 10. El escalón actual es `N`. |
| Escalón (step) | Posición dentro de la escalera. Sube tras cesta ganadora, se reinicia tras perdedora. |
| Promediado (averaging / DCA) | Nueva ráfaga añadida cuando el precio va en contra y toca un nivel técnico. Mejora el precio medio. |
| Nivel de promediado (averaging level) | Cada ráfaga adicional. Nivel 0 es la ráfaga inicial. |
| Precio medio de la cesta | Media ponderada por lote de los precios de apertura. |
| TP de cesta (basket take profit) | Cierre de todas las posiciones cuando el P/L neto supera el objetivo. |
| TP por posición | Cierre individual de cada posición cuando su P/L neto supera su objetivo. |
| Stop de equity (equity stop) | Cierre forzoso de toda la cesta cuando la pérdida flotante neta alcanza el porcentaje configurado del balance. |
| Neto | Bruto − spread pagado − comisión − swap − reserva de impuestos. |
| Swap triple | Cargo de tres noches de swap que el bróker aplica en el rollover del miércoles. |
| Soporte / resistencia | Nivel bajo el precio donde se espera rebote alcista (soporte) o sobre el precio donde se espera rechazo bajista (resistencia). Un BUY promedia en soporte, un SELL en resistencia. |
| Swing low / swing high | Mínimo / máximo local de las últimas N velas. |
| Fractal | Patrón de 5 velas de Bill Williams donde la central tiene el extremo. |
| Pivot points | Niveles diarios S1-S3 / R1-R3 calculados con el máximo, mínimo y cierre del día anterior. |
| ATR | Average True Range. Medida de volatilidad usada como unidad de distancia. |
| Cuenta cent | Cuenta cuyo balance se expresa en centavos. El sufijo "c" en XAUUSDc. |

---

## 3. Parámetros configurables (inputs)

Todo lo que el usuario quiso tener a mano está aquí. Los valores por defecto son
mi recomendación y se justifican en la columna derecha. Los nombres siguen la
convención `Inp...` del EA actual.

### 3.1 Identificación

| Input | Defecto | Notas |
|---|---|---|
| `InpMagicNumber` | 202610030 | Distinto del EA actual para que ambos puedan convivir. |
| `InpTradeComment` | "SMBasket" | Prefijo. Se añade el `basket_id` al comentario de cada orden. |

### 3.2 Dirección

| Input | Defecto | Opciones / Notas |
|---|---|---|
| `InpDirectionMode` | `DIR_BOTH_BY_SIGNAL` | `DIR_BUY_ONLY`, `DIR_SELL_ONLY`, `DIR_BOTH_BY_SIGNAL`. Cambiar aquí de sell a buy sin tocar nada más. |
| (cestas opuestas simultáneas) | no | v0.1 gestiona una sola cesta a la vez. Una cesta BUY y una SELL simultáneas no están implementadas. |

### 3.3 Señal de entrada (dispara la ráfaga inicial)

| Input | Defecto | Notas |
|---|---|---|
| `InpSignalMode` | `SIG_BB_RSI` | `SIG_BB_RSI` (reutiliza la lógica del EA actual), `SIG_SUPPORT_TOUCH` (entra al tocar el nivel de 3.6 sin esperar RSI), `SIG_MANUAL` (no abre sola; el usuario pulsa un botón del panel). |
| `InpAnalysisTF` | PERIOD_M5 | Timeframe de la señal. |
| `InpBBPeriod` / `InpBBDeviation` | 20 / 2.0 | Igual que el EA actual. |
| `InpRSIPeriod` / `InpRSIOversold` / `InpRSIOverbought` | 14 / 30 / 70 | Igual. |
| `InpRequireRejectionCandle` | true | Exigir cierre dentro de la banda. |

### 3.4 Ráfaga y escalera

| Input | Defecto | Notas |
|---|---|---|
| `InpLadderStart` | 2 | Tamaño de ráfaga del primer escalón. |
| `InpLadderStep` | 2 | Incremento por cesta ganadora. |
| `InpLadderMax` | 10 | Techo. |
| `InpLadderResetOnLoss` | true | Cesta perdedora vuelve a `InpLadderStart`. Si false, baja un escalón. |
| `InpLadderResetOnDay` | false | Si true, cada día empieza en `InpLadderStart`. |
| `InpBurstDelayMs` | 400 | Milisegundos entre órdenes de la ráfaga. Simula la pulsación manual y evita que el bróker rechace por ráfaga. |
| `InpBurstMaxSpreadPoints` | 200 | Si el spread sube por encima durante la ráfaga, se detiene la ráfaga y la cesta queda con las posiciones ya abiertas. |
| `InpBurstMaxSlippagePoints` | 30 | Si una orden de la ráfaga se llena a más de esta distancia de la primera, se detiene la ráfaga. |

### 3.5 Promediado (entradas adicionales en contra)

| Input | Defecto | Notas |
|---|---|---|
| `InpMaxAveragingLevels` | 2 | Ráfagas adicionales permitidas tras la inicial. 0 desactiva el promediado. |
| `InpAveragingBurstSize` | 0 | 0 = igual que el escalón actual N. Otro valor fija el tamaño de las ráfagas de promediado. |
| `InpAveragingLotMultiplier` | 1.0 | Multiplicador de lote por nivel. 1.0 = lotes iguales. >1.0 convierte el promediado en martingala parcial. Dejar en 1.0 salvo que se sepa lo que se hace. |
| `InpMinAveragingDistanceATR` | 0.8 | Distancia mínima entre el último nivel y el nuevo, en múltiplos de ATR. Evita apilar al mismo precio. |
| `InpAveragingRequireRejection` | true | Exigir vela de rechazo en el nivel antes de promediar. |

### 3.6 Detección de soporte / resistencia (opcional por modo)

| Input | Defecto | Notas |
|---|---|---|
| `InpLevelMode` | `LVL_SWING` | `LVL_SWING`, `LVL_FRACTAL`, `LVL_PIVOT_DAILY`, `LVL_BOLLINGER`, `LVL_FIXED_ATR`. |
| `InpLevelTF` | PERIOD_M15 | Timeframe donde se buscan los niveles. Más alto que la señal para que sean niveles "de verdad". |
| `InpSwingLookback` | 20 | Solo `LVL_SWING`. Velas hacia atrás para el mínimo/máximo local. |
| `InpFractalMinAgeBars` | 3 | Solo `LVL_FRACTAL`. Un fractal necesita 2 velas posteriores para confirmarse; esto exige una más. |
| `InpPivotLevelsToUse` | 3 | Solo `LVL_PIVOT_DAILY`. Usa S1..S3 o R1..R3. |
| `InpLevelToleranceATR` | 0.3 | Tolerancia alrededor del nivel para considerar que el precio "lo tocó". |
| `InpFixedGridATR` | 1.0 | Solo `LVL_FIXED_ATR`. Rejilla pura: nuevo nivel cada X ATR desde la última entrada. |

Cómo se usan según la dirección:

- Cesta BUY: el EA busca **soportes** (swing low, fractal inferior, S1-S3, banda inferior).
- Cesta SELL: el EA busca **resistencias** (swing high, fractal superior, R1-R3, banda superior).

### 3.7 Cierre de la cesta

| Input | Defecto | Notas |
|---|---|---|
| `InpCloseMode` | `CLOSE_BASKET_NET` | `CLOSE_BASKET_NET`: cierra todo cuando el neto total ≥ objetivo. `CLOSE_PER_POSITION`: cada posición cierra sola al alcanzar su neto; las perdedoras esperan. `CLOSE_HYBRID`: cierra ganadoras individualmente Y cierra el resto cuando su neto conjunto ≥ objetivo. |
| `InpTargetMode` | `TGT_PERCENT_BALANCE` | `TGT_PERCENT_BALANCE`, `TGT_FIXED_MONEY`, `TGT_POINTS_FROM_AVG`. |
| `InpTargetPercent` | 0.4 | % del balance como utilidad neta objetivo de la cesta. |
| `InpTargetMoney` | 10.0 | Moneda de la cuenta. Solo `TGT_FIXED_MONEY`. |
| `InpTargetPoints` | 150 | Puntos desde el precio medio. Solo `TGT_POINTS_FROM_AVG`. |
| `InpPerPositionTargetPoints` | 80 | Solo `CLOSE_PER_POSITION` y `CLOSE_HYBRID`. Objetivo neto de cada posición en puntos. |
| `InpMaxBasketAgeHours` | 48 | Pasado este tiempo, la cesta se cierra en cuanto el neto sea ≥ 0, aunque no llegue al objetivo. 0 desactiva. |

### 3.8 Costes (para que el objetivo sea neto de verdad)

| Input | Defecto | Notas |
|---|---|---|
| `InpCommissionPerLotRoundTrip` | 0.0 | Comisión ida y vuelta por lote en moneda de la cuenta. En cuentas Standard de Exness es 0 (va en el spread). Rellenar si la cuenta cobra comisión. |
| `InpTaxPercentOnProfit` | 0.0 | Reserva de impuestos como % del beneficio bruto. El EA infla el objetivo para que, tras impuestos, quede la utilidad deseada. El EA no liquida impuestos; solo reserva. |
| `InpIncludeSwapInNet` | true | Suma el swap real acumulado de cada posición al cálculo neto. |
| `InpEstimateSpreadOnClose` | true | Resta el spread actual al cerrar, porque el cierre también lo paga. |

### 3.9 Riesgo

| Input | Defecto | Notas |
|---|---|---|
| `InpBasketRiskPercent` | 3.0 | Pérdida flotante neta máxima de la cesta como % del balance al abrir la cesta. Es el stop de equity. **Riesgo total de la cesta, no por entrada.** |
| `InpRiskScalesWithLadder` | false | Si true, el riesgo real por cesta es `InpBasketRiskPercent × N / InpLadderMax`, de modo que el escalón 2 arriesga 0.6% y el escalón 10 arriesga 3%. Si false, toda cesta arriesga 3% y la escalera solo afina el reparto del lote. |
| `InpStopDistanceATR` | 3.0 | Distancia hipotética del precio medio al stop, en ATR, usada SOLO para calcular el lote total. El stop real es monetario. |
| `InpMaxTotalLots` | 5.0 | Techo de lotes sumados de la cesta. |
| `InpMaxDailyDrawdownPercent` | 6.0 | Heredado. Dos cestas perdedoras en un día detienen el EA hasta el día siguiente. |
| `InpMaxGlobalDrawdownPercent` | 12.0 | Heredado. Desde el pico de equity. |
| `InpCloseAllOnGlobalLimit` | true | Heredado. |

### 3.10 Filtro de swap triple (miércoles)

| Input | Defecto | Notas |
|---|---|---|
| `InpWednesdayMode` | `WED_CLOSE_IF_POSITIVE` | `WED_IGNORE`: nada especial. `WED_NO_NEW_BASKETS`: no abre cestas nuevas desde `InpWednesdayCutoffHour`. `WED_CLOSE_IF_POSITIVE`: además, cierra la cesta antes del rollover si el neto ≥ 0. |
| `InpWednesdayCutoffHour` | 20 | Hora del servidor. |
| `InpSwapTripleDay` | 3 | Día de la semana del swap triple, convención MT5 (0 = domingo, 3 = miércoles, 5 = viernes). Algunos brókeres lo aplican el viernes. |

### 3.11 Filtros heredados del EA actual

Sesiones horarias, spread máximo, ATR mínimo/máximo, rollover diario y bordes de
semana se mantienen tal cual, con los mismos inputs. Bloquean **ráfagas nuevas**
(inicial y promediado), nunca el cierre de una cesta ya abierta.

El filtro de noticias cambia a un modo con tres opciones:

| Input | Defecto | Notas |
|---|---|---|
| `InpNewsMode` | `NEWS_CLOSE_IF_POSITIVE` | `NEWS_IGNORE`: sin filtro. `NEWS_BLOCK_ENTRIES`: bloquea ráfagas en la ventana alrededor de noticias de alto impacto. `NEWS_CLOSE_IF_POSITIVE`: además, si la próxima noticia cae dentro de la ventana "antes" y la cesta tiene neto ≥ 0, la cierra (R-12b). |
| `InpNewsMinutesBefore` / `InpNewsMinutesAfter` | 15 / 15 | Ventana de bloqueo. |
| `InpNewsCurrency` | USD | Divisa filtrada. |

El calendario se consulta una vez por minuto. En el Strategy Tester no hay calendario, así que este filtro solo actúa en cuenta demo o real.

### 3.12 Panel y registro

| Input | Defecto | Notas |
|---|---|---|
| `InpShowPanel` | true | Panel en el gráfico organizado en bloques: CESTA, RESULTADO Y OBJETIVO, RIESGO Y STOP, CUENTA Y DRAWDOWN, FILTROS, BLOQUEO ACTUAL. Detalle en 3.13. |
| `InpPanelManualButtons` | true | Botones "Cerrar cesta", "Pausar", "Ráfaga BUY", "Ráfaga SELL". |
| `InpVerboseLogging` | true | Heredado. |
| `InpDrawLines` | true | Dibujar las líneas de 3.13 en el gráfico. |
| `InpLineEntryColor` | amarillo | Color de la línea de arranque de la cesta. |
| `InpLineStopColor` | rojo | Color de la línea del stop de equity y del límite diario. |
| `InpLineTargetColor` | verde | Color de la línea del objetivo. |
| `InpLineAvgColor` | naranja | Color del precio medio. |
| `InpLineNextLevelColor` | azul | Color del próximo nivel de promediado. |

### 3.13 Contenido del panel y líneas del gráfico

El panel se refresca una vez por segundo y muestra:

- **CESTA.** Estado (sin cesta / abierta BUY o SELL con id y tiempo abierta / cerrando), escalón actual y a dónde va si gana o pierde, posiciones abiertas sobre capacidad, lotes totales y lote por posición, niveles de promediado usados y método, próximo nivel con distancia en puntos, precio y hora de arranque, precio medio y precio actual.
- **RESULTADO Y OBJETIVO (TP).** Bruto, swap, comisión estimada, spread de cierre estimado, NETO en verde o rojo, meta de la cesta con su definición y cuánto falta, precio aproximado al que se alcanza la meta, barra de progreso.
- **RIESGO Y STOP (SL).** Stop de equity en dinero y porcentaje, margen restante antes del stop, precio aproximado del stop, edad máxima y edad actual.
- **CUENTA Y DRAWDOWN (DD).** Balance, equity, pico de equity, resultado del día en dinero y porcentaje frente al límite diario, precio aproximado al que se tocaría el límite diario, realizado hoy por este EA y cestas cerradas hoy, drawdown global frente a su límite, resultado de las últimas 10 cestas (G/P).
- **FILTROS.** Sesión (dentro/fuera y próxima ventana), spread y ATR actuales frente a sus límites, noticias (bloqueo activo o próxima noticia de alto impacto con nombre y cuenta atrás), tratamiento del día de swap triple, rollover y corte del viernes.
- **BLOQUEO ACTUAL.** Motivo por el que el EA no abre ráfagas en este momento, y si está pausado.

Líneas en el gráfico mientras hay cesta abierta:

| Línea | Color | Significado |
|---|---|---|
| Horizontal continua gruesa | amarillo | Precio medio de la primera ráfaga (arranque de la cesta). |
| Vertical punteada | amarillo | Hora de arranque de la cesta. Se conserva al cerrar como historial. |
| Horizontal punteada | naranja | Precio medio actual de la cesta. |
| Horizontal continua gruesa | rojo | Precio aproximado al que el neto toca el stop de equity. Se recalcula cada segundo porque el swap lo mueve. |
| Horizontal discontinua | rojo | Precio aproximado al que la equity tocaría el límite de pérdida diaria. |
| Horizontal discontinua | verde | Precio aproximado al que el neto alcanza la meta. |
| Horizontal punto-raya | azul | Próximo nivel de promediado detectado. |

Los precios de stop y meta son aproximados: suponen que todas las posiciones se mueven el mismo número de puntos, y no incluyen el swap que se acumule después.

### 3.14 Estilo visual y seguridad tomados de MALLA v0.8.3

El EA de malla del usuario (su mejor EA hasta la fecha) marca el estándar visual. Se adoptan de él:

- **Motor del panel.** Recuadro azul marino con franja de título, línea teal, secciones en teal, renglones en gris claro, barra gris de estado ("SIN CESTA" / "CESTA ABIERTA"), pie de página, letra Consolas escalada por DPI, redibujo solo de los renglones que cambian y máximo dos refrescos por segundo. Inputs `InpPanelTam`, `InpPanelFuente`.
- **Estilo del gráfico.** `InpEstiloGrafico` pinta fondo oscuro, velas teal/rojo y sin cuadrícula al arrancar. No se aplica en el Strategy Tester.
- **Nombre grande abajo a la derecha.** `InpNombrePantalla` en verde operando; en rojo con "DETENIDA" o "PAUSADA" cuando no opera.
- **Línea de stop-out del bróker** (magenta, `InpSO_Linea`). Precio al que el bróker liquidaría con el capital de este momento, calculado con equity y margen de toda la cuenta y todas las posiciones del símbolo. Si la cuenta tiene crédito o bono, una segunda línea naranja marca dónde el capital propio llega a cero. Es distinta del stop de equity de la cesta: ese es nuestro, este es el real.
- **Bloque MARGEN.** Equity, margen, nivel de margen, crédito, margin call y stop-out que informa el bróker.
- **Semáforo.** Verde, amarillo o rojo según el consumo del stop de cesta, del límite diario y el nivel de margen (`InpAviso_ML`, `InpAlarma_ML`).
- **Freno de cuenta muerta.** Detención total si el bróker liquida por stop-out (detectado por el motivo del deal), si el balance baja de `InpBalanceMin`, si una orden es rechazada por falta de dinero, o tras `InpMaxRechazos` rechazos seguidos. La detención persiste en la variable global y solo se sale recargando el EA tras revisar la cuenta.
- **AutoTrading apagado.** No se envía ninguna orden y el panel lo muestra en rojo. No cuenta como rechazo.
- **Avisos push** (`InpPush`) al abrir y cerrar cestas, en el stop de equity y en cualquier detención, y latido "sigo viva" cada `InpLatidoMin` minutos. Su silencio avisa de que el terminal murió.

No se adopta el modo observador de MALLA: este EA reconstruye la cesta al recargar.

---

## 4. Reglas de la estrategia

### Ciclo de vida de la cesta

```
IDLE ──señal + filtros OK──▶ BURSTING ──ráfaga completa──▶ OPEN
                                                           │
                       ┌───────────────────────────────────┤
                       │ nivel tocado + filtros OK          │ neto ≥ objetivo
                       ▼                                   │ o stop de equity
                   AVERAGING ──ráfaga completa──▶ OPEN     │ o edad máxima con neto ≥ 0
                                                           ▼
                                                        CLOSING ──todo cerrado──▶ IDLE
```

**R-01 Estado IDLE.** No hay posiciones del EA. El EA evalúa señal cada vela nueva del `InpAnalysisTF`.

**R-02 Apertura de cesta.** Con señal válida y todos los filtros de 3.11 en verde, el EA crea un `basket_id` nuevo, guarda el balance de apertura y pasa a BURSTING.

**R-03 Ráfaga.** Envía N órdenes a mercado del mismo lado, con `InpBurstDelayMs` entre ellas, sin SL ni TP individuales en el bróker (el stop es de cesta). Se detiene antes de tiempo si el spread o el slippage superan 3.4. Las posiciones abiertas hasta ese momento forman la cesta igualmente.

**R-04 Lote por posición.**

```
riesgo_dinero   = balance_apertura × riesgo_efectivo%
                  donde riesgo_efectivo% = InpBasketRiskPercent
                  (o × N / InpLadderMax si InpRiskScalesWithLadder)
capacidad       = N + InpMaxAveragingLevels × tamaño_ráfaga_promediado
distancia_stop  = InpStopDistanceATR × ATR(InpAnalysisTF)   [en puntos]
valor_punto     = SYMBOL_TRADE_TICK_VALUE / SYMBOL_TRADE_TICK_SIZE × SYMBOL_POINT
lote_total      = riesgo_dinero / (distancia_stop × valor_punto)
lote_total      = min(lote_total, InpMaxTotalLots)
lote_posición   = normalizar(lote_total / capacidad)   [step, min, max del símbolo]
```

Si `lote_posición` queda por debajo del mínimo del símbolo, el EA reduce la capacidad (menos posiciones por ráfaga) hasta que el lote mínimo quepa, y lo anota en el log. Nunca sube el riesgo para "hacer que quepa".

**R-05 Precio medio.** `media = Σ(precio_i × lote_i) / Σ(lote_i)`. Se recalcula tras cada ráfaga.

**R-06 Promediado.** En estado OPEN, si el precio va en contra y toca un nivel según `InpLevelMode` (con tolerancia 3.6), la distancia al último nivel es ≥ `InpMinAveragingDistanceATR`, hay vela de rechazo si se exige, los filtros de 3.11 están en verde y el número de niveles usados es < `InpMaxAveragingLevels`, el EA lanza una ráfaga de promediado del mismo lado. Un nivel solo se usa una vez por cesta.

**R-07 Cálculo del neto.**

```
bruto         = Σ POSITION_PROFIT
swap          = Σ POSITION_SWAP                       (si InpIncludeSwapInNet)
comisión      = Σ lote_i × InpCommissionPerLotRoundTrip
spread_cierre = Σ lote_i × spread_actual × valor_punto (si InpEstimateSpreadOnClose)
neto_pre_tax  = bruto + swap − comisión − spread_cierre
neto          = neto_pre_tax × (1 − InpTaxPercentOnProfit/100)   si neto_pre_tax > 0
              = neto_pre_tax                                      si ≤ 0
```

Al cerrar la cesta, el EA lee las comisiones reales de los deals del historial y registra la diferencia entre estimado y real para calibrar `InpCommissionPerLotRoundTrip`.

**R-08 Objetivo.** Según `InpTargetMode`: `balance_apertura × InpTargetPercent/100`, o `InpTargetMoney`, o la ganancia que resulta de `InpTargetPoints` desde el precio medio con los lotes actuales.

**R-09 Cierre por objetivo.**

- `CLOSE_BASKET_NET`: cuando `neto ≥ objetivo`, cierra todas las posiciones de la cesta, de la más antigua a la más nueva.
- `CLOSE_PER_POSITION`: cada posición cierra sola cuando su neto individual ≥ `InpPerPositionTargetPoints × lote × valor_punto`. La cesta termina cuando no queda ninguna. Las perdedoras esperan al promediado.
- `CLOSE_HYBRID`: aplica lo anterior y, además, si el neto de las que quedan ≥ objetivo de cesta, las cierra todas.

**R-10 Stop de equity.** En todo momento y en todo modo de cierre: si `neto ≤ −riesgo_dinero`, cierra toda la cesta de inmediato. Es la única salida que ignora los filtros de spread y sesión. Se evalúa en cada tick, no en cada vela.

**R-11 Edad máxima.** Si la cesta supera `InpMaxBasketAgeHours` y `neto ≥ 0`, se cierra. Si está en negativo, sigue esperando al objetivo o al stop.

**R-12 Miércoles.** Según `InpWednesdayMode`, a partir de `InpWednesdayCutoffHour` del día `InpSwapTripleDay`: bloquea cestas nuevas y, si procede, cierra la cesta con neto ≥ 0 antes del rollover. El EA registra en el log el swap cobrado cada noche por cesta para que el histórico diga si conviene operar ese día.

**R-12b Noticias.** Con `NEWS_CLOSE_IF_POSITIVE`, si la próxima noticia de alto impacto está a menos de `InpNewsMinutesBefore` minutos y el neto de la cesta es ≥ 0, se cierra la cesta. Si está en negativo, se mantiene y se confía en el stop de equity. Justificación: en oro, una noticia como el NFP o el IPC mueve el precio varias veces el ATR en segundos.

**R-13 Resultado de la cesta.** Al quedar vacía, `resultado = Σ beneficio realizado neto de los deals`. Ganadora si > 0, perdedora si ≤ 0.

**R-14 Escalera.** Ganadora: `N = min(N + InpLadderStep, InpLadderMax)`. Perdedora: `N = InpLadderStart` (o `max(N − InpLadderStep, InpLadderStart)` si `InpLadderResetOnLoss` es false). Cierre manual desde el panel no mueve la escalera.

**R-15 Persistencia.** `basket_id`, escalón N, balance de apertura, niveles usados, hora de apertura y pico de equity se guardan en variables globales del terminal con prefijo `SMB_<magic>_`. Tras reinicio, el EA reconstruye la cesta leyendo las posiciones abiertas con su magic y las variables globales.

**R-16 Drawdown diario y global.** Heredados. Al alcanzarlos se cierra la cesta abierta y se bloquea la apertura hasta el reinicio correspondiente.

**R-17 Dirección.** `DIR_BUY_ONLY` ignora señales de venta; `DIR_SELL_ONLY` ignora las de compra; `DIR_BOTH_BY_SIGNAL` toma la que dé la señal. Mientras haya una cesta abierta no se abre otra.

**R-18 Modo manual.** Con `SIG_MANUAL` el EA no abre sola. Los botones del panel lanzan la ráfaga del escalón actual en la dirección pulsada; el botón salta los filtros de sesión, noticias y miércoles (el usuario decide), pero respeta spread máximo, mercado abierto y límites de drawdown. Promediado, cierre, stop y escalera funcionan igual que en automático.

---

## 5. Decisiones que tomé y por qué

1. **Modo de cierre por defecto: cesta entera.** El cierre por posición acumula perdedoras sin límite de tiempo y es el modo que más cuentas quema en esta familia. Queda disponible, pero no es el defecto.
2. **Riesgo fijo por cesta, no creciente con la escalera.** Con riesgo fijo, subir de 2 a 10 posiciones afina el promediado sin subir la exposición. `InpRiskScalesWithLadder` permite el comportamiento contrario si se quiere probar.
3. **Niveles en M15, señal en M5.** Los soportes del mismo timeframe que la señal son ruido. Un timeframe por encima filtra mucho.
4. **Máximo 2 niveles de promediado.** Con la ráfaga inicial, hasta 3 ráfagas por cesta. Más niveles acercan la estrategia a la martingala pura.
5. **Multiplicador de lote 1.0.** Promediar con lotes crecientes es martingala. Se deja el input para experimentar, pero con advertencia.
6. **Objetivo por defecto 0.4% del balance.** Con stop al 3%, la relación es 1:7.5. Exige acierto por encima del 88% para no perder. Es el número a vigilar en el backtest: si el acierto real está por debajo, hay que subir el objetivo o bajar el riesgo, no tocar la escalera.
7. **Stop de equity evaluado por tick.** En oro, un movimiento de 3% de cuenta puede ocurrir en segundos. Evaluar por vela sería tarde.
8. **Edad máxima 48 h.** Dos noches de swap. Más tiempo y el swap se come el objetivo.

---

## 6. Riesgos conocidos de esta familia

- **Asimetría.** Muchas ganancias pequeñas y pérdidas grandes ocasionales. El rendimiento depende casi por completo del acierto, no de la gestión.
- **Tendencia fuerte en contra.** El promediado funciona en rango y falla en tendencia. En oro, las caídas por noticias no respetan soportes.
- **Gaps de fin de semana.** Una cesta abierta el viernes puede abrir el lunes más allá del stop. El filtro de viernes heredado mitiga, no elimina.
- **Spread en ráfaga.** Diez entradas pagan diez spreads. En XAUUSDc el spread es el coste principal.
- **Cuenta cent.** Todo el sizing lee tick value, tick size, contract size y lote mínimo del símbolo. Nunca se asume 100 onzas por lote.
- **Rechazo del bróker por ráfaga.** Algunos brókeres limitan órdenes por segundo. El retardo entre órdenes y la detención por spread están para eso.

---

## 7. Plan de validación antes de dinero real

1. Compilar sin warnings en MetaEditor.
2. Backtest en Strategy Tester, XAUUSDc, modo "Every tick based on real ticks", 2023-01 a la fecha, con el swap y spread reales de la cuenta.
3. Métricas mínimas: factor de beneficio > 1.3, drawdown máximo < 15%, acierto de cestas, resultado separado por día de la semana (para el miércoles), resultado separado por escalón.
4. Repetir con cada `InpCloseMode` y cada `InpLevelMode`. Documentar en `docs/backtests/` con el .set usado.
5. Walk-forward: optimizar 2023-2024, validar 2025-2026 sin tocar parámetros.
6. Demo con cuenta cent dos semanas antes de real.

---

## 8. Qué se reutiliza del EA actual

Filtros de mercado (módulo 1 completo), señal BB+RSI (módulo 2), cálculo de valor de punto y normalización de lote, variables globales de drawdown, envío de órdenes con reintentos y logging. El EA nuevo se escribe como archivo separado `ScalpMetals_Basket_EA.mq5` y el actual se conserva.
