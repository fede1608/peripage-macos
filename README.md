# PeriPrint

App nativa de macOS (SwiftUI) para imprimir en impresoras térmicas **PeriPage A6 / A6+** por Bluetooth,
sin la app oficial y sin mandar datos a ningún servidor. Incluye un **driver de impresión** para imprimir
desde cualquier app (Word, Chrome, Safari…) con ⌘P.

## Instalar

```bash
curl -fsSL https://raw.githubusercontent.com/fede1608/peripage-macos/main/install.sh | bash
```

Instala `PeriPrint.app` (en `/Applications`, o `~/Applications` si no tenés permisos), la herramienta de
terminal `peripage` y el driver de impresión, y abre la app. Requiere **macOS 14 o posterior y una Mac con
Apple silicon**.

```bash
# Sin el driver de impresión
curl -fsSL https://raw.githubusercontent.com/fede1608/peripage-macos/main/install.sh | bash -s -- --no-driver
# Una versión puntual
curl -fsSL https://raw.githubusercontent.com/fede1608/peripage-macos/main/install.sh | bash -s -- --version v0.1.0
# Desinstalar (conserva tus presets e historial)
curl -fsSL https://raw.githubusercontent.com/fede1608/peripage-macos/main/install.sh | bash -s -- --uninstall
```

