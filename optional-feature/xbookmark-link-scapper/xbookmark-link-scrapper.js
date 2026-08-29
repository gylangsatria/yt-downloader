let mediaLinks = [];
let previousCount = 0;
let unchangedCount = 0;
let isComplete = false;
let scrollAttempts = 0;

const SCROLL_INTERVAL = 3000;
const SCROLL_STEP = 800;
const MAX_UNCHANGED = 5;
const MAX_SCROLLS = 200;

function extractTweetLinks() {
    const links = new Set();
    
    // Cari semua link tweet yang memiliki media (foto/video)
    document.querySelectorAll('article[data-testid="tweet"]').forEach(tweet => {
        // Cari link ke tweet itu sendiri
        const linkElement = tweet.querySelector('a[href*="/status/"]');
        if (linkElement) {
            let href = linkElement.getAttribute('href');
            // Pastikan link lengkap
            if (href && href.startsWith('/')) {
                href = 'https://x.com' + href;
            }
            
            // Cek apakah tweet ini punya media
            const hasMedia = tweet.querySelector('img[src*="media"], img[src*="twimg.com"], video');
            if (hasMedia && href) {
                // Deteksi apakah ini video atau foto
                const isVideo = tweet.querySelector('video, a[href*="/video/"]');
                if (isVideo) {
                    // Tambahkan /video/1 di akhir untuk link video
                    links.add(href + '/video/1');
                } else {
                    // Untuk foto, cukup link tweet-nya
                    links.add(href);
                }
            }
        }
    });
    
    return Array.from(links);
}

function updateMediaList() {
    const newLinks = extractTweetLinks();
    newLinks.forEach(link => {
        if (!mediaLinks.includes(link)) {
            mediaLinks.push(link);
        }
    });
    console.log(`Link media terkumpul: ${mediaLinks.length}`);
    return mediaLinks.length;
}

function scrollAndCollect() {
    if (isComplete) return;
    
    scrollAttempts++;
    const currentCount = updateMediaList();
    
    console.log(`Scroll ke-${scrollAttempts} | Link: ${currentCount} | Sisa: ${MAX_SCROLLS - scrollAttempts}`);
    
    if (currentCount === previousCount) {
        unchangedCount++;
        if (unchangedCount >= MAX_UNCHANGED || scrollAttempts >= MAX_SCROLLS) {
            isComplete = true;
            console.log('Pengumpulan selesai!');
            console.log(`Total link media ditemukan: ${mediaLinks.length}`);
            
            const json = JSON.stringify(mediaLinks, null, 2);
            const blob = new Blob([json], { type: 'application/json' });
            const url = URL.createObjectURL(blob);
            const link = document.createElement('a');
            link.href = url;
            link.download = `media_links_${new Date().toISOString().slice(0,10)}.json`;
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);
            
            console.log('File berhasil didownload!');
            clearInterval(intervalId);
        }
    } else {
        unchangedCount = 0;
    }
    
    previousCount = currentCount;
    window.scrollBy(0, SCROLL_STEP);
    
    // Klik tombol "Show more" jika ada
    document.querySelectorAll('[role="button"]').forEach(btn => {
        if (btn.textContent.includes('Show') || btn.textContent.includes('Lihat')) {
            btn.click();
        }
    });
}

console.log('Memulai pengumpulan link media dari bookmark...');
updateMediaList();
const intervalId = setInterval(scrollAndCollect, SCROLL_INTERVAL);

const observer = new MutationObserver(() => {
    if (!isComplete) {
        updateMediaList();
    }
});
observer.observe(document.body, { childList: true, subtree: true });

console.log('Silakan tunggu, script sedang berjalan...');
console.log(`Akan berhenti setelah ${MAX_SCROLLS} kali scroll atau tidak ada link baru`);