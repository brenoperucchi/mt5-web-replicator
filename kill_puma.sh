#!/bin/bash

# Caminho para o arquivo PID
PID_FILE="/Users/brenoperucchi/Devs/signalforex/tmp/pids/server3.pid"

# Verifica se o arquivo PID existe
if [ -f "$PID_FILE" ]; then
    # Lê o PID do arquivo
    PID=$(cat "$PID_FILE")

    # Verifica se o processo está rodando
    if ps -p $PID > /dev/null; then
        echo "Matando o processo Puma com PID: $PID"
        kill -9 $PID
    else
        echo "Processo com PID $PID não está rodando."
    fi
else
    echo "Arquivo PID não encontrado: $PID_FILE"
fi

