# Tonnetz

The `Tonnetz` module maps chroma vectors into the six-dimensional tonnetz space, encoding tonal relationships along the axes of fifths, minor thirds, and major thirds. This geometric representation captures harmonic proximity that chroma vectors alone do not express.

## Why Tonnetz?

The tonnetz (German for "tone network") is a lattice from neo-Riemannian music theory where harmonically related pitches are geometrically close. Mapping chroma to tonnetz coordinates makes chord progressions, key relationships, and tonal distance measurable as Euclidean distances. This is valuable for harmonic analysis, key tracking, and music similarity.

## Procedures

### ComputeTonnetz

```modula2
PROCEDURE ComputeTonnetz(chroma: ARRAY OF LONGREAL;
                          VAR tonnetz: ARRAY OF LONGREAL);
```

Map a 12-element chroma vector to 6 tonnetz dimensions. The `tonnetz` array must have at least 6 elements. Each chroma bin is projected onto three circular axes:

| Index | Dimension | Projection |
|-------|-----------|------------|
| 0 | Fifths Y | sin(i * pi/2) |
| 1 | Fifths X | cos(i * pi/2) |
| 2 | Minor 3rds Y | sin(i * 2*pi/3) |
| 3 | Minor 3rds X | cos(i * 2*pi/3) |
| 4 | Major 3rds Y | sin(i * 7*pi/6) |
| 5 | Major 3rds X | cos(i * 7*pi/6) |

The result is weighted by chroma energy and normalized, so each dimension lies in [-1, 1].

```modula2
VAR t: ARRAY [0..5] OF LONGREAL;
ComputeTonnetz(chroma, t);
(* t encodes the tonal position in 6D tonnetz space *)
```
