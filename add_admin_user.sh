#!/bin/bash

# Скрипт для создания пользователя Kubernetes с правами cluster-admin
# и генерации для него готового kubeconfig файла.
#
# Использование: ./create-user.sh <имя_пользователя>
# Пример: ./create-user.sh dev-user

# Останавливаемся при любой ошибке
set -e

# --- 1. Проверка входных данных ---
if [ -z "$1" ]; then
  echo "Ошибка: Не указано имя пользователя."
  echo "Использование: $0 <имя_пользователя>"
  exit 1
fi

USERNAME=$1
# Группа, которую можно использовать для RBAC. Для cluster-admin это не так важно.
GROUP="my-org"
echo "Создание пользователя: ${USERNAME}..."

# --- 2. Генерация ключа и запроса на сертификат (CSR) ---
echo "Шаг 1: Генерация ключа и CSR..."
openssl genrsa -out ${USERNAME}.key 2048
openssl req -new -key ${USERNAME}.key -out ${USERNAME}.csr -subj "/CN=${USERNAME}/O=${GROUP}"

# --- 3. Отправка и подтверждение CSR в Kubernetes ---
echo "Шаг 2: Отправка и подтверждение CSR..."
CSR_NAME=${USERNAME}-csr

# Удаляем старый CSR, если он существует
kubectl delete csr ${CSR_NAME} --ignore-not-found=true

# Создаем новый CSR
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: ${CSR_NAME}
spec:
  request: $(cat ${USERNAME}.csr | base64 | tr -d '\n')
  signerName: kubernetes.io/kube-apiserver-client
  usages:
  - client auth
EOF

# Подтверждаем CSR
kubectl certificate approve ${CSR_NAME}

# --- 4. Предоставление прав cluster-admin ---
echo "Шаг 3: Предоставление прав cluster-admin..."
# kubectl create clusterrolebinding может выдать ошибку, если binding уже существует.
# Используем apply для идемпотентности.
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ${USERNAME}-cluster-admin-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: User
  name: ${USERNAME}
EOF

# --- 5. Генерация kubeconfig файла ---
echo "Шаг 4: Генерация файла kubeconfig..."

# Получаем данные текущего кластера
CONTEXT_NAME=$(kubectl config current-context)
CLUSTER_NAME=$(kubectl config get-contexts $CONTEXT_NAME --no-headers | awk '{print $3}')
API_SERVER=$(kubectl config view -o jsonpath="{.clusters[?(@.name==\"$CLUSTER_NAME\")].cluster.server}")
CA_DATA=$(kubectl config view --raw -o jsonpath="{.clusters[?(@.name==\"$CLUSTER_NAME\")].cluster.certificate-authority-data}")

# Получаем сертификат пользователя
USER_CERT_DATA=$(kubectl get csr ${CSR_NAME} -o jsonpath='{.status.certificate}')

# Получаем ключ пользователя
USER_KEY_DATA=$(cat ${USERNAME}.key | base64 | tr -d '\n')

# Собираем kubeconfig
KUBECONFIG_FILE=${USERNAME}.kubeconfig
echo "apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: ${CA_DATA}
    server: ${API_SERVER}
  name: ${CLUSTER_NAME}
contexts:
- context:
    cluster: ${CLUSTER_NAME}
    user: ${USERNAME}
  name: ${USERNAME}-context
current-context: ${USERNAME}-context
users:
- name: ${USERNAME}
  user:
    client-certificate-data: ${USER_CERT_DATA}
    client-key-data: ${USER_KEY_DATA}
" > ${KUBECONFIG_FILE}

echo "Готово! Файл конфигурации сохранен как: ./${KUBECONFIG_FILE}"

# --- 6. Очистка временных файлов ---
echo "Шаг 5: Очистка временных файлов..."
rm ${USERNAME}.key ${USERNAME}.csr
echo "Пользователь ${USERNAME} успешно создан."

echo -e "\n--- Как использовать ---"
echo "Отправьте файл ./${KUBECONFIG_FILE} пользователю."
echo "Пользователь может использовать его так:"
echo "export KUBECONFIG=./${KUBECONFIG_FILE}"
echo "kubectl get nodes"