$ErrorActionPreference = "Stop"

# Check if azcopy is available before starting any operations
if (-not (Get-Command azcopy -ErrorAction SilentlyContinue)) {
    Write-Error @"
AzCopy is not installed or not in PATH. Please install AzCopy first:

Download from Microsoft:
https://learn.microsoft.com/azure/storage/common/storage-use-azcopy-v10

After installation, restart your PowerShell session to refresh the PATH.
"@
    exit 1
}

# ----- SOURCE (Tenant A) -----
$TENANT_A = "64682bb3-a1d1-41f2-bfd0-e21e4059eb5a"
$SUB_A = "42345215-fae0-4d93-b24c-f15b3cb6feeb"
$RG_A = "VM-RG"
$OS_DISK_ID = "/subscriptions/42345215-fae0-4d93-b24c-f15b3cb6feeb/resourceGroups/VM-RG/providers/Microsoft.Compute/disks/DesktopVM_OsDisk_1_e2ca4057497b4ebb9cb9150842e3ecfb"
$DATA0_DISK_ID = "/subscriptions/42345215-fae0-4d93-b24c-f15b3cb6feeb/resourceGroups/VM-RG/providers/Microsoft.Compute/disks/DesktopVM_DataDisk_0"
$LOC = "germanywestcentral"

# ----- TARGET (Tenant B) -----
$TENANT_B = "66d51e14-99b9-435a-8c05-449dc0c91710"
$SUB_B = "30748a75-b2b8-4e4f-b5df-e87aa4ceef7b"
$RG_B = "VM-RG-TARGET"
$SA_B = "vhdstgt830292774"           # must be globally unique
$CONTAINER = "vhds"

# Output VHD blob names in target
$OS_VHD = "osdisk.vhd"
$DATA0_VHD = "datadisk0.vhd"

# Expiry (UTC) for SAS (adjust as you like)
$EXPIRY_OS = (Get-Date).AddHours(24).ToString("yyyy-MM-ddTHH:mmZ")
$EXPIRY_DATA = (Get-Date).AddHours(24).ToString("yyyy-MM-ddTHH:mmZ")
$EXPIRY_DST = (Get-Date).AddHours(24).ToString("yyyy-MM-ddTHH:mmZ")


# Login + set context to SOURCE
az login --tenant $TENANT_A
az account set --subscription $SUB_A

# (Optional) Quiesce VM for consistency
# az vm deallocate -g $RG_A -n "DesktopVM"

# Create snapshots from managed disks (only if they don't already exist)
$osSnapExists = az snapshot show -g $RG_A -n "osdisk-snap" --query "name" -o tsv 2>$null
if (-not $osSnapExists) {
    Write-Host "Creating OS disk snapshot..."
    az snapshot create -g $RG_A -n "osdisk-snap" --source $OS_DISK_ID --sku Standard_LRS --location $LOC
}
else {
    Write-Host "OS disk snapshot 'osdisk-snap' already exists, skipping creation."
}

$dataSnapExists = az snapshot show -g $RG_A -n "data0-snap" --query "name" -o tsv 2>$null
if (-not $dataSnapExists) {
    Write-Host "Creating data disk snapshot..."
    az snapshot create -g $RG_A -n "data0-snap" --source $DATA0_DISK_ID --sku Standard_LRS --location $LOC
}
else {
    Write-Host "Data disk snapshot 'data0-snap' already exists, skipping creation."
}

# Grant read SAS on snapshots (returns full signed URLs) - with caching
$cacheDir = "$env:TEMP\vm-copy-cache"
if (-not (Test-Path $cacheDir)) {
    New-Item -Path $cacheDir -ItemType Directory -Force | Out-Null
}

$sasOsCacheFile = "$cacheDir\os-snapshot-sas.json"
$sasDataCacheFile = "$cacheDir\data-snapshot-sas.json"

# Check if cached SAS tokens exist and are still valid
$SRC_OS_SAS = $null
$SRC_DATA0_SAS = $null

