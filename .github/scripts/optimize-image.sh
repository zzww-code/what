#!/usr/bin/env bash
# Shrink one image in place (same path, same format, so every link to it still works), keeping its name and format. Prints "before after name".
set -euo pipefail
f="$1"; MAXW="${MAXW:-2400}"; GIFW="${GIFW:-1000}"; MINSIZE="${MINSIZE:-200000}"
IM=$(command -v magick || command -v convert)
before=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f")
# Small images are not worth touching.
[ "$before" -ge "$MINSIZE" ] || exit 0
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
ext="$(echo "${f##*.}" | tr A-Z a-z)"
case "$ext" in
  png)
    cp "$f" "$tmp/in.png"
    # An animated PNG would lose its frames to a resize: leave it alone.
    if grep -qa "acTL" "$tmp/in.png"; then exit 0; fi
    # Already shrunk by an earlier run (an 8-bit palette, within the size cap): a second
    # lossy pass would only degrade it.
    if file -b "$tmp/in.png" | grep -q colormap && [ "$(identify -format %w "$tmp/in.png" | head -c 6)" -le "$MAXW" ]; then exit 0; fi
    "$IM" "$tmp/in.png" -resize "${MAXW}x>" "$tmp/r.png"
    pngquant --quality=65-90 --speed 1 --strip --force --output "$tmp/q.png" "$tmp/r.png" || cp "$tmp/r.png" "$tmp/q.png"
    # Lossless squeeze on top, where oxipng is installed (it is on a Mac, not in apt).
    ! command -v oxipng >/dev/null || oxipng -o 3 --strip safe -q "$tmp/q.png"
    out="$tmp/q.png" ;;
  jpg|jpeg)
    # Already at or below the target quality and size: leave it.
    if [ "$(identify -format '%Q' "$f")" -le 82 ] && [ "$(identify -format %w "$f")" -le "$MAXW" ]; then exit 0; fi
    "$IM" "$f" -auto-orient -resize "${MAXW}x>" -strip -interlace Plane -sampling-factor 4:2:0 -quality 82 "$tmp/o.jpg"
    out="$tmp/o.jpg" ;;
  gif)
    gifsicle -O3 --lossy=80 --resize-width "$GIFW" "$f" -o "$tmp/o.gif" 2>/dev/null \
      || gifsicle -O3 --lossy=80 "$f" -o "$tmp/o.gif"
    out="$tmp/o.gif" ;;
  *) exit 0 ;;
esac
after=$(stat -c%s "$out" 2>/dev/null || stat -f%z "$out")
# Only keep a result that is clearly smaller (never grow or churn a file).
if [ "$after" -lt $(( before * 9 / 10 )) ]; then cp "$out" "$f"; echo "$before $after $f"; else echo "$before $before $f"; fi
