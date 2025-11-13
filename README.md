````markdown
# Rede Hyperledger Besu QBFT em Kubernetes (kind) – Guia passo a passo

Este documento descreve, do zero, como subir uma rede privada Hyperledger Besu usando consenso QBFT com 4 nós validadores rodando em Kubernetes via kind.

Inclui:

* Instalação das ferramentas necessárias
* Geração (ou uso) do `genesis.json` e das chaves dos nós
* Criação do cluster Kubernetes e namespace
* Criação de ConfigMap/Secrets
* Manifests dos 4 nós (Node1–Node4)
* Comandos para subir, verificar, logar e interagir com a rede

## 1. Pré-requisitos

### 1.1. Docker

Instale Docker Engine (ou Docker Desktop) para sua distro Linux.

(Usado tanto pelo kind quanto pela imagem do Besu.)

### 1.2. kubectl

Instale o client oficial do Kubernetes (kubectl) conforme a documentação:
Exemplo em Ubuntu (via repositório apt, versão estável):

```bash
# Atualiza lista de pacotes
sudo apt update

# Instala dependências do repositório Kubernetes
sudo apt install -y apt-transport-https ca-certificates curl gnupg

# Adiciona chave GPG do repositório
sudo mkdir -p /etc/apt/keyrings
curl -fsSL [https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key](https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key) \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Adiciona repositório do Kubernetes
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
[https://pkgs.k8s.io/core:/stable:/v1.30/deb/](https://pkgs.k8s.io/core:/stable:/v1.30/deb/) /" \
| sudo tee /etc/apt/sources.list.d/kubernetes.list

# Instala kubectl
sudo apt update
sudo apt install -y kubectl

# Verifica
kubectl version --client
````

### 1.3. kind (Kubernetes in Docker)

Instale o kind seguindo o quick start oficial.
Exemplo instalação com `go install`:

```bash
GO111MODULE="on" go install sigs.k8s.io/kind@v0.30.0

# Certifique-se de que $(go env GOPATH)/bin está no seu PATH
export PATH="$(go env GOPATH)/bin:$PATH"

kind version
```

Ou use o binário pronto do site do kind (mesmo link do quick start).

### 1.4. Hyperledger Besu (para gerar rede QBFT)

Você pode usar o binário do Besu para gerar `genesis.json` e chaves. A doc oficial de rede QBFT mostra o fluxo usando o comando `besu operator generate-blockchain-config`.

Se você já tem:

  * pasta `QBFT-Network/`
  * arquivo `genesis.json`
  * pastas `Node-1/data/key`, `Node-2/data/key`, `Node-3/data/key`, `Node-4/data/key`

pode pular para a próxima seção.

Caso queira (re)gerar do zero, siga o tutorial “Create a network using QBFT” do Besu.
Resumo do comando principal:

```bash
cd QBFT-Network

besu operator generate-blockchain-config \
  --config-file=qbftConfigFile.json \
  --to=networkFiles \
  --private-key-file-name=key
```

Isso cria:

  * `networkFiles/genesis.json`
  * `networkFiles/keys/<endereço>/key` para cada nó

Depois, copie:

```bash
cp networkFiles/genesis.json ./genesis.json

# Por conveniência, copie cada key para seu diretório de nó
mkdir -p Node-1/data Node-2/data Node-3/data Node-4/data
cp networkFiles/keys/<endereco1>/key Node-1/data/key
cp networkFiles/keys/<endereco2>/key Node-2/data/key
cp networkFiles/keys/<endereco3>/key Node-3/data/key
cp networkFiles/keys/<endereco4>/key Node-4/data/key
```

## 2\. Estrutura de diretórios recomendada

Dentro da pasta `QBFT-Network/`:

```
QBFT-Network/
  genesis.json
  qbftConfigFile.json          # (opcional, só para regenerar rede)
  networkFiles/                # (opcional, saída do generate-blockchain-config)
    keys/
      <address1>/key
      <address2>/key
      <address3>/key
      <address4>/key
  Node-1/
    data/
      key
  Node-2/
    data/
      key
  Node-3/
    data/
      key
  Node-4/
    data/
      key
  k8s/
    namespace.yaml
    node1.yaml
    node2.yaml
    node3.yaml
    node4.yaml