if (Test-Path $sasOsCacheFile) {
    try {
        $cachedSasData = Get-Content $sasOsCacheFile -Raw | ConvertFrom-Json
        $expiryTime = [DateTime]::ParseExact($cachedSasData.Expiry, "yyyy-MM-ddTHH:mmZ", $null)
        if ($expiryTime -gt (Get-Date).AddMinutes(120)) {
            $SRC_OS_SAS = $cachedSasData.SasUrl
            Write-Host "Using cached OS snapshot SAS token (expires: $($cachedSasData.Expiry))"
        }
        else {
            Write-Host "Cached OS snapshot SAS token expired, will generate new one"
        }
    }
    catch {
        Write-Host "Invalid cached OS SAS data, will generate new token"
    }
}

if (Test-Path $sasDataCacheFile) {
    try {
        $cachedSasData = Get-Content $sasDataCacheFile -Raw | ConvertFrom-Json
        $expiryTime = [DateTime]::ParseExact($cachedSasData.Expiry, "yyyy-MM-ddTHH:mmZ", $null)
        if ($expiryTime -gt (Get-Date).AddMinutes(120)) {
            $SRC_DATA0_SAS = $cachedSasData.SasUrl
            Write-Host "Using cached data snapshot SAS token (expires: $($cachedSasData.Expiry))"
        }
        else {
            Write-Host "Cached data snapshot SAS token expired, will generate new one"
        }
    }
    catch {
        Write-Host "Invalid cached data SAS data, will generate new token"
    }
}

# Generate new SAS tokens if not cached or expired
if (-not $SRC_OS_SAS) {
    Write-Host "Generating new OS snapshot SAS token..."
    $SRC_OS_SAS = az snapshot grant-access -g $RG_A -n "osdisk-snap" `
        --access-level Read --duration-in-seconds 86400 -o tsv --query accessSas
    
    # Cache the SAS token
    $sasCache = @{
        SasUrl       = $SRC_OS_SAS
        Expiry       = $EXPIRY_OS
        Generated    = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        SnapshotName = "osdisk-snap"
    }
    $sasCache | ConvertTo-Json -Depth 2 | Set-Content $sasOsCacheFile
    Write-Host "OS snapshot SAS token cached to: $sasOsCacheFile"
}

if (-not $SRC_DATA0_SAS) {
    Write-Host "Generating new data snapshot SAS token..."
    $SRC_DATA0_SAS = az snapshot grant-access -g $RG_A -n "data0-snap" `
        --access-level Read --duration-in-seconds 86400 -o tsv --query accessSas
    
    # Cache the SAS token
    $sasCache = @{
        SasUrl       = $SRC_DATA0_SAS
        Expiry       = $EXPIRY_DATA
        Generated    = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        SnapshotName = "data0-snap"
    }
    $sasCache | ConvertTo-Json -Depth 2 | Set-Content $sasDataCacheFile
    Write-Host "Data snapshot SAS token cached to: $sasDataCacheFile"
}


# Login + set context to TARGET
az login --tenant $TENANT_B
az account set --subscription $SUB_B

# Resource group + storage account + container
$rgExists = az group exists -n $RG_B
if ($rgExists -eq "false") {
    Write-Host "Creating resource group '$RG_B'..."
    az group create -n $RG_B -l $LOC
}
else {
    Write-Host "Resource group '$RG_B' already exists, skipping creation."
}

$saExists = az storage account show -g $RG_B -n $SA_B --query "name" -o tsv 2>$null
if (-not $saExists) {
    Write-Host "Creating storage account '$SA_B'..."
    az storage account create -g $RG_B -n $SA_B -l $LOC --sku Standard_LRS --kind StorageV2
}
else {
    Write-Host "Storage account '$SA_B' already exists, skipping creation."
}

$containerExists = az storage container exists --account-name $SA_B --name $CONTAINER --query "exists" -o tsv 2>$null
if ($containerExists -eq "false" -or -not $containerExists) {
    Write-Host "Creating storage container '$CONTAINER'..."
    az storage container create --account-name $SA_B --name $CONTAINER
}
else {
    Write-Host "Storage container '$CONTAINER' already exists, skipping creation."
}

# Generate WRITE SAS for container (allow create+write) - with caching
$sasContainerCacheFile = "$cacheDir\container-sas.json"
$DST_CONTAINER_SAS = $null
$requiredPermissions = "rwdlac"

