# Protocolo PeriPage A6 / A6+

Obtenido decompilando la app oficial de Android **PeriPage 6.10.11** (`com.ileadtek.peripage`, build 323)
con jadx. Clases relevantes (ofuscadas): `y0.e` (socket SPP), `y0.h` (comandos), `y0.d` (fachada SDK),
`y6.a` (secuencias de impresión y parsing de respuestas), `y6.f` (capacidades por modelo).

> Nota: jadx reemplaza el byte `0x10` por `UnionPtg.sid`, `0x1D` por `BoolPtg.sid`, `0x1F` por
> `NumberPtg.sid`, `0x12` por `UnaryPlusPtg.sid`, `0x40` por `Ptg.CLASS_ARRAY` y `0x30`/`0x31` por
> `TarConstants.LF_NORMAL`/`LF_LINK` (constantes de Apache POI / commons-compress con el mismo valor).

## Transporte

- **Bluetooth Classic, perfil SPP (RFCOMM)**. UUID `00001101-0000-1000-8000-00805F9B34FB`.
- Si falla la conexión por SDP, la app usa directamente el **canal RFCOMM 1**.
- La app escribe en bloques de **1024 bytes** con 1 ms de pausa (el control de flujo lo hace RFCOMM).
- La serie A3 (`PeriPage_A3_*`) usa otro SDK; no aplica al A6.

## Identificación del modelo (por nombre Bluetooth)

| Nombre BT                         | Modelo           | Ancho (px) | DPI | Feed final (dots) | Densidad enviada (bajo/normal/alto) |
|-----------------------------------|------------------|-----------:|----:|------------------:|-------------------------------------|
| `PeriPage_XXXX`                   | A6               | 384        | 203 | 64                | 0 / 1 / 2                           |
| `PeriPage+XXXX`                   | A6+              | 576        | 300 | 96                | 0 / 1 / 2                           |
| `PPG_A6_SD...`                    | A6 (nuevo)       | 384        | 203 | 64                | 0 / 1 / 2                           |
| `PPG_A6_HD/UD/UHD...`             | A6 (nuevo)       | 384        | 203 | 128               | 0 / 2 / 4                           |

`XXXX` = últimos 4 hex de la MAC. Todos los A6 usan el raster sin comprimir `GS v 0`
(el formato comprimido `1F 00 ...` es para A8/A9/A40/etc.). La escala de grises de 5 bits
(`GS v 1`) solo la habilita la app para A9Pro+/Q9Pro+, así que el A6 es **1 bit (blanco/negro)**.

## Comandos (host → impresora)

| Bytes                                   | Significado                                                        |
|-----------------------------------------|--------------------------------------------------------------------|
| `10 FF FE 01`                           | Inicio de trabajo de impresión / wake                              |
| `00 ×12`                                | Relleno que la app manda después del inicio                        |
| `1D 76 30 00 wL wH hL hH` + datos       | Raster 1 bpp (`GS v 0`). `w` = bytes por fila, `h` = filas, LE     |
| `1B 4A n`                               | Avanzar papel `n` dots (`ESC J`)                                   |
| `1D 0C`                                 | Posicionar en la siguiente etiqueta (papel con gap/marca negra)    |
| `10 FF FE 45`                           | Fin de trabajo de impresión                                        |
| `10 FF 10 00 n`                         | Densidad (concentración). Respuesta `OK` (`4F 4B`)                 |
| `10 FF 10 03 n`                         | Tipo de papel (0 continuo, 1 marca negra/plegado, 2 gap, 3 paginado)|
| `10 FF 81 n`                            | Retroceso de papel antes de imprimir (máx 80 @200dpi / 120 @300dpi)|
| `10 FF 80 01` / `10 FF 80 00`           | Habilitar / deshabilitar retroceso de papel                        |
| `10 FF 40`                              | Estado → 1 byte                                                    |
| `10 FF 50 F1`                           | Batería → 2 bytes, `[1]` = porcentaje                              |
| `10 FF 20 F0`                           | Modelo de impresora (ASCII)                                        |
| `10 FF 20 F1`                           | Versión de firmware (ASCII, ej. `V1.23_...OK`)                     |
| `10 FF 20 F2`                           | Número de serie (ASCII)                                            |
| `10 FF 30 10`                           | Versión firmware Bluetooth (ASCII)                                 |
| `10 FF 30 12`                           | MAC Bluetooth                                                      |
| `10 FF 70`                              | Info completa, ASCII separado por `|`                              |
| `10 FF 12 hi lo`                        | Tiempo de auto-apagado (minutos)                                   |

Datos del raster: fila por fila, MSB primero, **bit 1 = punto negro**. La app oficial usa umbral
simple (`(R+G+B)/3 < 190` → negro) o Floyd–Steinberg según el modo.

## Secuencia de impresión (A6, rollo continuo)

```
10 FF FE 01                 inicio
00 00 00 00 00 00 00 00 00 00 00 00
1D 76 30 00 30 00 hL hH     raster 384 px (48 bytes/fila) × h filas
<48*h bytes>
1B 4A 40                    feed 64 dots (≈8 mm) para que salga el papel
10 FF FE 45                 fin
```

La densidad (`10 FF 10 00 n`) se manda antes, en una operación separada, y se espera `OK`.
Para varias copias, la app repite el bloque raster dentro del mismo trabajo.

## Respuestas y eventos (impresora → host)

| Bytes        | Significado                       |
|--------------|-----------------------------------|
| `AA`         | Impresión terminada               |
| `4F 4B`      | `OK` (ack de configuración)       |
| `FF 01`      | Sin papel                         |
| `FF 02`      | Tapa abierta                      |
| `FF 03`      | Sobrecalentamiento                |
| `FF 04`      | Batería baja                      |
| `FF 05`      | Tapa cerrada                      |
| `FE xx`      | Error de papel                    |
| `FD 01`      | Abortar envío                     |
| `FD 02`      | Continuar envío                   |
| `FD 03`/`04` | Ocupada / libre                   |

Byte de estado (`10 FF 40`): `00` libre, `01` ocupada, `04` sin papel, `08` batería baja, `10` sobrecalentada.

## Privacidad

En cada impresión la app oficial manda telemetría a sus servidores (`CommonPresenter.dataCollect`):
modelo y SO del teléfono, UUID del móvil, nombre/MAC/SN/firmware de la impresora, tipo de papel y modo
de impresión. Además guarda una copia PNG local de la imagen impresa. La imagen en sí no se sube en ese
flujo. Esta app no manda nada a ningún servidor.

## Mediciones en hardware (PeriPage A6, firmware V1.11_203dpi)

- Escala: 8 dots/mm confirmado con una regla impresa (marcas cada 10 mm exactas).
- Ancho imprimible: 48 mm (384 dots) centrado en papel de 56–57 mm.
- Margen superior fijo de **~7 mm** entre el corte anterior y la primera línea (cabezal → barra de corte
  ≈ 6 mm + ~1 mm que la impresora avanza sola al empezar). No se puede achicar desde el host.
- Margen inferior = avance final − 6 mm. PeriPrint avanza 13 mm por defecto (`1B 4A 68`) para dejar
  7 mm abajo y que la tira quede simétrica. La app oficial avanza solo 64 dots (8 mm → ~2 mm abajo).
- Respuestas observadas: batería `00 1E` (30 %), estado `00`, firmware `V1.11_203dpi`, modelo `IP-200`,
  densidad `4F 4B`, fin de impresión `AA`. MTU RFCOMM 123, canal 1, no requiere emparejar en macOS.
