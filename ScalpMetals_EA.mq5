//+------------------------------------------------------------------+
//|                                              ScalpMetals_EA.mq5   |
//|  EA de scalping para metales (XAUUSD / XAGUSD) en MetaTrader 5   |
//|                                                                    |
//|  ESTRATEGIA: Reversión a la media con Bandas de Bollinger,        |
//|  confirmada por RSI en extremo y filtro de volatilidad (ATR),     |
//|  operando únicamente dentro de ventanas horarias configurables    |
//|  (sesiones de Londres/NY), con filtro de spread, filtro de        |
//|  rollover/fin de semana y filtro de noticias de alto impacto.     |
//|                                                                    |
//|  ARQUITECTURA MODULAR:                                            |
//|    1) MÓDULO DE FILTROS DE MERCADO (horario, spread, volatilidad, |
//|       noticias, estado del mercado)                               |
//|    2) MÓDULO DE SEÑAL (entrada/salida)                            |
//|    3) MÓDULO DE GESTIÓN DE RIESGO (sizing, SL/TP, drawdown)       |
//|    4) MÓDULO DE EJECUCIÓN (envío/gestión de órdenes)              |
//|                                                                    |
//|  AVISO: Este código es una herramienta de trading algorítmico,    |
//|  no constituye asesoría financiera. El trading apalancado de      |
//|  metales conlleva riesgo real de pérdida de capital. Los          |
//|  resultados de backtesting NO garantizan resultados futuros.      |
//|  Debe validarse exhaustivamente en demo antes de usar en real.    |
//+------------------------------------------------------------------+
#property copyright "Generado como asistencia técnica - no es asesoría financiera"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

CTrade trade;

//==================================================================
// INPUTS — NINGÚN PARÁMETRO DE RIESGO, SL/TP, HORARIO O FILTRO
// ESTÁ HARDCODEADO. TODO ES CONFIGURABLE DESDE AQUÍ.
//==================================================================

input group "=== IDENTIFICACIÓN DE LA INSTANCIA ==="
input long   InpMagicNumber          = 202609020;   // Número mágico único (usar uno distinto por símbolo/instancia)
input string InpTradeComment         = "ScalpMetalsEA"; // Comentario de las órdenes

input group "=== TIMEFRAME DE ANÁLISIS ==="
input ENUM_TIMEFRAMES InpAnalysisTF  = PERIOD_M5;    // Timeframe usado para calcular la señal (M1-M5 recomendado)

input group "=== SEÑAL: BANDAS DE BOLLINGER + RSI (reversión a la media) ==="
input int    InpBBPeriod             = 20;           // Periodo de la media móvil de las Bandas de Bollinger
input double InpBBDeviation          = 2.0;          // Desviación estándar de las bandas
input int    InpRSIPeriod            = 14;           // Periodo del RSI
input double InpRSIOversold          = 30.0;         // Umbral de sobreventa (señal de compra)
input double InpRSIOverbought        = 70.0;         // Umbral de sobrecompra (señal de venta)
input bool   InpRequireRejectionCandle = true;       // Exigir vela de rechazo (cierre dentro de la banda) para confirmar

input group "=== FILTRO DE VOLATILIDAD (ATR) ==="
input int    InpATRPeriod            = 14;           // Periodo del ATR
input double InpATRMinPoints         = 50;            // ATR mínimo en puntos (evita operar en mercado "muerto")
input double InpATRMaxPoints         = 900;           // ATR máximo en puntos (evita operar en picos anómalos de volatilidad)
// SUPUESTO DECLARADO: estos valores de ATR en puntos son un punto de partida orientativo,
// NO un dato de mercado verificado. Deben calibrarse con datos históricos reales del símbolo
// y bróker específicos antes de operar (ver bloque de resumen al final del archivo).

input group "=== GESTIÓN DE RIESGO: SIZING Y SL/TP ==="
input double InpRiskPercentPerTrade  = 1.0;   // % del capital arriesgado por operación (perfil agresivo)
input double InpMaxRiskPercentCap    = 2.0;   // Techo de seguridad absoluto: nunca se arriesga más que esto, aunque el input anterior se configure más alto
input double InpSL_ATR_Multiplier    = 1.2;   // Distancia de Stop Loss = ATR actual * este multiplicador
input double InpMinSLPoints          = 80;    // Distancia mínima de SL en puntos (evita SL irreales por ATR muy bajo)
input double InpRiskRewardRatio      = 1.3;   // Relación Riesgo:Beneficio mínima aceptable (TP = SL * este ratio)
input double InpMaxLotSize           = 5.0;   // Techo absoluto de volumen por operación (protección adicional)

