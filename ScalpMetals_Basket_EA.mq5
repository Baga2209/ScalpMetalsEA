//+------------------------------------------------------------------+
//|                                       ScalpMetals_Basket_EA.mq5   |
//|  EA de cesta (basket) para XAUUSDc en MetaTrader 5                |
//|                                                                    |
//|  Implementa docs/ESPECIFICACION_BasketEA.md (v0.1). Las reglas    |
//|  R-01..R-18 del documento se citan en los comentarios del código. |
//|                                                                    |
//|  RESUMEN:                                                          |
//|   - Señal (BB+RSI, toque de nivel, o manual) abre una RÁFAGA de   |
//|     N posiciones a mercado del mismo lado (R-02, R-03).           |
//|   - Si el precio va en contra y toca un soporte/resistencia, se   |
//|     PROMEDIA con otra ráfaga (R-06).                               |
//|   - La cesta se cierra cuando el beneficio NETO de costes alcanza |
//|     el objetivo (R-09) o cuando la pérdida flotante llega al      |
//|     stop de equity (R-10).                                         |
//|   - Escalera anti-martingala: N sube de 2 en 2 tras cesta         |
//|     ganadora, se reinicia tras perdedora (R-14).                   |
//|                                                                    |
//|  AVISO: herramienta de trading algorítmico, no asesoría           |
//|  financiera. Validar en Strategy Tester y demo antes de real.     |
//+------------------------------------------------------------------+
#property copyright "Generado como asistencia técnica - no es asesoría financiera"
#property version   "1.00"

#include <Trade\Trade.mqh>

CTrade trade;

//==================================================================
// ENUMERACIONES DE MODOS (todas seleccionables desde inputs)
//==================================================================
enum ENUM_DIRECTION_MODE
{
   DIR_BUY_ONLY       = 0,  // Solo compras
   DIR_SELL_ONLY      = 1,  // Solo ventas
   DIR_BOTH_BY_SIGNAL = 2   // Ambas, según la señal
};

enum ENUM_SIGNAL_MODE
{
   SIG_BB_RSI        = 0,  // Bollinger + RSI (reversión a la media)
   SIG_SUPPORT_TOUCH = 1,  // Toque de soporte/resistencia (sin RSI)
   SIG_MANUAL        = 2   // Manual: solo botones del panel
};

enum ENUM_LEVEL_MODE
{
   LVL_SWING       = 0,  // Swing low/high de las últimas N velas
   LVL_FRACTAL     = 1,  // Fractales de Bill Williams
   LVL_PIVOT_DAILY = 2,  // Pivot points diarios (S1-S3 / R1-R3)
   LVL_BOLLINGER   = 3,  // Banda de Bollinger exterior
   LVL_FIXED_ATR   = 4   // Rejilla fija cada X ATR
};

enum ENUM_CLOSE_MODE
{
   CLOSE_BASKET_NET   = 0,  // Cesta entera cuando el neto total >= objetivo
   CLOSE_PER_POSITION = 1,  // Cada posición cierra sola en positivo; las demás esperan
   CLOSE_HYBRID       = 2   // Ganadoras individuales + resto por neto conjunto
};

enum ENUM_TARGET_MODE
{
   TGT_PERCENT_BALANCE = 0, // % del balance de apertura de la cesta
   TGT_FIXED_MONEY     = 1, // Cantidad fija en moneda de la cuenta
   TGT_POINTS_FROM_AVG = 2  // Puntos desde el precio medio de la cesta
};

enum ENUM_WEDNESDAY_MODE
{
   WED_IGNORE            = 0, // Sin tratamiento especial
   WED_NO_NEW_BASKETS    = 1, // No abrir cestas nuevas desde la hora de corte
   WED_CLOSE_IF_POSITIVE = 2  // Además, cerrar la cesta si el neto >= 0
};

enum ENUM_NEWS_MODE
{
   NEWS_IGNORE            = 0, // Sin filtro de noticias
   NEWS_BLOCK_ENTRIES     = 1, // Bloquear ráfagas alrededor de noticias de alto impacto
   NEWS_CLOSE_IF_POSITIVE = 2  // Además, cerrar la cesta antes de la noticia si el neto >= 0
};

enum ENUM_BASKET_STATE
{
   ST_IDLE    = 0,
   ST_OPEN    = 1,
   ST_CLOSING = 2
};

//==================================================================
// INPUTS
//==================================================================
input group "=== IDENTIFICACIÓN ==="
input long   InpMagicNumber        = 202610030;  // Número mágico (distinto del EA de posición única)
input string InpTradeComment       = "SMBasket";  // Prefijo del comentario de las órdenes

input group "=== DIRECCIÓN ==="
input ENUM_DIRECTION_MODE InpDirectionMode = DIR_BOTH_BY_SIGNAL; // Dirección permitida

input group "=== SEÑAL DE ENTRADA (dispara la ráfaga inicial) ==="
input ENUM_SIGNAL_MODE InpSignalMode = SIG_BB_RSI;   // Tipo de señal
input ENUM_TIMEFRAMES  InpAnalysisTF = PERIOD_M5;    // Timeframe de la señal
input int    InpBBPeriod             = 20;           // Periodo Bollinger
input double InpBBDeviation          = 2.0;          // Desviación Bollinger
input int    InpRSIPeriod            = 14;           // Periodo RSI
input double InpRSIOversold          = 30.0;         // RSI sobreventa (compra)
input double InpRSIOverbought        = 70.0;         // RSI sobrecompra (venta)
input bool   InpRequireRejectionCandle = true;       // Exigir vela de rechazo en la señal

input group "=== RÁFAGA Y ESCALERA ==="
input int    InpLadderStart          = 2;     // Tamaño de ráfaga inicial
input int    InpLadderStep           = 2;     // Incremento por cesta ganadora
input int    InpLadderMax            = 10;    // Techo de la escalera
input bool   InpLadderResetOnLoss    = true;  // Perdedora: volver al inicio (false = bajar un escalón)
input bool   InpLadderResetOnDay     = false; // Reiniciar la escalera cada día
input int    InpBurstDelayMs         = 400;   // Milisegundos entre órdenes de la ráfaga
input double InpBurstMaxSpreadPoints = 200;   // Spread máximo durante la ráfaga (puntos)
input double InpBurstMaxSlippagePoints = 30;  // Distancia máxima entre primer y último fill (puntos)

input group "=== PROMEDIADO (entradas adicionales en contra) ==="
input int    InpMaxAveragingLevels     = 2;     // Ráfagas adicionales permitidas (0 = sin promediado)
input int    InpAveragingBurstSize     = 0;     // Tamaño de ráfaga de promediado (0 = igual que N)
input double InpAveragingLotMultiplier = 1.0;   // Multiplicador de lote por nivel (1.0 = iguales)
input double InpMinAveragingDistanceATR = 0.8;  // Distancia mínima entre niveles (ATR)
input bool   InpAveragingRequireRejection = true; // Exigir vela de rechazo antes de promediar

input group "=== DETECCIÓN DE SOPORTE / RESISTENCIA ==="
input ENUM_LEVEL_MODE InpLevelMode   = LVL_SWING;   // Método de detección de niveles
input ENUM_TIMEFRAMES InpLevelTF     = PERIOD_M15;  // Timeframe de los niveles
input int    InpSwingLookback        = 20;    // LVL_SWING: velas hacia atrás
input int    InpFractalMinAgeBars    = 3;     // LVL_FRACTAL: edad mínima del fractal (velas)
input int    InpPivotLevelsToUse     = 3;     // LVL_PIVOT_DAILY: usar S1..Sn / R1..Rn (1-3)
input double InpLevelToleranceATR    = 0.3;   // Tolerancia alrededor del nivel (ATR)
input double InpFixedGridATR         = 1.0;   // LVL_FIXED_ATR: distancia entre niveles (ATR)

input group "=== CIERRE DE LA CESTA ==="
input ENUM_CLOSE_MODE  InpCloseMode  = CLOSE_BASKET_NET;     // Modo de cierre
input ENUM_TARGET_MODE InpTargetMode = TGT_PERCENT_BALANCE;  // Cómo se define el objetivo
input double InpTargetPercent        = 0.4;   // Objetivo neto como % del balance
input double InpTargetMoney          = 10.0;  // Objetivo neto fijo (moneda de la cuenta)
input double InpTargetPoints         = 150;   // Objetivo en puntos desde el precio medio
input double InpPerPositionTargetPoints = 80; // Objetivo neto por posición (modos PER_POSITION / HYBRID)
input int    InpMaxBasketAgeHours    = 48;    // Edad máxima: cerrar con neto >= 0 (0 = sin límite)

input group "=== COSTES (para que el objetivo sea neto) ==="
input double InpCommissionPerLotRoundTrip = 0.0; // Comisión ida+vuelta por lote
input double InpTaxPercentOnProfit   = 0.0;   // Reserva de impuestos (% del beneficio bruto)
input bool   InpIncludeSwapInNet     = true;  // Incluir swap real acumulado
input bool   InpEstimateSpreadOnClose = true; // Restar el spread del cierre

input group "=== RIESGO ==="
input double InpBasketRiskPercent    = 3.0;   // Riesgo TOTAL de la cesta (% del balance) = stop de equity
input bool   InpRiskScalesWithLadder = false; // Riesgo crece con la escalera (N / LadderMax)
input double InpStopDistanceATR      = 3.0;   // Distancia hipotética al stop para dimensionar (ATR)
input double InpMaxTotalLots         = 5.0;   // Techo de lotes sumados de la cesta
input double InpMaxDailyDrawdownPercent  = 6.0;  // Drawdown diario máximo (%)
input double InpMaxGlobalDrawdownPercent = 12.0; // Drawdown global máximo desde pico de equity (%)
input bool   InpCloseAllOnGlobalLimit    = true; // Cerrar todo al alcanzar el límite global

input group "=== FILTRO DE SWAP TRIPLE ==="
input ENUM_WEDNESDAY_MODE InpWednesdayMode = WED_CLOSE_IF_POSITIVE; // Tratamiento del día de swap triple
input int    InpWednesdayCutoffHour  = 20;    // Hora de corte (servidor)
input int    InpSwapTripleDay        = 3;     // Día de swap triple (0=Dom, 1=Lun, 2=Mar, 3=Mié ... 6=Sáb)

input group "=== FILTROS DE EJECUCIÓN ==="
input double InpMaxSpreadPoints      = 200;   // Spread máximo para abrir ráfagas (puntos)
input int    InpATRPeriod            = 14;    // Periodo ATR
input double InpATRMinPoints         = 50;    // ATR mínimo (puntos)
input double InpATRMaxPoints         = 900;   // ATR máximo (puntos)
input int    InpSlippagePoints       = 20;    // Desviación máxima por orden
input int    InpMaxOrderRetries      = 3;     // Reintentos ante requote

