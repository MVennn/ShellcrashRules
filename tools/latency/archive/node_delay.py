import urllib.request, urllib.parse, json
def api(p):
    return urllib.request.urlopen("http://127.0.0.1:9090"+p, timeout=15).read().decode()
g = json.loads(api("/proxies/"+urllib.parse.quote("🤖 人工智能")))
print("AI group now ->", g.get("now"))
for n in ["🇸🇬 新加坡-优化-GPT","🇸🇬 新加坡-优化2-GPT","🇸🇬 新加坡-优化3",
          "🇺🇲 美国LA-优化-GPT","🇺🇲 美国LA-优化2-GPT","🇭🇰 香港-优化2",
          "🇯🇵 日本-优化","🇯🇵 日本-优化2","🇨🇦 加拿大-优化","🇬🇧 英国-优化-GPT",
          "🇩🇪 德国-优化","🇹🇼 台湾-优化2-GPT","🇮🇳 印度-优化"]:
    try:
        d = json.loads(api("/proxies/"+urllib.parse.quote(n)+"/delay?timeout=8000&url="+urllib.parse.quote("https://opencode.ai/", safe="")))
        print(f"{n:26s} {d}")
    except Exception as e:
        print(f"{n:26s} ERR {e}")