input group "=== GESTIÓN DE RIESGO: PROTECCIÓN DE GANANCIAS ==="
input bool   InpUseBreakeven         = true;  // Activar movimiento a break-even
input double InpBreakevenTriggerPoints = 60;  // Puntos de ganancia flotante para mover SL a break-even
input double InpBreakevenLockPoints  = 5;     // Puntos de beneficio asegurados al activar break-even
input bool   InpUseTrailingStop      = true;  // Activar trailing stop
input double InpTrailingStartPoints  = 100;   // Puntos de ganancia para empezar a "trailear"
input double InpTrailingStepPoints   = 30;    // Paso mínimo del trailing stop en puntos

input group "=== LÍMITES DE DRAWDOWN (obligatorios, no desactivables) ==="
input double InpMaxDailyDrawdownPercent  = 5.0;   // % máximo de pérdida diaria antes de detener el EA por el resto del día
input double InpMaxGlobalDrawdownPercent = 12.0;  // % máximo de pérdida desde el pico de equity antes de detener el EA por completo
input bool   InpCloseAllOnGlobalLimit    = true;  // Si se alcanza el límite global, cerrar también las posiciones abiertas

input group "=== FILTROS DE EJECUCIÓN ==="
input double InpMaxSpreadPoints      = 200;   // Spread máximo permitido, en puntos, para abrir nuevas operaciones
// SUPUESTO DECLARADO: 200 puntos es un valor de partida genérico (no un spread típico verificado
// de ningún bróker/símbolo concreto). El spread real de XAUUSD/XAGUSD varía enormemente entre
// brókers (cuentas ECN vs. cuentas estándar) y debe calibrarse observando el spread real del símbolo.
input int    InpMaxPositionsPerSymbol = 1;    // Máximo de posiciones simultáneas abiertas por el EA en este símbolo
input int    InpSlippagePoints        = 20;   // Desviación máxima de precio (slippage) tolerada al enviar órdenes
input int    InpMaxOrderRetries       = 3;    // Reintentos ante requote/error transitorio del bróker

input group "=== FILTRO DE HORARIO (hora del SERVIDOR del bróker, no la local) ==="
input bool   InpUseSessionFilter     = true;  // Activar filtro de ventanas horarias de negociación
input int    InpSession1StartHour    = 8;     // Inicio ventana 1 (ej. apertura de Londres) — CALIBRAR según GMT offset del bróker
input int    InpSession1EndHour      = 11;    // Fin ventana 1
input bool   InpUseSession2          = true;  // Activar segunda ventana horaria
input int    InpSession2StartHour    = 13;    // Inicio ventana 2 (ej. solapamiento Londres/NY)
input int    InpSession2EndHour      = 16;    // Fin ventana 2
// SUPUESTO DECLARADO: las horas por defecto asumen un servidor en GMT/GMT+2 aproximadamente
// referenciando Londres 08-11h y solapamiento Londres/NY 13-16h. CADA bróker publica su propia
// hora de servidor (a menudo GMT+2/GMT+3, con o sin horario de verano). Es obligatorio verificar
// la hora de servidor real (Herramientas > Opciones, o comparando reloj del terminal) antes de operar.

input group "=== FILTRO DE ROLLOVER Y BORDES DE SEMANA ==="
input bool   InpAvoidRollover        = true;  // Evitar operar durante el rollover diario (liquidez irregular)
input int    InpRolloverStartHour    = 22;    // Inicio ventana de rollover (hora servidor)
input int    InpRolloverEndHour      = 23;    // Fin ventana de rollover (hora servidor)
input bool   InpAvoidMondayOpenGap   = true;  // Evitar operar en la primera hora tras la apertura del domingo/lunes
input int    InpMondayAvoidUntilHour = 1;     // No operar hasta esta hora (servidor) tras la reapertura semanal
input bool   InpAvoidFridayClose     = true;  // Evitar abrir operaciones nuevas cerca del cierre semanal del viernes
input int    InpFridayCutoffHour     = 20;    // A partir de esta hora del viernes (servidor) no se abren nuevas operaciones