input group "=== FILTRO DE HORARIO (hora del servidor) ==="
input bool   InpUseSessionFilter     = true;  // Activar ventanas horarias
input int    InpSession1StartHour    = 8;     // Inicio ventana 1
input int    InpSession1EndHour      = 11;    // Fin ventana 1
input bool   InpUseSession2          = true;  // Activar ventana 2
input int    InpSession2StartHour    = 13;    // Inicio ventana 2
input int    InpSession2EndHour      = 16;    // Fin ventana 2

input group "=== FILTRO DE ROLLOVER Y BORDES DE SEMANA ==="
input bool   InpAvoidRollover        = true;  // Evitar rollover diario
input int    InpRolloverStartHour    = 22;    // Inicio rollover
input int    InpRolloverEndHour      = 23;    // Fin rollover
input bool   InpAvoidMondayOpenGap   = true;  // Evitar primera hora tras apertura semanal
input int    InpMondayAvoidUntilHour = 1;     // No operar hasta esta hora del lunes
input bool   InpAvoidFridayClose     = true;  // No abrir cestas cerca del cierre del viernes
input int    InpFridayCutoffHour     = 20;    // Hora de corte del viernes

input group "=== FILTRO DE NOTICIAS ==="
input ENUM_NEWS_MODE InpNewsMode     = NEWS_CLOSE_IF_POSITIVE; // Tratamiento de noticias de alto impacto (calendario MT5)
input int    InpNewsMinutesBefore    = 15;    // Minutos de bloqueo antes
input int    InpNewsMinutesAfter     = 15;    // Minutos de bloqueo después
input string InpNewsCurrency         = "USD"; // Divisa filtrada

input group "=== PANEL Y REGISTRO ==="
input bool   InpShowPanel            = true;  // Mostrar panel en el gráfico
input bool   InpPanelManualButtons   = true;  // Mostrar botones manuales
input bool   InpVerboseLogging       = true;  // Registrar motivos de bloqueo

input group "=== LÍNEAS EN EL GRÁFICO ==="
input bool   InpDrawLines            = true;          // Dibujar líneas de la cesta en el gráfico
input color  InpLineEntryColor       = clrYellow;     // Arranque de la cesta (primera entrada)
input color  InpLineStopColor        = clrRed;        // Precio aproximado del stop de equity y del límite diario
input color  InpLineTargetColor      = clrLime;       // Precio aproximado del objetivo
input color  InpLineAvgColor         = clrOrange;     // Precio medio de la cesta
input color  InpLineNextLevelColor   = clrDodgerBlue; // Próximo nivel de promediado

//==================================================================
// ESTADO GLOBAL
//==================================================================
int hBB = INVALID_HANDLE, hRSI = INVALID_HANDLE, hATR = INVALID_HANDLE;
int hLevelBB = INVALID_HANDLE, hFractal = INVALID_HANDLE;

string g_gvAccount = "";   // prefijo de GV a nivel de cuenta (drawdown)
string g_gvBasket  = "";   // prefijo de GV a nivel de instancia (cesta)

ENUM_BASKET_STATE g_state = ST_IDLE;
long     g_basketId        = 0;
int      g_basketDir       = 0;      // +1 BUY, -1 SELL
double   g_basketOpenBalance = 0.0;
datetime g_basketOpenTime  = 0;
int      g_ladderN         = 2;
int      g_levelsUsed      = 0;
double   g_lastLevelPrice  = 0.0;
double   g_riskMoney       = 0.0;
double   g_lotPerPosition  = 0.0;
int      g_capacity        = 0;
bool     g_manualClose     = false;  // la cesta se cerró a mano: no mueve la escalera
bool     g_paused          = false;
int      g_pendingManual   = 0;      // +1 / -1 desde los botones
bool     g_closeRequested  = false;

datetime g_lastBarTime     = 0;
bool     g_newBarThisTick  = false;
bool     g_dailyHaltAlerted  = false;
bool     g_globalHaltAlerted = false;
string   g_blockReason     = "";
datetime g_lastPanelUpdate = 0;
double   g_firstEntryPrice = 0.0;    // precio medio de la primera ráfaga (línea amarilla)
datetime g_newsCacheTime   = 0;
bool     g_newsBlackout    = false;
datetime g_newsNextTime    = 0;
string   g_newsNextName    = "";
double   g_hist[10];                 // resultados de las últimas cestas (0 = más reciente)
int      g_histN           = 0;
datetime g_lastSwapLogDay  = 0;

struct BasketStats
{
   int      count;
   double   lots;
   double   avgPrice;
   double   gross;
   double   swap;
   double   commission;
   double   spreadCost;
   double   netPreTax;
   double   net;
   datetime oldest;
};

#define PANEL_PREFIX "SMBP_"

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetAsyncMode(false);

   if(InpLadderStart < 1 || InpLadderStep < 1 || InpLadderMax < InpLadderStart)
   {
      Print("ERROR: parámetros de escalera inválidos (Start>=1, Step>=1, Max>=Start).");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpBasketRiskPercent <= 0.0 || InpStopDistanceATR <= 0.0)
   {
      Print("ERROR: InpBasketRiskPercent y InpStopDistanceATR deben ser > 0.");
      return INIT_PARAMETERS_INCORRECT;
   }

   hBB  = iBands(_Symbol, InpAnalysisTF, InpBBPeriod, 0, InpBBDeviation, PRICE_CLOSE);
   hRSI = iRSI(_Symbol, InpAnalysisTF, InpRSIPeriod, PRICE_CLOSE);
   hATR = iATR(_Symbol, InpAnalysisTF, InpATRPeriod);
   if(hBB == INVALID_HANDLE || hRSI == INVALID_HANDLE || hATR == INVALID_HANDLE)
   {
      Print("ERROR CRÍTICO: no se pudieron crear los handles de BB/RSI/ATR.");
      return INIT_FAILED;
   }
   if(InpLevelMode == LVL_BOLLINGER)
   {
      hLevelBB = iBands(_Symbol, InpLevelTF, InpBBPeriod, 0, InpBBDeviation, PRICE_CLOSE);
      if(hLevelBB == INVALID_HANDLE) { Print("ERROR: handle BB de niveles."); return INIT_FAILED; }
   }
   if(InpLevelMode == LVL_FRACTAL)
   {
      hFractal = iFractals(_Symbol, InpLevelTF);
      if(hFractal == INVALID_HANDLE) { Print("ERROR: handle de fractales."); return INIT_FAILED; }
   }

   g_gvAccount = StringFormat("SMBasket_%d_", (int)AccountInfoInteger(ACCOUNT_LOGIN));
   g_gvBasket  = StringFormat("SMB_%d_%s_", (int)InpMagicNumber, _Symbol);

   InitRiskTrackingIfNeeded();
   LoadBasketState();          // R-15
   ReconstructFromPositions(); // R-15

   if(InpShowPanel) PanelCreate();

   PrintFormat("ScalpMetals_Basket_EA iniciado en %s | Magic=%d | Estado=%s | Escalón N=%d | Cierre=%s | Niveles=%s | Dir=%s",
               _Symbol, (int)InpMagicNumber, EnumToString(g_state), g_ladderN,
               EnumToString(InpCloseMode), EnumToString(InpLevelMode), EnumToString(InpDirectionMode));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   SaveBasketState();
   if(hBB      != INVALID_HANDLE) IndicatorRelease(hBB);
   if(hRSI     != INVALID_HANDLE) IndicatorRelease(hRSI);
   if(hATR     != INVALID_HANDLE) IndicatorRelease(hATR);
   if(hLevelBB != INVALID_HANDLE) IndicatorRelease(hLevelBB);
   if(hFractal != INVALID_HANDLE) IndicatorRelease(hFractal);
   PanelDelete();
}

//+------------------------------------------------------------------+
//| OnTick — orquestador                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   g_newBarThisTick = IsNewBar();
   g_blockReason = "";

   // --- Riesgo de cuenta (R-16): siempre, antes que nada ---
   UpdateEquityTracking();
   bool globalHalted = IsGlobalDrawdownExceeded();
   bool dailyHalted  = IsDailyDrawdownExceeded();

   if(globalHalted)
   {
      HandleGlobalHalt();
      g_blockReason = "DETENIDO: drawdown global";
      PanelUpdate();
      return;
   }

   // --- Gestión de la cesta abierta (R-07..R-12): cada tick, sin filtros de sesión ---
   if(g_state == ST_OPEN || g_state == ST_CLOSING)
   {
      ManageBasket(dailyHalted);
      FinalizeBasketIfEmpty();
   }

   if(dailyHalted)
   {
      if(!g_dailyHaltAlerted)
      {
         string msg = StringFormat("[%s] LÍMITE DE DRAWDOWN DIARIO (%.2f%%). Sin cestas nuevas hasta mañana.",
                                   _Symbol, InpMaxDailyDrawdownPercent);
         Print(msg); Alert(msg);
         g_dailyHaltAlerted = true;
      }
      g_blockReason = "Drawdown diario alcanzado";
      PanelUpdate();
      return;
   }

   // --- Botones manuales ---
   if(g_closeRequested)
   {
      g_closeRequested = false;
      if(g_state == ST_OPEN)
      {
         g_manualClose = true;
         CloseBasket("Cierre manual desde el panel");
      }
   }

   if(g_state == ST_IDLE && g_pendingManual != 0)
   {
      int dir = g_pendingManual;
      g_pendingManual = 0;
      if(!IsMarketOpen())              g_blockReason = "Manual: mercado cerrado";
      else if(!IsSpreadAcceptable())   g_blockReason = "Manual: spread alto";
      else StartBasket(dir, true);     // R-18
      PanelUpdate();
      return;
   }

   // --- Apertura automática de cesta (R-01, R-02) ---
   if(g_state == ST_IDLE && !g_paused)
   {
      string reason = "";
      if(!EntryFiltersOk(reason, true))
         g_blockReason = reason;
      else if(InpSignalMode != SIG_MANUAL)
      {
         int dir = 0;
         if(InpSignalMode == SIG_BB_RSI && g_newBarThisTick)
            dir = EvaluateBBRSISignal();
         else if(InpSignalMode == SIG_SUPPORT_TOUCH)
            dir = EvaluateSupportTouchSignal();

         if(dir != 0 && DirectionAllowed(dir))
            StartBasket(dir, false);
         else if(dir != 0)
            g_blockReason = "Señal en dirección no permitida";
      }
      else
         g_blockReason = "Modo manual: esperando botón";
   }
   else if(g_paused)
      g_blockReason = "PAUSADO por el usuario";

   PanelUpdate();
}

//+------------------------------------------------------------------+
//| OnChartEvent — botones del panel                                  |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK) return;
   if(StringFind(sparam, PANEL_PREFIX) != 0) return;

   ObjectSetInteger(0, sparam, OBJPROP_STATE, false);

   if(sparam == PANEL_PREFIX + "BtnClose")      g_closeRequested = true;
   else if(sparam == PANEL_PREFIX + "BtnPause") { g_paused = !g_paused; PrintFormat("EA %s", g_paused ? "PAUSADO" : "REANUDADO"); }
   else if(sparam == PANEL_PREFIX + "BtnBuy")   g_pendingManual = +1;
   else if(sparam == PANEL_PREFIX + "BtnSell")  g_pendingManual = -1;

   ChartRedraw();
}

