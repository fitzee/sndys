# Waveform

The `Waveform` module renders an ASCII art waveform of an audio signal to stdout. Useful for quick visual inspection in the terminal without needing a graphical application.

## Why Waveform?

Sometimes you just need to see the shape of a signal -- where the loud and quiet parts are, whether it's clipping, or how the amplitude envelope looks. ASCII waveforms work over SSH and in any terminal.

## Procedures

### DrawWaveform

```modula2
PROCEDURE DrawWaveform(signal: ADDRESS; numSamples: CARDINAL;
                       width, height: CARDINAL);
```

Print an ASCII waveform to stdout. The signal is downsampled to fit `width` columns, and amplitude is scaled to `height` rows.

- `width`: number of columns (e.g. 80)
- `height`: number of rows (e.g. 20)

```modula2
DrawWaveform(signal, n, 80, 20);
(* Prints a visual representation of the waveform *)
```
