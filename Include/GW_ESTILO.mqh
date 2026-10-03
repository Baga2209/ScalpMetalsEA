//+------------------------------------------------------------------+
//| GW_ESTILO.mqh — Estándar visual MT5 de Antonio (v1, 01/10/2026)  |
//| Réplica del estilo del panel GW CRT v3.1 (medido en el Probador). |
//| Solo dibuja: no abre, cierra ni modifica operaciones.             |
//+------------------------------------------------------------------+
#ifndef GW_ESTILO_MQH
#define GW_ESTILO_MQH

//--- Paleta (RGB medidos del panel GW CRT; acento = teal #14B8A6)
#define GW_FONDO_GRAFICO   C'8,10,16'      // fondo del gráfico
#define GW_FONDO_PANEL     C'11,17,31'     // cuerpo de los recuadros
#define GW_FONDO_TITULO    C'14,23,40'     // franja del título
#define GW_ACENTO          C'20,184,166'   // línea bajo el título, secciones, valores
#define GW_ACENTO_TENUE    C'28,118,110'   // versión (v3.1), pie de página
#define GW_TEXTO           C'203,213,225'  // etiquetas ("Timeframe:")
#define GW_TEXTO_TITULO    C'246,252,253'  // título del recuadro
#define GW_NEUTRO          C'148,163,184'  // NONE / PENDING / "-"
#define GW_APAGADO         C'100,116,139'  // OFF
#define GW_OK              C'16,185,129'   // OK / ganancia
#define GW_ALERTA          C'242,54,69'    // BEARISH / pérdida / alerta
#define GW_BARRA_ESTADO    C'60,60,60'     // franja gris inferior ("NO POSITION")
#define GW_TEXTO_ESTADO    C'210,210,210'
#define GW_VELA_ALCISTA    C'20,184,166'
#define GW_VELA_BAJISTA    C'242,54,69'
#define GW_EJES            C'148,163,184'
#define GW_LINEA_BID       C'100,116,139'

#define GW_FUENTE          "Consolas"
#define GW_FUENTE_TITULO   "Consolas"      // MT5 no tiene negrita por objeto: el titulo va en blanco y 1 pt mas grande
#define GW_TAM             8
#define GW_TAM_TITULO      9
#define GW_ALTO_FILA       17

//--- Colores del gráfico (no toca indicadores ni el EA)
void GW_EstiloGrafico(const long chart_id=0)
  {
   ChartSetInteger(chart_id,CHART_MODE,CHART_CANDLES);
   ChartSetInteger(chart_id,CHART_SHOW_GRID,false);
   ChartSetInteger(chart_id,CHART_COLOR_BACKGROUND,GW_FONDO_GRAFICO);
   ChartSetInteger(chart_id,CHART_COLOR_FOREGROUND,GW_EJES);
   ChartSetInteger(chart_id,CHART_COLOR_GRID,GW_FONDO_TITULO);
   ChartSetInteger(chart_id,CHART_COLOR_CHART_UP,GW_VELA_ALCISTA);
   ChartSetInteger(chart_id,CHART_COLOR_CANDLE_BULL,GW_VELA_ALCISTA);
   ChartSetInteger(chart_id,CHART_COLOR_CHART_DOWN,GW_VELA_BAJISTA);
   ChartSetInteger(chart_id,CHART_COLOR_CANDLE_BEAR,GW_VELA_BAJISTA);
   ChartSetInteger(chart_id,CHART_COLOR_CHART_LINE,GW_VELA_ALCISTA);
   ChartSetInteger(chart_id,CHART_COLOR_VOLUME,GW_FONDO_TITULO);
   ChartSetInteger(chart_id,CHART_COLOR_BID,GW_LINEA_BID);
   ChartSetInteger(chart_id,CHART_COLOR_ASK,GW_ALERTA);
   ChartSetInteger(chart_id,CHART_COLOR_STOP_LEVEL,GW_ALERTA);
   ChartRedraw(chart_id);
  }

//--- Piezas del recuadro (todas con prefijo para borrarlas juntas)
void GW_Rect(const string n,int x,int y,int w,int h,color fondo)
  {
   if(ObjectFind(0,n)<0) ObjectCreate(0,n,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,n,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,n,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,n,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,n,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,n,OBJPROP_BGCOLOR,fondo);
   ObjectSetInteger(0,n,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,n,OBJPROP_COLOR,fondo);
   ObjectSetInteger(0,n,OBJPROP_BACK,false);
   ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,n,OBJPROP_HIDDEN,true);
  }

void GW_Texto(const string n,int x,int y,const string t,color c,int tam=GW_TAM,string fuente=GW_FUENTE)
  {
   if(ObjectFind(0,n)<0) ObjectCreate(0,n,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,n,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,n,OBJPROP_YDISTANCE,y);
   ObjectSetString(0,n,OBJPROP_TEXT,t);
   ObjectSetString(0,n,OBJPROP_FONT,fuente);
   ObjectSetInteger(0,n,OBJPROP_FONTSIZE,tam);
   ObjectSetInteger(0,n,OBJPROP_COLOR,c);
   ObjectSetInteger(0,n,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,n,OBJPROP_HIDDEN,true);
  }

//--- Recuadro completo: título con versión, línea acento, cuerpo y pie opcional
//    Devuelve la Y donde empieza el contenido.
int GW_Recuadro(const string p,int x,int y,int w,int h,const string titulo,const string version="",const string pie="")
  {
   GW_Rect(p+"_fondo",x,y,w,h,GW_FONDO_PANEL);
   GW_Rect(p+"_tit",x,y,w,22,GW_FONDO_TITULO);
   GW_Rect(p+"_lin",x,y+22,w,2,GW_ACENTO);
   GW_Texto(p+"_titt",x+8,y+5,titulo,GW_TEXTO_TITULO,GW_TAM_TITULO,GW_FUENTE_TITULO);
   if(version!="") GW_Texto(p+"_ver",x+w-38,y+6,version,GW_ACENTO_TENUE);
   if(pie!="")     GW_Texto(p+"_pie",x+w-8-StringLen(pie)*6,y+h-18,pie,GW_ACENTO_TENUE);
   return y+32;
  }

void GW_Seccion(const string n,int x,int y,const string t)          { GW_Texto(n,x+8,y,t,GW_ACENTO,7); }
void GW_Fila(const string n,int x,int y,const string etiqueta,const string valor,color cv=GW_ACENTO,int col=96)
  {
   GW_Texto(n+"_e",x+8,y,etiqueta,GW_TEXTO);
   GW_Texto(n+"_v",x+8+col,y,valor,cv);
  }
void GW_BarraEstado(const string p,int x,int y,int w,const string t)
  {
   GW_Rect(p+"_bar",x,y,w,20,GW_BARRA_ESTADO);
   GW_Texto(p+"_bart",x+8,y+4,t,GW_TEXTO_ESTADO,GW_TAM,GW_FUENTE_TITULO);
  }
void GW_Borrar(const string p) { ObjectsDeleteAll(0,p); }

#endif
