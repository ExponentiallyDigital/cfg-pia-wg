# Plan: shorter widget key lines, through a script (ID-467)

Where it stands is ID-467's `Now:` line in CHANGELOG.md, not here.

## Log

### 2026-11-04: the Authorized Keys check

- Andrew, in Chrome on stock's Administration, System, with nothing applied: the Authorized Keys box (`sshd_authkeys`) has `maxlength` 2999, and holds 3503 characters on 4 lines.
- The page's own scripts mention `sshd_authkeys` only to refuse an empty box when password login is off: no length check on Apply.
- So the widget keys alone have taken the box past its limit. Chrome won't take more typing or pasting there, so no key can be added or changed on that page. Whether Apply keeps all 3503 characters depends on the router's web server, and isn't measured; it would mean writing to the router, and the shorter lines make it moot.
- Shorter lines: about 210 characters each (the key and its type are 80, the four `no-` restrictions 64), against about 750 now. Four widget keys and a key of the user's own come to about 1100.
- Until fixed: don't Apply that page.
