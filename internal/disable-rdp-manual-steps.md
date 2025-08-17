# How to Manually Disable RDP Access to Azure VM

## Method 1: Through Network Security Group (NSG) Rules

### Step 1: Access Azure Portal
1. Open your web browser and go to [portal.azure.com](https://portal.azure.com)
2. Sign in with your Azure credentials

### Step 2: Navigate to Your VM
1. In the Azure Portal search bar, type "Virtual machines" and select it
2. Find and click on your VM from the list

### Step 3: Access Network Security Group
1. In your VM's overview page, look for the **"Networking"** tab in the left menu
2. Click on **"Networking"**
3. You'll see the network interfaces and associated Network Security Groups (NSGs)

### Step 4: Modify RDP Rule
1. Click on the **Network Security Group name** (usually ends with "-nsg")
2. In the NSG blade, click on **"Inbound security rules"** in the left menu
3. Find the RDP rule (usually named "RDP" or shows port 3389)
4. Click on the RDP rule to open it
5. Change the **"Action"** from **"Allow"** to **"Deny"**
6. Click **"Save"**

## Method 2: Delete the RDP Rule Temporarily

### Alternative to Step 4 above:
1. Instead of modifying the rule, you can **delete** the RDP rule entirely
2. In the "Inbound security rules" list, click the **three dots (...)** next to the RDP rule
3. Select **"Delete"**
4. Confirm the deletion

## Method 3: Through VM's Networking Tab (Quick Method)

### Step 1-2: Same as above (Navigate to VM)

### Step 3: Direct Rule Management
1. In your VM's **"Networking"** tab
2. Find the RDP rule in the **"Inbound port rules"** section
3. Click the **three dots (...)** next to the RDP rule
4. Select **"Delete"** or **"Edit"**
5. If editing, change Action to **"Deny"** and save

## To Re-enable RDP Later

### If you modified the rule (Method 1):
1. Go back to the same NSG rule
2. Change the "Action" back to **"Allow"**
3. Click **"Save"**

### If you deleted the rule (Method 2 or 3):
1. In the NSG "Inbound security rules", click **"+ Add"**
2. Set the following:
   - **Source**: Any (or your specific IP for better security)
   - **Source port ranges**: *
   - **Destination**: Any
   - **Destination port ranges**: 3389
   - **Protocol**: TCP
   - **Action**: Allow
   - **Priority**: 1000 (or available number)
   - **Name**: RDP
3. Click **"Add"**

## Security Note
For better security when re-enabling RDP, consider:
- Setting the **Source** to your specific public IP address instead of "Any"
- Using Azure Bastion for secure RDP access without exposing port 3389 to the internet
- Enabling Just-In-Time (JIT) access if you have Azure Security Center

## Verification
- After making changes, wait 1-2 minutes for the changes to take effect
- Try connecting via RDP - it should be blocked/denied
- Check the "Effective security rules" in the VM's Networking tab to confirm the rule is applied