input group "=== FILTRO DE NOTICIAS DE ALTO IMPACTO ==="
input bool   InpUseEconomicCalendar  = true;   // Usar el Calendario Económico nativo de MT5 (requiere datos de calendario sincronizados)
input int    InpNewsMinutesBefore    = 15;     // Minutos antes de una noticia de alto impacto en los que se bloquean entradas
input int    InpNewsMinutesAfter     = 15;     // Minutos después de una noticia de alto impacto en los que se bloquean entradas
input string InpNewsCurrency         = "USD";  // Divisa cuyo calendario se filtra (USD es la relevante para XAUUSD/XAGUSD)
// NOTA IMPORTANTE: el Calendario Económico de MT5 depende de que el terminal tenga los datos
// sincronizados con el servidor (normalmente requiere conexión a una cuenta real/demo activa;
// en el Strategy Tester su disponibilidad depende de la versión de terminal/build). Si la API
// no devuelve eventos, el EA lo registra en el log y CONTINÚA operando sin este filtro: no debe
// asumirse que "sin eventos devueltos" equivale a "sin noticias". Se recomienda complementar
// con supervisión manual del calendario económico real durante las primeras semanas de uso.

input group "=== VARIOS ==="
input bool   InpVerboseLogging       = true;   // Registrar en el log el motivo cuando NO se opera

//==================================================================
// VARIABLES GLOBALES DEL PROGRAMA
//==================================================================
int    hBB   = INVALID_HANDLE;   // handle Bandas de Bollinger
int    hRSI  = INVALID_HANDLE;   // handle RSI
int    hATR  = INVALID_HANDLE;   // handle ATR
datetime g_lastBarTime = 0;      // control de nueva vela
string   g_gvPrefix = "";        // prefijo de variables globales de terminal (persistentes y compartidas entre instancias del EA)
bool     g_dailyHaltAlerted  = false;
bool     g_globalHaltAlerted = false;

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetAsyncMode(false);

   hBB  = iBands(_Symbol, InpAnalysisTF, InpBBPeriod, 0, InpBBDeviation, PRICE_CLOSE);
   hRSI = iRSI(_Symbol, InpAnalysisTF, InpRSIPeriod, PRICE_CLOSE);
   hATR = iATR(_Symbol, InpAnalysisTF, InpATRPeriod);

   if(hBB == INVALID_HANDLE || hRSI == INVALID_HANDLE || hATR == INVALID_HANDLE)
   {
      Print("ERROR CRÍTICO: no se pudieron crear los handles de indicadores. Abortando inicialización.");
      return INIT_FAILED;
   }

   // Prefijo de variables globales de terminal: compartido a nivel de CUENTA (login),
   // de forma que si el EA se adjunta simultáneamente a XAUUSD y XAGUSD, ambas instancias
   // comparten el mismo estado de drawdown diario/global (el drawdown es una propiedad de la
   // cuenta, no de un símbolo individual).
   g_gvPrefix = StringFormat("ScalpMetalsEA_%d_", (int)AccountInfoInteger(ACCOUNT_LOGIN));

   InitRiskTrackingIfNeeded();

   PrintFormat("ScalpMetals_EA inicializado en %s | Magic=%d | TF análisis=%s",
               _Symbol, InpMagicNumber, EnumToString(InpAnalysisTF));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(hBB  != INVALID_HANDLE) IndicatorRelease(hBB);
   if(hRSI != INVALID_HANDLE) IndicatorRelease(hRSI);
   if(hATR != INVALID_HANDLE) IndicatorRelease(hATR);
}

