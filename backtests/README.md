# Backtests de RAFAGA

Un archivo por corrida: informe del Probador (.xlsx o .htm) y, si se usó, el .set de parámetros.

| Fecha | Archivo | Símbolo | Rango | Depósito | Resultado | Conclusión |
|---|---|---|---|---|---|---|
| 2026-10-03 | `2026-10-03_RAFAGA_XAUUSDm_2020-2026.xlsx` | XAUUSDm (3 decimales) | 2020-01-01 a 2026-10-01 | 5000 USD, 1:2000 | +128.40, 19 cestas, 17 G / 2 P, DD equity 3.85% | NO REPRESENTATIVO: filtros de ATR y spread en puntos, 10 veces demasiado estrictos para un símbolo de 3 decimales. Sin operaciones desde 2024-03. Corregido pasando los filtros a USD. |

## Lectura del backtest del 2026-10-03

- Las 17 cestas ganadoras cerraron en el objetivo del 0.4% (unos +24 USD cada una). Las 2 perdedoras cerraron en el stop del 3% (-134 y -150). Relación 1:6, acierto 89.5%. Es exactamente la asimetría prevista en la sección 5 de la especificación.
- Las dos perdedoras fueron en viernes. Con 2 casos no es estadística, pero es lo primero a vigilar en el próximo backtest.
- El promediado solo intervino en 2 de 19 cestas. Las cestas duran menos de 2 horas de media: el precio rara vez llega a un soporte antes de que la cesta cierre.
- La escalera funcionó como estaba previsto: 2, 4, 6, 8, 10 y reinicio tras perder.