Al primer uso macOS pide permiso de Bluetooth para **PeriPrint** y para **PeriPrint Driver**: aceptalos.
Las apps están firmadas *ad hoc* (no notarizadas); el instalador les quita la cuarentena para que abran.
También podés bajar el zip a mano desde [Releases](https://github.com/fede1608/peripage-macos/releases).

**Crear**
- **Foto**: recorte (1:1, 4:3, 16:9…), ancho, rotación/espejo, epígrafe y fecha. Brillo, contraste, gamma,
  nitidez y niveles automáticos. Seis tramas: Atkinson, Floyd–Steinberg, Stucki, Bayer, semitono y umbral.
- **Collage y fotomatón**: hasta 8 fotos en tira vertical, grilla o de a dos.
- **Stickers**: tamaño en mm, grilla de columnas × cantidad, línea de corte punteada, **contorno** automático
  para PNG sin fondo, marco decorativo y modo espejado para papel transparente.
- **Etiquetas 15 mm** (rollo troquelado de 56 mm, 7,5 mm de separación): una etiqueta por línea; texto,
  ícono + texto, QR + texto, código de barras o imagen, ajustados al alto. Cada trabajo termina con el corte
  al comienzo de una separación para que el siguiente arranque alineado; *Alinear rollo*, calibración y
  ajuste fino. La vista previa sombrea las separaciones.
- **Texto y notas**: plantillas libre / nota / lista de tareas / etiqueta, cualquier fuente, invertido y fecha.
- **Banner**: texto gigante impreso a lo largo del papel.
- **QR**: texto/URL o Wi-Fi para invitados.
- **19 marcos decorativos** para foto, texto, stickers, etiquetas y collage: doble línea, línea de corte con
  tijera, puntos, ticket dentado, estampilla, película, corazones, estrellas, flores, art déco, vintage,
  damero, ondas, confeti, Polaroid…

**Más**
- **Instagram y X**: pegá el link de un post (tweets con fotos, posts, carruseles, reels e **historias** de
  Instagram) y se arma una tarjeta, foto, sticker o etiqueta de 15 mm. Con **tu sesión iniciada** dentro de la
  app (en la página oficial; PeriPrint nunca ve la contraseña) también trae posts de cuentas privadas que
  seguís e historias. Para cualquier otra cosa en pantalla: navegador integrado con modo **Capturar**.
- **Juegos** generados al azar (con número para repetirlos y solución aparte): Sudoku 9×9 y 6×6, sopa de
  letras (12 temas en español o tus palabras), laberintos rectangulares y circulares, nonogramas, Futoshiki,
  Puentes (Hashi), **ajedrez: mate en 1 y en 2** (2.000 posiciones de partidas reales de la base abierta de
  Lichess, CC0, en 4 niveles de rating), Batalla naval, Timbiriche y Ta-te-ti. Generadores basados en la *Portable Puzzle
  Collection* de Simon Tatham y en *Mazes for Programmers* de Jamis Buck, con unicidad de solución verificada.
- **Tienda** (⇧⌘T): íconos de Iconify (en español), emojis de OpenMoji, imágenes libres de Openverse y fuentes
  de Google Fonts instalables; vista térmica, favoritos y licencias. Todo gratis y sin cuentas.
- **Historial** de impresiones con reimpresión.

**General**
- Ajustes por defecto elegidos con pruebas impresas en un A6 de 203 dpi: trama Stucki, gamma 1,3, contraste
  1,25, nitidez 0,6, niveles automáticos y densidad alta. Márgenes simétricos de 7 mm.
- Presets incluidos y propios; la vista previa muestra el papel real (56 mm) y es exactamente el bitmap que
  se imprime. Arrastrar y soltar, pegar (⇧⌘V), abrir (⌘O), imprimir (⌘P), conexión automática.
- **Driver de impresión** (`driver/`): imprimí desde Word, Chrome, Safari o cualquier app con ⌘P.

## Uso

1. Prendé la impresora. No hace falta emparejarla en macOS: en la app, menú `⋯` → *Buscar impresoras…* y
   elegila (queda recordada y se conecta sola al abrir).
2. Elegí un modo, un preset, ajustá y **Imprimir**.
3. Para imprimir desde otras apps: ⌘P → impresora **PeriPage A6**, papel de 48 mm y márgenes en cero.
   Detalles en [`driver/README.md`](driver/README.md).

## Compilar

Requiere macOS 14+ y las Command Line Tools (no hace falta Xcode).

```sh
scripts/build-app.sh            # → dist/PeriPrint.app y dist/peripage
scripts/build-app.sh --install  # además la copia a /Applications
driver/install.sh               # compila e instala el driver de impresión
scripts/swift.sh test           # tests
scripts/package.sh              # → dist/PeriPrint-macOS.zip (lo que publica el CI)
```

`scripts/swift.sh` es un wrapper de `swift` que esquiva dos archivos desactualizados que traen algunas
instalaciones de Command Line Tools (ver *Notas*); con Xcode o unas CLT sanas se comporta como `swift`.

El workflow [`.github/workflows/build.yml`](.github/workflows/build.yml) corre los tests y compila las apps
en cada push; al subir un tag `v*` publica `PeriPrint-macOS.zip` como release, que es lo que baja
`install.sh`.

## CLI

```sh
dist/peripage list                      # impresoras emparejadas
dist/peripage scan                      # búsqueda Bluetooth (10 s)
dist/peripage info                      # batería, estado, firmware, serie
dist/peripage print foto.jpg            # Stucki + tono recomendado, densidad alta
dist/peripage preview foto.jpg out.png  # genera la vista previa 1-bit sin imprimir
dist/peripage raw 10FF50F1              # manda bytes crudos y muestra la respuesta
```

Desde la terminal, el permiso de Bluetooth lo pide la app de terminal que estés usando.

## Estructura

```
Sources/PeriPageKit/    protocolo, modelos, Bluetooth (IOBluetooth RFCOMM), dithering, composición 1-bit
Sources/PeriRender/     texto, marcos decorativos y dibujo 1-bit compartido
Sources/PuzzleKit/      juegos y puzzles generados
Sources/SocialKit/      Instagram / X: links, navegador con captura, diseños
Sources/ResourceStore/  tienda: Iconify, OpenMoji, Openverse, Google Fonts
Sources/PeriPrint/      app SwiftUI
Sources/peripage-cli/   herramienta de línea de comandos
driver/                 PeriPrint Driver (impresora virtual IPP Everywhere)
Tests/                  tests (Swift Testing)
docs/PROTOCOL.md        protocolo obtenido de la app oficial de Android
```

## Notas

- El protocolo sale de decompilar la app oficial de Android (PeriPage 6.10.11). Detalle completo en
  [`docs/PROTOCOL.md`](docs/PROTOCOL.md).
- `IOBluetooth` bloquea el hilo que lo llama mientras el permiso de Bluetooth está sin decidir, y eso
  congela la app si pasa en el hilo principal. Por eso la app primero pide el permiso con CoreBluetooth
  (`BluetoothAuthorization`) y recién después usa IOBluetooth.
- Algunas instalaciones de Command Line Tools dejan `PackageDescription.private.swiftinterface` y
  `usr/include/swift/module.modulemap` desactualizados, que rompen SwiftPM; `scripts/swift.sh` los esquiva.
  La solución de raíz es reinstalar las CLT (`sudo rm -rf /Library/Developer/CommandLineTools && xcode-select --install`).

## Licencia

Código abierto bajo licencia [MIT](LICENSE). Los avisos de terceros (Simon Tatham's Puzzles, base de
puzzles de Lichess y recursos descargados en tiempo de uso) están en [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

## Créditos y licencias de terceros

- Puzzles de ajedrez: [base de puzzles de Lichess](https://database.lichess.org/#puzzles) (CC0).
- Generadores de juegos basados en la [Portable Puzzle Collection](https://www.chiark.greenend.org.uk/~sgtatham/puzzles/)
  de Simon Tatham (MIT) y en *Mazes for Programmers* de Jamis Buck.
- La tienda descarga en tiempo de uso íconos de [Iconify](https://iconify.design) (licencia de cada colección),
  emojis de [OpenMoji](https://openmoji.org) (CC BY-SA 4.0), imágenes de [Openverse](https://openverse.org)
  (licencias Creative Commons, con atribución) y fuentes de [Google Fonts](https://fonts.google.com) (OFL/Apache).
- Posts de X vía el endpoint público de embeds y [FxTwitter](https://github.com/FxEmbed/FxEmbed); Instagram vía
  su página pública de embed.
- Proyecto independiente, sin relación con PeriPage ni iLeadTek. El protocolo se documentó por interoperabilidad
  ([`docs/PROTOCOL.md`](docs/PROTOCOL.md)); el repo no incluye código de la app oficial.
