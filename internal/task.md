# 📝 Goal: Copy a VM Across Tenants to Apply a Subscription Discount

## 🎯 Objective
We have a VM running in **Subscription A (Tenant A)**.  
Our Azure discount applies only to **Subscription B (Tenant B)**.  

Since the subscriptions are in **different Azure Active Directory tenants**, we **cannot use Azure’s “Move” feature**.  
Instead, we need to **copy the VM’s disks across tenants** and re-create the VM in the discounted subscription — while still allowing the original account to manage it.

---

## 🔹 High-Level Steps

1. **Snapshot Disks in Tenant A**
   - Create snapshots of the VM’s OS disk and any data disks.

2. **Generate SAS URLs (Tenant A)**
   - Export read-only SAS links for the snapshots.

3. **Prepare Storage in Tenant B**
   - Create a storage account and container in the discounted subscription.
   - Generate a write SAS URL for the container.

4. **Copy Snapshots → VHDs Across Tenants**
   - Use **AzCopy** to stream the snapshots (Tenant A) into VHD blobs in Tenant B’s storage.

5. **Create Managed Disks in Tenant B**
   - Convert the uploaded VHDs into managed disks.

6. **Recreate Networking**
   - Deploy a new VNet, subnet, public IP, and NIC in Tenant B.

7. **Recreate the VM**
   - Attach the OS managed disk as the boot disk.
   - Attach the data disk(s) at the same LUNs.
   - Select the same VM size and region as before.

8. **Reconfigure Settings**
   - Enable boot diagnostics in Tenant B if needed.
   - Reinstall VM extensions (e.g., Network Watcher).
   - Apply license type if applicable (`Windows_Client` for AVD, otherwise none).

9. **Grant Access**
   - Assign RBAC (e.g., Owner role) in Tenant B so the original account can still manage the VM.

---

## ✅ End Result
- The VM runs under **Subscription B (Tenant B)** where the discount applies.  
- The **original account** from Tenant A still has access rights.  
- No downtime to the source VM beyond snapshot creation.  
- Target VM is logically identical (same disks/data) but has **new resource IDs** (new NIC, IP, etc.).