if (Test-Path $sasContainerCacheFile) {
    try {
        $cachedSasData = Get-Content $sasContainerCacheFile -Raw | ConvertFrom-Json
        $expiryTime = [DateTime]::ParseExact($cachedSasData.Expiry, "yyyy-MM-ddTHH:mmZ", $null)
        $permissionsMatch = $cachedSasData.Permissions -eq $requiredPermissions
        
        if ($expiryTime -gt (Get-Date).AddMinutes(10) -and $permissionsMatch) {
            $DST_CONTAINER_SAS = $cachedSasData.SasUrl
            Write-Host "Using cached container SAS token (expires: $($cachedSasData.Expiry), permissions: $($cachedSasData.Permissions))"
        }
        elseif (-not $permissionsMatch) {
            Write-Host "Cached container SAS token has different permissions ($($cachedSasData.Permissions) vs $requiredPermissions), will generate new one"
        }
        else {
            Write-Host "Cached container SAS token expired, will generate new one"
        }
    }
    catch {
        Write-Host "Invalid cached container SAS data, will generate new token"
    }
}

if (-not $DST_CONTAINER_SAS) {
    Write-Host "Generating new container SAS token with permissions: $requiredPermissions..."
    $DST_CONTAINER_SAS = az storage container generate-sas `
        --account-name $SA_B --name $CONTAINER `
        --permissions $requiredPermissions --expiry $EXPIRY_DST -o tsv
    
    # Cache the SAS token with permissions info
    $sasCache = @{
        SasUrl         = $DST_CONTAINER_SAS
        Expiry         = $EXPIRY_DST
        Permissions    = $requiredPermissions
        Generated      = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        StorageAccount = $SA_B
        Container      = $CONTAINER
    }
    $sasCache | ConvertTo-Json -Depth 2 | Set-Content $sasContainerCacheFile
    Write-Host "Container SAS token cached to: $sasContainerCacheFile"
}

# Destinations (container SAS goes at the end)
$DST_OS = "https://$SA_B.blob.core.windows.net/$CONTAINER/$OS_VHD`?$DST_CONTAINER_SAS"
$DST_DATA0 = "https://$SA_B.blob.core.windows.net/$CONTAINER/$DATA0_VHD`?$DST_CONTAINER_SAS"


# For cross-tenant copy, remove automatic authentication and rely on SAS tokens
if ($env:AZCOPY_AUTO_LOGIN_TYPE) {
    Remove-Item Env:AZCOPY_AUTO_LOGIN_TYPE
}
if ($env:AZCOPY_TENANT_ID) {
    Remove-Item Env:AZCOPY_TENANT_ID
}
Write-Host "Configured AzCopy to use SAS-only authentication for cross-tenant copy"

# Copy OS VHD (only if not already exists)
$osVhdExists = az storage blob exists --account-name $SA_B --container-name $CONTAINER --name $OS_VHD --query "exists" -o tsv 2>$null
if ($osVhdExists -eq "true") {
    Write-Host "OS VHD '$OS_VHD' already exists in destination, skipping copy."
}
else {
    Write-Host "Starting OS disk copy..."
    Write-Host "Source (Tenant A): $($SRC_OS_SAS.Substring(0, 50))..."
    Write-Host "Destination (Tenant B): $($DST_OS.Substring(0, 50))..."
    azcopy copy $SRC_OS_SAS $DST_OS --recursive=false
}

# Copy Data VHD (only if not already exists)
$dataVhdExists = az storage blob exists --account-name $SA_B --container-name $CONTAINER --name $DATA0_VHD --query "exists" -o tsv 2>$null
if ($dataVhdExists -eq "true") {
    Write-Host "Data VHD '$DATA0_VHD' already exists in destination, skipping copy."
}
else {
    Write-Host "Starting data disk copy..."
    Write-Host "Source (Tenant A): $($SRC_DATA0_SAS.Substring(0, 50))..."
    Write-Host "Destination (Tenant B): $($DST_DATA0.Substring(0, 50))..."
    azcopy copy $SRC_DATA0_SAS $DST_DATA0 --recursive=false
}

