//+------------------------------------------------------------------+
//| APLICAR_ESTILO_GW.mq5 — Script: pinta el gráfico activo con el    |
//| estándar visual GW (fondo, velas, ejes, sin cuadrícula).          |
//| No quita ni recarga el EA del gráfico: un script corre una vez    |
//| y termina; el EA sigue pegado y operando igual.                   |
//| Uso: en el Navegador, Scripts > doble clic sobre este script con  |
//| el gráfico elegido activo (o arrastrarlo al gráfico).             |
//+------------------------------------------------------------------+
#property copyright "Estándar visual de Antonio — réplica estilo GW CRT"
#property version   "1.00"
#property script_show_inputs false
#include <GW_ESTILO.mqh>

void OnStart()
  {
   GW_EstiloGrafico(0);
   Print("Estilo GW aplicado a ",_Symbol," ",EnumToString(_Period));
  }