//+------------------------------------------------------------------+
//|  MÓDULO 1: FILTROS DE MERCADO (heredados, sección 3.11)           |
//+------------------------------------------------------------------+
bool IsMarketOpen()
{
   datetime lastTick = (datetime)SymbolInfoInteger(_Symbol, SYMBOL_TIME);
   if(TimeCurrent() - lastTick > 300) return false;
   datetime from, to;
   if(!SymbolInfoSessionTrade(_Symbol, (ENUM_DAY_OF_WEEK)TimeDayOfWeek(TimeCurrent()), 0, from, to))
      return false;
   return true;
}

bool IsWithinTradingSession(datetime t)
{
   if(!InpUseSessionFilter) return true;
   int h = TimeHourOf(t);
   bool s1 = (h >= InpSession1StartHour && h < InpSession1EndHour);
   bool s2 = InpUseSession2 && (h >= InpSession2StartHour && h < InpSession2EndHour);
   return (s1 || s2);
}

bool IsRolloverWindow(datetime t)
{
   int h = TimeHourOf(t);
   if(InpRolloverStartHour <= InpRolloverEndHour)
      return (h >= InpRolloverStartHour && h < InpRolloverEndHour);
   return (h >= InpRolloverStartHour || h < InpRolloverEndHour);
}

bool IsWeekEdgeBlocked(datetime t)
{
   int dow = TimeDayOfWeek(t);
   int h   = TimeHourOf(t);
   if(InpAvoidMondayOpenGap && dow == 1 && h < InpMondayAvoidUntilHour) return true;
   if(InpAvoidFridayClose   && dow == 5 && h >= InpFridayCutoffHour)    return true;
   if(InpAvoidMondayOpenGap && dow == 0) return true;
   return false;
}

bool IsSpreadAcceptable()
{
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return (spread > 0 && spread <= (long)InpMaxSpreadPoints);
}

// ATR de la vela cerrada, en precio (no en puntos)
double GetATR()
{
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(hATR, 0, 1, 1, buf) <= 0) return 0.0;
   return buf[0];
}

bool IsVolatilityAcceptable(double &atrPointsOut)
{
   double atr = GetATR();
   if(atr <= 0.0) { atrPointsOut = 0.0; return false; }
   atrPointsOut = atr / _Point;
   return (atrPointsOut >= InpATRMinPoints && atrPointsOut <= InpATRMaxPoints);
}

// Consulta el calendario UNA vez por minuto: bloqueo actual y próxima noticia de alto impacto (24 h)
void RefreshNews()
{
   if(InpNewsMode == NEWS_IGNORE) { g_newsBlackout = false; g_newsNextTime = 0; g_newsNextName = ""; return; }
   if(g_newsCacheTime > 0 && TimeCurrent() - g_newsCacheTime < 60) return;
   g_newsCacheTime = TimeCurrent();
   g_newsBlackout = false; g_newsNextTime = 0; g_newsNextName = "";

   static bool warnedNoCalendar = false;
   datetime from = TimeCurrent() - (InpNewsMinutesAfter + 5) * 60;
   datetime to   = TimeCurrent() + 24 * 3600;

   MqlCalendarValue values[];
   int total = CalendarValueHistory(values, from, to, NULL, InpNewsCurrency);
   if(total <= 0)
   {
      if(!warnedNoCalendar && InpVerboseLogging)
      {
         Print("AVISO: el Calendario Económico no devolvió eventos. El filtro de noticias no está activo en este entorno (normal en el Strategy Tester).");
         warnedNoCalendar = true;
      }
      return;
   }
   for(int i = 0; i < total; i++)
   {
      MqlCalendarEvent evt;
      if(!CalendarEventById(values[i].event_id, evt)) continue;
      if(evt.importance != CALENDAR_IMPORTANCE_HIGH) continue;
      datetime t = values[i].time;
      if(TimeCurrent() >= t - InpNewsMinutesBefore * 60 && TimeCurrent() <= t + InpNewsMinutesAfter * 60)
         g_newsBlackout = true;
      if(t > TimeCurrent() && (g_newsNextTime == 0 || t < g_newsNextTime))
      {
         g_newsNextTime = t;
         g_newsNextName = evt.name;
      }
   }
}

bool IsNewsBlackout()
{
   RefreshNews();
   return g_newsBlackout;
}

// ¿La próxima noticia de alto impacto cae dentro de la ventana "antes"? (cierre preventivo)
bool IsNewsImminent()
{
   RefreshNews();
   return (g_newsNextTime > 0 && g_newsNextTime - TimeCurrent() <= InpNewsMinutesBefore * 60);
}

// R-12: bloqueo de cestas nuevas el día de swap triple desde la hora de corte
bool IsWednesdayBlocked(datetime t)
{
   if(InpWednesdayMode == WED_IGNORE) return false;
   return (TimeDayOfWeek(t) == InpSwapTripleDay && TimeHourOf(t) >= InpWednesdayCutoffHour);
}

// Todos los filtros que bloquean RÁFAGAS (inicial y de promediado). Nunca bloquean cierres.
bool EntryFiltersOk(string &reason, bool forNewBasket)
{
   datetime now = TimeCurrent();
   if(!IsMarketOpen())                              { reason = "Mercado cerrado / sin cotización"; return false; }
   if(!IsWithinTradingSession(now))                 { reason = "Fuera de ventana horaria"; return false; }
   if(InpAvoidRollover && IsRolloverWindow(now))    { reason = "Ventana de rollover"; return false; }
   if(IsWeekEdgeBlocked(now))                       { reason = "Borde de semana"; return false; }
   if(forNewBasket && IsWednesdayBlocked(now))      { reason = "Día de swap triple: sin cestas nuevas"; return false; }
   if(!IsSpreadAcceptable())
   {
      reason = StringFormat("Spread %d > %.0f pts", (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD), InpMaxSpreadPoints);
      return false;
   }
   if(InpNewsMode != NEWS_IGNORE && IsNewsBlackout()) { reason = "Noticia de alto impacto"; return false; }
   double atrPts = 0.0;
   if(!IsVolatilityAcceptable(atrPts))
   {
      reason = StringFormat("ATR %.0f pts fuera de [%.0f, %.0f]", atrPts, InpATRMinPoints, InpATRMaxPoints);
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//|  MÓDULO 2: SEÑAL DE ENTRADA (R-17 para la dirección)              |
//+------------------------------------------------------------------+
bool DirectionAllowed(int dir)
{
   if(InpDirectionMode == DIR_BUY_ONLY)  return dir > 0;
   if(InpDirectionMode == DIR_SELL_ONLY) return dir < 0;
   return true;
}

int EvaluateBBRSISignal()
{
   double upper[], lower[], rsi[], h[], l[], o[], c[];
   ArraySetAsSeries(upper, true); ArraySetAsSeries(lower, true); ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(h, true); ArraySetAsSeries(l, true); ArraySetAsSeries(o, true); ArraySetAsSeries(c, true);

   if(CopyBuffer(hBB, 1, 0, 3, upper) <= 0) return 0;
   if(CopyBuffer(hBB, 2, 0, 3, lower) <= 0) return 0;
   if(CopyBuffer(hRSI, 0, 0, 3, rsi)  <= 0) return 0;
   if(CopyHigh(_Symbol,  InpAnalysisTF, 0, 3, h) <= 0) return 0;
   if(CopyLow(_Symbol,   InpAnalysisTF, 0, 3, l) <= 0) return 0;
   if(CopyOpen(_Symbol,  InpAnalysisTF, 0, 3, o) <= 0) return 0;
   if(CopyClose(_Symbol, InpAnalysisTF, 0, 3, c) <= 0) return 0;

   bool touchedLower = (l[1] <= lower[1]);
   bool touchedUpper = (h[1] >= upper[1]);
   bool rsiOS = (rsi[1] <= InpRSIOversold);
   bool rsiOB = (rsi[1] >= InpRSIOverbought);
   bool bullRej = (c[1] > lower[1]) && (c[1] > o[1]);
   bool bearRej = (c[1] < upper[1]) && (c[1] < o[1]);

   bool buy  = touchedLower && rsiOS && (!InpRequireRejectionCandle || bullRej);
   bool sell = touchedUpper && rsiOB && (!InpRequireRejectionCandle || bearRej);
   if(buy && !sell) return 1;
   if(sell && !buy) return -1;
   return 0;
}

// SIG_SUPPORT_TOUCH: entra al tocar el nivel del módulo de niveles, sin exigir RSI.
int EvaluateSupportTouchSignal()
{
   double level = 0.0;
   if(DirectionAllowed(1) && GetLevel(1, 0.0, level) && IsPriceAtLevel(1, level))
   {
      if(!InpRequireRejectionCandle || (g_newBarThisTick && IsRejectionCandle(1, level)))
         return 1;
   }
   if(DirectionAllowed(-1) && GetLevel(-1, 0.0, level) && IsPriceAtLevel(-1, level))
   {
      if(!InpRequireRejectionCandle || (g_newBarThisTick && IsRejectionCandle(-1, level)))
         return -1;
   }
   return 0;
}

//+------------------------------------------------------------------+
//|  MÓDULO DE NIVELES: soporte (BUY) / resistencia (SELL)  (3.6)     |
//|  refPrice: precio del último nivel usado (0 = sin referencia).    |
//|  Devuelve el nivel candidato más cercano por debajo (BUY) o por   |
//|  encima (SELL) del precio actual.                                 |
//+------------------------------------------------------------------+
bool GetLevel(int dir, double refPrice, double &level)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double atr = GetATR();
   if(atr <= 0.0) return false;
   double tol = InpLevelToleranceATR * atr;
   level = 0.0;

   switch(InpLevelMode)
   {
      case LVL_SWING:
      {
         double arr[];
         ArraySetAsSeries(arr, true);
         if(dir > 0)
         {
            if(CopyLow(_Symbol, InpLevelTF, 1, InpSwingLookback, arr) <= 0) return false;
            level = arr[ArrayMinimum(arr)];
         }
         else
         {
            if(CopyHigh(_Symbol, InpLevelTF, 1, InpSwingLookback, arr) <= 0) return false;
            level = arr[ArrayMaximum(arr)];
         }
         return (level > 0.0);
      }

      case LVL_FRACTAL:
      {
         double buf[];
         ArraySetAsSeries(buf, true);
         int bufIdx = (dir > 0) ? 1 : 0;   // 0 = fractal superior, 1 = inferior
         int bars = 200;
         if(CopyBuffer(hFractal, bufIdx, InpFractalMinAgeBars, bars, buf) <= 0) return false;
         // el más reciente que esté del lado correcto del precio
         for(int i = 0; i < ArraySize(buf); i++)
         {
            if(buf[i] == EMPTY_VALUE || buf[i] == 0.0) continue;
            if(dir > 0 && buf[i] <= bid + tol) { level = buf[i]; return true; }
            if(dir < 0 && buf[i] >= ask - tol) { level = buf[i]; return true; }
         }
         return false;
      }

      case LVL_PIVOT_DAILY:
      {
         MqlRates r[];
         ArraySetAsSeries(r, true);
         if(CopyRates(_Symbol, PERIOD_D1, 1, 1, r) <= 0) return false;
         double H = r[0].high, L = r[0].low, C = r[0].close;
         double P = (H + L + C) / 3.0;
         double S[3], R[3];
         S[0] = 2.0 * P - H;  S[1] = P - (H - L);  S[2] = L - 2.0 * (H - P);
         R[0] = 2.0 * P - L;  R[1] = P + (H - L);  R[2] = H + 2.0 * (P - L);
         int n = MathMax(1, MathMin(3, InpPivotLevelsToUse));
         if(dir > 0)
         {
            // soporte más alto que esté por debajo del precio (con tolerancia)
            for(int i = 0; i < n; i++)
               if(S[i] <= bid + tol) { level = S[i]; return true; }
         }
         else
         {
            for(int i = 0; i < n; i++)
               if(R[i] >= ask - tol) { level = R[i]; return true; }
         }
         return false;
      }

      case LVL_BOLLINGER:
      {
         double b[];
         ArraySetAsSeries(b, true);
         int bufIdx = (dir > 0) ? 2 : 1;   // 2 = inferior, 1 = superior
         if(CopyBuffer(hLevelBB, bufIdx, 0, 2, b) <= 0) return false;
         level = b[0];
         return (level > 0.0);
      }

      case LVL_FIXED_ATR:
      {
         double base = (refPrice > 0.0) ? refPrice : ((dir > 0) ? ask : bid);
         level = (dir > 0) ? base - InpFixedGridATR * atr : base + InpFixedGridATR * atr;
         return true;
      }
   }
   return false;
}

bool IsPriceAtLevel(int dir, double level)
{
   double atr = GetATR();
   if(atr <= 0.0) return false;
   double tol = InpLevelToleranceATR * atr;
   double px = (dir > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   return (MathAbs(px - level) <= tol);
}

// Vela cerrada (índice 1) del timeframe de análisis que tocó el nivel y cerró a favor
bool IsRejectionCandle(int dir, double level)
{
   double atr = GetATR();
   if(atr <= 0.0) return false;
   double tol = InpLevelToleranceATR * atr;
   MqlRates r[];
   ArraySetAsSeries(r, true);
   if(CopyRates(_Symbol, InpAnalysisTF, 1, 1, r) <= 0) return false;
   if(dir > 0) return (r[0].low  <= level + tol && r[0].close > r[0].open);
   else        return (r[0].high >= level - tol && r[0].close < r[0].open);
}

//+------------------------------------------------------------------+
//|  MÓDULO 3: COSTES, NETO Y OBJETIVO (R-07, R-08)                    |
//+------------------------------------------------------------------+
// Valor en moneda de la cuenta de 1 punto por 1 lote
double PointValuePerLot()
{
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tv <= 0.0 || ts <= 0.0 || _Point <= 0.0) return 0.0;
   return tv / ts * _Point;
}

double ApplyTax(double netPreTax)
{
   if(netPreTax > 0.0 && InpTaxPercentOnProfit > 0.0)
      return netPreTax * (1.0 - InpTaxPercentOnProfit / 100.0);
   return netPreTax;
}

// Neto de UNA posición ya seleccionada con PositionGetTicket / PositionSelectByTicket
double SelectedPositionNet(double &lotsOut)
{
   double lots = PositionGetDouble(POSITION_VOLUME);
   double pvpl = PointValuePerLot();
   double gross = PositionGetDouble(POSITION_PROFIT);
   double swap  = InpIncludeSwapInNet ? PositionGetDouble(POSITION_SWAP) : 0.0;
   double comm  = lots * InpCommissionPerLotRoundTrip;
   double sprd  = InpEstimateSpreadOnClose ? lots * (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * pvpl : 0.0;
   lotsOut = lots;
   return ApplyTax(gross + swap - comm - sprd);
}

bool IsOurPosition()
{
   return (PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber);
}

void ComputeBasketStats(BasketStats &s)
{
   s.count = 0; s.lots = 0.0; s.avgPrice = 0.0; s.gross = 0.0; s.swap = 0.0;
   s.commission = 0.0; s.spreadCost = 0.0; s.netPreTax = 0.0; s.net = 0.0; s.oldest = 0;

   double pvpl = PointValuePerLot();
   double spreadPts = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   double weighted = 0.0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsOurPosition()) continue;
      double lots = PositionGetDouble(POSITION_VOLUME);
      s.count++;
      s.lots += lots;
      weighted += lots * PositionGetDouble(POSITION_PRICE_OPEN);
      s.gross += PositionGetDouble(POSITION_PROFIT);
      s.swap  += PositionGetDouble(POSITION_SWAP);
      s.commission += lots * InpCommissionPerLotRoundTrip;
      s.spreadCost += lots * spreadPts * pvpl;
      datetime t = (datetime)PositionGetInteger(POSITION_TIME);
      if(s.oldest == 0 || t < s.oldest) s.oldest = t;
   }
   if(s.lots > 0.0) s.avgPrice = weighted / s.lots;

   s.netPreTax = s.gross
               + (InpIncludeSwapInNet ? s.swap : 0.0)
               - s.commission
               - (InpEstimateSpreadOnClose ? s.spreadCost : 0.0);
   s.net = ApplyTax(s.netPreTax);
}

