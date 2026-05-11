# DJ voice bank tooling

End-to-end pipeline: source mp3 → fine-tuned F5-TTS checkpoint → 150
rendered DJ lines in the bank folder layout.

## 0. One-time install (local)

```
pip install faster-whisper f5-tts
winget install Gyan.FFmpeg
```

## 1. Prep training data — already done

```
python tools/prepare_training_data.py \
    --input "<source.mp3>" \
    --output data/training \
    --skip-intro 10 \
    --whisper-model large-v3
```

Outputs `data/training/wavs/*.wav` + `data/training/metadata.csv`. The
prep run on Through the Wormhole produced 862 clips / 66.3 min of
clean training audio.

## 2. Fine-tune on Google Colab

1. Tar the data: `cd data && tar -czf training.tar.gz training/`.
2. Upload `data/training.tar.gz` to Google Drive at
   `MyDrive/dj-voice/training.tar.gz`.
3. Open `tools/finetune_f5tts.ipynb` in Colab (File → Upload notebook,
   or "Open in Colab" if you push the repo to GitHub).
4. Runtime → Change runtime type → **T4 GPU**.
5. Run cells top to bottom. ~4–6 hours on the free tier. Keep the tab
   open or it disconnects.
6. The last cell writes three files to `MyDrive/dj-voice/`:
   - `dj_voice_finetuned.pt`
   - `reference.wav`
   - `reference.txt`

## 3. Render the bank locally

Download those three files into `data/finetuned/`. Then:

```
python tools/render_dj_voice_bank.py \
    --ckpt data/finetuned/dj_voice_finetuned.pt \
    --ref-audio data/finetuned/reference.wav \
    --ref-text-file data/finetuned/reference.txt \
    --output build/dj_voice_bank
```

Produces 150 `.opus` files under `build/dj_voice_bank/` in the
`generic/`, `artists/<slug>/`, `songs/<slug>/` layout that matches
`app/assets/dj_voice_bank/manifest.seed.json`. Inference on your i7
takes ~20–30 min for the full set.

Re-render a subset (e.g. only the artist clips) without redoing the
whole bank:

```
python tools/render_dj_voice_bank.py \
    --ckpt ... --ref-audio ... --ref-text-file ... \
    --output build/dj_voice_bank \
    --only artist_drake_,artist_don_toliver_
```

## 4. Activate on the phone

1. Copy `build/dj_voice_bank/` over to the device's
   `<app_documents>/dj_voice_bank/`.
2. Drop in `manifest.json` (start from
   `app/assets/dj_voice_bank/manifest.seed.json`; replace the song-id
   placeholders once you've wired it to the library).
3. Toggle `Settings → AI DJ → DJ voice` on. The selector picks a clip
   per transition and the bank player handles the rest.

## Troubleshooting

- **f5-tts CLI args drift between releases.** If the CLI errors on
  unknown flags, run `f5-tts_infer-cli --help` and update
  `render_dj_voice_bank.py`'s `render_line()` call to match.
- **Voice doesn't sound right after fine-tune.** Try a different
  reference clip (any `data/training/wavs/NNNN.wav` from a clean
  segment) — the ref shapes vocal characteristics at inference time
  more than the fine-tune does.
- **Out-of-memory on Colab.** Drop `--batch_size_per_gpu` to 2400 in
  the notebook's training cell.
