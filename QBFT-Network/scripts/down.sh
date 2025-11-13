#!/bin/bash
# Script para DERRUBAR a rede Besu QBFT no Kind
set -e

echo "🔥 Derrubando o cluster Kind 'besu-qbft'..."
kind delete cluster --name besu-qbft
echo "✅ Cluster destruído."