double BasketTargetMoney(const BasketStats &s)
{
   switch(InpTargetMode)
   {
      case TGT_PERCENT_BALANCE: return g_basketOpenBalance * InpTargetPercent / 100.0;
      case TGT_FIXED_MONEY:     return InpTargetMoney;
      case TGT_POINTS_FROM_AVG: return InpTargetPoints * s.lots * PointValuePerLot();
   }
   return 0.0;
}

//+------------------------------------------------------------------+
//|  MÓDULO 4: DIMENSIONADO (R-04)                                     |
//+------------------------------------------------------------------+
int AveragingBurstSize()
{
   return (InpAveragingBurstSize > 0) ? InpAveragingBurstSize : g_ladderN;
}

double EffectiveRiskPercent()
{
   if(InpRiskScalesWithLadder)
      return InpBasketRiskPercent * (double)g_ladderN / (double)InpLadderMax;
   return InpBasketRiskPercent;
}

// Calcula lote por posición y capacidad total de la cesta. Devuelve false si no cabe ni 1 posición.
bool ComputeLotPlan(double &lotPerPos, int &capacity, double &riskMoney)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   riskMoney = balance * EffectiveRiskPercent() / 100.0;

   double atr = GetATR();
   double pvpl = PointValuePerLot();
   if(atr <= 0.0 || pvpl <= 0.0) { Print("ERROR: ATR o valor de punto no disponible para dimensionar."); return false; }

   double stopDistPts = InpStopDistanceATR * atr / _Point;
   double lotTotal = riskMoney / (stopDistPts * pvpl);
   lotTotal = MathMin(lotTotal, InpMaxTotalLots);

   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(minLot <= 0.0 || lotStep <= 0.0) return false;

   // capacidad nominal: ráfaga inicial + niveles de promediado (con multiplicador en lotes-equivalentes)
   double capLots = (double)g_ladderN;
   double mult = 1.0;
   for(int k = 0; k < InpMaxAveragingLevels; k++)
   {
      mult *= MathMax(1.0, InpAveragingLotMultiplier);
      capLots += (double)AveragingBurstSize() * mult;
   }
   capacity = g_ladderN + InpMaxAveragingLevels * AveragingBurstSize();

   lotPerPos = lotTotal / capLots;
   lotPerPos = MathFloor(lotPerPos / lotStep) * lotStep;
   lotPerPos = MathMin(lotPerPos, maxLot);

   if(lotPerPos < minLot)
   {
      // No cabe el reparto completo: usar lote mínimo y reducir la capacidad (nunca subir el riesgo)
      int affordable = (int)MathFloor(lotTotal / minLot);
      if(affordable < 1)
      {
         PrintFormat("Sin operar: el riesgo %.2f%% (%.2f) no alcanza ni 1 posición al lote mínimo %.2f con stop a %.0f pts.",
                     EffectiveRiskPercent(), riskMoney, minLot, stopDistPts);
         return false;
      }
      lotPerPos = minLot;
      capacity = MathMin(capacity, affordable);
      PrintFormat("AVISO: lote repartido < mínimo. Se usa %.2f lotes y la capacidad baja a %d posiciones.", lotPerPos, capacity);
   }
   lotPerPos = NormalizeDouble(lotPerPos, 2);
   return true;
}

//+------------------------------------------------------------------+
//|  MÓDULO 5: CESTA — apertura, ráfaga, promediado, cierre           |
//+------------------------------------------------------------------+
// R-02: nueva cesta
void StartBasket(int dir, bool isManual)
{
   double lotPerPos = 0.0, riskMoney = 0.0;
   int capacity = 0;
   if(!ComputeLotPlan(lotPerPos, capacity, riskMoney))
   {
      g_blockReason = "Lote insuficiente para el riesgo configurado";
      return;
   }

   g_basketId   = (long)TimeCurrent();
   g_basketDir  = dir;
   g_basketOpenBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_basketOpenTime    = TimeCurrent();
   g_levelsUsed   = 0;
   g_lastLevelPrice = 0.0;
   g_firstEntryPrice = 0.0;
   g_riskMoney    = riskMoney;
   g_lotPerPosition = lotPerPos;
   g_capacity     = capacity;
   g_manualClose  = false;
   g_state        = ST_OPEN;
   SaveBasketState();

   int burst = MathMin(g_ladderN, capacity);
   PrintFormat("=== CESTA #%I64d ABIERTA (%s, %s) | N=%d | lote/pos=%.2f | capacidad=%d | riesgo=%.2f (%.2f%%) ===",
               g_basketId, (dir > 0 ? "BUY" : "SELL"), (isManual ? "manual" : "auto"),
               burst, lotPerPos, capacity, riskMoney, EffectiveRiskPercent());

   double avgFill = 0.0;
   int opened = OpenBurst(dir, burst, lotPerPos, 0, avgFill);
   if(opened == 0)
   {
      Print("Ráfaga inicial sin ninguna orden ejecutada. Cesta cancelada.");
      g_state = ST_IDLE;
      SaveBasketState();
      return;
   }
   g_lastLevelPrice  = avgFill;   // referencia para la distancia mínima de promediado
   g_firstEntryPrice = avgFill;   // arranque de la cesta (línea amarilla)
   SaveBasketState();
}

