# SpectralExtra

The `SpectralExtra` module provides additional spectral shape descriptors beyond the core set in `ShortFeats`: flatness, bandwidth, slope, and contrast. All procedures operate on a magnitude spectrum stored as `n` LONGREALs at a given ADDRESS.

## Why SpectralExtra?

These features capture complementary aspects of spectral shape. Flatness distinguishes noise-like signals from tonal ones. Bandwidth measures the spread of energy around the centroid. Slope indicates whether energy is concentrated in low or high frequencies. Contrast quantifies the per-band dynamic range, useful for music/speech discrimination and timbre analysis.

## Procedures

### SpectralFlatness

```modula2
PROCEDURE SpectralFlatness(mag: ADDRESS; n: CARDINAL): LONGREAL;
```

Compute the spectral flatness (Wiener entropy): geometric mean divided by arithmetic mean of the magnitude spectrum. Uses log-domain computation (`exp(mean(log(x))) / mean(x)`) for numerical stability. Returns 0.0 for silence. Values near 1.0 indicate noise-like spectra; values near 0.0 indicate tonal spectra.

### SpectralBandwidth

```modula2
PROCEDURE SpectralBandwidth(mag: ADDRESS; n: CARDINAL;
                             sampleRate: CARDINAL;
                             centroid: LONGREAL): LONGREAL;
```

Compute the energy-weighted bandwidth around a pre-computed spectral centroid: `sqrt(sum(|freq - centroid|^2 * mag) / sum(mag))`. The `centroid` parameter is the spectral centroid in Hz. The result is in Hz.

### SpectralSlope

```modula2
PROCEDURE SpectralSlope(mag: ADDRESS; n: CARDINAL): LONGREAL;
```

Compute the linear regression slope of the magnitude spectrum. Positive values indicate a rising spectrum (more high-frequency energy); negative values indicate a falling spectrum.

### SpectralContrast

```modula2
PROCEDURE SpectralContrast(mag: ADDRESS; n: CARDINAL;
                            numBands: CARDINAL;
                            VAR contrast: ARRAY OF LONGREAL);
```

Compute per-sub-band spectral contrast in dB. For each band, contrast is the difference between the mean of the top 20% and bottom 20% of magnitudes. The `contrast` array must have at least `numBands` elements. Higher contrast indicates more distinct peaks and valleys in each band.

```modula2
VAR c: ARRAY [0..5] OF LONGREAL;
SpectralContrast(mag, 512, 6, c);
(* c[0] = 18.3 dB, c[1] = 22.1 dB, ... *)
```