```

## 3\. Criar o cluster Kubernetes com kind

No host (Ubuntu), em qualquer pasta:

```bash
kind create cluster --name besu-qbft
```

Isso cria um cluster Kubernetes local com contexto `kind-besu-qbft`.
Verifique:

```bash
kubectl config current-context
# esperado: kind-besu-qbft

kubectl get nodes
```

## 4\. Namespace para a rede Besu

Crie o arquivo `k8s/namespace.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: besu-qbft
```

Aplique:

```bash
cd QBFT-Network
kubectl apply -f k8s/namespace.yaml
```

## 5\. ConfigMap com o genesis.json

Na raiz de `QBFT-Network/` (onde está `genesis.json`):

```bash
kubectl create configmap qbft-genesis \
  -n besu-qbft \
  --from-file=genesis.json=./genesis.json
```

## 6\. Secrets com as chaves dos 4 nós

Ainda na raiz de `QBFT-Network/`:

```bash
kubectl create secret generic besu-node1-key \
  -n besu-qbft \
  --from-file=key=./Node-1/data/key

kubectl create secret generic besu-node2-key \
  -n besu-qbft \
  --from-file=key=./Node-2/data/key

kubectl create secret generic besu-node3-key \
  -n besu-qbft \
  --from-file=key=./Node-3/data/key

kubectl create secret generic besu-node4-key \
  -n besu-qbft \
  --from-file=key=./Node-4/data/key
```

Esses Secrets serão montados nos pods para o parâmetro `--node-private-key-file`.

## 7\. Manifests dos nós (Deployments + Services)

### 7.1. Node1 – Bootnode

Crie `k8s/node1.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: besu-node1
  namespace: besu-qbft
spec:
  replicas: 1
  selector:
    matchLabels:
      app: besu
      node: node1
  template:
    metadata:
      labels:
        app: besu
        node: node1
    spec:
      containers:
      - name: besu
        image: hyperledger/besu:latest
        args:
        - --genesis-file=/opt/besu/genesis.json
        - --data-path=/opt/besu/data
        - --node-private-key-file=/opt/besu/keys/key
        - --data-storage-format=FOREST
        - --p2p-port=30303
        - --rpc-http-enabled
        - --rpc-http-host=0.0.0.0
        - --rpc-http-api=ETH,NET,QBFT,ADMIN
        - --host-allowlist=*
        - --rpc-http-cors-origins=*
        - --metrics-enabled
        - --metrics-host=0.0.0.0
        ports:
        - name: p2p
          containerPort: 30303
          protocol: TCP
        - name: p2p-udp
          containerPort: 30303
          protocol: UDP
        - name: rpc
          containerPort: 8545
          protocol: TCP
        - name: metrics
          containerPort: 9545
          protocol: TCP
        volumeMounts:
        - name: genesis
          mountPath: /opt/besu/genesis.json
          subPath: genesis.json
        - name: data
          mountPath: /opt/besu/data
        - name: nodekey
          mountPath: /opt/besu/keys
      volumes:
      - name: genesis
        configMap:
          name: qbft-genesis
      - name: data
        emptyDir: {}
      - name: nodekey
        secret:
          secretName: besu-node1-key
---
apiVersion: v1
kind: Service
metadata:
  name: besu-node1-p2p
  namespace: besu-qbft
spec:
  selector:
    app: besu
    node: node1
  ports:
  - name: p2p-tcp
    port: 30303
    targetPort: p2p
    protocol: TCP
  - name: p2p-udp
    port: 30303
    targetPort: p2p-udp
    protocol: UDP