// R-03: ráfaga de `count` órdenes. Devuelve cuántas se abrieron; avgFill = precio medio de la ráfaga.
int OpenBurst(int dir, int count, double lots, int levelIdx, double &avgFill)
{
   int opened = 0;
   double firstFill = 0.0, sumFill = 0.0;
   ENUM_ORDER_TYPE type = (dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   string comment = StringFormat("%s#%I64d L%d", InpTradeComment, g_basketId, levelIdx);

   for(int n = 0; n < count; n++)
   {
      if(n > 0 && InpBurstDelayMs > 0) Sleep(InpBurstDelayMs);   // Sleep se ignora en el Strategy Tester

      long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      if(spread > (long)InpBurstMaxSpreadPoints)
      {
         PrintFormat("Ráfaga detenida en %d/%d: spread %d > %.0f pts.", n, count, (int)spread, InpBurstMaxSpreadPoints);
         break;
      }

      double fill = 0.0;
      if(!SendMarketOrder(type, lots, comment, fill))
      {
         PrintFormat("Ráfaga detenida en %d/%d: orden rechazada.", n, count);
         break;
      }
      opened++;
      sumFill += fill;
      if(firstFill == 0.0) firstFill = fill;
      else if(MathAbs(fill - firstFill) / _Point > InpBurstMaxSlippagePoints)
      {
         PrintFormat("Ráfaga detenida en %d/%d: deslizamiento %.0f pts > %.0f.", opened, count,
                     MathAbs(fill - firstFill) / _Point, InpBurstMaxSlippagePoints);
         break;
      }
   }
   avgFill = (opened > 0) ? sumFill / opened : 0.0;
   PrintFormat("Ráfaga nivel %d: %d/%d órdenes %s de %.2f lotes, fill medio %.*f",
               levelIdx, opened, count, EnumToString(type), lots, _Digits, avgFill);
   return opened;
}

bool SendMarketOrder(ENUM_ORDER_TYPE type, double lots, string comment, double &fillPrice)
{
   for(int attempt = 1; attempt <= InpMaxOrderRetries; attempt++)
   {
      double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      bool ok = (type == ORDER_TYPE_BUY) ? trade.Buy(lots, _Symbol, price, 0.0, 0.0, comment)
                                         : trade.Sell(lots, _Symbol, price, 0.0, 0.0, comment);
      uint rc = trade.ResultRetcode();
      if(ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_DONE_PARTIAL))
      {
         fillPrice = trade.ResultPrice();
         if(fillPrice <= 0.0) fillPrice = price;
         return true;
      }
      if(rc == TRADE_RETCODE_REQUOTE || rc == TRADE_RETCODE_PRICE_CHANGED ||
         rc == TRADE_RETCODE_PRICE_OFF || rc == TRADE_RETCODE_TIMEOUT)
      {
         PrintFormat("Reintento %d/%d tras retcode=%d (%s)", attempt, InpMaxOrderRetries, rc, trade.ResultRetcodeDescription());
         Sleep(200);
         continue;
      }
      PrintFormat("ERROR orden %s: retcode=%d (%s). Sin reintento.", EnumToString(type), rc, trade.ResultRetcodeDescription());
      return false;
   }
   return false;
}

// Gestión por tick de la cesta abierta
void ManageBasket(bool dailyHalted)
{
   BasketStats s;
   ComputeBasketStats(s);
   if(s.count == 0) return;   // FinalizeBasketIfEmpty se encarga

   if(g_state == ST_CLOSING)
   {
      CloseBasket("Reintento de cierre");   // quedaron posiciones sin cerrar en el intento anterior
      return;
   }

   // R-10: stop de equity. Prioridad absoluta, por tick, ignora filtros.
   if(s.netPreTax <= -g_riskMoney)
   {
      PrintFormat("STOP DE EQUITY: neto %.2f <= -%.2f", s.netPreTax, g_riskMoney);
      CloseBasket("Stop de equity de la cesta");
      return;
   }

   double target = BasketTargetMoney(s);

   // R-09: cierre por posición (modos PER_POSITION y HYBRID)
   if(InpCloseMode == CLOSE_PER_POSITION || InpCloseMode == CLOSE_HYBRID)
   {
      ClosePositionsInProfit();
      ComputeBasketStats(s);
      if(s.count == 0) return;
   }

   // R-09: cierre de cesta por neto (modos BASKET_NET y HYBRID)
   if(InpCloseMode == CLOSE_BASKET_NET || InpCloseMode == CLOSE_HYBRID)
   {
      if(s.net >= target)
      {
         PrintFormat("OBJETIVO ALCANZADO: neto %.2f >= %.2f", s.net, target);
         CloseBasket("Objetivo neto de la cesta");
         return;
      }
   }

   // R-11: edad máxima
   if(InpMaxBasketAgeHours > 0 && s.oldest > 0)
   {
      double ageH = (double)(TimeCurrent() - s.oldest) / 3600.0;
      if(ageH >= InpMaxBasketAgeHours && s.net >= 0.0)
      {
         PrintFormat("EDAD MÁXIMA: %.1f h con neto %.2f >= 0", ageH, s.net);
         CloseBasket("Edad máxima con neto >= 0");
         return;
      }
   }

   // R-12: antes del rollover del día de swap triple, cerrar si el neto >= 0
   if(InpWednesdayMode == WED_CLOSE_IF_POSITIVE && IsWednesdayBlocked(TimeCurrent()) && s.net >= 0.0)
   {
      PrintFormat("SWAP TRIPLE: cierre con neto %.2f >= 0 antes del rollover", s.net);
      CloseBasket("Evitar swap triple con neto >= 0");
      return;
   }

   // Noticia de alto impacto inminente: cerrar si el neto >= 0 (opcional, InpNewsMode)
   if(InpNewsMode == NEWS_CLOSE_IF_POSITIVE && IsNewsImminent() && s.net >= 0.0)
   {
      PrintFormat("NOTICIA '%s' a las %s: cierre preventivo con neto %.2f >= 0",
                  g_newsNextName, TimeToString(g_newsNextTime, TIME_MINUTES), s.net);
      CloseBasket("Cierre preventivo por noticia de alto impacto");
      return;
   }

   LogDailySwap(s);

   // R-06: promediado
   if(!dailyHalted && !g_paused) TryAveraging(s);
}

// Cierra individualmente las posiciones cuyo neto >= objetivo por posición
void ClosePositionsInProfit()
{
   double pvpl = PointValuePerLot();
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsOurPosition()) continue;
      double lots = 0.0;
      double net = SelectedPositionNet(lots);
      double target = InpPerPositionTargetPoints * lots * pvpl;
      if(net >= target)
      {
         if(trade.PositionClose(ticket))
            PrintFormat("Posición #%I64u cerrada en positivo: neto %.2f >= %.2f", ticket, net, target);
         else
            PrintFormat("ERROR cerrando #%I64u: retcode=%d (%s)", ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
      }
   }
}

// R-06: ¿toca un nivel válido? Entonces ráfaga de promediado.
void TryAveraging(const BasketStats &s)
{
   if(InpMaxAveragingLevels <= 0 || g_levelsUsed >= InpMaxAveragingLevels) return;
   if(s.count >= g_capacity) return;

   // el precio debe ir en contra del precio medio
   double px = (g_basketDir > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(g_basketDir > 0 && px >= s.avgPrice) return;
   if(g_basketDir < 0 && px <= s.avgPrice) return;

   double level = 0.0;
   if(!GetLevel(g_basketDir, g_lastLevelPrice, level)) return;

   // distancia mínima respecto al último nivel usado
   double atr = GetATR();
   if(atr <= 0.0) return;
   double dist = (g_basketDir > 0) ? (g_lastLevelPrice - level) : (level - g_lastLevelPrice);
   if(g_lastLevelPrice > 0.0 && dist < InpMinAveragingDistanceATR * atr) return;

   if(!IsPriceAtLevel(g_basketDir, level)) return;

   if(InpAveragingRequireRejection)
   {
      if(!g_newBarThisTick) return;
      if(!IsRejectionCandle(g_basketDir, level)) return;
   }

   string reason = "";
   if(!EntryFiltersOk(reason, false)) { g_blockReason = "Promediado bloqueado: " + reason; return; }

   int levelIdx = g_levelsUsed + 1;
   int burst = MathMin(AveragingBurstSize(), g_capacity - s.count);
   double lots = g_lotPerPosition * MathPow(MathMax(1.0, InpAveragingLotMultiplier), levelIdx);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   lots = NormalizeDouble(MathMin(MathFloor(lots / lotStep) * lotStep, maxLot), 2);

   PrintFormat("PROMEDIADO nivel %d en %.*f (precio medio %.*f): ráfaga de %d x %.2f lotes",
               levelIdx, _Digits, level, _Digits, s.avgPrice, burst, lots);

   double avgFill = 0.0;
   int opened = OpenBurst(g_basketDir, burst, lots, levelIdx, avgFill);
   if(opened > 0)
   {
      g_levelsUsed = levelIdx;
      g_lastLevelPrice = level;
      SaveBasketState();
   }
}

// Cierra todas las posiciones de la cesta, de la más antigua a la más nueva
void CloseBasket(string reason)
{
   g_state = ST_CLOSING;
   SaveBasketState();

   ulong tickets[]; datetime times[];
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsOurPosition()) continue;
      ArrayResize(tickets, n + 1); ArrayResize(times, n + 1);
      tickets[n] = ticket; times[n] = (datetime)PositionGetInteger(POSITION_TIME);
      n++;
   }
   // orden ascendente por tiempo de apertura (inserción)
   for(int i = 1; i < n; i++)
   {
      ulong t = tickets[i]; datetime tm = times[i]; int j = i - 1;
      while(j >= 0 && times[j] > tm) { tickets[j+1] = tickets[j]; times[j+1] = times[j]; j--; }
      tickets[j+1] = t; times[j+1] = tm;
   }
   for(int i = 0; i < n; i++)
   {
      if(!trade.PositionClose(tickets[i]))
         PrintFormat("ERROR al cerrar #%I64u por '%s': retcode=%d (%s)", tickets[i], reason,
                     trade.ResultRetcode(), trade.ResultRetcodeDescription());
   }
   if(n > 0) PrintFormat("Cierre de cesta #%I64d (%d posiciones): %s", g_basketId, n, reason);
}

// R-13 / R-14: cuando no queda ninguna posición, liquidar el resultado y mover la escalera
void FinalizeBasketIfEmpty()
{
   if(g_state == ST_IDLE) return;
   if(CountEAPositions() > 0) return;

   double result = BasketRealizedResult();
   bool winner = (result > 0.0);

   int before = g_ladderN;
   if(g_manualClose)
   {
      // cierre manual: no mueve la escalera
   }
   else if(winner)
      g_ladderN = MathMin(g_ladderN + InpLadderStep, InpLadderMax);
   else if(InpLadderResetOnLoss)
      g_ladderN = InpLadderStart;
   else
      g_ladderN = MathMax(g_ladderN - InpLadderStep, InpLadderStart);

   PrintFormat("=== CESTA #%I64d CERRADA | resultado neto realizado %.2f (%s) | escalera %d -> %d%s ===",
               g_basketId, result, (winner ? "GANADORA" : "PERDEDORA"), before, g_ladderN,
               (g_manualClose ? " (manual, sin cambio)" : ""));

   PushHistory(result);
   LinesDelete();

   g_state = ST_IDLE;
   g_basketId = 0; g_basketDir = 0; g_levelsUsed = 0; g_lastLevelPrice = 0.0; g_firstEntryPrice = 0.0;
   g_riskMoney = 0.0; g_lotPerPosition = 0.0; g_capacity = 0; g_manualClose = false;
   SaveBasketState();
}

