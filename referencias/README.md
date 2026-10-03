# Referencias: bots de malla (grid) para comparar

Carpeta para subir los EAs de malla que tienes en tu computadora (carpeta "cerebro").
Sirven como referencia de diseño de panel y de lógica, no se usan en producción.

Cómo subir desde GitHub:
1. Entra en esta carpeta `referencias/` en la rama `ccr-7a836d35-xvxijb`.
2. Botón "Add file" > "Upload files".
3. Arrastra los archivos `.mq5` (código fuente). Los `.ex5` compilados no sirven para leer el diseño.
4. Si solo tienes capturas de pantalla del recuadro, súbelas también (`.png` o `.jpg`).
5. "Commit changes".

Qué se revisará de cada bot:
- Qué información muestra su recuadro y cómo la organiza.
- Cómo calcula y muestra DD, TP de cesta, SL y pérdida del día.
- Qué líneas dibuja en el gráfico.

## Estándar visual GW

- `Include/GW_ESTILO.mqh`: paleta y funciones de dibujo del estándar de Antonio. Va en `MQL5\Include\`.
- `Scripts/APLICAR_ESTILO_GW.mq5`: script que pinta el gráfico activo con ese estándar. Va en `MQL5\Scripts\`.

`ScalpMetals_Basket_EA.mq5` NO necesita el include: lleva la misma paleta copiada dentro y aplica el estilo al arrancar.
