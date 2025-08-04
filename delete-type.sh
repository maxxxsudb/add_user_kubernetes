# === Скрипт для очистки engineimages.longhorn.io ===

RESOURCE_TYPE="engineimages.longhorn.io"
NAMESPACE="longhorn-system"

echo "--- Cleaning up $RESOURCE_TYPE in namespace $NAMESPACE ---"

# Получаем имена всех ресурсов этого типа
for resource in $(kubectl get $RESOURCE_TYPE -n $NAMESPACE -o name); do
  echo "Patching finalizer for $resource ..."
  kubectl patch $resource -n $NAMESPACE -p '{"metadata":{"finalizers":[]}}' --type='merge'
done

echo "--- Finished cleaning up $RESOURCE_TYPE ---"