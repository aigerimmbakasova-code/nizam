# Nizam / Низам

A time tracker for five spheres of life: spiritual, physical, academic, social and creative. Works in English, Russian, Turkish and Kyrgyz.

Трекер времени по пяти сферам жизни: духовной, физической, учебной, социальной и творческой.

## Files

- `index.html` — the whole app
- `manifest.json`, `sw.js`, `icons/` — make it installable on phones and usable offline
- `CNAME` — your custom domain (add it once you have one)

## Data

Data is stored in the browser on each device (localStorage). Use **Settings → Data → Export / Import** to back it up or move it between devices.

## Updating

Edit `index.html` and commit. GitHub Pages republishes automatically within a minute or two.
When you change the app, also bump `VERSION` in `sw.js` (for example `nizam-v2`) so installed copies on phones pick up the new version.

## Reports

**Summary → Monthly report** opens a printable report for any month (totals, time per day, spheres, top activities, checklist). Press **Download PDF** and choose "Save as PDF" in the print window.