//+------------------------------------------------------------------+
//| OnTick — orquestador principal. Delega en los módulos.            |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1) Gestión de riesgo global: actualizar tracking de equity y comprobar límites.
   //    Esto se hace SIEMPRE, incluso si no se puede operar, para poder detectar el
   //    cruce de un límite de drawdown en tiempo real.
   UpdateEquityTracking();

   bool dailyHalted  = IsDailyDrawdownExceeded();
   bool globalHalted = IsGlobalDrawdownExceeded();

   if(globalHalted)
   {
      HandleGlobalHalt();
      // Aunque el trading esté detenido, seguimos gestionando (breakeven/trailing) las
      // posiciones que pudieran quedar abiertas, salvo que el input pida cerrarlas todas.
      if(!InpCloseAllOnGlobalLimit)
         ManageOpenPositions();
      return;
   }

   if(dailyHalted)
   {
      if(!g_dailyHaltAlerted)
      {
         string msg = StringFormat("[%s] LÍMITE DE DRAWDOWN DIARIO ALCANZADO (%.2f%%). EA detiene nuevas operaciones hasta el próximo día.",
                                    _Symbol, InpMaxDailyDrawdownPercent);
         Print(msg);
         Alert(msg);
         g_dailyHaltAlerted = true;
      }
      ManageOpenPositions(); // seguimos protegiendo lo abierto, pero no abrimos nada nuevo
      return;
   }

   // 2) Módulo de filtros de mercado: ¿puede el EA siquiera considerar operar ahora?
   if(!IsMarketOpen())
   {
      LogSkip("Mercado cerrado o sin cotización reciente (fin de semana / símbolo inactivo).");
      return;
   }

   // Gestionar posiciones existentes en cada tick, independientemente de si se abre algo nuevo.
   ManageOpenPositions();

   bool entryWindowOk = true;
   string skipReason = "";

   if(!IsWithinTradingSession(TimeCurrent()))
   {
      entryWindowOk = false;
      skipReason = "Fuera de la ventana horaria de negociación configurada.";
   }
   else if(InpAvoidRollover && IsRolloverWindow(TimeCurrent()))
   {
      entryWindowOk = false;
      skipReason = "Ventana de rollover diario (liquidez irregular).";
   }
   else if(IsWeekEdgeBlocked(TimeCurrent()))
   {
      entryWindowOk = false;
      skipReason = "Borde de sesión semanal (apertura dominical o cierre de viernes).";
   }
   else if(!IsSpreadAcceptable())
   {
      entryWindowOk = false;
      skipReason = StringFormat("Spread actual (%d pts) supera el máximo permitido (%.0f pts).",
                                 (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD), InpMaxSpreadPoints);
   }
   else if(InpUseEconomicCalendar && IsNewsBlackout())
   {
      entryWindowOk = false;
      skipReason = "Ventana de bloqueo por noticia de alto impacto (calendario económico).";
   }

   if(!entryWindowOk)
   {
      LogSkip(skipReason);
      return;
   }

   // 3) Sólo evaluar señales una vez por vela cerrada (evita múltiples señales intra-vela
   //    y reduce el riesgo de sobreoperar / look-ahead sobre una vela aún en formación).
   if(!IsNewBar())
      return;

   double atrPoints = 0.0;
   if(!IsVolatilityAcceptable(atrPoints))
   {
      LogSkip(StringFormat("ATR actual (%.1f pts) fuera del rango de volatilidad aceptable [%.1f, %.1f].",
                            atrPoints, InpATRMinPoints, InpATRMaxPoints));
      return;
   }

   if(CountEAPositions() >= InpMaxPositionsPerSymbol)
   {
      LogSkip("Ya hay el máximo de posiciones abiertas permitidas para este símbolo.");
      return;
   }

   // 4) Módulo de señal
   int signal = EvaluateSignal();
   if(signal == 0)
      return;

   // 5) Módulo de gestión de riesgo: calcular distancias y tamaño de posición
   double slPoints = GetStopLossDistancePoints(atrPoints);
   double tpPoints = slPoints * InpRiskRewardRatio;
   double lots     = CalculateLotSize(slPoints);

   if(lots <= 0.0)
   {
      LogSkip("Tamaño de posición calculado es 0 (capital insuficiente para el riesgo configurado o límites de bróker). No se opera.");
      return;
   }

   // 6) Módulo de ejecución
   if(signal > 0)
      ExecuteMarketOrder(ORDER_TYPE_BUY, lots, slPoints, tpPoints);
   else
      ExecuteMarketOrder(ORDER_TYPE_SELL, lots, slPoints, tpPoints);
}

//+------------------------------------------------------------------+
//|                                                                    |
//|  MÓDULO 1: FILTROS DE MERCADO                                     |
//|  (horario, spread, volatilidad, noticias, estado del mercado)     |
//|                                                                    |
//+------------------------------------------------------------------+

