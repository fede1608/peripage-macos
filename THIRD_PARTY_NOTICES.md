# Third-party notices

PeriPrint is MIT-licensed (see `LICENSE`). It includes or derives from the following third-party work.

## Simon Tatham's Portable Puzzle Collection

The Sudoku, Futoshiki, Nonogram and Bridges (Hashi) generators and the human-technique solver in
`Sources/PuzzleKit/` are based on the algorithms of Simon Tatham's Portable Puzzle Collection
(https://www.chiark.greenend.org.uk/~sgtatham/puzzles/), distributed under the following licence:

```
This software is copyright (c) 2004-2024 Simon Tatham.

Portions copyright Richard Boulton, James Harvey, Mike Pinna, Jonas
Kölker, Dariusz Olszewski, Michael Schierl, Lambros Lambrou, Bernd
Schmidt, Steffen Bauer, Lennard Sprong, Rogier Goossens, Michael
Quevillon, Asher Gordon, Didi Kohen, Ben Harris and Anders Höglund.

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation files
(the "Software"), to deal in the Software without restriction,
including without limitation the rights to use, copy, modify, merge,
publish, distribute, sublicense, and/or sell copies of the Software,
and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Lichess puzzle database

`Sources/PuzzleKit/ChessPuzzleData.swift` contains a selection of puzzles from the Lichess puzzle
database (https://database.lichess.org/#puzzles), released into the public domain under
Creative Commons CC0 1.0.

## Resources downloaded at run time (not included in this repository)

The in-app store and the social module fetch content on demand; it keeps its own licence:

- Icons from Iconify (https://iconify.design): the licence of each icon set, shown in the app.
- Emoji from OpenMoji (https://openmoji.org): CC BY-SA 4.0, attribution shown in the app.
- Images from Openverse (https://openverse.org): Creative Commons licences, attribution shown in the app.
- Fonts from Google Fonts (https://fonts.google.com): SIL Open Font License or Apache 2.0.
- Posts from X and Instagram belong to their authors; PeriPrint only prints them for personal use.

## Mazes

The maze generators follow the algorithms described in Jamis Buck, *Mazes for Programmers*
(Pragmatic Bookshelf, 2015): recursive backtracker and Wilson's algorithm. No code from the book is included.