---
apiVersion: v1
kind: Service
metadata:
  name: besu-node1-rpc
  namespace: besu-qbft
spec:
  type: NodePort
  selector:
    app: besu
    node: node1
  ports:
  - name: rpc
    port: 8545
    targetPort: rpc
    nodePort: 30001
  - name: metrics
    port: 9545
    targetPort: metrics
    nodePort: 31001
```

**Observações:**

  * Estamos usando `emptyDir` para `/opt/besu/data` → estado da blockchain não persiste se o pod for recriado (bom para laboratório).
  * O Service `besu-node1-p2p` é usado pelos outros nós como bootnode.

### 7.2. Node2 – com bootnode via DNS

Besu, por padrão, espera IP no `--bootnodes`. Para usar um hostname (o Service `besu-node1-p2p.besu-qbft.svc.cluster.local`), habilitamos o suporte a DNS com as flags `--Xdns-enabled=true` e `--Xdns-update-enabled=true`.

Crie `k8s/node2.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: besu-node2
  namespace: besu-qbft
spec:
  replicas: 1
  selector:
    matchLabels:
      app: besu
      node: node2
  template:
    metadata:
      labels:
        app: besu
        node: node2
    spec:
      containers:
      - name: besu
        image: hyperledger/besu:latest
        args:
        - --genesis-file=/opt/besu/genesis.json
        - --data-path=/opt/besu/data
        - --node-private-key-file=/opt/besu/keys/key
        - --data-storage-format=FOREST
        - --p2p-port=30303
        - --rpc-http-enabled
        - --rpc-http-host=0.0.0.0
        - --rpc-http-api=ETH,NET,QBFT,ADMIN
        - --host-allowlist=*
        - --rpc-http-cors-origins=*
        - --metrics-enabled
        - --metrics-host=0.0.0.0
        - --Xdns-enabled=true
        - --Xdns-update-enabled=true
        - --bootnodes=enode://<ENODE_ID_DO_NODE1>@besu-node1-p2p.besu-qbft.svc.cluster.local:30303
        ports:
        - name: p2p
          containerPort: 30303
          protocol: TCP
        - name: p2p-udp
          containerPort: 30303
          protocol: UDP
        - name: rpc
          containerPort: 8545
          protocol: TCP
        - name: metrics
          containerPort: 9545
          protocol: TCP
        volumeMounts:
        - name: genesis
          mountPath: /opt/besu/genesis.json
          subPath: genesis.json
        - name: data
          mountPath: /opt/besu/data
        - name: nodekey
          mountPath: /opt/besu/keys
      volumes:
      - name: genesis
        configMap:
          name: qbft-genesis
      - name: data
        emptyDir: {}
      - name: nodekey
        secret:
          secretName: besu-node2-key
---
apiVersion: v1
kind: Service
metadata:
  name: besu-node2-rpc
  namespace: besu-qbft
spec:
  type: NodePort
  selector:
    app: besu
    node: node2
  ports:
  - name: rpc
    port: 8545
    targetPort: rpc
    nodePort: 30002
  - name: metrics
    port: 9545
    targetPort: metrics
    nodePort: 31002
```

**Nota:** Troque `<ENODE_ID_DO_NODE1>` pelo `enode` real do seu Node1 (o mesmo que você usava no Docker, mas trocando o IP pelo DNS do Service).

### 7.3. Node3 e Node4

Crie `k8s/node3.yaml` copiando o `node2.yaml` e alterando:

  * `name: besu-node3`
  * label `node: node3`
  * Secret: `besu-node3-key`
  * NodePort RPC/metrics: `30003` e `31003`

Crie `k8s/node4.yaml` copiando o `node2.yaml` e alterando:

  * `name: besu-node4`
  * label `node: node4`
  * Secret: `besu-node4-key`
  * NodePort RPC/metrics: `30004` e `31004`

O `--bootnodes` é o mesmo em todos (apontando para o Node1).

## 8\. Subindo a rede

Dentro de `QBFT-Network/`:

### 8.1. Aplicar Node1 primeiro

```bash
kubectl apply -f k8s/node1.yaml
kubectl get pods -n besu-qbft
kubectl logs -f -n besu-qbft deployment/besu-node1
```

Espere o Node1 ficar `1/1 Running`.

### 8.2. Aplicar Node2, Node3, Node4

```bash
kubectl apply -f k8s/node2.yaml
kubectl apply -f k8s/node3.yaml
kubectl apply -f k8s/node4.yaml

