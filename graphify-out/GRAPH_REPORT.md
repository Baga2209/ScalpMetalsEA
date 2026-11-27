# Graph Report - ScalpMetalsEA  (2026-11-27)

## Corpus Check
- 1 files · ~4,593 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 38 nodes · 87 edges · 7 communities (4 shown, 3 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- Estado de riesgo, depósitos y retiros
- Señal y filtros de mercado
- Ciclo OnTick
- Filtros de horario y sesión
- Detección de operaciones de balance
- Ejecución de órdenes
- Paro global y cierre

## God Nodes (most connected - your core abstractions)
1. `OnTick()` - 20 edges
2. `GVGetOrInit()` - 8 edges
3. `GVName()` - 7 edges
4. `ApplyCashflowAdjustments()` - 6 edges
5. `UpdateEquityTracking()` - 6 edges
6. `IsWeekEdgeBlocked()` - 5 edges
7. `InitRiskTrackingIfNeeded()` - 5 edges
8. `TimeHourOf()` - 5 edges
9. `IsWithinTradingSession()` - 4 edges
10. `IsRolloverWindow()` - 4 edges

## Surprising Connections (you probably didn't know these)
- `OnTick()` --calls--> `CountEAPositions()`  [EXTRACTED]
  ScalpMetals_EA.mq5 → ScalpMetals_EA.mq5  _Bridges community 2 → community 1_
- `OnTick()` --calls--> `ExecuteMarketOrder()`  [EXTRACTED]
  ScalpMetals_EA.mq5 → ScalpMetals_EA.mq5  _Bridges community 2 → community 5_
- `OnTick()` --calls--> `HandleGlobalHalt()`  [EXTRACTED]
  ScalpMetals_EA.mq5 → ScalpMetals_EA.mq5  _Bridges community 2 → community 6_
- `OnTick()` --calls--> `IsGlobalDrawdownExceeded()`  [EXTRACTED]
  ScalpMetals_EA.mq5 → ScalpMetals_EA.mq5  _Bridges community 2 → community 0_
- `OnTick()` --calls--> `IsRolloverWindow()`  [EXTRACTED]
  ScalpMetals_EA.mq5 → ScalpMetals_EA.mq5  _Bridges community 2 → community 3_

## Import Cycles
- None detected.

## Communities (7 total, 3 thin omitted)

### Community 0 - "Estado de riesgo, depósitos y retiros"
Cohesion: 0.38
Nodes (9): ApplyCashflowAdjustments(), CashflowMarkerNowMsc(), GVGetOrInit(), GVName(), InitRiskTrackingIfNeeded(), IsGlobalDrawdownExceeded(), OnInit(), ServerNow() (+1 more)

### Community 1 - "Señal y filtros de mercado"
Cohesion: 0.25
Nodes (5): CountEAPositions(), EvaluateSignal(), GetStopLossDistancePoints(), IsNewsBlackout(), IsSpreadAcceptable()

### Community 2 - "Ciclo OnTick"
Cohesion: 0.25
Nodes (8): CalculateLotSize(), IsDailyDrawdownExceeded(), IsMarketOpen(), IsNewBar(), IsVolatilityAcceptable(), LogSkip(), ManageOpenPositions(), OnTick()

### Community 3 - "Filtros de horario y sesión"
Cohesion: 0.60
Nodes (5): IsRolloverWindow(), IsWeekEdgeBlocked(), IsWithinTradingSession(), TimeDayOfWeek(), TimeHourOf()

## Knowledge Gaps
- **3 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `OnTick()` connect `Ciclo OnTick` to `Estado de riesgo, depósitos y retiros`, `Señal y filtros de mercado`, `Filtros de horario y sesión`, `Ejecución de órdenes`, `Paro global y cierre`?**
  _High betweenness centrality (0.152) - this node is a cross-community bridge._
- **Why does `IsCashflowDeal()` connect `Detección de operaciones de balance` to `Estado de riesgo, depósitos y retiros`, `Señal y filtros de mercado`?**
  _High betweenness centrality (0.054) - this node is a cross-community bridge._
- **Why does `ExecuteMarketOrder()` connect `Ejecución de órdenes` to `Señal y filtros de mercado`, `Ciclo OnTick`?**
  _High betweenness centrality (0.054) - this node is a cross-community bridge._