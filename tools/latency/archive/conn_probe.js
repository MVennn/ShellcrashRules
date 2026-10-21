const net = require("net");
const hosts = process.argv.slice(2);
const proxyHost = process.env.MIHOMO_HOST || "127.0.0.1";
const proxyPort = Number(process.env.MIHOMO_PORT || 7890);
const socks = [];
for (const h of hosts) {
  const s = net.connect(proxyPort, proxyHost, () => {
    s.write(`CONNECT ${h}:443 HTTP/1.1\r\nHost: ${h}:443\r\n\r\n`);
  });
  s.on("data", (d) => console.log(h, "->", d.toString().split("\r\n")[0]));
  s.on("error", (e) => console.log(h, "ERR", e.message));
  socks.push(s);
}
setTimeout(() => { socks.forEach((s) => s.destroy()); process.exit(0); }, 15000);