kubectl get pods -n besu-qbft
kubectl get deployments -n besu-qbft
```

Estado esperado:

```
NAME         READY   UP-TO-DATE   AVAILABLE
besu-node1   1/1     1            1
besu-node2   1/1     1            1
besu-node3   1/1     1            1
besu-node4   1/1     1            1
```

## 9\. Verificando a rede (logs e RPC)

### 9.1. Logs dos nós

```bash
kubectl logs -f -n besu-qbft deployment/besu-node1
kubectl logs -f -n besu-qbft deployment/besu-node2
kubectl logs -f -n besu-qbft deployment/besu-node3
kubectl logs -f -n besu-qbft deployment/besu-node4
```

Ou todos de uma vez:

```bash
kubectl logs -f -n besu-qbft -l app=besu
```

### 9.2. Acessando RPC com kubectl port-forward (kind)

Como o cluster é `kind`, o jeito mais simples de acessar o RPC é com `port-forward`.

**Node1**
`kubectl port-forward -n besu-qbft svc/besu-node1-rpc 8545:8545`

Em outro terminal:

```bash
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

**Node2, Node3, Node4**

```bash
kubectl port-forward -n besu-qbft svc/besu-node2-rpc 8546:8545
kubectl port-forward -n besu-qbft svc/besu-node3-rpc 8547:8545
kubectl port-forward -n besu-qbft svc/besu-node4-rpc 8548:8545
```

Depois:

```bash
curl -X POST http://localhost:8546 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

Os `result` retornados devem ser iguais (ou bem próximos) para todos os nós.

### 9.3. Checando peers e validadores QBFT

Com o port-forward do Node1 ativo:

**Número de peers:**

```bash
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}'
```

Esperado: `0x3` para um cluster com 4 nós (Node1 vendo Node2, 3 e 4).

**Validadores QBFT (API QBFT):**

```bash
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"qbft_getValidatorsByBlockNumber","params":["latest"],"id":1}'
```

Deve retornar a lista dos 4 validadores definidos no `genesis.json`.

## 10\. Operações básicas com Kubernetes

### 10.1. “Derrubar” um nó (simular falha)

```bash
kubectl scale deployment besu-node3 -n besu-qbft --replicas=0
kubectl get pods -n besu-qbft
```

Depois, para trazê-lo de volta:

```bash
kubectl scale deployment besu-node3 -n besu-qbft --replicas=1
```

### 10.2. Deletar/Recriar pods

```bash
kubectl delete pod -n besu-qbft <nome-do-pod>
# o Deployment recria o pod automaticamente
```

### 10.3. Entrar dentro de um container

```bash
kubectl exec -it -n besu-qbft <nome-do-pod-node1> -- /bin/sh
```

## 11\. Observações finais

Este setup foi pensado como ambiente de desenvolvimento/lab:

  * `emptyDir` → dados da blockchain não são persistidos se os pods forem recriados.

Para produção, você deve:

  * Usar `PersistentVolumes` e `PersistentVolumeClaims` em vez de `emptyDir`;
  * Considerar usar Helm charts ou projetos como Hyperledger Bevel para automatizar a criação de redes Besu;
  * Configurar monitoração, logs centralizados, etc.

<!-- end list -->
