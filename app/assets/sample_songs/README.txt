Drop sample assets here so the dev-seed gives the simulator real
playback / cover art / lyrics for the placeholder row.

How it works
============
On every tap of the bug-report icon in the Library header, DevSeed copies
any files in this directory to <app docs>/sample_songs/ and points the
seeded row at them. Anything missing falls back to /dev/null/dev_alot.mp3,
a null cover (procedural gradient), and "No lyrics available".

Currently seeded
================
Just one row — "a lot" by 21 Savage. Drop any combo of:
  a_lot.mp3  (or .m4a / .opus / .wav / .aac / .flac)
  a_lot.jpg  (or .jpeg / .png / .webp)
  a_lot.lrc

The seed wires up whichever ones it finds; you don't need all three.
