const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = 3000;
const DATA_DIR = path.join(__dirname, 'data');
const CONTENT_FILE = path.join(DATA_DIR, 'content-unlock.json');
const STATIC_ROOT = __dirname;

const MIME_TYPES = {
    '.css': 'text/css; charset=utf-8',
    '.html': 'text/html; charset=utf-8',
    '.js': 'application/javascript; charset=utf-8',
    '.json': 'application/json; charset=utf-8',
    '.png': 'image/png',
    '.svg': 'image/svg+xml; charset=utf-8',
    '.txt': 'text/plain; charset=utf-8'
};

// Ensure data directory exists
if (!fs.existsSync(DATA_DIR)) {
    fs.mkdirSync(DATA_DIR, { recursive: true });
}

if (!fs.existsSync(CONTENT_FILE)) {
    fs.writeFileSync(CONTENT_FILE, '[]', 'utf8');
}

// Helper to sanitize username to prevent directory traversal
function sanitizeUsername(username) {
    if (!username || typeof username !== 'string') return null;
    const cleaned = username.replace(/[^a-zA-Z0-9_\-]/g, '').trim();
    if (cleaned.length === 0 || cleaned.length > 50) return null;
    return cleaned;
}

function sendJson(res, statusCode, payload) {
    res.writeHead(statusCode, { 'Content-Type': 'application/json; charset=utf-8' });
    res.end(JSON.stringify(payload));
}

function sendText(res, statusCode, text) {
    res.writeHead(statusCode, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end(text);
}

function getContentType(filePath) {
    return MIME_TYPES[path.extname(filePath).toLowerCase()] || 'application/octet-stream';
}

function resolveStaticPath(pathname) {
    const decoded = decodeURIComponent(pathname === '/' ? '/index.html' : pathname);
    const normalized = path.normalize(decoded).replace(/^(\.\.[/\\])+/, '');
    const relativePath = normalized.replace(/^[/\\]+/, '');
    const filePath = path.join(STATIC_ROOT, relativePath || 'index.html');

    if (!filePath.startsWith(STATIC_ROOT)) {
        return null;
    }

    return filePath;
}

function serveStaticFile(res, pathname) {
    const filePath = resolveStaticPath(pathname);
    if (!filePath) {
        sendText(res, 403, 'Forbidden');
        return;
    }

    if (!fs.existsSync(filePath) || fs.statSync(filePath).isDirectory()) {
        sendText(res, 404, 'Not found');
        return;
    }

    res.writeHead(200, { 'Content-Type': getContentType(filePath) });
    fs.createReadStream(filePath).pipe(res);
}

const server = http.createServer((req, res) => {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

    if (req.method === 'OPTIONS') {
        res.writeHead(204);
        res.end();
        return;
    }

    try {
        const url = new URL(req.url, `http://${req.headers.host}`);
        const pathname = url.pathname;

        if (pathname === '/api/content') {
            if (req.method !== 'GET') {
                sendText(res, 405, 'Method not allowed');
                return;
            }

            const data = fs.readFileSync(CONTENT_FILE, 'utf8');
            res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
            res.end(data);
        } else if (pathname === '/api/progress') {
            const rawUser = url.searchParams.get('user');
            const user = sanitizeUsername(rawUser);

            if (!user) {
                sendJson(res, 400, { error: "Invalid or missing 'user' parameter. Use alphanumeric characters only." });
                return;
            }

            const filePath = path.join(DATA_DIR, `${user}.json`);

            if (req.method === 'GET') {
                if (fs.existsSync(filePath)) {
                    const data = fs.readFileSync(filePath, 'utf8');
                    res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
                    res.end(data);
                } else {
                    res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
                    res.end(JSON.stringify({}));
                }
            } else if (req.method === 'POST') {
                let body = '';
                req.on('data', chunk => {
                    body += chunk.toString();
                    if (body.length > 1e6) {
                        req.destroy();
                    }
                });

                req.on('end', () => {
                    try {
                        const parsedBody = JSON.parse(body);
                        fs.writeFileSync(filePath, JSON.stringify(parsedBody), 'utf8');
                        sendJson(res, 200, { success: true });
                    } catch (e) {
                        sendJson(res, 400, { error: 'Invalid JSON format' });
                    }
                });
            } else {
                sendText(res, 405, 'Method not allowed');
            }
        } else {
            serveStaticFile(res, pathname);
        }
    } catch (e) {
        console.error(e);
        sendText(res, 500, 'Internal Server Error');
    }
});

server.listen(PORT, () => {
    console.log(`FFXIV Unlocklist Backend running on port ${PORT}`);
    console.log(`Saving profiles locally inside: ${DATA_DIR}`);
    console.log(`Serving content data from: ${CONTENT_FILE}`);
});
