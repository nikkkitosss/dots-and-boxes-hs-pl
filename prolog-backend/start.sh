#!/bin/sh
# Запуск всередині Docker контейнера

# Prolog на порту 3002 (внутрішній)
swipl -g "server(3002)" prolog-server.pl &

# Чекаємо поки Prolog стартує
sleep 3

# CORS proxy на порту 3001 (зовнішній)
node cors-proxy.js