# OS managed disk
$osDiskExists = az disk show -g $RG_B -n "DesktopVM-OS-Managed" --query "name" -o tsv 2>$null
if (-not $osDiskExists) {
    Write-Host "Creating OS managed disk 'DesktopVM-OS-Managed'..."
    az disk create -g $RG_B -n "DesktopVM-OS-Managed" `
        --source "https://$SA_B.blob.core.windows.net/$CONTAINER/$OS_VHD" `
        --os-type Windows --sku Standard_LRS --location $LOC
}
else {
    Write-Host "OS managed disk 'DesktopVM-OS-Managed' already exists, skipping creation."
}

# Data managed disk
$dataDiskExists = az disk show -g $RG_B -n "DesktopVM-Data0-Managed" --query "name" -o tsv 2>$null
if (-not $dataDiskExists) {
    Write-Host "Creating data managed disk 'DesktopVM-Data0-Managed'..."
    az disk create -g $RG_B -n "DesktopVM-Data0-Managed" `
        --source "https://$SA_B.blob.core.windows.net/$CONTAINER/$DATA0_VHD" `
        --sku Standard_LRS --location $LOC
}
else {
    Write-Host "Data managed disk 'DesktopVM-Data0-Managed' already exists, skipping creation."
}

# VNet + Subnet
$vnetExists = az network vnet show -g $RG_B -n "vnet-DesktopVM" --query "name" -o tsv 2>$null
if (-not $vnetExists) {
    Write-Host "Creating VNet 'vnet-DesktopVM' with subnet..."
    az network vnet create -g $RG_B -n "vnet-DesktopVM" --address-prefix 10.10.0.0/16 `
        --subnet-name "snet-desktopvm" --subnet-prefix 10.10.1.0/24
}
else {
    Write-Host "VNet 'vnet-DesktopVM' already exists, skipping creation."
}

# Public IP (optional)
$pipExists = az network public-ip show -g $RG_B -n "pip-desktopvm" --query "name" -o tsv 2>$null
if (-not $pipExists) {
    Write-Host "Creating public IP 'pip-desktopvm'..."
    az network public-ip create -g $RG_B -n "pip-desktopvm" --sku Basic --version IPv4
}
else {
    Write-Host "Public IP 'pip-desktopvm' already exists, skipping creation."
}

# NIC
$nicExists = az network nic show -g $RG_B -n "nic-desktopvm" --query "name" -o tsv 2>$null
if (-not $nicExists) {
    Write-Host "Creating NIC 'nic-desktopvm'..."
    az network nic create -g $RG_B -n "nic-desktopvm" `
        --vnet-name "vnet-DesktopVM" --subnet "snet-desktopvm" `
        --public-ip-address "pip-desktopvm"
}
else {
    Write-Host "NIC 'nic-desktopvm' already exists, skipping creation."
}


# Create VM by ATTACHING OS disk (no imageReference!)
$vmExists = az vm show -g $RG_B -n "DesktopVM" --query "name" -o tsv 2>$null
if (-not $vmExists) {
    Write-Host "Creating VM 'DesktopVM'..."
    az vm create -g $RG_B -n "DesktopVM" `
        --attach-os-disk "DesktopVM-OS-Managed" `
        --os-type windows `
        --size "Standard_A2m_v2" `
        --nics "nic-desktopvm"

    # Attach data disk
    Write-Host "Attaching data disk to VM..."
    az vm disk attach -g $RG_B --vm-name "DesktopVM" `
        --name "DesktopVM-Data0-Managed" --lun 0 --caching None
}
else {
    Write-Host "VM 'DesktopVM' already exists, skipping creation."
    
    # Check if data disk is already attached
    $dataDiskAttached = az vm show -g $RG_B -n "DesktopVM" --query "storageProfile.dataDisks[?name=='DesktopVM-Data0-Managed'].name" -o tsv 2>$null
    if (-not $dataDiskAttached) {
        Write-Host "Attaching data disk to existing VM..."
        az vm disk attach -g $RG_B --vm-name "DesktopVM" `
            --name "DesktopVM-Data0-Managed" --lun 0 --caching None
    }
    else {
        Write-Host "Data disk already attached to VM."
    }
}


  