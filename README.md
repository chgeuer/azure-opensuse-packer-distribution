# Distribute images

## Download ISO image

```bash
export openSuseVersion=42.3
export imageLocation="https://download.opensuse.org/distribution/leap/${openSuseVersion}/iso/openSUSE-Leap-${openSuseVersion}-DVD-x86_64.iso"
curl --get --location --output "openSUSE-Leap-${openSuseVersion}-DVD-x86_64.iso" --url $imageLocation
```

## Build a vhdx file

### install packer, if needed

```bash
go get github.com/mitchellh/packer
```

### Use packer, to install and build openSUSE in a local Hyper-V installation

```cmd
set PACKER_LOG=1
packer build packer-hyper-v.json
```

- The installation is configured through the `http/autoinst.xml` file. The file stucture is defined in [AutoYaST documentation](https://doc.opensuse.org/projects/autoyast/).
- The `packer build` run creates a `.vhdx` file in `output-hyperv-iso\Virtual Hard Disks\packer-hyperv-iso.vhdx`. 

### Convert `.vhdx` to fixed-size `.vhd`

```powershell
Convert-VHD –Path "output-hyperv-iso\Virtual Hard Disks\packer-hyperv-iso.vhdx" -DestinationPath "output-hyperv-iso\Virtual Hard Disks\packer-hyperv-iso.vhd" -VHDType Fixed
```

### Create target ingest storage account

```bash
managementSubscriptionId=724467b5-bee4-484b-bf13-d6a5505d2b51
demoPrefix=hecdemo
managementResourceGroup="${demoPrefix}management"
imageIngestDataCenter=westeurope

az account set --subscription $managementSubscriptionId

#
# Create the management resource group
#
az group create --name "${managementResourceGroup}" --location "${imageIngestDataCenter}"

#
# Create the storage account where images are uploaded to
#
az storage account create \
  --name "${demoPrefix}imageingest" \
  --resource-group "${managementResourceGroup}" \
  --location "${imageIngestDataCenter}" \
  --https-only true \
  --kind Storage \
  --sku Standard_RAGRS

#
# Fetch storage account key
#
storageAccountKeyImageIngest=$(az storage account keys list \
  --resource-group "${managementResourceGroup}" \
  --account-name "${demoPrefix}imageingest" \
  --query "[?contains(keyName,'key1')].[value]" \
  --o tsv)

#
# Create the storage container where images are uploaded
#
az storage container create \
  --account-name "${demoPrefix}imageingest" \
  --account-key  "${storageAccountKeyImageIngest}" \
  --name "imagedistribution" \
  --public-access off
```

Upload `[az storage blob upload --type=page](https://docs.microsoft.com/en-us/cli/azure/storage/blob?view=azure-cli-latest#az_storage_blob_upload)` 

```bash
az storage blob upload \
  --account-name "${demoPrefix}imageingest" \
  --account-key "${storageAccountKeyImageIngest}" \
  --container-name "imagedistribution" \
  --type page \
  --file "output-hyperv-iso/Virtual Hard Disks/packer-hyperv-iso.vhd" \
  --name "2017-12-06-opensuse-image.vhd"
```

## links

- [Azure: Prepare a SLES or openSUSE virtual machine for Azure](https://docs.microsoft.com/en-us/azure/virtual-machines/linux/suse-create-upload-vhd)
