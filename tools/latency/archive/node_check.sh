#!/bin/sh
# Query mihomo API for group state and node delays
API="http://127.0.0.1:9999"

echo "=== AI group (🤖 人工智能) ==="
curl -s --max-time 8 "$API/proxies/%F0%9F%A4%96%20%E4%BA%BA%E5%B7%A5%E6%99%BA%E8%83%BD" | tr ',' '\n' | grep -E '"now"|"type"' | head -5

echo ""
echo "=== opencode.ai delay per node (ms) ==="
for enc in \
  "%F0%9F%87%B8%F0%9F%87%AC%20%E6%96%B0%E5%8A%A0%E5%9D%A1-%E4%BC%98%E5%8C%96-GPT" \
  "%F0%9F%87%B8%F0%9F%87%AC%20%E6%96%B0%E5%8A%A0%E5%9D%A1-%E4%BC%98%E5%8C%962-GPT" \
  "%F0%9F%87%B8%F0%9F%87%AC%20%E6%96%B0%E5%8A%A0%E5%9D%A1-%E4%BC%98%E5%8C%963" \
  "%F0%9F%87%BA%F0%9F%87%B2%20%E7%BE%8E%E5%9B%BDLA-%E4%BC%98%E5%8C%96-GPT" \
  "%F0%9F%87%BA%F0%9F%87%B2%20%E7%BE%8E%E5%9B%BDLA-%E4%BC%98%E5%8C%962-GPT" \
  "%F0%9F%87%AD%F0%9F%87%B0%20%E9%A6%99%E6%B8%AF-%E4%BC%98%E5%8C%962" \
  "%F0%9F%87%AF%F0%9F%87%B5%20%E6%97%A5%E6%9C%AC-%E4%BC%98%E5%8C%96" \
  "%F0%9F%87%AF%F0%9F%87%B5%20%E6%97%A5%E6%9C%AC-%E4%BC%98%E5%8C%962" \
  "%F0%9F%87%A8%F0%9F%87%A6%20%E5%8A%A0%E6%8B%BF%E5%A4%A7-%E4%BC%98%E5%8C%96" \
  "%F0%9F%87%AC%F0%9F%87%A7%20%E8%8B%B1%E5%9B%BD-%E4%BC%98%E5%8C%96-GPT" \
  "%F0%9F%87%A9%F0%9F%87%AA%20%E5%BE%B7%E5%9B%BD-%E4%BC%98%E5%8C%96" \
  "%F0%9F%87%B9%F0%9F%87%BC%20%E5%8F%B0%E6%B9%BE-%E4%BC%98%E5%8C%962-GPT" \
  "%F0%9F%87%AE%F0%9F%87%B3%20%E5%8D%B0%E5%BA%A6-%E4%BC%98%E5%8C%96" ; do
  printf "%-14.14s " "$enc"
  curl -s --max-time 12 "$API/proxies/$enc/delay?timeout=8000&url=https%3A%2F%2Fopencode.ai%2F"
  echo ""
done
