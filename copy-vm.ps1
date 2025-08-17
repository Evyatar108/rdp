# ----- SOURCE (Tenant A) -----
TENANT_A="64682bb3-a1d1-41f2-bfd0-e21e4059eb5a"
SUB_A="42345215-fae0-4d93-b24c-f15b3cb6feeb"
RG_A="VM-RG"
OS_DISK_ID="/subscriptions/42345215-fae0-4d93-b24c-f15b3cb6feeb/resourceGroups/VM-RG/providers/Microsoft.Compute/disks/DesktopVM_OsDisk_1_e2ca4057497b4ebb9cb9150842e3ecfb"
DATA0_DISK_ID="/subscriptions/42345215-fae0-4d93-b24c-f15b3cb6feeb/resourceGroups/VM-RG/providers/Microsoft.Compute/disks/DesktopVM_DataDisk_0"
LOC="germanywestcentral"

# ----- TARGET (Tenant B) -----
TENANT_B="66d51e14-99b9-435a-8c05-449dc0c91710"
SUB_B="30748a75-b2b8-4e4f-b5df-e87aa4ceef7b"
RG_B="VM-RG-TARGET"
SA_B="vhdstgt$RANDOM"           # must be globally unique
CONTAINER="vhds"

# Output VHD blob names in target
OS_VHD="osdisk.vhd"
DATA0_VHD="datadisk0.vhd"

# Expiry (UTC) for SAS (adjust as you like)
EXPIRY_OS=$(date -u -d "+24 hours" +"%Y-%m-%dT%H:%MZ")
EXPIRY_DATA=$(date -u -d "+24 hours" +"%Y-%m-%dT%H:%MZ")
EXPIRY_DST=$(date -u -d "+24 hours" +"%Y-%m-%dT%H:%MZ")


# Login + set context to SOURCE
az login --tenant "$TENANT_A"
az account set --subscription "$SUB_A"

# (Optional) Quiesce VM for consistency
# az vm deallocate -g "$RG_A" -n "DesktopVM"

# Create snapshots from managed disks
az snapshot create -g "$RG_A" -n "osdisk-snap"   --source "$OS_DISK_ID"   --sku Standard_LRS --location "$LOC"
az snapshot create -g "$RG_A" -n "data0-snap"    --source "$DATA0_DISK_ID" --sku Standard_LRS --location "$LOC"

# Grant read SAS on snapshots (returns full signed URLs)
SRC_OS_SAS=$(az snapshot grant-access -g "$RG_A" -n "osdisk-snap" \
  --access-level Read --duration-in-seconds 86400 -o tsv --query accessSas)

SRC_DATA0_SAS=$(az snapshot grant-access -g "$RG_A" -n "data0-snap" \
  --access-level Read --duration-in-seconds 86400 -o tsv --query accessSas)


# Login + set context to TARGET
az login --tenant "$TENANT_B"
az account set --subscription "$SUB_B"

# Resource group + storage account + container
az group create -n "$RG_B" -l "$LOC"
az storage account create -g "$RG_B" -n "$SA_B" -l "$LOC" --sku Standard_LRS --kind StorageV2
az storage container create --account-name "$SA_B" --name "$CONTAINER"

# Generate WRITE SAS for container (allow create+write)
DST_CONTAINER_SAS=$(az storage container generate-sas \
  --account-name "$SA_B" --name "$CONTAINER" \
  --permissions cw --expiry "$EXPIRY_DST" -o tsv)

# Destinations (container SAS goes at the end)
DST_OS="https://${SA_B}.blob.core.windows.net/${CONTAINER}/${OS_VHD}?${DST_CONTAINER_SAS}"
DST_DATA0="https://${SA_B}.blob.core.windows.net/${CONTAINER}/${DATA0_VHD}?${DST_CONTAINER_SAS}"


# If you haven't already:
#   https://learn.microsoft.com/azure/storage/common/storage-use-azcopy-v10
#   azcopy login    # optional; using SAS on both ends means login isn't required.

# Copy OS VHD
azcopy copy "$SRC_OS_SAS" "$DST_OS" --recursive=false

# Copy Data VHD
azcopy copy "$SRC_DATA0_SAS" "$DST_DATA0" --recursive=false


# OS managed disk
az disk create -g "$RG_B" -n "DesktopVM-OS-Managed" \
  --source "https://${SA_B}.blob.core.windows.net/${CONTAINER}/${OS_VHD}" \
  --os-type Windows --sku Standard_LRS --location "$LOC"

# Data managed disk
az disk create -g "$RG_B" -n "DesktopVM-Data0-Managed" \
  --source "https://${SA_B}.blob.core.windows.net/${CONTAINER}/${DATA0_VHD}" \
  --sku Standard_LRS --location "$LOC"


# VNet + Subnet
az network vnet create -g "$RG_B" -n "vnet-DesktopVM" --address-prefix 10.10.0.0/16 \
  --subnet-name "snet-desktopvm" --subnet-prefix 10.10.1.0/24

# Public IP (optional)
az network public-ip create -g "$RG_B" -n "pip-desktopvm" --sku Basic --version IPv4

# NIC
az network nic create -g "$RG_B" -n "nic-desktopvm" \
  --vnet-name "vnet-DesktopVM" --subnet "snet-desktopvm" \
  --public-ip-address "pip-desktopvm"


# Create VM by ATTACHING OS disk (no imageReference!)
az vm create -g "$RG_B" -n "DesktopVM" \
  --attach-os-disk "DesktopVM-OS-Managed" \
  --os-type windows \
  --size "Standard_A2m_v2" \
  --nics "nic-desktopvm"

# Attach data disk
az vm disk attach -g "$RG_B" --vm-name "DesktopVM" \
  --name "DesktopVM-Data0-Managed" --lun 0 --caching None


  