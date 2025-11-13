#!/bin/bash
# Script para SUBIR a rede Besu QBFT no Kind
set -e

echo "🚀 1/5: Criando cluster Kind 'besu-qbft'..."
kind create cluster --name besu-qbft --config=../kind-config.yaml

echo "🐙 Adicionando repositórios Helm..."
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add elastic https://helm.elastic.co
helm repo update

echo "🚢 Instalando Ingress-NGINX..."
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --wait

echo "📊 Instalando Prometheus + Grafana..."
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --wait

echo "🔍 Instalando Elasticsearch + Kibana..."
# 1. Instala o Elasticsearch (o "banco de dados" de logs)
helm install elasticsearch elastic/elasticsearch \
  --namespace logging \
  --create-namespace \
  --set replicas=1 \
  --set minimumMasterNodes=1 \
  --wait

# 2. Instala o Kibana (a "interface" de logs)
helm install kibana elastic/kibana \
  --namespace logging \
  --wait

echo "🌐 2/5: Criando Namespace 'besu-qbft'..."
kubectl apply -f ./../k8s/namespace.yaml

echo "📄 3/5: Criando ConfigMap (genesis.json)..."
kubectl create configmap qbft-genesis -n besu-qbft --from-file=genesis.json=./../genesis.json

echo "🔑 4/5: Criando Secrets (chaves dos nós)..."
kubectl create secret generic besu-node1-key -n besu-qbft --from-file=key=../Node-1/data/key
kubectl create secret generic besu-node2-key -n besu-qbft --from-file=key=../Node-2/data/key
kubectl create secret generic besu-node3-key -n besu-qbft --from-file=key=../Node-3/data/key
kubectl create secret generic besu-node4-key -n besu-qbft --from-file=key=../Node-4/data/key

echo "🚢 5/5: Aplicando Deployments e Services dos nós..."
kubectl apply -f ./../k8s/node1.yaml
kubectl apply -f ./../k8s/node2.yaml
kubectl apply -f ./../k8s/node3.yaml
kubectl apply -f ./../k8s/node4.yaml

echo ""
echo "🎉 Rede Besu QBFT subindo! Aguardando 15s para os pods iniciarem..."
sleep 20
echo ""
echo "🔎 Verificando status dos pods:"
kubectl get pods -n besu-qbft -o wide
