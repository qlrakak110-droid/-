// Minimal dependency-free WebSocket server (RFC 6455): text frames, ping/pong, close.
// Enough for this game so the server runs with plain `node server.js` — no npm install.
import crypto from 'node:crypto';
import { EventEmitter } from 'node:events';

const GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

class Socket extends EventEmitter {
  constructor(socket, maxPayload) {
    super();
    this.socket = socket;
    this.maxPayload = maxPayload;
    this.readyState = 1; // OPEN
    this.buf = Buffer.alloc(0);
    this.fragments = [];
    socket.setNoDelay(true);
    socket.on('data', (d) => this.onData(d));
    socket.on('close', () => this.finish());
    socket.on('error', () => this.finish());
  }
  get bufferedAmount() { return this.socket.writableLength; }

  onData(chunk) {
    this.buf = this.buf.length ? Buffer.concat([this.buf, chunk]) : chunk;
    while (this.readyState === 1) {
      const b = this.buf;
      if (b.length < 2) return;
      const fin = (b[0] & 0x80) !== 0, op = b[0] & 0x0f, masked = (b[1] & 0x80) !== 0;
      let len = b[1] & 0x7f, off = 2;
      if (len === 126) { if (b.length < 4) return; len = b.readUInt16BE(2); off = 4; }
      else if (len === 127) {
        if (b.length < 10) return;
        if (b.readUInt32BE(2) !== 0) return this.fail(1009);
        len = b.readUInt32BE(6); off = 10;
      }
      if (!masked) return this.fail(1002); // clients must mask
      if (len > this.maxPayload) return this.fail(1009);
      if (b.length < off + 4 + len) return;
      const mask = b.subarray(off, off + 4);
      const data = Buffer.from(b.subarray(off + 4, off + 4 + len));
      for (let i = 0; i < data.length; i++) data[i] ^= mask[i & 3];
      this.buf = b.subarray(off + 4 + len);
      this.onFrame(fin, op, data);
    }
  }

  onFrame(fin, op, data) {
    if (op === 0x8) { this.close(); return; }
    if (op === 0x9) { this.frame(0xa, data); return; }
    if (op === 0xa) { this.emit('pong'); return; }
    if (op === 0x1 || op === 0x2 || op === 0x0) {
      this.fragments.push(data);
      const total = this.fragments.reduce((n, f) => n + f.length, 0);
      if (total > this.maxPayload) return this.fail(1009);
      if (!fin) return;
      const msg = Buffer.concat(this.fragments);
      this.fragments = [];
      this.emit('message', msg.toString('utf8'));
    }
  }

  frame(op, payload) {
    if (this.socket.destroyed) return;
    const len = payload.length;
    let head;
    if (len < 126) { head = Buffer.alloc(2); head[1] = len; }
    else if (len < 65536) { head = Buffer.alloc(4); head[1] = 126; head.writeUInt16BE(len, 2); }
    else { head = Buffer.alloc(10); head[1] = 127; head.writeUInt32BE(0, 2); head.writeUInt32BE(len, 6); }
    head[0] = 0x80 | op;
    this.socket.write(Buffer.concat([head, payload]));
  }

  send(text) { if (this.readyState === 1) this.frame(0x1, Buffer.from(text, 'utf8')); }
  ping() { if (this.readyState === 1) this.frame(0x9, Buffer.alloc(0)); }

  close(code = 1000) {
    if (this.readyState !== 1) return;
    const p = Buffer.alloc(2);
    p.writeUInt16BE(code, 0);
    this.frame(0x8, p);
    this.readyState = 2; // CLOSING
    this.socket.end();
    setTimeout(() => this.socket.destroy(), 1000).unref();
  }
  fail(code) { this.close(code); }
  terminate() { this.socket.destroy(); }

  finish() {
    if (this.readyState === 3) return;
    this.readyState = 3; // CLOSED
    this.emit('close');
  }
}

export class WebSocketServer extends EventEmitter {
  constructor({ server, maxPayload = 64 * 1024 }) {
    super();
    this.clients = new Set();
    server.on('upgrade', (req, socket) => {
      const key = req.headers['sec-websocket-key'];
      if (!key || String(req.headers.upgrade).toLowerCase() !== 'websocket') {
        socket.end('HTTP/1.1 400 Bad Request\r\n\r\n');
        return;
      }
      const accept = crypto.createHash('sha1').update(key + GUID).digest('base64');
      socket.write(
        'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n' +
        `Sec-WebSocket-Accept: ${accept}\r\n\r\n`,
      );
      const ws = new Socket(socket, maxPayload);
      this.clients.add(ws);
      ws.on('close', () => this.clients.delete(ws));
      this.emit('connection', ws, req);
    });
  }
}