bool IsMarketOpen()
{
   // No hay cotización si el último tick es muy antiguo (símbolo suspendido/mercado cerrado)
   // o si el bróker marca la sesión de trading como cerrada para este momento.
   datetime lastTick = (datetime)SymbolInfoInteger(_Symbol, SYMBOL_TIME);
   if(TimeCurrent() - lastTick > 300) // más de 5 minutos sin tick nuevo => sospechoso de mercado cerrado
      return false;

   datetime from, to;
   if(!SymbolInfoSessionTrade(_Symbol, (ENUM_DAY_OF_WEEK)TimeDayOfWeek(TimeCurrent()), 0, from, to))
      return false; // sin sesión de trading definida para hoy (ej. sábado/domingo en muchos brókers)

   return true;
}

bool IsWithinTradingSession(datetime t)
{
   if(!InpUseSessionFilter)
      return true;

   int h = TimeHourOf(t);

   bool inSession1 = (h >= InpSession1StartHour && h < InpSession1EndHour);
   bool inSession2 = InpUseSession2 && (h >= InpSession2StartHour && h < InpSession2EndHour);

   return (inSession1 || inSession2);
}

bool IsRolloverWindow(datetime t)
{
   int h = TimeHourOf(t);
   if(InpRolloverStartHour <= InpRolloverEndHour)
      return (h >= InpRolloverStartHour && h < InpRolloverEndHour);
   // ventana que cruza medianoche
   return (h >= InpRolloverStartHour || h < InpRolloverEndHour);
}

bool IsWeekEdgeBlocked(datetime t)
{
   int dow = TimeDayOfWeek(t);
   int h   = TimeHourOf(t);

   if(InpAvoidMondayOpenGap && dow == 1 && h < InpMondayAvoidUntilHour)
      return true;
   if(InpAvoidFridayClose && dow == 5 && h >= InpFridayCutoffHour)
      return true;
   // Domingo: la mayoría de brókers de metales reabren tarde el domingo; por seguridad,
   // si aún así hay cotización un domingo, se trata igual que apertura semanal.
   if(InpAvoidMondayOpenGap && dow == 0)
      return true;

   return false;
}

bool IsSpreadAcceptable()
{
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return (spread > 0 && spread <= (long)InpMaxSpreadPoints);
}

bool IsVolatilityAcceptable(double &atrPointsOut)
{
   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(hATR, 0, 1, 1, atrBuf) <= 0)
   {
      atrPointsOut = 0.0;
      return false; // sin datos de ATR, por seguridad no operamos
   }
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   atrPointsOut = atrBuf[0] / point;

   return (atrPointsOut >= InpATRMinPoints && atrPointsOut <= InpATRMaxPoints);
}

