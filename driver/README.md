# PeriPrint Driver

Imprimí en la PeriPage A6 desde **cualquier app** (Word, Chrome, Safari, Vista Previa, Pages…) con ⌘P.

## Cómo funciona

macOS no permite instalar *backends* de CUPS de terceros con SIP activado, y además un proceso de CUPS
no tiene permiso de Bluetooth. Por eso el driver es una **impresora virtual IPP Everywhere** (el mismo
estándar que AirPrint) que corre con tu usuario:

```
App (⌘P) ──► CUPS ──► IPP (localhost:8631) ──► ippeveprinter ──► PeriPrint Driver (job) ──► Bluetooth ──► A6
                 cola "PeriPage_A6"          (incluido en macOS)    rasteriza, recorta, imprime
```

- **PeriPrint Driver.app** vive en la barra de menú. Lanza `/usr/bin/ippeveprinter` como proceso hijo
  con los atributos de `peripage-a6.conf` (papel de 48 mm, sin márgenes, 203 dpi). Como es su hijo,
  hereda el permiso de Bluetooth de la app.
- Por cada trabajo, `ippeveprinter` vuelve a ejecutar el mismo binario con el documento. macOS lo manda
  ya rasterizado a 203 dpi (Apple Raster/URF o PWG Raster), así que el driver decodifica, convierte a 1 bit
  (texto nítido o trama Stucki para fotos), recorta el blanco sobrante y lo imprime.
- Si PeriPrint está abierta y conectada, el driver le pide la impresora y PeriPrint la suelta.

## Instalar

```sh
driver/install.sh        # compila, copia a ~/Applications, agrega el agente de inicio y la cola "PeriPage A6"
driver/uninstall.sh      # deshace todo
```

La primera vez macOS pide permiso de Bluetooth para "PeriPrint Driver". La impresora usada es la que
elegiste en PeriPrint.

## Usar

1. ⌘P en cualquier app → impresora **PeriPage A6**.
2. Tamaño de papel: **48 × 100 mm** (u otro de 48 mm). Para textos largos elegí uno largo (48 × 300 mm,
   48 × 500 mm o un tamaño personalizado de 48 mm de ancho): el blanco del final se recorta solo.
3. En el menú del ícono de impresora de la barra de menú: calidad (automática / texto / fotos),
   densidad, recorte de blanco, página de prueba y registro.

Consejo para Word: en *Formato del documento* poné márgenes de 2–3 mm; para el navegador, en el diálogo
de impresión elegí *Márgenes: ninguno*.

## Archivos

- `PeriPrintDriver/` — código (target `PeriPrintDriver` del paquete Swift).
- `peripage-a6.conf` — atributos IPP (formato `ipptool`): tamaños, márgenes, resolución.
- `Info.plist` — bundle de la app de barra de menú (`LSUIElement`, permiso de Bluetooth).
- `install.sh` / `uninstall.sh`.
