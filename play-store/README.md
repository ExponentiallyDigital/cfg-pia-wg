# Play Store listing material

Everything the Google Play listing needs that is not the app itself.

| File | What it is | Who edits it |
| --- | --- | --- |
| `description.md` | The store description, short and full. 4000-character cap on the full one. | By hand, then pasted into Play Console |
| `privacy.html` | The privacy policy, published at the URL the listing points to. | By hand |
| `361 (0.7.01).txt` | A release note from before the pipeline wrote them. Kept as a sample of the house voice. | Nobody - historical |

---

## Release notes are NOT written here any more

**The "what's new" text lives in `CHANGELOG.md`, in the release block, inside a fenced ` ```play `
block.** `release.yml` extracts it at build time, writes `distribution/whatsnew/whatsnew-en-AU`, and
the upload puts it on the Play listing. You should never have to type a release note into Play
Console again.

Write it under the date line, first thing, while the release is fresh:

````markdown
2026-09-12 v0.8.71 build 441 - the watchdog checks it can survive a reboot

```play
Watchdog reliability, and two device assignment fixes.

Fixed: a device sent to the plain internet stayed there, ignoring later changes.
```

- FIX: the developer-facing bullets carry on as normal, outside the fence.
````

Everything **outside** the fence becomes the GitHub release body. The fence itself becomes the Play
note. One block, two audiences, written at the same moment so they cannot drift.

### The rules that will bite you

- **500 Unicode characters**, per language. Google's documented limit. **The build FAILS if you go over**, naming the count, so you find out in CI rather than from a rejected upload. The first draft of build 441's note was 512 characters and was refused.
- **No markdown.** Asterisks render as asterisks. Write plain sentences.
- **No links.** A URL appears as dead text nobody can tap. Say "see the changelog" rather than pasting one.
- **No fence, no note.** A release block without one gets a warning in the build log and Play falls back to a link to the hosted changelog. Not a failure, but not what anyone wants either.
- Rendered on GitHub the fence shows as a plain monospace block. That is deliberate: it is an honest preview of how Play will show it, with no formatting to flatter it.

### Why the format differs from `361 (0.7.01).txt`

That older file wraps its text in `<en-AU>` tags. The upload action used here takes a **directory of
plain-text files named by locale** instead - `whatsnew-en-AU`, no tags, no wrapper. Do not copy the
tags into a ` ```play ` fence; they would be published literally.

### Adding another language

Add a second file alongside `whatsnew-en-AU` in the same directory. Today the workflow writes only
`en-AU`, so a second locale means teaching the parser about a second fence. Nothing needs it yet.

---

## Known stale content

`description.md` still describes the watchdog as Asuswrt-Merlin only. Stock ASUS firmware has been
supported since the 0.8 line, and device assignment is not mentioned at all. Updating the store
description is on the CHANGELOG pending list under documentation and publicity.
