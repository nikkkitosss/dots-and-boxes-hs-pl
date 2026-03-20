
const http = require('http');

const PROLOG_PORT = 3002;
const PROXY_PORT  = 3001;

const server = http.createServer((req, res) => {
  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      'Access-Control-Allow-Origin':  '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    });
    res.end();
    return;
  }

  const options = {
    hostname: '127.0.0.1',
    port: PROLOG_PORT,
    path: req.url,
    method: req.method,
    headers: req.headers,
  };

  const proxy = http.request(options, (prologRes) => {
    const headers = Object.assign({}, prologRes.headers, {
      'Access-Control-Allow-Origin':  '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    });
    res.writeHead(prologRes.statusCode, headers);
    prologRes.pipe(res);
  });

  proxy.on('error', (e) => {
    res.writeHead(502, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Prolog недоступний: ' + e.message }));
  });

  req.pipe(proxy);
});

server.listen(PROXY_PORT, () => {
  console.log(`CORS proxy :${PROXY_PORT} -> Prolog :${PROLOG_PORT}`);
});