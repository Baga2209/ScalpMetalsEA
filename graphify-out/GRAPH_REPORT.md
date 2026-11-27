# Graph Report - ScalpMetalsEA  (2026-11-27)

## Corpus Check
- 1 files · ~3,914 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 33 nodes · 72 edges · 7 communities (4 shown, 3 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- Filtros de horario y sesión
- Ciclo OnTick y filtros de mercado
- Seguimiento de equity y drawdown
- Señal, lotaje y posiciones
- Ejecución de órdenes
- Paro global y cierre
- Inicialización

## God Nodes (most connected - your core abstractions)
1. `OnTick()` - 20 edges
2. `GVGetOrInit()` - 7 edges
3. `IsWeekEdgeBlocked()` - 5 edges
4. `GVName()` - 5 edges
5. `TimeHourOf()` - 5 edges
6. `IsWithinTradingSession()` - 4 edges
7. `IsRolloverWindow()` - 4 edges
8. `UpdateEquityTracking()` - 4 edges
9. `IsGlobalDrawdownExceeded()` - 4 edges
10. `TimeDayOfWeek()` - 4 edges

## Surprising Connections (you probably didn't know these)
- `OnTick()` --calls--> `CalculateLotSize()`  [EXTRACTED]
  ScalpMetals_EA.mq5 → ScalpMetals_EA.mq5  _Bridges community 1 → community 3_
- `OnTick()` --calls--> `ExecuteMarketOrder()`  [EXTRACTED]
  ScalpMetals_EA.mq5 → ScalpMetals_EA.mq5  _Bridges community 1 → community 4_
- `OnTick()` --calls--> `HandleGlobalHalt()`  [EXTRACTED]
  ScalpMetals_EA.mq5 → ScalpMetals_EA.mq5  _Bridges community 1 → community 5_
- `OnTick()` --calls--> `IsDailyDrawdownExceeded()`  [EXTRACTED]
  ScalpMetals_EA.mq5 → ScalpMetals_EA.mq5  _Bridges community 1 → community 2_
- `OnTick()` --calls--> `IsMarketOpen()`  [EXTRACTED]
  ScalpMetals_EA.mq5 → ScalpMetals_EA.mq5  _Bridges community 1 → community 0_

## Import Cycles
- None detected.

## Communities (7 total, 3 thin omitted)

### Community 0 - "Filtros de horario y sesión"
Cohesion: 0.48
Nodes (6): IsMarketOpen(), IsRolloverWindow(), IsWeekEdgeBlocked(), IsWithinTradingSession(), TimeDayOfWeek(), TimeHourOf()

### Community 1 - "Ciclo OnTick y filtros de mercado"
Cohesion: 0.29
Nodes (7): GetStopLossDistancePoints(), IsNewBar(), IsNewsBlackout(), IsSpreadAcceptable(), IsVolatilityAcceptable(), ManageOpenPositions(), OnTick()

### Community 2 - "Seguimiento de equity y drawdown"
Cohesion: 0.43
Nodes (6): GVGetOrInit(), GVName(), IsDailyDrawdownExceeded(), IsGlobalDrawdownExceeded(), LogSkip(), UpdateEquityTracking()

### Community 3 - "Señal, lotaje y posiciones"
Cohesion: 0.33
Nodes (3): CalculateLotSize(), CountEAPositions(), EvaluateSignal()

## Knowledge Gaps
- **3 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `OnTick()` connect `Ciclo OnTick y filtros de mercado` to `Filtros de horario y sesión`, `Seguimiento de equity y drawdown`, `Señal, lotaje y posiciones`, `Ejecución de órdenes`, `Paro global y cierre`?**
  _High betweenness centrality (0.206) - this node is a cross-community bridge._
- **Why does `ExecuteMarketOrder()` connect `Ejecución de órdenes` to `Ciclo OnTick y filtros de mercado`, `Señal, lotaje y posiciones`?**
  _High betweenness centrality (0.062) - this node is a cross-community bridge._
- **Why does `GVGetOrInit()` connect `Seguimiento de equity y drawdown` to `Señal, lotaje y posiciones`, `Inicialización`?**
  _High betweenness centrality (0.023) - this node is a cross-community bridge._