// Filtro de noticias de alto impacto usando el Calendario Económico nativo de MT5.
// Si el terminal no tiene datos de calendario sincronizados, la función registra un
// aviso UNA VEZ y devuelve false (no bloquea) para no dejar el EA inoperante de forma
// silenciosa por falta de datos; esto se documenta explícitamente como limitación.
bool IsNewsBlackout()
{
   static bool warnedNoCalendar = false;

   datetime from = TimeCurrent() - (InpNewsMinutesAfter + 5) * 60;
   datetime to   = TimeCurrent() + (InpNewsMinutesBefore + 5) * 60;

   MqlCalendarValue values[];
   int total = CalendarValueHistory(values, from, to, NULL, InpNewsCurrency);

   if(total <= 0)
   {
      if(!warnedNoCalendar && InpVerboseLogging)
      {
         Print("AVISO: el Calendario Económico no devolvió eventos (puede no estar disponible en este ",
               "entorno/Strategy Tester, o no haber noticias en la ventana consultada). El filtro de ",
               "noticias NO puede garantizar protección en este momento; considérese supervisión manual.");
         warnedNoCalendar = true;
      }
      return false;
   }

   for(int i = 0; i < total; i++)
   {
      MqlCalendarEvent evt;
      if(!CalendarEventById(values[i].event_id, evt))
         continue;

      if(evt.importance != CALENDAR_IMPORTANCE_HIGH)
         continue;

      datetime eventTime = values[i].time;
      datetime blockFrom = eventTime - InpNewsMinutesBefore * 60;
      datetime blockTo   = eventTime + InpNewsMinutesAfter  * 60;

      if(TimeCurrent() >= blockFrom && TimeCurrent() <= blockTo)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//|                                                                    |
//|  MÓDULO 2: SEÑAL DE ENTRADA                                       |
//|  Reversión a la media: precio toca banda exterior + RSI en        |
//|  extremo + (opcional) vela de rechazo que cierra dentro de banda. |
//|  Se evalúa SIEMPRE sobre velas YA CERRADAS (índice 1), nunca      |
//|  sobre la vela en formación (índice 0), para evitar look-ahead.   |
//|                                                                    |
//+------------------------------------------------------------------+
int EvaluateSignal()
{
   double upper[], lower[], middle[], rsi[];
   double h[], l[], o[], c[];
   ArraySetAsSeries(upper, true);  ArraySetAsSeries(lower, true);  ArraySetAsSeries(middle, true);
   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(h, true); ArraySetAsSeries(l, true); ArraySetAsSeries(o, true); ArraySetAsSeries(c, true);

   if(CopyBuffer(hBB, 1, 0, 3, upper)  <= 0) return 0; // buffer 1 = banda superior
   if(CopyBuffer(hBB, 2, 0, 3, lower)  <= 0) return 0; // buffer 2 = banda inferior
   if(CopyBuffer(hBB, 0, 0, 3, middle) <= 0) return 0; // buffer 0 = media central
   if(CopyBuffer(hRSI, 0, 0, 3, rsi)   <= 0) return 0;

   if(CopyHigh(_Symbol, InpAnalysisTF, 0, 3, h)  <= 0) return 0;
   if(CopyLow(_Symbol,  InpAnalysisTF, 0, 3, l)  <= 0) return 0;
   if(CopyOpen(_Symbol, InpAnalysisTF, 0, 3, o)  <= 0) return 0;
   if(CopyClose(_Symbol,InpAnalysisTF, 0, 3, c)  <= 0) return 0;

   // índice 1 = última vela cerrada
   bool touchedLower = (l[1] <= lower[1]);
   bool touchedUpper = (h[1] >= upper[1]);
   bool rsiOversold   = (rsi[1] <= InpRSIOversold);
   bool rsiOverbought = (rsi[1] >= InpRSIOverbought);

   bool bullishRejection = (c[1] > lower[1]) && (c[1] > o[1]);
   bool bearishRejection = (c[1] < upper[1]) && (c[1] < o[1]);

   bool buySignal  = touchedLower && rsiOversold   && (!InpRequireRejectionCandle || bullishRejection);
   bool sellSignal = touchedUpper && rsiOverbought && (!InpRequireRejectionCandle || bearishRejection);

   // Si por alguna anomalía ambas condiciones se cumplieran a la vez, no se opera (ambigüedad = abstención).
   if(buySignal && !sellSignal) return 1;
   if(sellSignal && !buySignal) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//|                                                                    |
//|  MÓDULO 3: GESTIÓN DE RIESGO                                      |
//|  (sizing dinámico, distancias de SL/TP, límites de drawdown)      |
//|                                                                    |
//+------------------------------------------------------------------+

double GetStopLossDistancePoints(double atrPoints)
{
   double slFromATR = atrPoints * InpSL_ATR_Multiplier;
   return MathMax(slFromATR, InpMinSLPoints);
}

// Calcula el volumen (lotes) de forma que la pérdida en caso de tocar el SL sea
// aproximadamente InpRiskPercentPerTrade % del BALANCE actual, respetando el techo
// de seguridad InpMaxRiskPercentCap y los límites de volumen del símbolo/bróker.
double CalculateLotSize(double slPoints)
{
   double riskPercent = MathMin(InpRiskPercentPerTrade, InpMaxRiskPercentCap);
   double balance     = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney   = balance * (riskPercent / 100.0);

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(tickValue <= 0 || tickSize <= 0 || point <= 0)
   {
      Print("ERROR: no se pudieron leer las propiedades del símbolo para calcular el tamaño de posición.");
      return 0.0;
   }

   double slPriceDistance = slPoints * point;
   double valuePerLot = (slPriceDistance / tickSize) * tickValue;
   if(valuePerLot <= 0)
      return 0.0;

   double lots = riskMoney / valuePerLot;

   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMin(lots, InpMaxLotSize);
   lots = MathMin(lots, maxLot);

   if(lots < minLot)
      return 0.0; // el riesgo configurado no alcanza ni el lote mínimo del bróker: abstenerse, no forzar

   return NormalizeDouble(lots, 2);
}

// --- Tracking de equity/balance para drawdown, persistente entre instancias (GlobalVariable) ---

string GVName(string key) { return g_gvPrefix + key; }

double GVGetOrInit(string key, double initValue)
{
   if(GlobalVariableCheck(GVName(key)))
      return GlobalVariableGet(GVName(key));
   GlobalVariableSet(GVName(key), initValue);
   return initValue;
}

void InitRiskTrackingIfNeeded()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   GVGetOrInit("DayStartBalance", balance);
   GVGetOrInit("DayStamp", (double)(TimeCurrent() / 86400));
   GVGetOrInit("EquityPeak", equity);
   GVGetOrInit("GlobalHalted", 0.0);
}

void UpdateEquityTracking()
{
   double today = MathFloor((double)TimeCurrent() / 86400.0);
   double storedDay = GVGetOrInit("DayStamp", today);

   if(today != storedDay)
   {
      // Nuevo día de trading: reiniciar el contador de drawdown diario.
      GlobalVariableSet(GVName("DayStamp"), today);
      GlobalVariableSet(GVName("DayStartBalance"), AccountInfoDouble(ACCOUNT_BALANCE));
      g_dailyHaltAlerted = false;
      if(InpVerboseLogging)
         Print("Nuevo día de trading detectado: contador de drawdown diario reiniciado.");
   }

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double peak   = GVGetOrInit("EquityPeak", equity);
   if(equity > peak)
      GlobalVariableSet(GVName("EquityPeak"), equity);
}

bool IsDailyDrawdownExceeded()
{
   double dayStart = GVGetOrInit("DayStartBalance", AccountInfoDouble(ACCOUNT_BALANCE));
   double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
   if(dayStart <= 0) return false;

   double ddPercent = (dayStart - equity) / dayStart * 100.0;
   return (ddPercent >= InpMaxDailyDrawdownPercent);
}

bool IsGlobalDrawdownExceeded()
{
   if(GVGetOrInit("GlobalHalted", 0.0) >= 1.0)
      return true; // una vez detenido globalmente, permanece detenido hasta intervención manual

   double peak   = GVGetOrInit("EquityPeak", AccountInfoDouble(ACCOUNT_EQUITY));
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(peak <= 0) return false;

   double ddPercent = (peak - equity) / peak * 100.0;
   if(ddPercent >= InpMaxGlobalDrawdownPercent)
   {
      GlobalVariableSet(GVName("GlobalHalted"), 1.0);
      return true;
   }
   return false;
}

void HandleGlobalHalt()
{
   if(!g_globalHaltAlerted)
   {
      string msg = StringFormat("[%s] LÍMITE DE DRAWDOWN GLOBAL ALCANZADO (%.2f%%). EA DETENIDO POR COMPLETO. ",
                                 _Symbol, InpMaxGlobalDrawdownPercent);
      msg += InpCloseAllOnGlobalLimit ? "Cerrando todas las posiciones abiertas." :
                                         "Las posiciones abiertas se mantienen (según configuración) — revísense manualmente.";
      Print(msg);
      Alert(msg);
      g_globalHaltAlerted = true;
   }
   if(InpCloseAllOnGlobalLimit)
      CloseAllEAPositions("Límite de drawdown global alcanzado");
}

//+------------------------------------------------------------------+
//|                                                                    |
//|  MÓDULO 4: EJECUCIÓN                                              |
//|  (envío de órdenes, manejo de errores/requotes, gestión de        |
//|   posiciones abiertas: break-even y trailing stop)                |
//|                                                                    |
//+------------------------------------------------------------------+

bool ExecuteMarketOrder(ENUM_ORDER_TYPE type, double lots, double slPoints, double tpPoints)
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   for(int attempt = 1; attempt <= InpMaxOrderRetries; attempt++)
   {
      double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                                : SymbolInfoDouble(_Symbol, SYMBOL_BID);

      double sl = (type == ORDER_TYPE_BUY) ? price - slPoints * point : price + slPoints * point;
      double tp = (type == ORDER_TYPE_BUY) ? price + tpPoints * point : price - tpPoints * point;
      sl = NormalizeDouble(sl, digits);
      tp = NormalizeDouble(tp, digits);

      bool ok;
      if(type == ORDER_TYPE_BUY)
         ok = trade.Buy(lots, _Symbol, price, sl, tp, InpTradeComment);
      else
         ok = trade.Sell(lots, _Symbol, price, sl, tp, InpTradeComment);

      uint retcode = trade.ResultRetcode();

      if(ok && (retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_DONE_PARTIAL))
      {
         PrintFormat("Orden ejecutada: %s %.2f lotes en %s | SL=%.*f TP=%.*f | intento %d",
                     EnumToString(type), lots, _Symbol, digits, sl, digits, tp, attempt);
         return true;
      }

      // Errores transitorios que justifican reintento
      if(retcode == TRADE_RETCODE_REQUOTE || retcode == TRADE_RETCODE_PRICE_CHANGED ||
         retcode == TRADE_RETCODE_PRICE_OFF || retcode == TRADE_RETCODE_TIMEOUT)
      {
         PrintFormat("Reintentando orden (%s) tras retcode=%d (%s), intento %d/%d",
                     EnumToString(type), retcode, trade.ResultRetcodeDescription(), attempt, InpMaxOrderRetries);
         Sleep(200);
         continue;
      }

      // Error no transitorio (fondos insuficientes, mercado cerrado, volumen inválido, etc.):
      // se registra y NO se reintenta, para no insistir en un error estructural.
      PrintFormat("ERROR al enviar orden %s: retcode=%d (%s). No se reintenta.",
                  EnumToString(type), retcode, trade.ResultRetcodeDescription());
      return false;
   }

   Print("ERROR: se agotaron los reintentos de envío de orden sin éxito.");
   return false;
}

int CountEAPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      count++;
   }
   return count;
}