// Historial de las últimas 10 cestas y contador de cestas del día
void PushHistory(double result)
{
   if(g_histN < 10) g_histN++;
   for(int i = g_histN - 1; i > 0; i--) g_hist[i] = g_hist[i - 1];
   g_hist[0] = result;
   GlobalVariableSet(GVB("BasketsToday"), GVGetOrInit(GVB("BasketsToday"), 0.0) + 1.0);
}

// Resultado realizado hoy por este EA (deals de hoy con este magic y símbolo)
double DailyRealizedEA()
{
   datetime d0 = TimeCurrent() - (TimeCurrent() % 86400);
   if(!HistorySelect(d0, TimeCurrent() + 60)) return 0.0;
   double total = 0.0;
   int deals = HistoryDealsTotal();
   for(int i = 0; i < deals; i++)
   {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0) continue;
      if(HistoryDealGetString(d, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(d, DEAL_MAGIC) != InpMagicNumber) continue;
      total += HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_SWAP) + HistoryDealGetDouble(d, DEAL_COMMISSION);
   }
   return total;
}

// Suma exacta de profit + swap + comisión de todos los deals de esta instancia desde la apertura
double BasketRealizedResult()
{
   if(!HistorySelect(g_basketOpenTime - 60, TimeCurrent() + 60)) return 0.0;
   double total = 0.0;
   int deals = HistoryDealsTotal();
   for(int i = 0; i < deals; i++)
   {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0) continue;
      if(HistoryDealGetString(d, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(d, DEAL_MAGIC) != InpMagicNumber) continue;
      total += HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_SWAP) + HistoryDealGetDouble(d, DEAL_COMMISSION);
   }
   return total;
}

int CountEAPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsOurPosition()) continue;
      count++;
   }
   return count;
}

// R-12: registro del swap acumulado una vez al día para evaluar el histórico
void LogDailySwap(const BasketStats &s)
{
   datetime day = (datetime)(TimeCurrent() / 86400);
   if(day == g_lastSwapLogDay) return;
   g_lastSwapLogDay = day;
   if(s.swap != 0.0)
      PrintFormat("SWAP cesta #%I64d: acumulado %.2f en %d posiciones (día %s)", g_basketId, s.swap, s.count,
                  TimeToString(TimeCurrent(), TIME_DATE));
}

//+------------------------------------------------------------------+
//|  PERSISTENCIA (R-15)                                               |
//+------------------------------------------------------------------+
string GVA(string key) { return g_gvAccount + key; }
string GVB(string key) { return g_gvBasket + key; }

double GVGetOrInit(string name, double initValue)
{
   if(GlobalVariableCheck(name)) return GlobalVariableGet(name);
   GlobalVariableSet(name, initValue);
   return initValue;
}

void SaveBasketState()
{
   GlobalVariableSet(GVB("State"),       (double)g_state);
   GlobalVariableSet(GVB("BasketId"),    (double)g_basketId);
   GlobalVariableSet(GVB("Dir"),         (double)g_basketDir);
   GlobalVariableSet(GVB("OpenBalance"), g_basketOpenBalance);
   GlobalVariableSet(GVB("OpenTime"),    (double)g_basketOpenTime);
   GlobalVariableSet(GVB("LadderN"),     (double)g_ladderN);
   GlobalVariableSet(GVB("LevelsUsed"),  (double)g_levelsUsed);
   GlobalVariableSet(GVB("LastLevel"),   g_lastLevelPrice);
   GlobalVariableSet(GVB("RiskMoney"),   g_riskMoney);
   GlobalVariableSet(GVB("LotPerPos"),   g_lotPerPosition);
   GlobalVariableSet(GVB("Capacity"),    (double)g_capacity);
   GlobalVariableSet(GVB("LadderDay"),   MathFloor((double)TimeCurrent() / 86400.0));
   GlobalVariableSet(GVB("FirstEntry"),  g_firstEntryPrice);
   GlobalVariableSet(GVB("HistN"),       (double)g_histN);
   for(int i = 0; i < g_histN; i++) GlobalVariableSet(GVB("H" + IntegerToString(i)), g_hist[i]);
}

void LoadBasketState()
{
   g_state     = (ENUM_BASKET_STATE)(int)GVGetOrInit(GVB("State"), 0.0);
   g_basketId  = (long)GVGetOrInit(GVB("BasketId"), 0.0);
   g_basketDir = (int)GVGetOrInit(GVB("Dir"), 0.0);
   g_basketOpenBalance = GVGetOrInit(GVB("OpenBalance"), 0.0);
   g_basketOpenTime    = (datetime)GVGetOrInit(GVB("OpenTime"), 0.0);
   g_ladderN   = (int)GVGetOrInit(GVB("LadderN"), (double)InpLadderStart);
   g_levelsUsed = (int)GVGetOrInit(GVB("LevelsUsed"), 0.0);
   g_lastLevelPrice = GVGetOrInit(GVB("LastLevel"), 0.0);
   g_riskMoney = GVGetOrInit(GVB("RiskMoney"), 0.0);
   g_lotPerPosition = GVGetOrInit(GVB("LotPerPos"), 0.0);
   g_capacity  = (int)GVGetOrInit(GVB("Capacity"), 0.0);
   g_firstEntryPrice = GVGetOrInit(GVB("FirstEntry"), 0.0);
   g_histN = (int)MathMin(10, GVGetOrInit(GVB("HistN"), 0.0));
   for(int i = 0; i < g_histN; i++) g_hist[i] = GVGetOrInit(GVB("H" + IntegerToString(i)), 0.0);

   g_ladderN = MathMax(InpLadderStart, MathMin(InpLadderMax, g_ladderN));
   if(InpLadderResetOnDay)
   {
      double today = MathFloor((double)TimeCurrent() / 86400.0);
      if(GVGetOrInit(GVB("LadderDay"), today) != today) g_ladderN = InpLadderStart;
   }
}

// Si hay posiciones nuestras pero el estado dice IDLE (o al revés), reconciliar.
void ReconstructFromPositions()
{
   int count = CountEAPositions();
   if(count == 0)
   {
      if(g_state != ST_IDLE)
      {
         Print("Estado guardado con cesta abierta pero sin posiciones: se liquida como cesta cerrada.");
         FinalizeBasketIfEmpty();
      }
      return;
   }
   if(g_state != ST_IDLE) return;   // estado coherente

   // Adoptar las posiciones como cesta
   datetime oldest = 0; int dir = 0; double lots = 0.0; int n = 0; double oldestPrice = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsOurPosition()) continue;
      datetime t = (datetime)PositionGetInteger(POSITION_TIME);
      if(oldest == 0 || t < oldest) { oldest = t; oldestPrice = PositionGetDouble(POSITION_PRICE_OPEN); }
      if(dir == 0) dir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      lots += PositionGetDouble(POSITION_VOLUME); n++;
   }
   g_state = ST_OPEN;
   g_basketId = (long)oldest;
   g_basketDir = dir;
   g_basketOpenTime = oldest;
   g_basketOpenBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_riskMoney = g_basketOpenBalance * EffectiveRiskPercent() / 100.0;
   g_lotPerPosition = (n > 0) ? NormalizeDouble(lots / n, 2) : 0.0;
   g_capacity = MathMax(n, g_ladderN + InpMaxAveragingLevels * AveragingBurstSize());
   g_levelsUsed = 0;
   g_lastLevelPrice = oldestPrice;
   g_firstEntryPrice = oldestPrice;
   SaveBasketState();
   PrintFormat("Cesta reconstruida desde %d posiciones abiertas (%s).", n, (dir > 0 ? "BUY" : "SELL"));
}

//+------------------------------------------------------------------+
//|  DRAWDOWN DIARIO Y GLOBAL (R-16, heredado)                          |
//+------------------------------------------------------------------+
void InitRiskTrackingIfNeeded()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   GVGetOrInit(GVA("DayStartBalance"), balance);
   GVGetOrInit(GVA("DayStamp"), MathFloor((double)TimeCurrent() / 86400.0));
   GVGetOrInit(GVA("EquityPeak"), equity);
   GVGetOrInit(GVA("GlobalHalted"), 0.0);
}

void UpdateEquityTracking()
{
   double today = MathFloor((double)TimeCurrent() / 86400.0);
   double storedDay = GVGetOrInit(GVA("DayStamp"), today);
   if(today != storedDay)
   {
      GlobalVariableSet(GVA("DayStamp"), today);
      GlobalVariableSet(GVA("DayStartBalance"), AccountInfoDouble(ACCOUNT_BALANCE));
      g_dailyHaltAlerted = false;
      GlobalVariableSet(GVB("BasketsToday"), 0.0);
      if(InpLadderResetOnDay && g_state == ST_IDLE) { g_ladderN = InpLadderStart; SaveBasketState(); }
      if(InpVerboseLogging) Print("Nuevo día: contador de drawdown diario reiniciado.");
   }
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double peak   = GVGetOrInit(GVA("EquityPeak"), equity);
   if(equity > peak) GlobalVariableSet(GVA("EquityPeak"), equity);
}

bool IsDailyDrawdownExceeded()
{
   double dayStart = GVGetOrInit(GVA("DayStartBalance"), AccountInfoDouble(ACCOUNT_BALANCE));
   double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
   if(dayStart <= 0) return false;
   return ((dayStart - equity) / dayStart * 100.0 >= InpMaxDailyDrawdownPercent);
}

bool IsGlobalDrawdownExceeded()
{
   if(GVGetOrInit(GVA("GlobalHalted"), 0.0) >= 1.0) return true;
   double peak   = GVGetOrInit(GVA("EquityPeak"), AccountInfoDouble(ACCOUNT_EQUITY));
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(peak <= 0) return false;
   if((peak - equity) / peak * 100.0 >= InpMaxGlobalDrawdownPercent)
   {
      GlobalVariableSet(GVA("GlobalHalted"), 1.0);
      return true;
   }
   return false;
}

void HandleGlobalHalt()
{
   if(!g_globalHaltAlerted)
   {
      string msg = StringFormat("[%s] LÍMITE DE DRAWDOWN GLOBAL (%.2f%%). EA DETENIDO. ", _Symbol, InpMaxGlobalDrawdownPercent);
      msg += InpCloseAllOnGlobalLimit ? "Cerrando la cesta." : "La cesta se mantiene: revisar manualmente.";
      Print(msg); Alert(msg);
      g_globalHaltAlerted = true;
   }
   if(InpCloseAllOnGlobalLimit && g_state != ST_IDLE)
   {
      CloseBasket("Límite de drawdown global");
      FinalizeBasketIfEmpty();
   }
}

