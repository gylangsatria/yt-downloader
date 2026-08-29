# Twitter/X Bookmark Media Link Scraper

Script to extract all media links (images/videos) from your Twitter/X bookmarks using the browser console.

## Features

- Collects all tweet links containing media (image or video) from bookmarks
- Video link format: `https://x.com/username/status/[id]/video/1`
- Image link format: `https://x.com/username/status/[id]`
- Auto-scrolls to load all bookmarks
- Exports results as JSON
- No API key or extra login required

## Usage

1. **Open Bookmarks Page** — Open `x.com/i/bookmarks` in your browser.
2. **Open Browser Console**:
   - **Chrome/Edge**: `Ctrl + Shift + J` (Windows) or `Cmd + Option + J` (Mac)
   - **Firefox**: `Ctrl + Shift + K` (Windows) or `Cmd + Option + K` (Mac)
3. **Run the Script** — Copy the script, paste it into the console, then press `Enter`.
4. **Wait for the Process to Finish** — The script auto-scrolls and collects all media links. It stops when:
   - No new links after 5 consecutive scrolls
   - The maximum scroll limit is reached (200 times)
5. **Download Results** — The file `media_links_YYYY-MM-DD.json` downloads automatically.

## Configuration

The following variables can be adjusted at the top of the script:

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `SCROLL_INTERVAL` | `3000` | Delay between scrolls (ms) |
| `SCROLL_STEP` | `800` | Scroll distance each time (px) |
| `MAX_UNCHANGED` | `5` | Stop when no new links appear after N scrolls |
| `MAX_SCROLLS` | `200` | Maximum number of scrolls |

## Output

Example JSON output file:

```json
[
  "https://x.com/username1/status/1234567890123456789/video/1",
  "https://x.com/username2/status/9876543210987654321",
  "https://x.com/username3/status/1122334455667788990/video/1"
]
```

## Important Notes

- Disable your adblocker for X.com before running the script
- Do not switch tabs or close the browser while the process is running
- The process can take 5–30 minutes depending on the number of bookmarks
- This script is for personal use; use it responsibly
- Automated scripting may violate X's Terms of Service

## Script

For the full script, paste the code from the `xbookmark-link-scrapper.js` file into the browser console.