void ManageOpenPositions()
{
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

      long   type      = PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      double profitPoints = (type == POSITION_TYPE_BUY)
                             ? (bid - openPrice) / point
                             : (openPrice - ask) / point;

      double newSL = currentSL;
      bool modify = false;

      // --- Break-even ---
      if(InpUseBreakeven && profitPoints >= InpBreakevenTriggerPoints)
      {
         double beSL = (type == POSITION_TYPE_BUY)
                       ? openPrice + InpBreakevenLockPoints * point
                       : openPrice - InpBreakevenLockPoints * point;

         bool needsBE = (type == POSITION_TYPE_BUY) ? (currentSL < beSL) : (currentSL > beSL || currentSL == 0);
         if(needsBE)
         {
            newSL = beSL;
            modify = true;
         }
      }

      // --- Trailing stop (sólo una vez superado el umbral de arranque) ---
      if(InpUseTrailingStop && profitPoints >= InpTrailingStartPoints)
      {
         double trailSL = (type == POSITION_TYPE_BUY)
                          ? bid - InpTrailingStepPoints * point
                          : ask + InpTrailingStepPoints * point;

         bool improves = (type == POSITION_TYPE_BUY) ? (trailSL > newSL) : (trailSL < newSL || newSL == 0);
         if(improves)
         {
            newSL = trailSL;
            modify = true;
         }
      }

      if(modify)
      {
         newSL = NormalizeDouble(newSL, digits);
         if(!trade.PositionModify(ticket, newSL, currentTP))
            PrintFormat("Aviso: no se pudo modificar SL del ticket #%d (retcode=%d, %s)",
                        (int)ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
      }
   }
}