//+------------------------------------------------------------------+
//|  PANEL Y LÍNEAS EN EL GRÁFICO (3.12)                               |
//|  Objetos: BG (fondo), Rnn (filas), Btn* (botones),                |
//|  HL_* (líneas horizontales de la cesta activa),                   |
//|  VLS_<id> (línea vertical del arranque; se conserva al cerrar).   |
//+------------------------------------------------------------------+
int g_panelRow = 0;

void PanelRow(int &y, string text, color clr = clrWhite, int lineHeight = 14)
{
   string full = PANEL_PREFIX + StringFormat("R%02d", g_panelRow++);
   if(ObjectFind(0, full) < 0)
   {
      ObjectCreate(0, full, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, full, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, full, OBJPROP_XDISTANCE, 14);
      ObjectSetInteger(0, full, OBJPROP_FONTSIZE, 9);
      ObjectSetString(0, full, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, full, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, full, OBJPROP_HIDDEN, true);
   }
   ObjectSetInteger(0, full, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, full, OBJPROP_COLOR, clr);
   ObjectSetString(0, full, OBJPROP_TEXT, text);
   y += lineHeight;
}

void PanelBackground(int height)
{
   string full = PANEL_PREFIX + "BG";
   if(ObjectFind(0, full) < 0)
   {
      ObjectCreate(0, full, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, full, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, full, OBJPROP_XDISTANCE, 6);
      ObjectSetInteger(0, full, OBJPROP_YDISTANCE, 14);
      ObjectSetInteger(0, full, OBJPROP_XSIZE, 520);
      ObjectSetInteger(0, full, OBJPROP_BGCOLOR, C'18,20,28');
      ObjectSetInteger(0, full, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, full, OBJPROP_COLOR, C'70,80,100');
      ObjectSetInteger(0, full, OBJPROP_BACK, false);
      ObjectSetInteger(0, full, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, full, OBJPROP_HIDDEN, true);
   }
   ObjectSetInteger(0, full, OBJPROP_YSIZE, height);
}

void PanelButton(string name, int x, int y, string text, color bg)
{
   string full = PANEL_PREFIX + name;
   if(ObjectFind(0, full) < 0)
   {
      ObjectCreate(0, full, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, full, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, full, OBJPROP_XSIZE, 118);
      ObjectSetInteger(0, full, OBJPROP_YSIZE, 24);
      ObjectSetInteger(0, full, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, full, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, full, OBJPROP_HIDDEN, true);
   }
   ObjectSetInteger(0, full, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, full, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, full, OBJPROP_BGCOLOR, bg);
   ObjectSetString(0, full, OBJPROP_TEXT, text);
}

void HLine(string name, double price, color clr, ENUM_LINE_STYLE style, int width, string descr)
{
   string full = PANEL_PREFIX + name;
   if(price <= 0.0) { ObjectDelete(0, full); return; }
   if(ObjectFind(0, full) < 0)
   {
      ObjectCreate(0, full, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, full, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, full, OBJPROP_BACK, true);
   }
   ObjectSetDouble(0, full, OBJPROP_PRICE, price);
   ObjectSetInteger(0, full, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, full, OBJPROP_STYLE, style);
   ObjectSetInteger(0, full, OBJPROP_WIDTH, width);
   ObjectSetString(0, full, OBJPROP_TEXT, descr);
   ObjectSetString(0, full, OBJPROP_TOOLTIP, descr);
}

void VLine(string name, datetime t, color clr, string descr)
{
   string full = PANEL_PREFIX + name;
   if(ObjectFind(0, full) >= 0) return;
   ObjectCreate(0, full, OBJ_VLINE, 0, t, 0);
   ObjectSetInteger(0, full, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, full, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, full, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, full, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, full, OBJPROP_BACK, true);
   ObjectSetString(0, full, OBJPROP_TEXT, descr);
   ObjectSetString(0, full, OBJPROP_TOOLTIP, descr);
}

void LinesDelete()
{
   ObjectDelete(0, PANEL_PREFIX + "HL_Entry");
   ObjectDelete(0, PANEL_PREFIX + "HL_Avg");
   ObjectDelete(0, PANEL_PREFIX + "HL_Stop");
   ObjectDelete(0, PANEL_PREFIX + "HL_Daily");
   ObjectDelete(0, PANEL_PREFIX + "HL_Target");
   ObjectDelete(0, PANEL_PREFIX + "HL_Next");
}

string FormatDuration(long seconds)
{
   if(seconds < 0) seconds = 0;
   long h = seconds / 3600, m = (seconds % 3600) / 60;
   if(h >= 48) return StringFormat("%dd %dh", (int)(h / 24), (int)(h % 24));
   return StringFormat("%dh %02dm", (int)h, (int)m);
}

string ProgressBar(double fraction, int width)
{
   if(fraction < 0.0) fraction = 0.0;
   if(fraction > 1.0) fraction = 1.0;
   int filled = (int)MathRound(fraction * width);
   string bar = "";
   for(int i = 0; i < width; i++) bar += (i < filled) ? "#" : ".";
   return bar;
}

string SessionText()
{
   if(!InpUseSessionFilter) return "sin filtro horario";
   int h = TimeHourOf(TimeCurrent());
   string w = StringFormat("%02d-%02dh", InpSession1StartHour, InpSession1EndHour);
   if(InpUseSession2) w += StringFormat(" y %02d-%02dh", InpSession2StartHour, InpSession2EndHour);
   if(IsWithinTradingSession(TimeCurrent())) return "DENTRO (" + w + ")";
   int next;
   if(h < InpSession1StartHour) next = InpSession1StartHour;
   else if(InpUseSession2 && h < InpSession2StartHour) next = InpSession2StartHour;
   else next = InpSession1StartHour;
   return StringFormat("FUERA (%s), próxima %02d:00", w, next);
}

string CloseModeText()
{
   switch(InpCloseMode)
   {
      case CLOSE_BASKET_NET:   return "cesta entera por neto";
      case CLOSE_PER_POSITION: return "posición a posición";
      case CLOSE_HYBRID:       return "híbrido";
   }
   return "";
}

string LevelModeText()
{
   switch(InpLevelMode)
   {
      case LVL_SWING:       return StringFormat("swing %d velas %s", InpSwingLookback, EnumToString(InpLevelTF));
      case LVL_FRACTAL:     return "fractales " + EnumToString(InpLevelTF);
      case LVL_PIVOT_DAILY: return StringFormat("pivots diarios S/R1-%d", InpPivotLevelsToUse);
      case LVL_BOLLINGER:   return "banda Bollinger " + EnumToString(InpLevelTF);
      case LVL_FIXED_ATR:   return StringFormat("rejilla cada %.1f ATR", InpFixedGridATR);
   }
   return "";
}

void PanelCreate()
{
   g_lastPanelUpdate = 0;
   PanelUpdate();
}

