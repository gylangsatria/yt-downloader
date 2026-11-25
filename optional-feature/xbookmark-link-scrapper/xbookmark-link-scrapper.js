let mediaLinks = [];
let previousCount = 0;
let unchangedCount = 0;
let isComplete = false;
let scrollAttempts = 0;

const SCROLL_INTERVAL = 3000;
const SCROLL_STEP = 1000;
const MAX_UNCHANGED = 10;
const MAX_SCROLLS = 500;

function extractTweetLinks() {
    const links = new Set();
    
    // X sering mengganti selector, kita coba beberapa pendekatan sekaligus
    // 1. Berdasarkan article (standar)
    // 2. Berdasarkan cellInnerDiv (kontainer tweet di list)
    const tweetContainers = document.querySelectorAll('article[data-testid="tweet"], [data-testid="cellInnerDiv"] article');
    
    tweetContainers.forEach(tweet => {
        let href = null;
        
        // Cari link status melalui elemen time
        const timeElement = tweet.querySelector('time');
        if (timeElement && timeElement.closest('a')) {
            href = timeElement.closest('a').getAttribute('href');
        }
        
        // Fallback: Cari link apa saja yang mengandung /status/
        if (!href) {
            const allLinks = Array.from(tweet.querySelectorAll('a[href*="/status/"]'));
            // Cari yang polanya /username/status/数字
            const statusLink = allLinks.find(a => /\/[^\/]+\/status\/\d+/.test(a.getAttribute('href')));
            if (statusLink) href = statusLink.getAttribute('href');
        }

        if (href) {
            href = href.split('?')[0];
            if (href.startsWith('/')) href = window.location.origin + href;
            
            // Deteksi media dengan cakupan lebih luas
            const hasMedia = !!(
                tweet.querySelector('[data-testid="tweetPhoto"]') || 
                tweet.querySelector('[data-testid="videoPlayer"]') ||
                tweet.querySelector('video') ||
                tweet.querySelector('img[src*="pbs.twimg.com/media/"]') ||
                tweet.querySelector('[data-testid="playButton"]') ||
                tweet.querySelector('[data-testid="card.wrapper"]') ||
                tweet.querySelector('[aria-label*="Embedded video"]')
            );
            
            if (hasMedia) {
                const isVideo = !!(
                    tweet.querySelector('[data-testid="videoPlayer"]') || 
                    tweet.querySelector('video') || 
                    tweet.querySelector('[data-testid="playButton"]') ||
                    tweet.querySelector('[aria-label*="Embedded video"]')
                );

                if (isVideo) {
                    const videoLink = href.endsWith('/video/1') ? href : href + '/video/1';
                    links.add(videoLink);
                } else {
                    links.add(href);
                }
            }
        }
    });

    // Seringkali link ada di luar article jika struktur berubah lagi
    // Cari semua link status yang memiliki gambar/video di dekatnya jika mediaLinks masih 0
    if (links.size === 0) {
        document.querySelectorAll('a[href*="/status/"]').forEach(a => {
            const href = a.getAttribute('href');
            if (/\/[^\/]+\/status\/\d+$/.test(href.split('?')[0])) {
                // Cek apakah di dalam kontainer yang sama ada indikasi media
                const container = a.closest('[data-testid="cellInnerDiv"]') || a.parentElement.parentElement;
                if (container && (container.querySelector('img[src*="media"]') || container.querySelector('video'))) {
                    let fullUrl = href.split('?')[0];
                    if (fullUrl.startsWith('/')) fullUrl = window.location.origin + fullUrl;
                    links.add(fullUrl);
                }
            }
        });
    }
    
    return Array.from(links);
}

function updateMediaList() {
    const newLinks = extractTweetLinks();
    let added = 0;
    newLinks.forEach(link => {
        if (!mediaLinks.includes(link)) {
            mediaLinks.push(link);
            added++;
        }
    });
    if (added > 0) {
        console.log(`+ Tambah ${added} link baru. (Total: ${mediaLinks.length})`);
    }
    return mediaLinks.length;
}

function scrollAndCollect() {
    if (isComplete) return;
    
    scrollAttempts++;
    const currentCount = updateMediaList();
    
    console.log(`Scroll #${scrollAttempts} | Link: ${currentCount}`);
    
    if (currentCount === previousCount) {
        unchangedCount++;
        if (unchangedCount >= MAX_UNCHANGED || scrollAttempts >= MAX_SCROLLS) {
            finishCollection();
        }
    } else {
        unchangedCount = 0;
    }
    
    previousCount = currentCount;
    window.scrollBy(0, SCROLL_STEP);
    
    // Auto click Retry jika ada error loading di halaman
    document.querySelectorAll('[role="button"]').forEach(btn => {
        const txt = btn.textContent.toLowerCase();
        if (txt.includes('retry') || txt.includes('coba lagi') || txt.includes('show more')) {
            btn.click();
        }
    });
}

function finishCollection() {
    if (isComplete) return;
    isComplete = true;
    clearInterval(intervalId);
    observer.disconnect();
    
    console.log('%c --- SELESAI --- ', 'background: #222; color: #bada55; font-size: 20px');
    console.log(`Total ditemukan: ${mediaLinks.length}`);
    
    if (mediaLinks.length > 0) {
        // Gabungkan dengan newline, tanpa koma, tanpa quote
        const textData = mediaLinks.join('\n');
        const blob = new Blob([textData], { type: 'text/plain' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `x_links_${Date.now()}.txt`;
        a.click();
        console.log('File .txt berhasil dibuat. Masukkan isinya ke queue.txt');
    } else {
        console.error('NOL link ditemukan.');
    }
}

console.clear();
console.log('%c Memulai Scraper Media X... ', 'background: #1DA1F2; color: white; font-size: 16px');
updateMediaList();
const intervalId = setInterval(scrollAndCollect, SCROLL_INTERVAL);
const observer = new MutationObserver(() => { if (!isComplete) updateMediaList(); });
observer.observe(document.body, { childList: true, subtree: true });