void CloseAllEAPositions(string reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

      if(!trade.PositionClose(ticket))
         PrintFormat("ERROR al cerrar posición #%d por '%s': retcode=%d (%s)",
                     (int)ticket, reason, trade.ResultRetcode(), trade.ResultRetcodeDescription());
      else
         PrintFormat("Posición #%d cerrada por: %s", (int)ticket, reason);
   }
}

//+------------------------------------------------------------------+
//|                                                                    |
//|  UTILIDADES GENÉRICAS                                             |
//|                                                                    |
//+------------------------------------------------------------------+

bool IsNewBar()
{
   datetime t[];
   ArraySetAsSeries(t, true);
   if(CopyTime(_Symbol, InpAnalysisTF, 0, 1, t) <= 0)
      return false;
   if(t[0] != g_lastBarTime)
   {
      g_lastBarTime = t[0];
      return true;
   }
   return false;
}

int TimeHourOf(datetime t)
{
   MqlDateTime s;
   TimeToStruct(t, s);
   return s.hour;
}

int TimeDayOfWeek(datetime t)
{
   MqlDateTime s;
   TimeToStruct(t, s);
   return s.day_of_week; // 0=Domingo ... 6=Sábado
}

void LogSkip(string reason)
{
   if(InpVerboseLogging)
      PrintFormat("[%s] Sin operar: %s", _Symbol, reason);
}
//+------------------------------------------------------------------+