void PanelUpdate()
{
   if(!InpShowPanel) return;
   if(TimeCurrent() == g_lastPanelUpdate) return;   // máximo una vez por segundo
   g_lastPanelUpdate = TimeCurrent();

   // ---------- datos ----------
   BasketStats s;
   ComputeBasketStats(s);
   bool   open    = (g_state != ST_IDLE && s.count > 0);
   double pvpl    = PointValuePerLot();
   double target  = open ? BasketTargetMoney(s) : 0.0;
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double dayStart = GVGetOrInit(GVA("DayStartBalance"), balance);
   double peak     = GVGetOrInit(GVA("EquityPeak"), equity);
   double dayPL    = equity - dayStart;
   double dayPct   = (dayStart > 0.0) ? dayPL / dayStart * 100.0 : 0.0;
   double dayLimitMoney = dayStart * InpMaxDailyDrawdownPercent / 100.0;
   double ddGlobal = (peak > 0.0) ? (peak - equity) / peak * 100.0 : 0.0;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double px  = (g_basketDir > 0) ? bid : ask;

   double marginToStop = g_riskMoney + s.netPreTax;
   double stopPrice = 0.0, targetPrice = 0.0, dailyPrice = 0.0;
   double ptsStop = 0.0, ptsTarget = 0.0;
   if(open && s.lots > 0.0 && pvpl > 0.0)
   {
      double perPoint = s.lots * pvpl;
      ptsStop   = marginToStop / perPoint;
      double targetPre = (InpTaxPercentOnProfit > 0.0) ? target / (1.0 - InpTaxPercentOnProfit / 100.0) : target;
      ptsTarget = (targetPre - s.netPreTax) / perPoint;
      double ptsDaily = (equity - (dayStart - dayLimitMoney)) / perPoint;
      if(g_basketDir > 0)
      {
         stopPrice = px - ptsStop * _Point;  targetPrice = px + ptsTarget * _Point;  dailyPrice = px - ptsDaily * _Point;
      }
      else
      {
         stopPrice = px + ptsStop * _Point;  targetPrice = px - ptsTarget * _Point;  dailyPrice = px + ptsDaily * _Point;
      }
   }
   double nextLvl = 0.0;
   bool hasNext = open && g_levelsUsed < InpMaxAveragingLevels && s.count < g_capacity
                  && GetLevel(g_basketDir, g_lastLevelPrice, nextLvl);

   RefreshNews();
   double atrPts = GetATR() / _Point;
   long   spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   double progress = (target > 0.0) ? s.net / target : 0.0;
   int    basketsToday = (int)GVGetOrInit(GVB("BasketsToday"), 0.0);
   double realizedToday = DailyRealizedEA();

   color cSec = clrDeepSkyBlue, cDim = clrSilver, cOk = clrLime, cBad = clrOrangeRed, cWarn = clrKhaki;

   // ---------- filas ----------
   g_panelRow = 0;
   int y = 20;
   PanelRow(y, StringFormat("SCALPMETALS BASKET EA   %s   %s srv", _Symbol, TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS)), clrGold, 18);

   // CESTA
   PanelRow(y, "CESTA", cSec);
   string stateTxt;
   if(g_state == ST_IDLE)         stateTxt = "SIN CESTA (esperando señal)";
   else if(g_state == ST_CLOSING) stateTxt = "CERRANDO...";
   else stateTxt = StringFormat("ABIERTA %s  #%I64d  hace %s", (g_basketDir > 0 ? "BUY" : "SELL"), g_basketId,
                                FormatDuration((long)(TimeCurrent() - g_basketOpenTime)));
   PanelRow(y, " Estado      " + stateTxt, (g_state == ST_IDLE ? cDim : clrWhite));
   PanelRow(y, StringFormat(" Escalón     N=%d de %d   si gana -> %d   si pierde -> %d", g_ladderN, InpLadderMax,
            MathMin(g_ladderN + InpLadderStep, InpLadderMax),
            (InpLadderResetOnLoss ? InpLadderStart : MathMax(g_ladderN - InpLadderStep, InpLadderStart))));
   PanelRow(y, StringFormat(" Posiciones  %d de %d   lotes %.2f   lote/pos %.2f", s.count, g_capacity, s.lots, g_lotPerPosition));
   PanelRow(y, StringFormat(" Promediado  %d de %d niveles   método: %s", g_levelsUsed, InpMaxAveragingLevels, LevelModeText()));
   PanelRow(y, " Próx. nivel " + (hasNext ? StringFormat("%.*f  (línea azul, a %.0f pts)", _Digits, nextLvl, MathAbs(px - nextLvl) / _Point) : "-"),
            (hasNext ? clrDodgerBlue : cDim));
   PanelRow(y, " Arranque    " + (open ? StringFormat("%.*f  %s  (línea amarilla)", _Digits, g_firstEntryPrice,
            TimeToString(g_basketOpenTime, TIME_DATE | TIME_MINUTES)) : "-"), (open ? clrYellow : cDim));
   PanelRow(y, " Precio medio" + (open ? StringFormat(" %.*f  (línea naranja)   precio actual %.*f", _Digits, s.avgPrice, _Digits, px) : " -"),
            (open ? clrOrange : cDim));

   // RESULTADO / TP
   PanelRow(y, "RESULTADO Y OBJETIVO (TP)", cSec);
   PanelRow(y, StringFormat(" Bruto %+.2f   swap %+.2f   comisión -%.2f   spread cierre -%.2f", s.gross, s.swap, s.commission, s.spreadCost));
   PanelRow(y, StringFormat(" NETO  %+.2f   (modo: %s)", s.net, CloseModeText()), (s.net >= 0.0 ? cOk : cBad));
   string tgtTxt;
   if(InpTargetMode == TGT_PERCENT_BALANCE) tgtTxt = StringFormat("%.2f%% del balance de apertura", InpTargetPercent);
   else if(InpTargetMode == TGT_FIXED_MONEY) tgtTxt = "cantidad fija";
   else tgtTxt = StringFormat("%.0f pts desde el precio medio", InpTargetPoints);
   PanelRow(y, StringFormat(" Meta cesta  %+.2f  (%s)   falta %.2f", target, tgtTxt, MathMax(0.0, target - s.net)));
   PanelRow(y, " Precio meta " + (open ? StringFormat("~ %.*f  (línea verde, a %.0f pts)", _Digits, targetPrice, ptsTarget) : "-"), (open ? cOk : cDim));
   PanelRow(y, StringFormat(" Progreso    [%s] %3.0f%%", ProgressBar(progress, 24), progress * 100.0), (progress >= 1.0 ? cOk : clrWhite));

   // RIESGO / SL
   PanelRow(y, "RIESGO Y STOP (SL)", cSec);
   PanelRow(y, StringFormat(" Stop equity -%.2f  (%.2f%% del balance)   margen restante %.2f", g_riskMoney, EffectiveRiskPercent(), marginToStop),
            (open && marginToStop < g_riskMoney * 0.3 ? cBad : clrWhite));
   PanelRow(y, " Precio stop " + (open ? StringFormat("~ %.*f  (línea roja, a %.0f pts)", _Digits, stopPrice, ptsStop) : "-"), (open ? clrRed : cDim));
   PanelRow(y, StringFormat(" Edad máx.   %s   edad actual %s", (InpMaxBasketAgeHours > 0 ? StringFormat("%dh (cierra con neto>=0)", InpMaxBasketAgeHours) : "sin límite"),
            (open ? FormatDuration((long)(TimeCurrent() - s.oldest)) : "-")));

   // CUENTA / DD
   PanelRow(y, "CUENTA Y DRAWDOWN (DD)", cSec);
   PanelRow(y, StringFormat(" Balance %.2f   Equity %.2f   Pico %.2f", balance, equity, peak));
   PanelRow(y, StringFormat(" Hoy         %+.2f (%+.2f%%)   límite diario -%.2f%% (-%.2f)%s", dayPL, dayPct, InpMaxDailyDrawdownPercent, dayLimitMoney,
            (open ? StringFormat("   precio ~ %.*f", _Digits, dailyPrice) : "")), (dayPL >= 0.0 ? cOk : (dayPL < -dayLimitMoney * 0.6 ? cBad : cWarn)));
   PanelRow(y, StringFormat(" Realizado   %+.2f hoy en %d cesta(s) cerradas por este EA", realizedToday, basketsToday), (realizedToday >= 0.0 ? cOk : cBad));
   PanelRow(y, StringFormat(" DD global   %.2f%% desde el pico   límite %.2f%%", ddGlobal, InpMaxGlobalDrawdownPercent),
            (ddGlobal > InpMaxGlobalDrawdownPercent * 0.6 ? cBad : clrWhite));
   string hist = "";
   for(int i = 0; i < g_histN; i++) hist += (g_hist[i] > 0.0 ? "G " : "P ");
   PanelRow(y, " Últimas cestas (reciente->antigua): " + (g_histN > 0 ? hist : "ninguna"), cDim);

   // FILTROS
   PanelRow(y, "FILTROS", cSec);
   PanelRow(y, " Sesión      " + SessionText(), (IsWithinTradingSession(TimeCurrent()) ? cOk : cWarn));
   PanelRow(y, StringFormat(" Spread      %d / %.0f pts     ATR %.0f pts [%.0f - %.0f]", (int)spread, InpMaxSpreadPoints, atrPts, InpATRMinPoints, InpATRMaxPoints),
            ((spread <= (long)InpMaxSpreadPoints && atrPts >= InpATRMinPoints && atrPts <= InpATRMaxPoints) ? clrWhite : cWarn));
   string newsTxt;
   if(InpNewsMode == NEWS_IGNORE) newsTxt = "filtro desactivado";
   else if(g_newsBlackout) newsTxt = "BLOQUEO ACTIVO (±" + IntegerToString(InpNewsMinutesBefore) + "/" + IntegerToString(InpNewsMinutesAfter) + " min)";
   else if(g_newsNextTime > 0) newsTxt = StringFormat("próxima %s %s (en %s)%s", TimeToString(g_newsNextTime, TIME_MINUTES), g_newsNextName,
                                                      FormatDuration((long)(g_newsNextTime - TimeCurrent())),
                                                      (InpNewsMode == NEWS_CLOSE_IF_POSITIVE ? "  cierra si neto>=0" : ""));
   else newsTxt = "sin noticias de alto impacto en 24h (o sin calendario)";
   PanelRow(y, " Noticias " + InpNewsCurrency + " " + newsTxt, (g_newsBlackout ? cBad : clrWhite));
   string wedTxt;
   if(InpWednesdayMode == WED_IGNORE) wedTxt = "sin tratamiento";
   else if(InpWednesdayMode == WED_NO_NEW_BASKETS) wedTxt = StringFormat("sin cestas nuevas desde %02d:00", InpWednesdayCutoffHour);
   else wedTxt = StringFormat("desde %02d:00 sin cestas nuevas y cierre si neto>=0", InpWednesdayCutoffHour);
   PanelRow(y, StringFormat(" Swap triple día %d: %s", InpSwapTripleDay, wedTxt), (IsWednesdayBlocked(TimeCurrent()) ? cWarn : clrWhite));
   PanelRow(y, StringFormat(" Rollover    %02d-%02dh %s   viernes corte %02d:00 %s", InpRolloverStartHour, InpRolloverEndHour,
            (InpAvoidRollover ? "activo" : "off"), InpFridayCutoffHour, (InpAvoidFridayClose ? "activo" : "off")), cDim);

   // BLOQUEO
   PanelRow(y, "BLOQUEO ACTUAL: " + (g_blockReason == "" ? "ninguno" : g_blockReason) + (g_paused ? "   [PAUSADO]" : ""),
            (g_blockReason == "" && !g_paused ? cOk : cWarn), 20);

   // botones
   if(InpPanelManualButtons)
   {
      PanelButton("BtnClose", 14,  y, "Cerrar cesta", clrFireBrick);
      PanelButton("BtnPause", 138, y, (g_paused ? "Reanudar" : "Pausar"), (g_paused ? clrDarkOrange : clrDimGray));
      PanelButton("BtnBuy",   262, y, "Ráfaga BUY",  clrSeaGreen);
      PanelButton("BtnSell",  386, y, "Ráfaga SELL", clrIndianRed);
      y += 30;
   }
   PanelBackground(y - 10);

   // ---------- líneas en el gráfico ----------
   if(InpDrawLines)
   {
      if(open)
      {
         HLine("HL_Entry",  g_firstEntryPrice, InpLineEntryColor, STYLE_SOLID, 2, StringFormat("Arranque cesta #%I64d", g_basketId));
         VLine(StringFormat("VLS_%I64d", g_basketId), g_basketOpenTime, InpLineEntryColor, StringFormat("Arranque cesta #%I64d", g_basketId));
         HLine("HL_Avg",    s.avgPrice,  InpLineAvgColor,   STYLE_DOT,     1, "Precio medio de la cesta");
         HLine("HL_Stop",   stopPrice,   InpLineStopColor,  STYLE_SOLID,   2, StringFormat("Stop de equity ~ (-%.2f)", g_riskMoney));
         HLine("HL_Daily",  dailyPrice,  InpLineStopColor,  STYLE_DASH,    1, StringFormat("Límite de pérdida diaria ~ (-%.2f)", dayLimitMoney));
         HLine("HL_Target", targetPrice, InpLineTargetColor, STYLE_DASH,   1, StringFormat("Objetivo neto ~ (+%.2f)", target));
         if(hasNext) HLine("HL_Next", nextLvl, InpLineNextLevelColor, STYLE_DASHDOT, 1, "Próximo nivel de promediado");
         else ObjectDelete(0, PANEL_PREFIX + "HL_Next");
      }
      else
         LinesDelete();
   }
   ChartRedraw();
}

void PanelDelete()
{
   ObjectsDeleteAll(0, PANEL_PREFIX + "R");
   ObjectsDeleteAll(0, PANEL_PREFIX + "Btn");
   ObjectsDeleteAll(0, PANEL_PREFIX + "BG");
   LinesDelete();
   // las líneas verticales VLS_<id> se conservan como historial de arranques de cesta
   ChartRedraw();
}

//+------------------------------------------------------------------+
//|  UTILIDADES                                                        |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime t[];
   ArraySetAsSeries(t, true);
   if(CopyTime(_Symbol, InpAnalysisTF, 0, 1, t) <= 0) return false;
   if(t[0] != g_lastBarTime) { g_lastBarTime = t[0]; return true; }
   return false;
}

int TimeHourOf(datetime t)   { MqlDateTime s; TimeToStruct(t, s); return s.hour; }
int TimeDayOfWeek(datetime t){ MqlDateTime s; TimeToStruct(t, s); return s.day_of_week; }

void LogSkip(string reason)
{
   if(InpVerboseLogging) PrintFormat("[%s] Sin operar: %s", _Symbol, reason);
}
//+------------------------------------------------------------------+
