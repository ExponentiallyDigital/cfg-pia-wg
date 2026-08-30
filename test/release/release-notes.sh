TARGET_TAG="v0.7.07" \
GITHUB_REPOSITORY="ExponentiallyDigital/cfg-pia-wg" \
python3 -c '
import re, os, json, urllib.request

changelog_path = "CHANGELOG.md"
target_tag = os.environ.get("TARGET_TAG", "")
repo = os.environ.get("GITHUB_REPOSITORY", "")
token = os.environ.get("GITHUB_TOKEN", "")

def is_already_released(tag_name):
    if not repo or not token or not tag_name: return False
    url = f"https://api.github.com/repos/{repo}/releases/tags/{tag_name}"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json"})
    try:
        with urllib.request.urlopen(req) as resp: return resp.status == 200
    except Exception: return False

header_heading = "1.2. Implemented - chronological change history"
version_header_re = re.compile(r"^\d{4}-\d{2}-\d{2}\s+(v\d+\.\d+\.\d+.*)")

blocks, current_block, in_target_section = [], None, False

if os.path.exists(changelog_path):
    with open(changelog_path, "r", encoding="utf-8") as f:
        for line in f:
            stripped = line.strip()
            if header_heading in stripped:
                in_target_section = True
                continue
            if not in_target_section: continue

            m = version_header_re.match(stripped)
            if m:
                tag_match = re.search(r"v\d+\.\d+\.\d+", stripped)
                extracted_tag = tag_match.group(0) if tag_match else ""
                if current_block and extracted_tag and extracted_tag != target_tag:
                    if is_already_released(extracted_tag): break
                current_block = {"header": stripped, "lines": []}
                blocks.append(current_block)
                continue
            if current_block is not None and stripped:
                current_block["lines"].append(stripped)

formatted_output = []
for block in blocks:
    block["lines"].sort()
    formatted_output.append(block["header"] + "\n\n" + "\n".join(block["lines"]))

print("\n--- RESULTING GITHUB RELEASE NOTES ---\n")
print("\n\n".join(formatted_output))
'